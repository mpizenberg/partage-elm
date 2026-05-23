module Page.Welcome exposing (fundingUrl, view)

import FeatherIcons
import Route exposing (Route)
import Translations as T exposing (I18n, Language)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


{-| Placeholder funding link until the actual sponsorship platform is set up.
-}
fundingUrl : String
fundingUrl =
    "https://github.com/sponsors/mpizenberg"


view :
    I18n
    ->
        { onGenerate : msg
        , onSwitchLanguage : Language -> msg
        , onNavigate : Route -> msg
        , isGenerating : Bool
        , hasIdentity : Bool
        }
    -> Ui.Element msg
view i18n config =
    Ui.column [ Ui.spacing Theme.spacing.xxl, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.xl ]
        [ heroSection i18n
        , primaryCta i18n config
        , languageSection i18n config.onSwitchLanguage
        , whySection i18n
        , featuresSection i18n
        , screenshotsSection i18n
        , detailsSection i18n
        , howItWorksSection i18n
        , fundingSection i18n
        , if config.hasIdentity then
            aboutFooterLink i18n config.onNavigate

          else
            Ui.none
        ]



-- HERO


heroSection : I18n -> Ui.Element msg
heroSection i18n =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill, Ui.contentCenterX ]
        [ Ui.el [ Ui.centerX ] (UI.Components.appLogo 96)
        , Ui.el
            [ Ui.Font.size Theme.font.xxxl
            , Ui.Font.weight Theme.fontWeight.bold
            , Ui.Font.letterSpacing Theme.letterSpacing.tight
            , Ui.centerX
            ]
            (Ui.text (T.welcomeHeading i18n))
        , Ui.el
            [ Ui.Font.size Theme.font.md
            , Ui.Font.color Theme.base.textSubtle
            , Ui.centerX
            , Ui.Font.center
            ]
            (Ui.text (T.welcomeTagline i18n))
        ]



-- PRIMARY CTA


primaryCta :
    I18n
    ->
        { a
            | onGenerate : msg
            , onNavigate : Route -> msg
            , isGenerating : Bool
            , hasIdentity : Bool
        }
    -> Ui.Element msg
primaryCta i18n config =
    if config.isGenerating then
        Ui.el
            [ Ui.centerX
            , Ui.Font.size Theme.font.md
            , Ui.Font.color Theme.base.textSubtle
            , Ui.Font.weight Theme.fontWeight.medium
            ]
            (Ui.text (T.welcomeGenerating i18n))

    else if config.hasIdentity then
        UI.Components.btnPrimary []
            { label = T.welcomeOpenMyGroups i18n
            , onPress = config.onNavigate Route.Home
            }

    else
        UI.Components.btnPrimary []
            { label = T.welcomeGenerateButton i18n
            , onPress = config.onGenerate
            }



-- WHY


whySection : I18n -> Ui.Element msg
whySection i18n =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.welcomeWhyTitle i18n)
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.text
                ]
                (Ui.text (T.welcomeWhyBody i18n))
            ]
        ]



-- FEATURES


featuresSection : I18n -> Ui.Element msg
featuresSection i18n =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.welcomeFeaturesTitle i18n)
        , Ui.column [ Ui.spacing Theme.spacing.md, Ui.centerX ]
            [ featureRow FeatherIcons.lock (T.welcomeFeatureEncrypted i18n)
            , featureRow FeatherIcons.key (T.welcomeFeatureNoAccount i18n)
            , featureRow FeatherIcons.wifiOff (T.welcomeFeatureLocalFirst i18n)
            , featureRow FeatherIcons.gitMerge (T.welcomeFeatureSettleUp i18n)
            , featureRow FeatherIcons.globe (T.welcomeFeatureMultiCurrency i18n)
            , featureRow FeatherIcons.clock (T.welcomeFeatureActivityLog i18n)
            , featureRow FeatherIcons.smartphone (T.welcomeFeatureInstallable i18n)
            , featureRow FeatherIcons.heart (T.welcomeFeatureOpenSource i18n)
            ]
        ]


featureRow : FeatherIcons.Icon -> String -> Ui.Element msg
featureRow icon label =
    Ui.row [ Ui.spacing Theme.spacing.md, Ui.contentCenterY ]
        [ Ui.el [ Ui.Font.color Theme.primary.solid, Ui.width Ui.shrink ] (UI.Components.featherIcon 20 icon)
        , Ui.el [ Ui.Font.size Theme.font.sm ] (Ui.text label)
        ]



-- SCREENSHOTS


screenshotsSection : I18n -> Ui.Element msg
screenshotsSection i18n =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.welcomeScreenshotsTitle i18n)
        , Ui.column [ Ui.spacing Theme.spacing.xl, Ui.width Ui.fill, Ui.contentCenterX ]
            [ screenshot i18n "https://github.com/user-attachments/assets/11f892b5-6a9c-4495-98b3-aaa99fd86a96" (T.welcomeScreenshotBalance i18n)
            , screenshot i18n "https://github.com/user-attachments/assets/e18a1a55-d3be-49ec-a5b1-b74f40e82b27" (T.welcomeScreenshotMultiCurrency i18n)
            , screenshot i18n "https://github.com/user-attachments/assets/1338983d-4acb-41c5-9a74-cf2eef77d298" (T.welcomeScreenshotActivity i18n)
            , screenshot i18n "https://github.com/user-attachments/assets/a9a57610-83a7-4c55-9641-700fb32a3699" (T.welcomeScreenshotInvite i18n)
            ]
        ]


screenshot : I18n -> String -> String -> Ui.Element msg
screenshot i18n source caption =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.centerX, Ui.width (Ui.px 280) ]
        [ Ui.imageWithFallback
            [ Ui.width (Ui.px 280)
            , Ui.height (Ui.px 623)
            , Ui.rounded Theme.spacing.sm
            , Ui.border 1
            , Ui.borderColor Theme.base.accent
            ]
            { source = source
            , fallback = screenshotPlaceholder i18n caption
            }
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.textSubtle
            , Ui.Font.center
            , Ui.centerX
            ]
            (Ui.text caption)
        ]


screenshotPlaceholder : I18n -> String -> Ui.Element msg
screenshotPlaceholder i18n caption =
    Ui.column
        [ Ui.width Ui.fill
        , Ui.height Ui.fill
        , Ui.contentCenterX
        , Ui.contentCenterY
        , Ui.spacing Theme.spacing.sm
        , Ui.background Theme.base.bgSubtle
        ]
        [ Ui.el [ Ui.Font.color Theme.base.textSubtle, Ui.centerX ]
            (UI.Components.featherIcon 32 FeatherIcons.image)
        , Ui.el
            [ Ui.Font.size Theme.font.xs
            , Ui.Font.color Theme.base.textSubtle
            , Ui.Font.center
            , Ui.centerX
            , Ui.paddingXY Theme.spacing.sm 0
            ]
            (Ui.text caption)
        , Ui.el
            [ Ui.Font.size Theme.font.xs
            , Ui.Font.color Theme.base.textSubtle
            , Ui.Font.center
            , Ui.centerX
            ]
            (Ui.text ("(" ++ T.welcomeScreenshotPending i18n ++ ")"))
        ]



-- DETAILS THAT MATTER


detailsSection : I18n -> Ui.Element msg
detailsSection i18n =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.welcomeDetailsTitle i18n)
        , Ui.column [ Ui.spacing Theme.spacing.md, Ui.centerX ]
            [ featureRow FeatherIcons.filter (T.welcomeDetailFilter i18n)
            , featureRow FeatherIcons.download (T.welcomeDetailBackup i18n)
            , featureRow FeatherIcons.creditCard (T.welcomeDetailPaymentMethods i18n)
            , featureRow FeatherIcons.users (T.welcomeDetailMembers i18n)
            , featureRow FeatherIcons.trendingUp (T.welcomeDetailEntryTypes i18n)
            , featureRow FeatherIcons.rotateCcw (T.welcomeDetailHistory i18n)
            , featureRow FeatherIcons.userCheck (T.welcomeDetailPreferences i18n)
            , featureRow FeatherIcons.gift (T.welcomeDetailNoLimits i18n)
            ]
        ]



-- HOW IT WORKS


howItWorksSection : I18n -> Ui.Element msg
howItWorksSection i18n =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.welcomeHowItWorksTitle i18n)
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.el
                [ Ui.Font.size Theme.font.sm
                , Ui.Font.color Theme.base.text
                ]
                (Ui.text (T.welcomeHowItWorks i18n))
            ]
        ]



-- FUNDING


fundingSection : I18n -> Ui.Element msg
fundingSection i18n =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.welcomeFundingTitle i18n)
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                [ Ui.el
                    [ Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.base.text
                    ]
                    (Ui.text (T.welcomeFundingBody i18n))
                , Ui.row
                    [ Ui.centerX
                    , Ui.spacing Theme.spacing.xs
                    , Ui.Font.size Theme.font.sm
                    , Ui.Font.weight Theme.fontWeight.semibold
                    , Ui.Font.color Theme.primary.text
                    , Ui.contentCenterY
                    , Ui.linkNewTab fundingUrl
                    , Ui.pointer
                    ]
                    [ UI.Components.featherIcon 16 FeatherIcons.heart
                    , Ui.text (T.welcomeFundingCta i18n)
                    ]
                ]
            ]
        ]



-- LANGUAGE


languageSection : I18n -> (Language -> msg) -> Ui.Element msg
languageSection i18n onSwitchLanguage =
    Ui.el [ Ui.centerX ]
        (UI.Components.languageSelector onSwitchLanguage (T.currentLanguage i18n))



-- ABOUT FOOTER LINK


aboutFooterLink : I18n -> (Route -> msg) -> Ui.Element msg
aboutFooterLink i18n onNavigate =
    Ui.el
        ([ Ui.centerX
         , Ui.Font.size Theme.font.sm
         , Ui.Font.color Theme.primary.text
         , Ui.pointer
         ]
            ++ UI.Components.spaLinkAttrs (Route.toPath Route.About) (onNavigate Route.About)
        )
        (Ui.text (T.welcomeAboutLink i18n))
