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
            , featureRow FeatherIcons.wifiOff (T.welcomeFeatureLocalFirst i18n)
            , featureRow FeatherIcons.refreshCw (T.welcomeFeatureGroupSharing i18n)
            , featureRow FeatherIcons.heart (T.welcomeFeatureOpenSource i18n)
            ]
        ]


featureRow : FeatherIcons.Icon -> String -> Ui.Element msg
featureRow icon label =
    Ui.row [ Ui.spacing Theme.spacing.md, Ui.contentCenterY ]
        [ Ui.el [ Ui.Font.color Theme.primary.solid, Ui.width Ui.shrink ] (UI.Components.featherIcon 20 icon)
        , Ui.el [ Ui.Font.size Theme.font.sm ] (Ui.text label)
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
