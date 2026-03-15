module Page.Group.NewEntry.TransferView exposing (transferFields)

{-| Transfer-specific view functions for the new entry form.
-}

import Domain.Member as Member
import FeatherIcons
import Field
import Form
import Format
import List.Extra
import Page.Group.NewEntry.Shared as Shared exposing (ModelData, Msg(..))
import Translations as T exposing (I18n)
import UI.Components
import UI.Theme as Theme
import Ui
import Ui.Anim as Anim
import Ui.Font
import Ui.Input


transferFields : I18n -> List Member.ChainState -> ModelData -> List (Ui.Element Msg)
transferFields i18n activeMembers data =
    [ Shared.amountCurrencyField i18n data
    , Shared.defaultCurrencyAmountField i18n data
    , Shared.dateField i18n data
    , transferMembersField i18n activeMembers data
    , Shared.notesField i18n data
    , transferSummary activeMembers data
    ]


transferMembersField : I18n -> List Member.ChainState -> ModelData -> Ui.Element Msg
transferMembersField i18n activeMembers data =
    let
        memberRole : Member.Id -> Maybe String
        memberRole memberId =
            if data.fromMemberId == Just memberId then
                Just "From"

            else if data.toMemberId == Just memberId then
                Just "To"

            else
                Nothing

        missingSelection : Bool
        missingSelection =
            data.submitted && (data.fromMemberId == Nothing || data.toMemberId == Nothing)

        sameFromTo : Bool
        sameFromTo =
            data.submitted
                && data.fromMemberId
                /= Nothing
                && data.fromMemberId
                == data.toMemberId
    in
    Shared.formField { label = T.newEntryTransferLabel i18n, required = True }
        [ Ui.row [ Ui.spacing Theme.spacing.sm, Ui.wrap ]
            (List.map
                (\member ->
                    transferMemberBtn
                        { name = member.name
                        , initials = String.left 2 (String.toUpper member.name)
                        , role = memberRole member.rootId
                        , onPress = CycleTransferRole member.rootId
                        }
                )
                activeMembers
            )
        , Shared.errorWhen missingSelection (T.newEntrySelectBoth i18n)
        , Shared.errorWhen sameFromTo (T.newEntrySameFromTo i18n)
        ]


transferMemberBtn :
    { name : String
    , initials : String
    , role : Maybe String
    , onPress : msg
    }
    -> Ui.Element msg
transferMemberBtn config =
    let
        ( borderClr, backgroundColor, avatarColor ) =
            case config.role of
                Just "From" ->
                    ( Theme.success.solid, Theme.success.bg, UI.Components.AvatarAccent )

                Just "To" ->
                    ( Theme.warning.solid, Theme.warning.bg, UI.Components.AvatarRed )

                _ ->
                    ( Theme.base.solid, Theme.base.bg, UI.Components.AvatarNeutral )
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
        [ UI.Components.avatar avatarColor config.initials
        , case config.role of
            Just role ->
                Ui.el
                    [ Ui.alignRight
                    , Ui.Font.size Theme.font.md
                    , Ui.Font.weight Theme.fontWeight.semibold
                    , Ui.Font.color borderClr
                    ]
                    (Ui.text <| String.toUpper role ++ ":")

            Nothing ->
                Ui.none
        , Ui.el [ Ui.Font.weight Theme.fontWeight.medium ]
            (Ui.text config.name)
        ]


transferSummary : List Member.ChainState -> ModelData -> Ui.Element Msg
transferSummary activeMembers data =
    case ( data.fromMemberId, data.toMemberId ) of
        ( Just fromId, Just toId ) ->
            let
                amountCents : Int
                amountCents =
                    Form.get .amount data.form |> Field.toMaybe |> Maybe.withDefault 0

                amountText : String
                amountText =
                    Format.formatCentsWithCurrency amountCents data.currency

                memberSummary : Ui.Attribute Msg -> String -> Ui.Element Msg
                memberSummary alignAttr name =
                    Ui.el
                        [ Ui.Font.size Theme.font.lg
                        , Ui.Font.weight Theme.fontWeight.semibold
                        , Ui.width Ui.shrink
                        , alignAttr
                        ]
                        (Ui.text name)

                findName : Member.Id -> String
                findName mid =
                    activeMembers
                        |> List.Extra.find (\m -> m.rootId == mid)
                        |> Maybe.map .name
                        |> Maybe.withDefault "?"
            in
            Ui.row
                [ Ui.contentCenterX
                , Ui.contentBottom
                , Ui.spacing Theme.spacing.md
                , Ui.width Ui.shrink
                , Ui.centerX
                , Ui.Font.color Theme.base.textSubtle
                ]
                [ memberSummary Ui.alignRight (findName fromId)
                , Ui.column [ Ui.spacing Theme.spacing.xs, Ui.contentCenterX ]
                    [ Ui.el
                        [ Ui.Font.size Theme.font.sm
                        , Ui.Font.weight Theme.fontWeight.medium
                        ]
                        (Ui.text amountText)
                    , Ui.el [ Ui.centerX ]
                        (UI.Components.featherIcon 20 FeatherIcons.arrowRight)
                    ]
                , memberSummary Ui.alignLeft (findName toId)
                ]

        _ ->
            Ui.none
