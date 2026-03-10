module Page.DesignSystem exposing (Model, Msg, init, update, view)

{-| Design system showcase page.
Displays all visual tokens and component patterns used in the app.
-}

import Set exposing (Set)
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input
import Ui.Prose


type alias Model =
    { textInput : String
    , multilineInput : String
    , checkboxChecked : Bool
    , radioSelected : Maybe String
    , expandedSections : Set String
    , confirmingDelete : Bool
    }


type Msg
    = InputText String
    | InputMultiline String
    | ToggleCheckbox Bool
    | SelectRadio String
    | ToggleSection String
    | StartConfirmDelete
    | CancelConfirmDelete
    | NoOp


init : Model
init =
    { textInput = ""
    , multilineInput = ""
    , checkboxChecked = False
    , radioSelected = Nothing
    , expandedSections = Set.empty
    , confirmingDelete = False
    }


update : Msg -> Model -> Model
update msg model =
    case msg of
        InputText val ->
            { model | textInput = val }

        InputMultiline val ->
            { model | multilineInput = val }

        ToggleCheckbox val ->
            { model | checkboxChecked = val }

        SelectRadio val ->
            { model | radioSelected = Just val }

        ToggleSection key ->
            { model
                | expandedSections =
                    if Set.member key model.expandedSections then
                        Set.remove key model.expandedSections

                    else
                        Set.insert key model.expandedSections
            }

        StartConfirmDelete ->
            { model | confirmingDelete = True }

        CancelConfirmDelete ->
            { model | confirmingDelete = False }

        NoOp ->
            model


view : Model -> Ui.Element Msg
view model =
    Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ pageTitle
        , typographySection
        , colorSection
        , spacingSection
        , buttonSection
        , cardSection
        , formInputSection model
        , bannerSection
        , navigationSection
        , miscSection model
        ]



-- PAGE TITLE


pageTitle : Ui.Element msg
pageTitle =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.hero, Ui.Font.bold ] (Ui.text "Design System")
        , Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.neutral500 ]
            (Ui.text "Visual tokens and component patterns for Partage")
        ]



-- SECTION HELPER


sectionTitle : String -> Ui.Element msg
sectionTitle title =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text title)
        , divider
        ]


divider : Ui.Element msg
divider =
    Ui.el [ Ui.height (Ui.px 1), Ui.width Ui.fill, Ui.background Theme.neutral300 ] Ui.none


subsectionTitle : String -> Ui.Element msg
subsectionTitle title =
    Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold, Ui.Font.color Theme.neutral700 ] (Ui.text title)



-- 1. TYPOGRAPHY


typographySection : Ui.Element msg
typographySection =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Typography"
        , Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
            [ subsectionTitle "Scale"
            , typographySample "hero" Theme.fontSize.hero "The quick brown fox"
            , typographySample "xl" Theme.fontSize.xl "The quick brown fox"
            , typographySample "lg" Theme.fontSize.lg "The quick brown fox"
            , typographySample "md" Theme.fontSize.md "The quick brown fox"
            , typographySample "sm" Theme.fontSize.sm "The quick brown fox"
            ]
        , Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
            [ subsectionTitle "Styles"
            , Ui.row [ Ui.spacing Theme.spacing.lg ]
                [ Ui.el [ Ui.Font.bold ] (Ui.text "Bold")
                , Ui.el [ Ui.Font.italic ] (Ui.text "Italic")
                , Ui.el [ Ui.Font.underline ] (Ui.text "Underline")
                , Ui.el [ Ui.Font.strike ] (Ui.text "Strikethrough")
                ]
            ]
        , Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
            [ subsectionTitle "Colors"
            , Ui.row [ Ui.spacing Theme.spacing.lg, Ui.wrap ]
                [ Ui.el [ Ui.Font.color Theme.primary ] (Ui.text "Primary")
                , Ui.el [ Ui.Font.color Theme.success ] (Ui.text "Success")
                , Ui.el [ Ui.Font.color Theme.danger ] (Ui.text "Danger")
                , Ui.el [ Ui.Font.color Theme.warning ] (Ui.text "Warning")
                , Ui.el [ Ui.Font.color Theme.neutral700 ] (Ui.text "Neutral 700")
                , Ui.el [ Ui.Font.color Theme.neutral500 ] (Ui.text "Neutral 500")
                ]
            ]
        ]


typographySample : String -> Int -> String -> Ui.Element msg
typographySample label size sample =
    Ui.row [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el [ Ui.width (Ui.px 100), Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (label ++ " (" ++ String.fromInt size ++ "px)"))
        , Ui.el [ Ui.Font.size size ] (Ui.text sample)
        ]



-- 2. COLORS


colorSection : Ui.Element msg
colorSection =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Colors"
        , subsectionTitle "Brand & Semantic"
        , Ui.row [ Ui.spacing Theme.spacing.md, Ui.wrap ]
            [ colorSwatch "Primary" Theme.primary
            , colorSwatch "Primary Light" Theme.primaryLight
            , colorSwatch "Success" Theme.success
            , colorSwatch "Success Light" Theme.successLight
            , colorSwatch "Danger" Theme.danger
            , colorSwatch "Danger Light" Theme.dangerLight
            , colorSwatch "Warning" Theme.warning
            , colorSwatch "Warning Light" Theme.warningLight
            ]
        , subsectionTitle "Neutrals"
        , Ui.row [ Ui.spacing Theme.spacing.md, Ui.wrap ]
            [ colorSwatch "White" Theme.white
            , colorSwatch "Neutral 200" Theme.neutral200
            , colorSwatch "Neutral 300" Theme.neutral300
            , colorSwatch "Neutral 500" Theme.neutral500
            , colorSwatch "Neutral 700" Theme.neutral700
            ]
        ]


colorSwatch : String -> Ui.Color -> Ui.Element msg
colorSwatch label color =
    Ui.column [ Ui.spacing Theme.spacing.xs ]
        [ Ui.el
            [ Ui.width (Ui.px 64)
            , Ui.height (Ui.px 48)
            , Ui.background color
            , Ui.rounded Theme.rounding.sm
            , Ui.border Theme.borderWidth.sm
            , Ui.borderColor Theme.neutral300
            ]
            Ui.none
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral700 ] (Ui.text label)
        ]



-- 3. SPACING & LAYOUT


spacingSection : Ui.Element msg
spacingSection =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Spacing & Layout"
        , subsectionTitle "Spacing Scale"
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ spacingBar "xs" Theme.spacing.xs
            , spacingBar "sm" Theme.spacing.sm
            , spacingBar "md" Theme.spacing.md
            , spacingBar "lg" Theme.spacing.lg
            , spacingBar "xl" Theme.spacing.xl
            ]
        , subsectionTitle "Border Radius"
        , Ui.row [ Ui.spacing Theme.spacing.md ]
            [ Ui.column [ Ui.spacing Theme.spacing.xs ]
                [ Ui.el
                    [ Ui.width (Ui.px 64)
                    , Ui.height (Ui.px 48)
                    , Ui.background Theme.primaryLight
                    , Ui.rounded Theme.rounding.sm
                    , Ui.border Theme.borderWidth.sm
                    , Ui.borderColor Theme.primary
                    ]
                    Ui.none
                , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text "sm (6px)")
                ]
            , Ui.column [ Ui.spacing Theme.spacing.xs ]
                [ Ui.el
                    [ Ui.width (Ui.px 64)
                    , Ui.height (Ui.px 48)
                    , Ui.background Theme.primaryLight
                    , Ui.rounded Theme.rounding.md
                    , Ui.border Theme.borderWidth.sm
                    , Ui.borderColor Theme.primary
                    ]
                    Ui.none
                , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text "md (8px)")
                ]
            ]
        , subsectionTitle "Border Width"
        , Ui.row [ Ui.spacing Theme.spacing.md ]
            [ Ui.column [ Ui.spacing Theme.spacing.xs ]
                [ Ui.el
                    [ Ui.width (Ui.px 64)
                    , Ui.height (Ui.px 48)
                    , Ui.rounded Theme.rounding.sm
                    , Ui.border Theme.borderWidth.sm
                    , Ui.borderColor Theme.neutral700
                    ]
                    Ui.none
                , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text "sm (1px)")
                ]
            , Ui.column [ Ui.spacing Theme.spacing.xs ]
                [ Ui.el
                    [ Ui.width (Ui.px 64)
                    , Ui.height (Ui.px 48)
                    , Ui.rounded Theme.rounding.sm
                    , Ui.border Theme.borderWidth.md
                    , Ui.borderColor Theme.neutral700
                    ]
                    Ui.none
                , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text "md (2px)")
                ]
            ]
        , Ui.row [ Ui.spacing Theme.spacing.sm ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text "Content max width:")
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ] (Ui.text (String.fromInt Theme.contentMaxWidth ++ "px"))
            ]
        ]


spacingBar : String -> Int -> Ui.Element msg
spacingBar label size =
    Ui.row [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el [ Ui.width (Ui.px 60), Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text (label ++ " (" ++ String.fromInt size ++ ")"))
        , Ui.el
            [ Ui.width (Ui.px (size * 4))
            , Ui.height (Ui.px 16)
            , Ui.background Theme.primary
            , Ui.rounded Theme.rounding.sm
            ]
            Ui.none
        ]



-- 4. BUTTONS


buttonSection : Ui.Element msg
buttonSection =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Buttons"
        , Ui.row [ Ui.spacing Theme.spacing.md, Ui.wrap ]
            [ primaryButton "Primary"
            , secondaryButton "Secondary"
            , dangerButton "Danger"
            , disabledButton "Disabled"
            ]
        , Ui.row [ Ui.spacing Theme.spacing.md, Ui.wrap ]
            [ smallButton "Small Action"
            , textLinkButton "Text Link"
            ]
        ]


primaryButton : String -> Ui.Element msg
primaryButton label =
    Ui.el
        [ Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.bold
        , Ui.Font.size Theme.fontSize.md
        , Ui.rounded Theme.rounding.md
        , Ui.padding Theme.spacing.md
        , Ui.pointer
        ]
        (Ui.text label)


secondaryButton : String -> Ui.Element msg
secondaryButton label =
    Ui.el
        [ Ui.border Theme.borderWidth.md
        , Ui.borderColor Theme.neutral500
        , Ui.Font.color Theme.neutral700
        , Ui.Font.bold
        , Ui.Font.size Theme.fontSize.md
        , Ui.rounded Theme.rounding.md
        , Ui.padding Theme.spacing.md
        , Ui.pointer
        ]
        (Ui.text label)


dangerButton : String -> Ui.Element msg
dangerButton label =
    Ui.el
        [ Ui.background Theme.danger
        , Ui.Font.color Theme.white
        , Ui.Font.bold
        , Ui.Font.size Theme.fontSize.md
        , Ui.rounded Theme.rounding.md
        , Ui.padding Theme.spacing.md
        , Ui.pointer
        ]
        (Ui.text label)


disabledButton : String -> Ui.Element msg
disabledButton label =
    Ui.el
        [ Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.bold
        , Ui.Font.size Theme.fontSize.md
        , Ui.rounded Theme.rounding.md
        , Ui.padding Theme.spacing.md
        , Ui.opacity 0.5
        ]
        (Ui.text label)


smallButton : String -> Ui.Element msg
smallButton label =
    Ui.el
        [ Ui.background Theme.primary
        , Ui.Font.color Theme.white
        , Ui.Font.size Theme.fontSize.sm
        , Ui.rounded Theme.rounding.sm
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.pointer
        ]
        (Ui.text label)


textLinkButton : String -> Ui.Element msg
textLinkButton label =
    Ui.el
        [ Ui.Font.color Theme.primary
        , Ui.Font.size Theme.fontSize.sm
        , Ui.pointer
        ]
        (Ui.text label)



-- 5. CARDS


cardSection : Ui.Element msg
cardSection =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Cards"
        , subsectionTitle "Balance Cards"
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ balanceCardDemo "Alice (you)" "24.50" "is owed to you" Theme.successLight Theme.success True
            , balanceCardDemo "Bob" "12.75" "owes" Theme.dangerLight Theme.danger False
            , balanceCardDemo "Charlie" "0.00" "settled" Theme.neutral200 Theme.neutral500 False
            ]
        , subsectionTitle "Entry Card"
        , entryCardDemo
        , subsectionTitle "Member Row"
        , Ui.column [ Ui.width Ui.fill ]
            [ memberRowDemo "Alice (you)"
            , memberRowDemo "Bob"
            , memberRowDemoVirtual "Guest"
            ]
        , subsectionTitle "Settlement Row"
        , settlementRowDemo
        ]


balanceCardDemo : String -> String -> String -> Ui.Color -> Ui.Color -> Bool -> Ui.Element msg
balanceCardDemo name amount statusText bgColor fgColor showPayButton =
    Ui.column
        [ Ui.width Ui.fill
        , Ui.background bgColor
        , Ui.rounded Theme.rounding.md
        , Ui.padding Theme.spacing.md
        , Ui.spacing Theme.spacing.xs
        ]
        [ Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
            [ Ui.el [ Ui.Font.bold, Ui.Font.size Theme.fontSize.md ] (Ui.text name)
            , Ui.el [ Ui.alignRight, Ui.Font.color fgColor, Ui.Font.bold, Ui.Font.size Theme.fontSize.lg ]
                (Ui.text amount)
            ]
        , Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral700 ]
                (Ui.text statusText)
            , if showPayButton then
                Ui.el
                    [ Ui.alignRight
                    , Ui.Font.size Theme.fontSize.sm
                    , Ui.Font.color Theme.white
                    , Ui.background Theme.primary
                    , Ui.rounded Theme.rounding.sm
                    , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
                    , Ui.pointer
                    ]
                    (Ui.text "Pay Them")

              else
                Ui.none
            ]
        ]


entryCardDemo : Ui.Element msg
entryCardDemo =
    Ui.column [ Ui.width Ui.fill ]
        [ Ui.row
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.md
            , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
            , Ui.borderColor Theme.neutral200
            , Ui.spacing Theme.spacing.md
            , Ui.pointer
            ]
            [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                [ Ui.el [ Ui.Font.bold ] (Ui.text "Dinner at Chez Marcel")
                , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text "Paid by Alice")
                ]
            , Ui.el [ Ui.alignRight, Ui.Font.bold ] (Ui.text "45.00 EUR")
            ]
        , Ui.row
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.md
            , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
            , Ui.borderColor Theme.neutral200
            , Ui.spacing Theme.spacing.md
            , Ui.pointer
            ]
            [ Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.xs ]
                [ Ui.el [ Ui.Font.bold ] (Ui.text "Transfer")
                , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text "Bob -> Alice")
                ]
            , Ui.el [ Ui.alignRight, Ui.Font.bold ] (Ui.text "15.00 EUR")
            ]
        ]


memberRowDemo : String -> Ui.Element msg
memberRowDemo name =
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
        , Ui.borderColor Theme.neutral200
        , Ui.spacing Theme.spacing.sm
        , Ui.pointer
        ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text name) ]


memberRowDemoVirtual : String -> Ui.Element msg
memberRowDemoVirtual name =
    Ui.row
        [ Ui.width Ui.fill
        , Ui.padding Theme.spacing.md
        , Ui.borderWith { bottom = Theme.borderWidth.sm, top = 0, left = 0, right = 0 }
        , Ui.borderColor Theme.neutral200
        , Ui.spacing Theme.spacing.sm
        , Ui.pointer
        ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text name)
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text "virtual")
        ]


settlementRowDemo : Ui.Element msg
settlementRowDemo =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ Ui.row
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.spacing Theme.spacing.sm
            , Ui.background Theme.primaryLight
            , Ui.rounded Theme.rounding.sm
            ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm ] (Ui.text "Bob")
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text "pays")
            , Ui.el [ Ui.Font.size Theme.fontSize.sm ] (Ui.text "Alice")
            , Ui.el [ Ui.alignRight, Ui.Font.bold, Ui.Font.size Theme.fontSize.sm ] (Ui.text "12.75")
            , Ui.el
                [ Ui.Font.size Theme.fontSize.sm
                , Ui.Font.color Theme.white
                , Ui.background Theme.primary
                , Ui.rounded Theme.rounding.sm
                , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
                , Ui.pointer
                ]
                (Ui.text "Mark as Paid")
            ]
        , Ui.row
            [ Ui.width Ui.fill
            , Ui.padding Theme.spacing.sm
            , Ui.spacing Theme.spacing.sm
            , Ui.background Theme.neutral200
            , Ui.rounded Theme.rounding.sm
            ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm ] (Ui.text "Charlie")
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text "pays")
            , Ui.el [ Ui.Font.size Theme.fontSize.sm ] (Ui.text "Alice")
            , Ui.el [ Ui.alignRight, Ui.Font.bold, Ui.Font.size Theme.fontSize.sm ] (Ui.text "11.75")
            , Ui.el
                [ Ui.Font.size Theme.fontSize.sm
                , Ui.Font.color Theme.white
                , Ui.background Theme.primary
                , Ui.rounded Theme.rounding.sm
                , Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
                , Ui.pointer
                ]
                (Ui.text "Mark as Paid")
            ]
        ]



-- 6. FORM INPUTS


formInputSection : Model -> Ui.Element Msg
formInputSection model =
    let
        textLabel =
            Ui.Input.label "ds-text-input" [] (Ui.text "Text Input")

        multilineLabel =
            Ui.Input.label "ds-multiline-input" [] (Ui.text "Multiline Input")

        checkboxLabel =
            Ui.Input.label "ds-checkbox" [] (Ui.text "Enable notifications")

        radioLabel =
            Ui.Input.label "ds-radio" [] (Ui.text "Choose an option")
    in
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Form Inputs"
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ textLabel.element
            , Ui.Input.text
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.sm
                , Ui.rounded Theme.rounding.sm
                , Ui.border Theme.borderWidth.sm
                , Ui.borderColor Theme.neutral300
                ]
                { onChange = InputText
                , text = model.textInput
                , placeholder = Just "Enter something..."
                , label = textLabel.id
                }
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                (Ui.text "Helper text goes here")
            ]
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ multilineLabel.element
            , Ui.Input.multiline
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.sm
                , Ui.rounded Theme.rounding.sm
                , Ui.border Theme.borderWidth.sm
                , Ui.borderColor Theme.neutral300
                , Ui.height (Ui.px 80)
                ]
                { onChange = InputMultiline
                , text = model.multilineInput
                , placeholder = Just "Write notes..."
                , label = multilineLabel.id
                , spellcheck = False
                }
            ]
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ subsectionTitle "Checkbox"
            , Ui.Input.checkbox []
                { onChange = ToggleCheckbox
                , icon = Nothing
                , checked = model.checkboxChecked
                , label = checkboxLabel.id
                }
            , checkboxLabel.element
            ]
        , Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ subsectionTitle "Radio / Choose One"
            , radioLabel.element
            , Ui.Input.chooseOne Ui.column
                [ Ui.spacing Theme.spacing.sm ]
                { onChange = SelectRadio
                , selected = model.radioSelected
                , label = radioLabel.id
                , options =
                    [ Ui.Input.option "share" (Ui.text "Split by shares")
                    , Ui.Input.option "exact" (Ui.text "Split by exact amounts")
                    , Ui.Input.option "equal" (Ui.text "Split equally")
                    ]
                }
            ]
        , subsectionTitle "Error State"
        , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
            [ Ui.Input.text
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.sm
                , Ui.rounded Theme.rounding.sm
                , Ui.border Theme.borderWidth.sm
                , Ui.borderColor Theme.danger
                ]
                { onChange = \_ -> NoOp
                , text = ""
                , placeholder = Just "Required field"
                , label = Ui.Input.labelHidden "error-demo"
                }
            , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                (Ui.text "This field is required")
            ]
        ]



-- 7. BANNERS & TOASTS


bannerSection : Ui.Element msg
bannerSection =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Banners & Toasts"
        , subsectionTitle "Banners"
        , bannerDemo Theme.warningLight Theme.warning "You are currently offline" Nothing
        , bannerDemo Theme.primaryLight Theme.primary "A new version is available" (Just "Update")
        , bannerDemo Theme.primaryLight Theme.primary "Install Partage for the best experience" (Just "Install")
        , subsectionTitle "Toasts"
        , toastDemo Theme.successLight Theme.success "Group created successfully"
        , toastDemo Theme.dangerLight Theme.danger "Failed to save entry. Please try again."
        ]


bannerDemo : Ui.Color -> Ui.Color -> String -> Maybe String -> Ui.Element msg
bannerDemo bgColor textColor message action =
    Ui.row
        [ Ui.width Ui.fill
        , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        , Ui.background bgColor
        , Ui.spacing Theme.spacing.md
        , Ui.rounded Theme.rounding.sm
        ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color textColor, Ui.width Ui.fill ] (Ui.text message)
        , case action of
            Just label ->
                Ui.el
                    [ Ui.paddingXY Theme.spacing.md Theme.spacing.xs
                    , Ui.rounded Theme.rounding.sm
                    , Ui.background textColor
                    , Ui.Font.color Theme.white
                    , Ui.Font.size Theme.fontSize.sm
                    , Ui.Font.bold
                    , Ui.pointer
                    ]
                    (Ui.text label)

            Nothing ->
                Ui.none
        ]


toastDemo : Ui.Color -> Ui.Color -> String -> Ui.Element msg
toastDemo bgColor textColor message =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
        , Ui.background bgColor
        , Ui.rounded Theme.rounding.md
        , Ui.border Theme.borderWidth.sm
        , Ui.borderColor textColor
        ]
        (Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color textColor ] (Ui.text message))



-- 8. NAVIGATION


navigationSection : Ui.Element msg
navigationSection =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Navigation"
        , subsectionTitle "Header"
        , Ui.el
            [ Ui.width Ui.fill
            , Ui.background Theme.primary
            , Ui.paddingXY Theme.spacing.md Theme.spacing.sm
            , Ui.rounded Theme.rounding.sm
            ]
            (Ui.row [ Ui.width Ui.fill ]
                [ Ui.el
                    [ Ui.Font.color Theme.white
                    , Ui.Font.size Theme.fontSize.xl
                    , Ui.Font.bold
                    ]
                    (Ui.text "Partage")
                , Ui.el [ Ui.alignRight, Ui.Font.color Theme.white, Ui.Font.size Theme.fontSize.lg ]
                    (Ui.text "EN")
                ]
            )
        , subsectionTitle "Tab Bar"
        , Ui.row
            [ Ui.width Ui.fill
            , Ui.borderWith { top = Theme.borderWidth.sm, bottom = 0, left = 0, right = 0 }
            , Ui.borderColor Theme.neutral200
            , Ui.rounded Theme.rounding.sm
            ]
            [ tabDemo "Balance" True
            , tabDemo "Entries" False
            , tabDemo "Members" False
            , tabDemo "Activity" False
            ]
        , subsectionTitle "Language Selector"
        , Ui.row [ Ui.spacing Theme.spacing.xs ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.opacity 1.0 ] (Ui.text "\u{1F1EC}\u{1F1E7}")
            , Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.opacity 0.5 ] (Ui.text "\u{1F1EB}\u{1F1F7}")
            ]
        ]


tabDemo : String -> Bool -> Ui.Element msg
tabDemo label isActive =
    Ui.el
        [ Ui.width Ui.fill
        , Ui.paddingXY Theme.spacing.sm Theme.spacing.sm
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



-- 9. MISCELLANEOUS


miscSection : Model -> Ui.Element Msg
miscSection model =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ sectionTitle "Miscellaneous"
        , subsectionTitle "Badges & Tags"
        , Ui.row [ Ui.spacing Theme.spacing.sm, Ui.wrap ]
            [ badge Theme.primaryLight Theme.primary "virtual"
            , badge Theme.successLight Theme.success "settled"
            , badge Theme.dangerLight Theme.danger "overdue"
            , badge Theme.warningLight Theme.warning "pending"
            ]
        , subsectionTitle "Expandable Section"
        , expandableDemo model
        , subsectionTitle "Two-Stage Confirmation"
        , twoStageConfirmDemo model
        , subsectionTitle "Divider"
        , divider
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text "A 1px horizontal line using neutral300")
        , subsectionTitle "Empty State"
        , emptyStateDemo
        ]


badge : Ui.Color -> Ui.Color -> String -> Ui.Element msg
badge bgColor textColor label =
    Ui.el
        [ Ui.paddingXY Theme.spacing.sm Theme.spacing.xs
        , Ui.rounded Theme.rounding.sm
        , Ui.background bgColor
        , Ui.Font.color textColor
        , Ui.Font.size Theme.fontSize.sm
        ]
        (Ui.text label)


expandableDemo : Model -> Ui.Element Msg
expandableDemo model =
    let
        isExpanded =
            Set.member "demo" model.expandedSections

        arrow =
            if isExpanded then
                "v "

            else
                "> "
    in
    Ui.column [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
        [ Ui.row
            [ Ui.width Ui.fill
            , Ui.pointer
            , Ui.Events.onClick (ToggleSection "demo")
            , Ui.padding Theme.spacing.sm
            , Ui.background Theme.neutral200
            , Ui.rounded Theme.rounding.sm
            , Ui.spacing Theme.spacing.sm
            ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text arrow)
            , Ui.el [ Ui.Font.size Theme.fontSize.md, Ui.Font.bold ] (Ui.text "Settlement Preferences")
            ]
        , if isExpanded then
            Ui.column
                [ Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.background Theme.neutral200
                , Ui.rounded Theme.rounding.sm
                , Ui.spacing Theme.spacing.sm
                ]
                [ Ui.el [ Ui.Font.size Theme.fontSize.sm ] (Ui.text "Choose who you prefer to receive payments from.")
                , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text "This helps optimize the settlement plan.")
                ]

          else
            Ui.none
        ]


twoStageConfirmDemo : Model -> Ui.Element Msg
twoStageConfirmDemo model =
    if model.confirmingDelete then
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                (Ui.text "Are you sure? This action cannot be undone.")
            , Ui.row [ Ui.spacing Theme.spacing.sm ]
                [ Ui.el
                    [ Ui.background Theme.danger
                    , Ui.Font.color Theme.white
                    , Ui.Font.bold
                    , Ui.Font.size Theme.fontSize.md
                    , Ui.rounded Theme.rounding.md
                    , Ui.padding Theme.spacing.md
                    , Ui.pointer
                    , Ui.Events.onClick CancelConfirmDelete
                    ]
                    (Ui.text "Confirm Delete")
                , Ui.el
                    [ Ui.border Theme.borderWidth.md
                    , Ui.borderColor Theme.neutral500
                    , Ui.Font.color Theme.neutral700
                    , Ui.Font.size Theme.fontSize.md
                    , Ui.rounded Theme.rounding.md
                    , Ui.padding Theme.spacing.md
                    , Ui.pointer
                    , Ui.Events.onClick CancelConfirmDelete
                    ]
                    (Ui.text "Cancel")
                ]
            ]

    else
        Ui.el
            [ Ui.border Theme.borderWidth.md
            , Ui.borderColor Theme.danger
            , Ui.Font.color Theme.danger
            , Ui.Font.bold
            , Ui.Font.size Theme.fontSize.md
            , Ui.rounded Theme.rounding.md
            , Ui.padding Theme.spacing.md
            , Ui.pointer
            , Ui.Events.onClick StartConfirmDelete
            ]
            (Ui.text "Delete Group")


emptyStateDemo : Ui.Element msg
emptyStateDemo =
    Ui.column
        [ Ui.width Ui.fill
        , Ui.paddingXY 0 Theme.spacing.xl
        , Ui.spacing Theme.spacing.sm
        ]
        [ Ui.el [ Ui.centerX, Ui.Font.size Theme.fontSize.lg, Ui.Font.color Theme.neutral500 ]
            (Ui.text "No entries yet")
        , Ui.el [ Ui.centerX, Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
            (Ui.text "Add your first expense to get started")
        ]
