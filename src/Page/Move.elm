module Page.Move exposing
    ( Effect(..)
    , Model
    , Msg
    , groupSeeded
    , handoffDelivered
    , init
    , payloadReady
    , refresh
    , update
    , view
    )

{-| The source side of a domain migration: pick the groups, seed the target's
relay with them, then hand the profile over. Groups seed one at a time — each
costs a proof-of-work, and a sequential run keeps per-group progress honest.
-}

import Dict exposing (Dict)
import Domain.Group as Group
import FeatherIcons
import Html
import Html.Attributes
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Prose


type Model
    = Model Data


type alias Data =
    { selected : List Group.Id
    , statuses : Dict Group.Id Status
    , phase : Phase
    , payload : Maybe String
    , delivered : Bool
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
    | OpenTarget


{-| `Seed` asks the host to run the seeding task for one group and feed the
result back through `groupSeeded`. `AllSeeded` asks it to build the handoff
payload for the seeded groups and feed it back through `payloadReady`.
`SendHandoff` asks it to open the destination and post the payload there.
-}
type Effect
    = NoEffect
    | Seed Group.Id
    | AllSeeded (List Group.Id)
    | SendHandoff String


init : List Group.Summary -> Model
init groups =
    Model
        { selected =
            groups
                |> List.filter (\g -> not g.isArchived)
                |> List.map .id
        , statuses = Dict.empty
        , phase = Choosing
        , payload = Nothing
        , delivered = False
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
                                    (( first, InFlight ) :: List.map (\id -> ( id, Queued )) rest)
                        }
                    , Seed first
                    )

                _ ->
                    ( Model data, NoEffect )

        OpenTarget ->
            case data.payload of
                Just payload ->
                    ( Model data, SendHandoff payload )

                Nothing ->
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
                ( Model { data | phase = Done }, AllSeeded data.selected )

            else
                ( Model data, NoEffect )


payloadReady : String -> Model -> Model
payloadReady payload (Model data) =
    Model { data | payload = Just payload }


handoffDelivered : Model -> Model
handoffDelivered (Model data) =
    Model { data | delivered = True }



-- VIEW


view :
    I18n
    ->
        { targetName : String
        , groups : List Group.Summary
        , codeOnly : Bool
        }
    -> (Msg -> msg)
    -> Model
    -> Ui.Element msg
view i18n { targetName, groups, codeOnly } toMsg (Model data) =
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
                viewDone i18n targetName codeOnly data selectedGroups
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


viewDone : I18n -> String -> Bool -> Data -> List Group.Summary -> List (Ui.Element Msg)
viewDone i18n targetName codeOnly data selectedGroups =
    [ statusList i18n data selectedGroups
    , UI.Components.card [ Ui.padding Theme.spacing.lg ]
        [ Ui.el [ Ui.Font.size Theme.font.md ] (Ui.text (T.moveAllSeeded targetName i18n))
        ]
    , case data.payload of
        Nothing ->
            hint (T.moveBuildingHandoff i18n)

        Just payload ->
            handoffSection i18n targetName codeOnly data.delivered payload
    ]


{-| The one-tap button needs the destination's browser tab and installed app to
share storage. iOS never guarantees that, regardless of which install hint its
current browser reports, so every iOS source uses the code.
-}
handoffSection : I18n -> String -> Bool -> Bool -> String -> Ui.Element Msg
handoffSection i18n targetName codeOnly delivered payload =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ hint (T.moveHandoffIntro targetName i18n)
        , if codeOnly then
            Ui.none

          else
            UI.Components.btnPrimary [ Ui.width Ui.shrink ]
                { label = T.moveHandoffOpen targetName i18n
                , onPress = OpenTarget
                }
        , if delivered then
            Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.success.text ]
                (Ui.text (T.moveHandoffDelivered i18n))

          else
            Ui.none
        , hint
            (if codeOnly then
                T.moveHandoffCodeIos targetName i18n

             else
                T.moveHandoffCodeHint i18n
            )
        , codeBlock payload
        , copyBtn payload (T.moveHandoffCopy i18n)
        ]


{-| A paragraph, not an `el`: the code is one unbroken 2 KB word, and only
paragraph layout breaks it across lines instead of past the border.
-}
codeBlock : String -> Ui.Element Msg
codeBlock payload =
    Ui.Prose.paragraph
        [ Ui.Font.size Theme.font.xs
        , Ui.Font.family [ Ui.Font.monospace ]
        , Ui.Font.color Theme.base.textSubtle
        , Ui.background Theme.base.tint
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.radius.sm
        , Ui.border Theme.border
        , Ui.borderColor Theme.base.accent
        , Ui.height (Ui.px 120)
        , Ui.clip
        ]
        [ Ui.text payload ]


copyBtn : String -> String -> Ui.Element Msg
copyBtn copyText label =
    Ui.row
        (Ui.width Ui.shrink
            :: Ui.inFront
                (Ui.el [ Ui.width Ui.fill, Ui.height Ui.fill ]
                    (Ui.html
                        (Html.node "copy-button"
                            [ Html.Attributes.attribute "data-copy" copyText
                            , Html.Attributes.style "display" "block"
                            , Html.Attributes.style "width" "100%"
                            , Html.Attributes.style "height" "100%"
                            , Html.Attributes.style "cursor" "pointer"
                            ]
                            []
                        )
                    )
                )
            :: UI.Components.btnOutlineAttrs
        )
        [ UI.Components.featherIcon 16 FeatherIcons.copy
        , Ui.text label
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
