module Page.Group.EntriesTab exposing (view)

{-| Entries tab showing expense and transfer cards.
-}

import Domain.GroupState as GroupState exposing (GroupState)
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


view : I18n -> msg -> GroupState -> Ui.Element msg
view i18n onNewEntry state =
    let
        resolveName =
            GroupState.resolveMemberName state

        entries =
            GroupState.activeEntries state
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text (T.entriesTabTitle i18n))
        , if List.isEmpty entries then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text (T.entriesNone i18n))

          else
            let
                card =
                    UI.Components.entryCard i18n resolveName
            in
            Ui.column [ Ui.width Ui.fill ]
                (List.map card entries)
        , newEntryButton i18n onNewEntry
        ]


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
