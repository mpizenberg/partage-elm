module UI.Components exposing
    ( sectionLabel, formLabel, formTextField
    , card, horizontalSeparator
    , btnPrimary, btnOutline, btnOutlineAttrs, btnDark, btnDanger, btnSuccess
    , iconButton
    , spaLinkAttrs
    , chip, toggle, expandTrigger, toggleMemberBtn
    , filterToggleButton, filterSection, filterSummaryChip, clearAllFiltersButton
    , avatar, AvatarColor(..)
    , fab
    , featherIcon
    , languageSelector, pwaBanners, readOnlyBanner
    )

{-| Reusable UI components.


# Layout

@docs sectionLabel, formLabel, formTextField
@docs card, horizontalSeparator


# Buttons

@docs btnPrimary, btnOutline, btnOutlineAttrs, btnDark, btnDanger, btnSuccess
@docs iconButton
@docs spaLinkAttrs


# Interactive

@docs chip, toggle, expandTrigger, toggleMemberBtn
@docs filterToggleButton, filterSection, filterSummaryChip, clearAllFiltersButton


# Avatar

@docs avatar, AvatarColor


# Overlays

@docs fab


# Icons

@docs featherIcon


# Domain components

@docs languageSelector, pwaBanners, readOnlyBanner

-}

import FeatherIcons
import Json.Decode
import Svg.Attributes
import Translations as T exposing (I18n, Language(..))
import UI.Theme as Theme
import Ui
import Ui.Anim as Anim
import Ui.Events
import Ui.Font
import Ui.Input



-- SECTION LABEL


{-| Uppercase section label for content grouping.
-}
sectionLabel : String -> Ui.Element msg
sectionLabel label =
    Ui.el sectionLabelAttrs (Ui.text (String.toUpper label))


sectionLabelAttrs : List (Ui.Attribute msg)
sectionLabelAttrs =
    [ Ui.Font.size Theme.font.xs
    , Ui.Font.weight Theme.fontWeight.semibold
    , Ui.Font.letterSpacing Theme.letterSpacing.wide
    , Ui.Font.color Theme.base.textSubtle
    , Ui.paddingBottom Theme.spacing.md
    ]


{-| Form field label with optional required indicator.
-}
formLabel : String -> Bool -> Ui.Element msg
formLabel label required =
    Ui.row [ Ui.spacing Theme.spacing.xs, Ui.width Ui.shrink ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.weight Theme.fontWeight.semibold
            ]
            (Ui.text label)
        , if required then
            Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.primary.solid
                ]
                (Ui.text "*")

          else
            Ui.none
        ]


{-| Form text field with optional icon, required indicator, and error display.
-}
formTextField :
    { icon : Maybe FeatherIcons.Icon
    , label : String
    , required : Bool
    , placeholder : Maybe String
    , value : String
    , onChange : String -> msg
    , error : Maybe String
    }
    -> Ui.Element msg
formTextField config =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ case config.icon of
            Just icon ->
                Ui.row [ Ui.spacing Theme.spacing.sm, Ui.contentCenterY, Ui.width Ui.shrink ]
                    [ Ui.el [ Ui.Font.color Theme.base.textSubtle ] (featherIcon 16 icon)
                    , formLabel config.label config.required
                    ]

            Nothing ->
                formLabel config.label config.required
        , Ui.Input.text
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.rounded Theme.radius.sm
            , Ui.border Theme.border
            , Ui.borderColor Theme.base.accent
            ]
            { onChange = config.onChange
            , text = config.value
            , placeholder = config.placeholder
            , label = Ui.Input.labelHidden config.label
            }
        , case config.error of
            Just errorMsg ->
                Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.danger.text ]
                    (Ui.text errorMsg)

            Nothing ->
                Ui.none
        ]



-- CARD


{-| Card container with white background, border, shadow, and rounded corners.
-}
card : List (Ui.Attribute msg) -> List (Ui.Element msg) -> Ui.Element msg
card attrs children =
    Ui.column
        ([ Ui.background (Ui.rgb 255 255 255)
         , Ui.rounded Theme.radius.lg
         , Theme.shadow
         , Ui.border Theme.border
         , Ui.borderColor Theme.base.accent
         , Ui.width Ui.fill
         ]
            ++ attrs
        )
        children


{-| Horizontal line separator.
-}
horizontalSeparator : Ui.Element msg
horizontalSeparator =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.height (Ui.px 1)
        , Ui.background Theme.base.accent
        ]
        Ui.none



-- BUTTONS


{-| Primary action button (solid accent color, full width).
-}
btnPrimary : List (Ui.Attribute msg) -> { label : String, onPress : msg } -> Ui.Element msg
btnPrimary attrs config =
    Ui.el
        (Ui.Input.button config.onPress
            :: Ui.width Ui.fill
            :: Ui.background Theme.primary.solid
            :: Ui.rounded Theme.radius.md
            :: Ui.paddingXY Theme.spacing.xl Theme.spacing.md
            :: Ui.Font.size Theme.font.md
            :: Ui.Font.weight Theme.fontWeight.semibold
            :: Ui.Font.color Theme.primary.solidText
            :: Ui.Font.center
            :: Ui.pointer
            :: attrs
        )
        (Ui.text config.label)


{-| Common visual attributes for outline-style buttons.
Useful when building custom buttons that should match the outline style.
-}
btnOutlineAttrs : List (Ui.Attribute msg)
btnOutlineAttrs =
    [ Ui.spacing Theme.spacing.sm
    , Ui.contentCenterX
    , Ui.contentCenterY
    , Ui.background Theme.base.bg
    , Ui.border Theme.border
    , Ui.borderColor Theme.base.accent
    , Ui.rounded Theme.radius.md
    , Ui.paddingXY Theme.spacing.lg Theme.spacing.md
    , Ui.Font.size Theme.font.md
    , Ui.Font.weight Theme.fontWeight.medium
    , Ui.Font.color Theme.base.text
    , Ui.pointer
    ]


{-| Outline button with optional icon (bordered, full width).
-}
btnOutline : List (Ui.Attribute msg) -> { label : String, icon : Maybe (Ui.Element msg), onPress : msg } -> Ui.Element msg
btnOutline attrs config =
    Ui.row
        (Ui.Input.button config.onPress :: Ui.width Ui.fill :: btnOutlineAttrs ++ attrs)
        (case config.icon of
            Just icon ->
                [ icon, Ui.text config.label ]

            Nothing ->
                [ Ui.text config.label ]
        )


{-| Dark button (dark background, light text).
-}
btnDark : List (Ui.Attribute msg) -> { label : String, onPress : msg } -> Ui.Element msg
btnDark attrs config =
    Ui.el
        (Ui.Input.button config.onPress
            :: Ui.background Theme.base.text
            :: Ui.rounded Theme.radius.md
            :: Ui.paddingXY Theme.spacing.lg Theme.spacing.md
            :: Ui.Font.color Theme.base.bg
            :: Ui.Font.size Theme.font.md
            :: Ui.Font.weight Theme.fontWeight.semibold
            :: Ui.Font.center
            :: Ui.contentCenterX
            :: Ui.pointer
            :: attrs
        )
        (Ui.text config.label)


{-| Danger button with icon (solid red, full width).
-}
btnDanger : List (Ui.Attribute msg) -> { label : String, icon : FeatherIcons.Icon, onPress : msg } -> Ui.Element msg
btnDanger attrs config =
    Ui.row
        (Ui.Input.button config.onPress
            :: Ui.width Ui.fill
            :: Ui.spacing Theme.spacing.sm
            :: Ui.contentCenterX
            :: Ui.contentCenterY
            :: Ui.padding Theme.spacing.md
            :: Ui.rounded Theme.radius.md
            :: Ui.background Theme.danger.solid
            :: Ui.Font.color Theme.danger.solidText
            :: Ui.Font.weight Theme.fontWeight.semibold
            :: Ui.pointer
            :: attrs
        )
        [ featherIcon 16 config.icon
        , Ui.text config.label
        ]


{-| Success button with icon (solid green, full width).
-}
btnSuccess : List (Ui.Attribute msg) -> { label : String, icon : FeatherIcons.Icon, onPress : msg } -> Ui.Element msg
btnSuccess attrs config =
    Ui.row
        (Ui.Input.button config.onPress
            :: Ui.width Ui.fill
            :: Ui.spacing Theme.spacing.sm
            :: Ui.contentCenterX
            :: Ui.contentCenterY
            :: Ui.padding Theme.spacing.md
            :: Ui.rounded Theme.radius.md
            :: Ui.background Theme.success.solid
            :: Ui.Font.color Theme.success.solidText
            :: Ui.Font.weight Theme.fontWeight.semibold
            :: Ui.pointer
            :: attrs
        )
        [ featherIcon 16 config.icon
        , Ui.text config.label
        ]


{-| Attributes for SPA link+button pattern: renders as `<a>` with href
but intercepts clicks for client-side navigation.
-}
spaLinkAttrs : String -> msg -> List (Ui.Attribute msg)
spaLinkAttrs href onPress =
    [ Ui.link href
    , Ui.Events.preventDefaultOn "click"
        (Json.Decode.succeed ( onPress, True ))
    ]


{-| Icon-only button (square, rounded, with a single Feather icon).
-}
iconButton : List (Ui.Attribute msg) -> { onPress : msg, size : Float, icon : FeatherIcons.Icon } -> Ui.Element msg
iconButton attrs config =
    Ui.el
        (Ui.Input.button config.onPress
            :: Ui.width (Ui.px Theme.sizing.lg)
            :: Ui.height (Ui.px Theme.sizing.lg)
            :: Ui.rounded Theme.radius.md
            :: Ui.contentCenterX
            :: Ui.contentCenterY
            :: Ui.pointer
            :: attrs
        )
        (featherIcon config.size config.icon)



-- CHIP


{-| Selectable pill for filters and multi-select.
-}
chip : { label : String, selected : Bool, onPress : msg } -> Ui.Element msg
chip config =
    let
        ( bg, borderColor, textColor ) =
            if config.selected then
                ( Theme.primary.solid, Theme.primary.solid, Theme.primary.solidText )

            else
                ( Ui.rgba 0 0 0 0, Theme.base.accent, Theme.base.textSubtle )
    in
    Ui.el
        [ Ui.Input.button config.onPress
        , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        , Ui.border Theme.border
        , Ui.rounded Theme.radius.xxl
        , Ui.Font.size Theme.font.sm
        , Ui.Font.weight Theme.fontWeight.medium
        , Ui.pointer
        , Ui.width Ui.shrink
        , Anim.transition (Anim.ms 200)
            [ Anim.backgroundColor bg
            , Anim.borderColor borderColor
            , Anim.fontColor textColor
            ]
        ]
        (Ui.text config.label)



-- TOGGLE


{-| Toggle switch control.
-}
toggle : { isOn : Bool, onPress : msg } -> Ui.Element msg
toggle config =
    let
        ( knobX, bgColor ) =
            if config.isOn then
                ( 21, Theme.primary.solid )

            else
                ( 3, Theme.base.accent )
    in
    Ui.el
        [ Ui.Input.button config.onPress
        , Ui.alignRight
        , Ui.width (Ui.px 44)
        , Ui.height (Ui.px 26)
        , Ui.rounded 13
        , Ui.pointer
        , Ui.contentCenterY
        , Anim.transition (Anim.ms 250)
            [ Anim.backgroundColor bgColor ]
        ]
        (Ui.el
            [ Ui.width (Ui.px 20)
            , Ui.height (Ui.px 20)
            , Ui.rounded Theme.radius.xxxl
            , Ui.background Theme.base.solidText
            , Theme.shadowKnob
            , Anim.transition (Anim.ms 250)
                [ Anim.x knobX
                    |> Anim.withTransition (Anim.bezier 0.16 1 0.3 1)
                ]
            ]
            Ui.none
        )



-- AVATAR


type AvatarColor
    = AvatarAccent
    | AvatarNeutral
    | AvatarNeutralInversed
    | AvatarRed


{-| Circular avatar with initials.
-}
avatar : AvatarColor -> String -> Ui.Element msg
avatar color initials =
    let
        ( bgColor, textColor ) =
            case color of
                AvatarAccent ->
                    ( Theme.primary.tint, Theme.primary.accent )

                AvatarNeutral ->
                    ( Theme.base.tint, Theme.base.textSubtle )

                AvatarNeutralInversed ->
                    ( Theme.base.bgSubtle, Theme.base.textSubtle )

                AvatarRed ->
                    ( Theme.danger.tint, Theme.danger.accent )
    in
    Ui.el
        [ Ui.width (Ui.px Theme.sizing.lg)
        , Ui.height (Ui.px Theme.sizing.lg)
        , Ui.rounded Theme.radius.xxxl
        , Ui.background bgColor
        , Ui.Font.color textColor
        , Ui.Font.weight Theme.fontWeight.semibold
        , Ui.Font.size Theme.font.md
        , Ui.contentCenterX
        , Ui.contentCenterY
        ]
        (Ui.text initials)



-- EXPAND TRIGGER


{-| Collapsible section header with animated chevron.
-}
expandTrigger : { label : String, isOpen : Bool, onPress : msg } -> Ui.Element msg
expandTrigger config =
    Ui.row
        ([ Ui.Input.button config.onPress
         , Ui.width Ui.fill
         , Ui.pointer
         ]
            ++ sectionLabelAttrs
        )
        [ Ui.text (String.toUpper config.label)
        , Ui.el
            [ Ui.alignRight
            , Anim.transition (Anim.ms 300)
                [ Anim.rotation
                    (if config.isOpen then
                        0.5

                     else
                        0
                    )
                    |> Anim.withTransition (Anim.bezier 0.16 1 0.3 1)
                ]
            ]
            (featherIcon 18 FeatherIcons.chevronDown)
        ]


{-| Pill-shaped member toggle button with avatar and name.
Selected state uses primary colors, unselected uses neutral.
-}
toggleMemberBtn :
    { name : String
    , initials : String
    , selected : Bool
    , onPress : msg
    }
    -> Ui.Element msg
toggleMemberBtn config =
    let
        ( borderClr, backgroundColor, avatarColor ) =
            if config.selected then
                ( Theme.primary.solid, Theme.primary.bg, AvatarAccent )

            else
                ( Theme.base.solid, Theme.base.bg, AvatarNeutral )
    in
    Ui.row
        [ Ui.Input.button config.onPress
        , Ui.width Ui.shrink
        , Ui.paddingWith { top = 0, bottom = 0, left = 0, right = Theme.spacing.sm }
        , Ui.rounded Theme.radius.xxxl
        , Ui.border Theme.border
        , Ui.spacing Theme.spacing.sm
        , Ui.contentCenterY
        , Ui.pointer
        , Anim.transition (Anim.ms 200)
            [ Anim.borderColor borderClr
            , Anim.backgroundColor backgroundColor
            ]
        ]
        [ avatar avatarColor config.initials
        , Ui.el [ Ui.Font.weight Theme.fontWeight.medium ]
            (Ui.text config.name)
        ]



-- FILTER HELPERS


{-| Filter toggle button with active/inactive styling.
-}
filterToggleButton : { showFilters : Bool, hasActiveFilters : Bool, onPress : msg } -> Ui.Element msg
filterToggleButton config =
    let
        ( bg, border, fontColor ) =
            if config.showFilters || config.hasActiveFilters then
                ( Theme.primary.solid, Theme.primary.solid, Theme.primary.solidText )

            else
                ( Theme.base.bgSubtle, Theme.base.accent, Theme.base.textSubtle )
    in
    iconButton
        [ Ui.alignRight
        , Ui.border Theme.border
        , Anim.transition (Anim.ms 200)
            [ Anim.backgroundColor bg
            , Anim.borderColor border
            , Anim.fontColor fontColor
            ]
        ]
        { onPress = config.onPress, size = 18, icon = FeatherIcons.filter }


{-| Filter section with uppercase label and wrapped row of chips.
-}
filterSection : String -> List (Ui.Element msg) -> Ui.Element msg
filterSection label chips =
    Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm, Ui.paddingBottom Theme.spacing.md ]
        [ Ui.el
            [ Ui.Font.size Theme.font.xs
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.Font.letterSpacing Theme.letterSpacing.wide
            , Ui.Font.color Theme.base.textSubtle
            ]
            (Ui.text (String.toUpper label))
        , Ui.row [ Ui.wrap, Ui.spacing Theme.spacing.xs ] chips
        ]


{-| Read-only filter summary chip showing category and label.
-}
filterSummaryChip : String -> String -> Ui.Element msg
filterSummaryChip category label =
    Ui.row
        [ Ui.Font.size Theme.font.xs
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded Theme.radius.md
        , Ui.background Theme.primary.tint
        , Ui.width Ui.shrink
        , Ui.spacing Theme.spacing.xs
        ]
        [ Ui.el [ Ui.Font.color Theme.base.textSubtle ] (Ui.text (category ++ ":"))
        , Ui.el
            [ Ui.Font.color Theme.primary.text
            , Ui.Font.weight Theme.fontWeight.medium
            ]
            (Ui.text label)
        ]


{-| Clear all filters button.
-}
clearAllFiltersButton : I18n -> msg -> Ui.Element msg
clearAllFiltersButton i18n onPress =
    Ui.el
        [ Ui.Input.button onPress
        , Ui.width Ui.fill
        , Ui.paddingTop Theme.spacing.md
        , Ui.pointer
        ]
        (Ui.el
            [ Ui.padding Theme.spacing.sm
            , Ui.Font.size Theme.font.sm
            , Ui.Font.weight Theme.fontWeight.medium
            , Ui.Font.color Theme.danger.text
            , Ui.Font.center
            , Ui.width Ui.fill
            , Ui.rounded Theme.radius.sm
            ]
            (Ui.text (T.filterClearAll i18n))
        )



-- FAB


{-| Floating action button (circular, accent color, positioned bottom-right).
-}
fab : { label : String, href : String, onPress : msg } -> Ui.Element msg
fab config =
    Ui.el
        (spaLinkAttrs config.href config.onPress
            ++ [ Ui.width (Ui.px Theme.sizing.xl)
               , Ui.height (Ui.px Theme.sizing.xl)
               , Ui.rounded Theme.radius.lg
               , Ui.background Theme.primary.solid
               , Ui.Font.color Theme.primary.solidText
               , Theme.shadowAccent
               , Ui.alignRight
               , Ui.pointer
               , Ui.contentCenterX
               , Ui.contentCenterY
               ]
        )
        (featherIconColored "white" (toFloat Theme.sizing.sm) FeatherIcons.plus)



-- ICONS


{-| Render a Feather icon as a UI element at the given size.
-}
featherIcon : Float -> FeatherIcons.Icon -> Ui.Element msg
featherIcon size icon =
    icon
        |> FeatherIcons.withSize size
        |> FeatherIcons.toHtml []
        |> Ui.html


{-| Render a Feather icon with a custom stroke color.
-}
featherIconColored : String -> Float -> FeatherIcons.Icon -> Ui.Element msg
featherIconColored strokeColor size icon =
    icon
        |> FeatherIcons.withSize size
        |> FeatherIcons.toHtml [ Svg.Attributes.stroke strokeColor ]
        |> Ui.html



-- LANGUAGE SELECTOR


{-| Flag-based language selector. Active language is full opacity, others dimmed.
-}
languageSelector : (Language -> msg) -> Language -> Ui.Element msg
languageSelector onSwitch current =
    Ui.row [ Ui.spacing Theme.spacing.xs ]
        (List.map
            (\lang ->
                Ui.el
                    [ Ui.pointer
                    , Ui.Font.size Theme.font.lg
                    , Ui.Events.onClick (onSwitch lang)
                    , if lang == current then
                        Ui.opacity 1.0

                      else
                        Ui.opacity 0.5
                    ]
                    (Ui.text (languageFlag lang))
            )
            T.languages
        )


languageFlag : Language -> String
languageFlag lang =
    case lang of
        En ->
            "🇬🇧"

        Fr ->
            "🇫🇷"



-- PWA BANNERS


{-| PWA banners: offline indicator, update prompt, and install prompt.
-}
pwaBanners : I18n -> { isOnline : Bool, updateAvailable : Bool, installAvailable : Bool, onUpdate : msg, onInstall : msg, onDismissInstall : msg } -> Ui.Element msg
pwaBanners i18n config =
    let
        showIf : Bool -> a -> Maybe a
        showIf condition elem =
            if condition then
                Just elem

            else
                Nothing

        banners : List (Ui.Element msg)
        banners =
            List.filterMap identity <|
                [ showIf (not config.isOnline) <|
                    pwaBanner (T.pwaOffline i18n)
                        { bgColor = Theme.warning.tint
                        , textColor = Theme.warning.text
                        , action = Nothing
                        , dismiss = Nothing
                        }
                , showIf config.updateAvailable <|
                    pwaBanner (T.pwaUpdateAvailable i18n)
                        { bgColor = Theme.warning.tint
                        , textColor = Theme.warning.text
                        , action = Just ( T.pwaUpdateButton i18n, config.onUpdate )
                        , dismiss = Nothing
                        }
                , showIf config.installAvailable <|
                    pwaBanner (T.pwaInstallPrompt i18n)
                        { bgColor = Theme.warning.tint
                        , textColor = Theme.warning.text
                        , action = Just ( T.pwaInstallButton i18n, config.onInstall )
                        , dismiss = Just config.onDismissInstall
                        }
                ]
    in
    if List.isEmpty banners then
        Ui.none

    else
        Ui.column [ Ui.spacing Theme.spacing.md ] banners


pwaBanner :
    String
    ->
        { bgColor : Ui.Color
        , textColor : Ui.Color
        , action : Maybe ( String, msg )
        , dismiss : Maybe msg
        }
    -> Ui.Element msg
pwaBanner message { bgColor, textColor, action, dismiss } =
    Ui.row
        [ Ui.width Ui.fill
        , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        , Ui.background bgColor
        , Ui.spacing Theme.spacing.md
        , Ui.Font.size Theme.font.sm
        ]
        [ Ui.el [ Ui.Font.color textColor, Ui.width Ui.fill ] (Ui.text message)
        , case action of
            Just ( label, msg ) ->
                Ui.el
                    [ Ui.Input.button msg
                    , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
                    , Ui.rounded Theme.radius.sm
                    , Ui.background textColor
                    , Ui.Font.color Theme.primary.solidText
                    , Ui.Font.weight Theme.fontWeight.semibold
                    , Ui.pointer
                    , Ui.width Ui.shrink
                    ]
                    (Ui.text label)

            Nothing ->
                Ui.none
        , case dismiss of
            Just msg ->
                Ui.el
                    [ Ui.Input.button msg
                    , Ui.Font.size Theme.font.md
                    , Ui.Font.color Theme.base.textSubtle
                    , Ui.pointer
                    , Ui.alignRight
                    , Ui.height <| Ui.px Theme.sizing.md
                    , Ui.width <| Ui.px Theme.sizing.md
                    , Ui.contentCenterX
                    , Ui.contentCenterY
                    ]
                    (featherIcon 18 FeatherIcons.x)

            Nothing ->
                Ui.none
        ]


{-| Read-only banner displayed when the user is not a member of the group.
-}
readOnlyBanner : I18n -> Ui.Element msg
readOnlyBanner i18n =
    pwaBanner (T.readOnlyBanner i18n)
        { bgColor = Theme.warning.tint
        , textColor = Theme.warning.text
        , action = Nothing
        , dismiss = Nothing
        }
