module UI.Shell exposing (appShell, groupShell)

{-| Application shell layouts.
-}

import Route exposing (GroupTab(..))
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font


{-| Top-level app shell with a header and max-width content area.
-}
appShell : { title : String, content : Ui.Element msg } -> Ui.Element msg
appShell config =
    Ui.column
        [ Ui.width Ui.fill
        , Ui.height Ui.fill
        ]
        [ header config.title
        , Ui.el
            [ Ui.width Ui.fill
            , Ui.widthMax Theme.contentMaxWidth
            , Ui.centerX
            , Ui.padding Theme.spacing.md
            ]
            config.content
        ]


header : String -> Ui.Element msg
header title =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.background Theme.primary
        , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        ]
        (Ui.el
            [ Ui.width Ui.fill
            , Ui.widthMax Theme.contentMaxWidth
            , Ui.centerX
            ]
            (Ui.el [ Ui.Font.color Theme.white, Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text title))
        )


{-| Group page shell with header showing group name and a bottom tab bar.
-}
groupShell :
    { groupName : String
    , activeTab : GroupTab
    , content : Ui.Element msg
    , onTabClick : GroupTab -> msg
    }
    -> Ui.Element msg
groupShell config =
    Ui.column
        [ Ui.width Ui.fill
        , Ui.height Ui.fill
        ]
        [ header config.groupName
        , Ui.el
            [ Ui.width Ui.fill
            , Ui.widthMax Theme.contentMaxWidth
            , Ui.centerX
            , Ui.padding Theme.spacing.md
            , Ui.height Ui.fill
            , Ui.scrollable
            ]
            config.content
        , tabBar config.activeTab config.onTabClick
        ]


tabBar : GroupTab -> (GroupTab -> msg) -> Ui.Element msg
tabBar activeTab onTabClick =
    Ui.row
        [ Ui.width Ui.fill
        , Ui.borderWith { top = Theme.borderWidth.sm, bottom = 0, left = 0, right = 0 }
        , Ui.borderColor Theme.neutral200
        ]
        [ tab activeTab onTabClick BalanceTab "Balance"
        , tab activeTab onTabClick EntriesTab "Entries"
        , tab activeTab onTabClick MembersTab "Members"
        , tab activeTab onTabClick ActivitiesTab "Activities"
        ]


tab : GroupTab -> (GroupTab -> msg) -> GroupTab -> String -> Ui.Element msg
tab activeTab onTabClick thisTab label =
    let
        isActive =
            thisTab == activeTab
    in
    Ui.el
        [ Ui.width Ui.fill
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.sm
        , Ui.pointer
        , Ui.Events.onClick (onTabClick thisTab)
        , Ui.Font.center
        , Ui.Font.size Theme.fontSize.sm
        , if isActive then
            Ui.Font.color Theme.primary

          else
            Ui.Font.color Theme.neutral500
        , if isActive then
            Ui.Font.bold

          else
            Ui.noAttr
        , if isActive then
            Ui.borderWith { top = 0, bottom = Theme.borderWidth.md, left = 0, right = 0 }

          else
            Ui.noAttr
        , if isActive then
            Ui.borderColor Theme.primary

          else
            Ui.noAttr
        ]
        (Ui.text label)
