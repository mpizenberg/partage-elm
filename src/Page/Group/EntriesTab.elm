module Page.Group.EntriesTab exposing (view)

{-| Entries tab showing expense and transfer cards.
-}

import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


view : GroupState -> (Member.Id -> String) -> Ui.Element msg
view state resolveName =
    let
        entries =
            GroupState.activeEntries state
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ] (Ui.text "Entries")
        , if List.isEmpty entries then
            Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text "No entries yet.")

          else
            let
                card entry =
                    UI.Components.entryCard { entry = entry, resolveName = resolveName }
            in
            Ui.column [ Ui.width Ui.fill ]
                (List.map card entries)
        ]
