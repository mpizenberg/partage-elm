module Page.About exposing (Model, Msg, Output(..), init, statsLoaded, update, view)

import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Font
import Ui.Input
import UsageStats exposing (CostBreakdown)


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


view : I18n -> Model -> Ui.Element Msg
view i18n model =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill, Ui.paddingXY 0 Theme.spacing.md ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.aboutTitle i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral700 ]
            (Ui.text (T.aboutDescription i18n))
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral700 ]
            (Ui.text (T.aboutPrivacy i18n))
        , usageSection i18n model
        ]


usageSection : I18n -> Model -> Ui.Element Msg
usageSection i18n model =
    Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
        [ Ui.el
            [ Ui.height (Ui.px Theme.borderWidth.sm)
            , Ui.width Ui.fill
            , Ui.background Theme.neutral300
            ]
            Ui.none
        , Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ]
            (Ui.text (T.aboutUsageTitle i18n))
        , case model of
            Loading ->
                Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
                    (Ui.text (T.aboutUsageLoading i18n))

            Loaded { breakdown, trackingSince, confirmingReset } ->
                Ui.column [ Ui.spacing Theme.spacing.md, Ui.width Ui.fill ]
                    [ costTable i18n breakdown
                    , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ]
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
        , Ui.el
            [ Ui.height (Ui.px Theme.borderWidth.sm)
            , Ui.width Ui.fill
            , Ui.background Theme.neutral200
            ]
            Ui.none
        , costRow (T.aboutCostTotal i18n) (UsageStats.formatDollars breakdown.totalCostCents)
        , if breakdown.monthsTracked >= 10 / 30.44 then
            costRow (T.aboutCostAvgPerMonth i18n) (UsageStats.formatDollars breakdown.avgPerMonthCents)

          else
            Ui.none
        ]


costRow : String -> String -> Ui.Element msg
costRow label value =
    Ui.row [ Ui.width Ui.fill, Ui.spacing Theme.spacing.sm ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral700 ] (Ui.text label)
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold, Ui.alignRight ] (Ui.text value)
        ]


resetSection : I18n -> Bool -> Ui.Element Msg
resetSection i18n confirmingReset =
    if confirmingReset then
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.danger ]
                (Ui.text (T.aboutResetConfirm i18n))
            , Ui.el
                [ Ui.Input.button ConfirmReset
                , Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.rounding.md
                , Ui.background Theme.danger
                , Ui.Font.color Theme.white
                , Ui.Font.center
                , Ui.Font.bold
                , Ui.pointer
                ]
                (Ui.text (T.aboutResetStats i18n))
            ]

    else
        Ui.el
            [ Ui.Input.button ToggleResetConfirm
            , Ui.width Ui.fill
            , Ui.padding Theme.spacing.md
            , Ui.rounded Theme.rounding.md
            , Ui.border Theme.borderWidth.md
            , Ui.borderColor Theme.neutral500
            , Ui.Font.color Theme.neutral700
            , Ui.Font.center
            , Ui.Font.bold
            , Ui.pointer
            ]
            (Ui.text (T.aboutResetStats i18n))
