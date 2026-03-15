module Page.About exposing (Model, Msg, Output(..), init, statsLoaded, update, view)

import FeatherIcons
import Infra.UsageStats as UsageStats exposing (CostBreakdown)
import Translations as T exposing (I18n, Language)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Font


type Model
    = Loading
    | Loaded
        { breakdown : CostBreakdown
        , trackingSince : String
        , confirmingReset : Bool
        }


type Msg
    = StatsLoaded CostBreakdown String
    | ToggleResetConfirm
    | ConfirmReset


type Output
    = RequestResetStats


init : Model
init =
    Loading


statsLoaded : CostBreakdown -> String -> Msg
statsLoaded =
    StatsLoaded


update : Msg -> Model -> ( Model, Maybe Output )
update msg model =
    case msg of
        StatsLoaded breakdown trackingSince ->
            ( Loaded
                { breakdown = breakdown
                , trackingSince = trackingSince
                , confirmingReset = False
                }
            , Nothing
            )

        ToggleResetConfirm ->
            case model of
                Loaded data ->
                    ( Loaded { data | confirmingReset = not data.confirmingReset }, Nothing )

                _ ->
                    ( model, Nothing )

        ConfirmReset ->
            ( model, Just RequestResetStats )


view : I18n -> { onSwitchLanguage : Language -> msg, toMsg : Msg -> msg } -> Model -> Ui.Element msg
view i18n config model =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ Ui.el
            [ Ui.Font.size Theme.font.xl
            , Ui.Font.weight Theme.fontWeight.bold
            ]
            (Ui.text (T.aboutTitle i18n))
        , UI.Components.card [ Ui.padding Theme.spacing.lg ]
            [ Ui.column [ Ui.spacing Theme.spacing.md ]
                [ Ui.el
                    [ Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.base.text
                    ]
                    (Ui.text (T.aboutDescription i18n))
                , Ui.el
                    [ Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.base.textSubtle
                    ]
                    (Ui.text (T.aboutPrivacy i18n))
                ]
            ]
        , languageSection i18n config.onSwitchLanguage
        , Ui.map config.toMsg (usageSection i18n model)
        ]


languageSection : I18n -> (Language -> msg) -> Ui.Element msg
languageSection i18n onSwitchLanguage =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.aboutLanguageTitle i18n)
        , UI.Components.languageSelector onSwitchLanguage (T.currentLanguage i18n)
        ]


usageSection : I18n -> Model -> Ui.Element Msg
usageSection i18n model =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ UI.Components.sectionLabel (T.aboutUsageTitle i18n)
        , case model of
            Loading ->
                Ui.el [ Ui.Font.size Theme.font.sm, Ui.Font.color Theme.base.textSubtle ]
                    (Ui.text (T.aboutUsageLoading i18n))

            Loaded { breakdown, trackingSince, confirmingReset } ->
                Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                    [ UI.Components.card [ Ui.padding Theme.spacing.lg ]
                        [ costTable i18n breakdown ]
                    , Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.color Theme.base.textSubtle
                        ]
                        (Ui.text (T.aboutUsageTrackingSince trackingSince i18n))
                    , resetSection i18n confirmingReset
                    ]
        ]


costTable : I18n -> CostBreakdown -> Ui.Element msg
costTable i18n breakdown =
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ costRow (T.aboutCostBase i18n) (UsageStats.formatDollars breakdown.baseCostCents)
        , costRow (T.aboutCostStorage i18n) (UsageStats.formatDollars breakdown.storageCostCents)
        , costRow (T.aboutCostCompute i18n) (UsageStats.formatDollars breakdown.computeCostCents)
        , costRow (T.aboutCostNetwork i18n) (UsageStats.formatDollars breakdown.networkCostCents)
        , UI.Components.horizontalSeparator
        , costRow (T.aboutCostTotal i18n) (UsageStats.formatDollars breakdown.totalCostCents)
        , if breakdown.monthsTracked >= 10 / 30.44 then
            costRow (T.aboutCostAvgPerMonth i18n) (UsageStats.formatDollars breakdown.avgPerMonthCents)

          else
            Ui.none
        ]


costRow : String -> String -> Ui.Element msg
costRow label value =
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
        [ Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.color Theme.base.text
            ]
            (Ui.text label)
        , Ui.el
            [ Ui.Font.size Theme.font.sm
            , Ui.Font.weight Theme.fontWeight.semibold
            , Ui.alignRight
            ]
            (Ui.text value)
        ]


resetSection : I18n -> Bool -> Ui.Element Msg
resetSection i18n confirmingReset =
    if confirmingReset then
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ UI.Components.card [ Ui.padding Theme.spacing.md ]
                [ Ui.el
                    [ Ui.Font.size Theme.font.sm
                    , Ui.Font.color Theme.danger.text
                    ]
                    (Ui.text (T.aboutResetConfirm i18n))
                ]
            , UI.Components.btnDanger []
                { label = T.aboutResetStats i18n
                , icon = FeatherIcons.trash2
                , onPress = ConfirmReset
                }
            ]

    else
        UI.Components.btnOutline []
            { label = T.aboutResetStats i18n
            , icon = Nothing
            , onPress = ToggleResetConfirm
            }
