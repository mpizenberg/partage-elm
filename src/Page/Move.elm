module Page.Move exposing
    ( Effect(..)
    , Model
    , Msg
    , groupSeeded
    , init
    , refresh
    , update
    , view
    )

{-| The source side of a domain migration: pick which groups move, seed the
target deployment's relay with each one's full history, then hand the profile
over. Seeding runs one group at a time — each group costs a proof-of-work and
its own upload, and a sequential run gives one honest progress line per group.
-}

import Dict exposing (Dict)
import Domain.Group as Group
import FeatherIcons
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


type Model
    = Model Data


type alias Data =
    { selected : List Group.Id
    , statuses : Dict Group.Id Status
    , phase : Phase
    }


type Phase
    = Choosing
    | Working
    | Done


type Status
    = Queued
    | InFlight
    | Seeded
    | Failed String


type Msg
    = ToggleGroup Group.Id
    | Start
    | RetryFailed


{-| `Seed` asks the host to run the seeding task for one group and feed the
result back through `groupSeeded`.
-}
type Effect
    = NoEffect
    | Seed Group.Id


init : List Group.Summary -> Model
init groups =
    Model
        { selected =
            groups
                |> List.filter (\g -> not g.isArchived)
                |> List.map .id
        , statuses = Dict.empty
        , phase = Choosing
        }


{-| Reset the checklist against the current group list — unless a run is in
progress or finished, whose status display must survive navigating away and
back.
-}
refresh : List Group.Summary -> Model -> Model
refresh groups ((Model data) as model) =
    case data.phase of
        Choosing ->
            init groups

        _ ->
            model


update : Msg -> Model -> ( Model, Effect )
update msg (Model data) =
    case msg of
        ToggleGroup groupId ->
            case data.phase of
                Choosing ->
                    ( Model
                        { data
                            | selected =
                                if List.member groupId data.selected then
                                    List.filter ((/=) groupId) data.selected

                                else
                                    data.selected ++ [ groupId ]
                        }
                    , NoEffect
                    )

                _ ->
                    ( Model data, NoEffect )

        Start ->
            case ( data.phase, data.selected ) of
                ( Choosing, first :: rest ) ->
                    ( Model
                        { data
                            | phase = Working
                            , statuses =
                                Dict.fromList
                                    ((first, InFlight) :: List.map (\id -> ( id, Queued )) rest)
                        }
                    , Seed first
                    )

                _ ->
                    ( Model data, NoEffect )

        RetryFailed ->
            let
                requeued : Dict Group.Id Status
                requeued =
                    Dict.map
                        (\_ status ->
                            case status of
                                Failed _ ->
                                    Queued

                                other ->
                                    other
                        )
                        data.statuses
            in
            launchNext { data | statuses = requeued }


{-| Record one group's seeding outcome and move on to the next queued group.
-}
groupSeeded : Group.Id -> Result String () -> Model -> ( Model, Effect )
groupSeeded groupId result (Model data) =
    let
        status : Status
        status =
            case result of
                Ok () ->
                    Seeded

                Err reason ->
                    Failed reason
    in
    launchNext { data | statuses = Dict.insert groupId status data.statuses }


launchNext : Data -> ( Model, Effect )
launchNext data =
    let
        statusOf : Group.Id -> Maybe Status
        statusOf id =
            Dict.get id data.statuses

        nextQueued : Maybe Group.Id
        nextQueued =
            List.filter (\id -> statusOf id == Just Queued) data.selected |> List.head
    in
    case nextQueued of
        Just groupId ->
            ( Model { data | phase = Working, statuses = Dict.insert groupId InFlight data.statuses }
            , Seed groupId
            )

        Nothing ->
            if List.any (\id -> statusOf id == Just InFlight) data.selected then
                ( Model data, NoEffect )

            else if List.all (\id -> statusOf id == Just Seeded) data.selected then
                ( Model { data | phase = Done }, NoEffect )

            else
                ( Model data, NoEffect )



-- VIEW


view : I18n -> { targetName : String, groups : List Group.Summary } -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n { targetName, groups } toMsg (Model data) =
    let
        selectedGroups : List Group.Summary
        selectedGroups =
            List.filterMap (\id -> List.filter (\g -> g.id == id) groups |> List.head) data.selected
    in
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        (case data.phase of
            Choosing ->
                viewChoosing i18n groups data

            Working ->
                viewProgress i18n targetName data selectedGroups

            Done ->
                viewDone i18n targetName data selectedGroups
        )
        |> Ui.map toMsg


viewChoosing : I18n -> List Group.Summary -> Data -> List (Ui.Element Msg)
viewChoosing i18n groups data =
    let
        ( activeGroups, archivedGroups ) =
            List.partition (\g -> not g.isArchived) groups

        groupToggle : Group.Summary -> Ui.Element Msg
        groupToggle group =
            UI.Components.togglePill
                { label = group.name
                , icon = Just FeatherIcons.check
                , selected = List.member group.id data.selected
                , onPress = ToggleGroup group.id
                }
    in
    [ hint (T.movePickGroups i18n)
    , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        (List.map groupToggle activeGroups)
    , if List.isEmpty archivedGroups then
        Ui.none

      else
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            (hint (T.moveArchivedHint i18n) :: List.map groupToggle archivedGroups)
    , if List.isEmpty data.selected then
        hint (T.moveNothingSelected i18n)

      else
        UI.Components.btnPrimary []
            { label = T.moveStart i18n
            , onPress = Start
            }
    ]


viewProgress : I18n -> String -> Data -> List Group.Summary -> List (Ui.Element Msg)
viewProgress i18n targetName data selectedGroups =
    let
        anyFailed : Bool
        anyFailed =
            List.any
                (\g -> isFailed (Dict.get g.id data.statuses))
                selectedGroups

        stillRunning : Bool
        stillRunning =
            List.any (\g -> Dict.get g.id data.statuses == Just InFlight) selectedGroups
    in
    [ hint (T.moveSeeding targetName i18n)
    , statusList i18n data selectedGroups
    , if anyFailed && not stillRunning then
        UI.Components.btnPrimary []
            { label = T.moveRetry i18n
            , onPress = RetryFailed
            }

      else
        Ui.none
    ]


viewDone : I18n -> String -> Data -> List Group.Summary -> List (Ui.Element Msg)
viewDone i18n targetName data selectedGroups =
    [ statusList i18n data selectedGroups
    , UI.Components.card [ Ui.padding Theme.spacing.lg ]
        [ Ui.el [ Ui.Font.size Theme.font.md ] (Ui.text (T.moveAllSeeded targetName i18n))
        ]
    ]


isFailed : Maybe Status -> Bool
isFailed status =
    case status of
        Just (Failed _) ->
            True

        _ ->
            False


statusList : I18n -> Data -> List Group.Summary -> Ui.Element Msg
statusList i18n data selectedGroups =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        (List.map
            (\group ->
                statusRow i18n group (Dict.get group.id data.statuses)
            )
            selectedGroups
        )


statusRow : I18n -> Group.Summary -> Maybe Status -> Ui.Element Msg
statusRow i18n group status =
    let
        ( icon, text, color ) =
            case status of
                Just InFlight ->
                    ( FeatherIcons.uploadCloud, T.moveStatusUploading i18n, Theme.base.textSubtle )

                Just Seeded ->
                    ( FeatherIcons.checkCircle, T.moveStatusDone i18n, Theme.success.text )

                Just (Failed reason) ->
                    ( FeatherIcons.alertCircle, reason, Theme.danger.text )

                _ ->
                    ( FeatherIcons.clock, T.moveStatusQueued i18n, Theme.base.textSubtle )
    in
    UI.Components.card [ Ui.padding Theme.spacing.md ]
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY ]
            [ Ui.el [ Ui.width Ui.shrink ] (UI.Components.featherIcon 16 icon)
            , Ui.el [ Ui.Font.size Theme.font.md ] (Ui.text group.name)
            , Ui.el
                [ Ui.Font.size Theme.font.sm, Ui.Font.color color, Ui.alignRight ]
                (Ui.text text)
            ]
        ]


hint : String -> Ui.Element Msg
hint text =
    Ui.el
        [ Ui.Font.size Theme.font.sm
        , Ui.Font.color Theme.base.textSubtle
        , Ui.width Ui.fill
        ]
        (Ui.text text)
