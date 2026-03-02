module Page.Group.EntriesTab exposing (Msg, view)

{-| Entries tab showing expense and transfer cards.
-}

import Dict
import Domain.Date exposing (Date)
import Domain.Entry as Entry
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Time
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input


{-| Callback messages for entry interactions on this tab.
-}
type alias Msg msg =
    { onNewEntry : msg
    , onEntryClick : Entry.Id -> msg
    , showDeleted : Bool
    , onToggleDeleted : msg
    }


{-| Render the entries tab with expense/transfer cards and a new entry button.
-}
view : I18n -> Msg msg -> GroupState -> Ui.Element msg
view i18n config state =
    let
        deletedCount : Int
        deletedCount =
            Dict.values state.entries
                |> List.filter .isDeleted
                |> List.length

        visibleEntries : List { entry : Entry.Entry, isDeleted : Bool }
        visibleEntries =
            (if config.showDeleted then
                let
                    allEntryStates : List GroupState.EntryState
                    allEntryStates =
                        Dict.values state.entries
                in
                List.map
                    (\es -> { entry = es.currentVersion, isDeleted = es.isDeleted })
                    allEntryStates

             else
                let
                    activeEntries : List Entry.Entry
                    activeEntries =
                        GroupState.activeEntries state
                in
                List.map
                    (\e -> { entry = e, isDeleted = False })
                    activeEntries
            )
                |> List.sortBy (\{ entry } -> entrySortKey entry)
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.entriesTabTitle i18n))
        , if deletedCount > 0 then
            deletedToggle i18n config.showDeleted deletedCount config.onToggleDeleted

          else
            Ui.none
        , if List.isEmpty visibleEntries then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.entriesNone i18n))

          else
            let
                resolveName : Member.Id -> String
                resolveName =
                    GroupState.resolveMemberName state
            in
            Ui.column [ Ui.width Ui.fill ]
                (List.map (entryRow i18n resolveName config.onEntryClick) visibleEntries)
        , newEntryButton i18n config.onNewEntry
        ]


entryRow : I18n -> (Entry.Id -> String) -> (Entry.Id -> msg) -> { entry : Entry.Entry, isDeleted : Bool } -> Ui.Element msg
entryRow i18n resolveName onEntryClick { entry, isDeleted } =
    let
        card : Ui.Element msg
        card =
            UI.Components.entryCard i18n resolveName (onEntryClick entry.meta.rootId) entry
    in
    if isDeleted then
        Ui.el [ Ui.opacity 0.5 ]
            (Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
                [ card
                , Ui.el
                    [ Ui.Font.size Theme.fontSize.sm
                    , Ui.Font.color Theme.danger
                    , Ui.Font.bold
                    ]
                    (Ui.text (T.entryDeletedBadge i18n))
                ]
            )

    else
        card


deletedToggle : I18n -> Bool -> Int -> msg -> Ui.Element msg
deletedToggle i18n showDeleted count onToggle =
    Ui.el
        [ Ui.pointer
        , Ui.Events.onClick onToggle
        , Ui.Font.size Theme.fontSize.sm
        , Ui.Font.color Theme.primary
        ]
        (Ui.text
            (if showDeleted then
                T.entriesHideDeleted i18n

             else
                T.entriesShowDeleted (String.fromInt count) i18n
            )
        )


newEntryButton : I18n -> msg -> Ui.Element msg
newEntryButton i18n onNewEntry =
    Ui.el
        [ Ui.Input.button onNewEntry
        , Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.rounded Theme.rounding.md
        , Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.center
        , Ui.Font.bold
        , Ui.pointer
        ]
        (Ui.text (T.shellNewEntry i18n))


entrySortKey : Entry.Entry -> ( Int, Int, String )
entrySortKey entry =
    let
        d : Date
        d =
            case entry.kind of
                Entry.Expense data ->
                    data.date

                Entry.Transfer data ->
                    data.date
    in
    ( -(d.year * 10000 + d.month * 100 + d.day)
    , -(Time.posixToMillis entry.meta.createdAt)
    , entry.meta.id
    )
