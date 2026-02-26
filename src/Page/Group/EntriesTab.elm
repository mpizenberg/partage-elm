module Page.Group.EntriesTab exposing (view)

{-| Entries tab showing expense and transfer cards.
-}

import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view : I18n -> GroupState -> (Member.Id -> String) -> Ui.Element msg
view i18n state resolveName =
    let
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
                card entry =
                    UI.Components.entryCard i18n { entry = entry, resolveName = resolveName }
            in
            Ui.column [ Ui.width Ui.fill ]
                (List.map card entries)
        ]
