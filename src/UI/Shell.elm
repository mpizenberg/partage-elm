module UI.Shell exposing (TabLabels, pageShell, tabBar, tabbedShell)

{-| Application shell layouts.

Three layout types:

  - **homeShell** — Home page: app title area, no tab bar.
  - **tabbedShell** — Group pages: page header + bottom tab bar.
  - **pageShell** — Sub-pages: page header with back navigation, no tab bar.

-}

import FeatherIcons
import Route exposing (GroupTab(..))
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input


{-| Labels for each tab in the group tab bar.
-}
type alias TabLabels =
    { balance : String
    , entries : String
    , members : String
    , activity : String
    }



-- TABBED SHELL


{-| Group page shell with a page header. The tab bar is NOT included here;
it should be placed in Ui.layout's Ui.inFront for viewport-fixed positioning.
-}
tabbedShell :
    { title : String
    , subtitle : String
    , onBack : msg
    , content : Ui.Element msg
    }
    -> Ui.Element msg
tabbedShell config =
    Ui.column
        [ Ui.height Ui.fill, Ui.paddingBottom Theme.sizing.xxxl ]
        [ pageHeader { title = config.title, subtitle = config.subtitle, onBack = config.onBack }
        , Ui.el
            [ Ui.width Ui.fill
            , Ui.height Ui.fill
            , Ui.paddingBottom Theme.sizing.xxl
            ]
            config.content
        ]



-- PAGE SHELL


{-| Page shell with a page header (back button + title). No tabs.
-}
pageShell : { title : String, onBack : msg } -> Ui.Element msg -> Ui.Element msg
pageShell config content =
    Ui.column [ Ui.height Ui.fill, Ui.paddingBottom Theme.spacing.xl ]
        [ pageHeader { title = config.title, subtitle = "", onBack = config.onBack }
        , content
        ]



-- PAGE HEADER


pageHeader : { title : String, subtitle : String, onBack : msg } -> Ui.Element msg
pageHeader config =
    Ui.row
        [ Ui.width Ui.fill
        , Ui.paddingWith { top = Theme.spacing.lg, bottom = Theme.spacing.lg, left = 0, right = 0 }
        , Ui.contentCenterY
        ]
        [ Ui.row
            [ Ui.spacing Theme.spacing.md
            , Ui.contentCenterY
            , Ui.width Ui.shrink
            , Ui.Input.button config.onBack
            , Ui.pointer
            ]
            [ Ui.el [] (UI.Components.featherIcon (toFloat Theme.sizing.sm) FeatherIcons.chevronLeft)
            , Ui.el
                [ Ui.Font.size Theme.font.xl
                , Ui.Font.weight Theme.fontWeight.bold
                ]
                (Ui.text config.title)
            ]
        , if config.subtitle == "" then
            Ui.none

          else
            Ui.el
                [ Ui.alignRight
                , Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.textSubtle
                ]
                (Ui.text config.subtitle)
        ]



-- TAB BAR


tabBar : TabLabels -> (GroupTab -> String) -> GroupTab -> (GroupTab -> msg) -> Ui.Element msg
tabBar labels tabHref activeTab onTabClick =
    Ui.row
        [ Ui.width Ui.fill
        , Ui.alignBottom
        , Ui.background Theme.base.bg
        , Ui.borderWith { top = Theme.border, bottom = 0, left = 0, right = 0 }
        , Ui.borderColor Theme.base.accent
        ]
        [ tab activeTab tabHref onTabClick BalanceTab FeatherIcons.dollarSign labels.balance
        , tab activeTab tabHref onTabClick EntriesTab FeatherIcons.list labels.entries
        , tab activeTab tabHref onTabClick MembersTab FeatherIcons.users labels.members
        , tab activeTab tabHref onTabClick ActivityTab FeatherIcons.activity labels.activity
        ]


tab : GroupTab -> (GroupTab -> String) -> (GroupTab -> msg) -> GroupTab -> FeatherIcons.Icon -> String -> Ui.Element msg
tab activeTab tabHref onTabClick thisTab icon label =
    let
        ( fontColor, fontWeight ) =
            if thisTab == activeTab then
                ( Ui.Font.color Theme.primary.solid
                , Ui.Font.weight Theme.fontWeight.semibold
                )

            else
                ( Ui.Font.color Theme.base.textSubtle
                , Ui.noAttr
                )
    in
    Ui.column
        (Ui.width Ui.fill
            :: Ui.paddingXY Theme.spacing.sm Theme.spacing.sm
            :: Ui.spacing Theme.spacing.xs
            :: Ui.pointer
            :: Ui.contentCenterX
            :: Ui.Font.center
            :: Ui.Font.size Theme.font.xs
            :: fontColor
            :: fontWeight
            :: UI.Components.spaLinkAttrs (tabHref thisTab) (onTabClick thisTab)
        )
        [ Ui.el [ Ui.centerX ] (UI.Components.featherIcon 18 icon)
        , Ui.text label
        ]
