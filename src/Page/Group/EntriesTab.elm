module Page.Group.EntriesTab exposing (Msg, view)

{-| Entries tab showing expense and transfer cards.
-}

import Dict
import Domain.Entry as Entry
import Domain.GroupState as GroupState exposing (GroupState)
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input


type alias Msg msg =
    { onNewEntry : msg
    , onEntryClick : Entry.Id -> msg
    , showDeleted : Bool
    , onToggleDeleted : msg
    }


view : I18n -> Msg msg -> GroupState -> Ui.Element msg
view i18n config state =
    let
        resolveName =
            GroupState.resolveMemberName state

        activeEntries =
            GroupState.activeEntries state

        deletedCount =
            Dict.values state.entries
                |> List.filter .isDeleted
                |> List.length

        allEntryStates =
            Dict.values state.entries

        visibleEntries =
            if config.showDeleted then
                List.map
                    (\es -> { entry = es.currentVersion, isDeleted = es.isDeleted })
                    allEntryStates

            else
                List.map
                    (\e -> { entry = e, isDeleted = False })
                    activeEntries
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
            Ui.column [ Ui.width Ui.fill ]
                (List.map (entryRow i18n resolveName config.onEntryClick) visibleEntries)
        , newEntryButton i18n config.onNewEntry
        ]


entryRow : I18n -> (Entry.Id -> String) -> (Entry.Id -> msg) -> { entry : Entry.Entry, isDeleted : Bool } -> Ui.Element msg
entryRow i18n resolveName onEntryClick { entry, isDeleted } =
    let
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
