module Page.MemberDetail exposing (Model, Msg, Output(..), init, update, view)

{-| Member detail view with rename, retire/unretire actions.
-}

import Domain.Member as Member
import Html
import Html.Attributes
import Translations as T exposing (I18n)
import UI.Theme as Theme
import Ui
import Ui.Events
import Ui.Font
import Ui.Input


{-| Actions that can be triggered from the member detail page.
-}
type Output
    = RenameOutput { memberId : Member.Id, oldName : String, newName : String }
    | RetireOutput Member.Id
    | UnretireOutput Member.Id
    | NavigateToEditMetadata
    | NavigateBack


{-| Page model holding the member data and rename form state.
-}
type Model
    = Model ModelData


type alias ModelData =
    { member : Member.ChainState
    , renaming : Bool
    , renameText : String
    }


{-| Messages produced by user interaction on the member detail page.
-}
type Msg
    = StartRename
    | CancelRename
    | InputRename String
    | SubmitRename
    | Retire
    | Unretire
    | GoEditMetadata
    | GoBack


{-| Initialize the model from a member's chain state.
-}
init : Member.ChainState -> Model
init member =
    Model
        { member = member
        , renaming = False
        , renameText = member.name
        }


{-| Handle user actions like rename, retire, and navigation.
-}
update : Msg -> Model -> ( Model, Maybe Output )
update msg (Model data) =
    case msg of
        StartRename ->
            ( Model { data | renaming = True, renameText = data.member.name }, Nothing )

        CancelRename ->
            ( Model { data | renaming = False }, Nothing )

        InputRename s ->
            ( Model { data | renameText = s }, Nothing )

        SubmitRename ->
            let
                trimmed : String
                trimmed =
                    String.trim data.renameText
            in
            if String.isEmpty trimmed || trimmed == data.member.name then
                ( Model { data | renaming = False }, Nothing )

            else
                ( Model { data | renaming = False }
                , Just
                    (RenameOutput
                        { memberId = data.member.rootId
                        , oldName = data.member.name
                        , newName = trimmed
                        }
                    )
                )

        Retire ->
            ( Model data, Just (RetireOutput data.member.rootId) )

        Unretire ->
            ( Model data, Just (UnretireOutput data.member.rootId) )

        GoEditMetadata ->
            ( Model data, Just NavigateToEditMetadata )

        GoBack ->
            ( Model data, Just NavigateBack )


{-| Render the member detail view with name, info, metadata, and action buttons.
-}
view : I18n -> Member.Id -> (Msg -> msg) -> Model -> Ui.Element msg
view i18n currentUserRootId toMsg (Model data) =
    Ui.column [ Ui.spacing Theme.spacing.lg, Ui.width Ui.fill ]
        [ backLink i18n
        , Ui.el [ Ui.Font.size Theme.fontSize.xl, Ui.Font.bold ] (Ui.text (T.memberDetailTitle i18n))
        , nameSection i18n data
        , infoSection i18n data.member
        , metadataSection i18n data.member
        , actionButtons i18n currentUserRootId data.member
        ]
        |> Ui.map toMsg


backLink : I18n -> Ui.Element Msg
backLink i18n =
    Ui.el
        [ Ui.pointer
        , Ui.Events.onClick GoBack
        , Ui.Font.size Theme.fontSize.sm
        , Ui.Font.color Theme.primary
        ]
        (Ui.text (T.memberDetailBack i18n))


nameSection : I18n -> ModelData -> Ui.Element Msg
nameSection i18n data =
    if data.renaming then
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.bold ]
                (Ui.text (T.memberRenameLabel i18n))
            , Ui.Input.text [ Ui.width Ui.fill ]
                { onChange = InputRename
                , text = data.renameText
                , placeholder = Nothing
                , label = Ui.Input.labelHidden (T.memberRenameLabel i18n)
                }
            , Ui.row [ Ui.spacing Theme.spacing.sm ]
                [ Ui.el
                    [ Ui.Input.button SubmitRename
                    , Ui.padding Theme.spacing.sm
                    , Ui.rounded Theme.rounding.sm
                    , Ui.background Theme.primary
                    , Ui.Font.color Theme.white
                    , Ui.Font.size Theme.fontSize.sm
                    , Ui.Font.bold
                    , Ui.pointer
                    ]
                    (Ui.text (T.memberRenameSave i18n))
                , Ui.el
                    [ Ui.pointer
                    , Ui.Events.onClick CancelRename
                    , Ui.Font.size Theme.fontSize.sm
                    , Ui.Font.color Theme.neutral500
                    ]
                    (Ui.text (T.memberRenameCancel i18n))
                ]
            ]

    else
        Ui.el [ Ui.Font.size Theme.fontSize.lg, Ui.Font.bold ]
            (Ui.text data.member.name)


infoSection : I18n -> Member.ChainState -> Ui.Element msg
infoSection i18n member =
    let
        typeLabel : String
        typeLabel =
            case member.currentMember.memberType of
                Member.Real ->
                    T.memberDetailTypeReal i18n

                Member.Virtual ->
                    T.memberDetailTypeVirtual i18n

        statusLabel : String
        statusLabel =
            if member.isRetired then
                T.memberDetailStatusRetired i18n

            else
                T.memberDetailStatusActive i18n
    in
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text typeLabel)
        , Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text statusLabel)
        ]


metadataSection : I18n -> Member.ChainState -> Ui.Element msg
metadataSection i18n member =
    let
        meta : Member.Metadata
        meta =
            member.metadata

        rows : List (Ui.Element msg)
        rows =
            List.filterMap identity
                [ Maybe.map (\v -> metadataLinkRow (T.memberMetadataPhone i18n) v ("tel:" ++ stripSpaces v)) meta.phone
                , Maybe.map (\v -> metadataLinkRow (T.memberMetadataEmail i18n) v ("mailto:" ++ v)) meta.email
                , Maybe.map (\v -> metadataRow (T.memberMetadataNotes i18n) v) meta.notes
                ]

        paymentRows : List (Ui.Element msg)
        paymentRows =
            case meta.payment of
                Just payment ->
                    List.filterMap identity
                        [ Maybe.map (\v -> metadataCopyRow (T.memberMetadataIban i18n) v) payment.iban
                        , Maybe.map (\v -> metadataCopyRow (T.memberMetadataWero i18n) v) payment.wero
                        , Maybe.map (\v -> metadataLinkRow (T.memberMetadataLydia i18n) v ("https://pay.lydia.me/l?t=" ++ normalizeHandle v)) payment.lydia
                        , Maybe.map (\v -> metadataLinkRow (T.memberMetadataRevolut i18n) v ("https://revolut.me/" ++ normalizeHandle v)) payment.revolut
                        , Maybe.map (\v -> metadataLinkRow (T.memberMetadataPaypal i18n) v ("https://paypal.me/" ++ normalizeHandle v)) payment.paypal
                        , Maybe.map (\v -> metadataLinkRow (T.memberMetadataVenmo i18n) v ("https://venmo.com/" ++ normalizeHandle v)) payment.venmo
                        , Maybe.map (\v -> metadataLinkRow (T.memberMetadataBtc i18n) v ("bitcoin:" ++ v)) payment.btcAddress
                        , Maybe.map (\v -> metadataCopyRow (T.memberMetadataAda i18n) v) payment.adaAddress
                        ]

                Nothing ->
                    []

        allRows : List (Ui.Element msg)
        allRows =
            rows ++ paymentRows
    in
    if List.isEmpty allRows then
        Ui.none

    else
        Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ] allRows


{-| Strip leading '@' and whitespace from a handle/username.
-}
normalizeHandle : String -> String
normalizeHandle value =
    value |> String.trim |> String.replace "@" ""


{-| Strip spaces from a string (used for phone numbers in tel: links).
-}
stripSpaces : String -> String
stripSpaces =
    String.filter (\c -> c /= ' ')


{-| Plain text metadata row (no link, no copy).
-}
metadataRow : String -> String -> Ui.Element msg
metadataRow label value =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text label)
        , Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text value)
        ]


{-| Metadata row with a clickable link and a copy button.
-}
metadataLinkRow : String -> String -> String -> Ui.Element msg
metadataLinkRow label value url =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text label)
        , Ui.row [ Ui.spacing Theme.spacing.xs ]
            [ Ui.el [ Ui.linkNewTab url, Ui.Font.size Theme.fontSize.md, Ui.Font.color Theme.primary ] (Ui.text value)
            , copyButton value
            ]
        ]


{-| Metadata row with a copy button but no link.
-}
metadataCopyRow : String -> String -> Ui.Element msg
metadataCopyRow label value =
    Ui.column [ Ui.spacing Theme.spacing.xs, Ui.width Ui.fill ]
        [ Ui.el [ Ui.Font.size Theme.fontSize.sm, Ui.Font.color Theme.neutral500 ] (Ui.text label)
        , Ui.row [ Ui.spacing Theme.spacing.xs ]
            [ Ui.el [ Ui.Font.size Theme.fontSize.md ] (Ui.text value)
            , copyButton value
            ]
        ]


{-| A small copy icon rendered as a <copy-button> custom element.
-}
copyButton : String -> Ui.Element msg
copyButton value =
    Ui.html
        (Html.node "copy-button"
            [ Html.Attributes.attribute "data-copy" value
            , Html.Attributes.style "cursor" "pointer"
            , Html.Attributes.style "opacity" "0.5"
            , Html.Attributes.style "font-size" (String.fromInt Theme.fontSize.sm ++ "px")
            ]
            [ Html.text "\u{1F4CB}" ]
        )


actionButtons : I18n -> Member.Id -> Member.ChainState -> Ui.Element Msg
actionButtons i18n currentUserRootId member =
    let
        renameBtn : Ui.Element Msg
        renameBtn =
            Ui.el
                [ Ui.Input.button StartRename
                , Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.rounding.md
                , Ui.background Theme.primary
                , Ui.Font.color Theme.white
                , Ui.Font.center
                , Ui.Font.bold
                , Ui.pointer
                ]
                (Ui.text (T.memberRenameButton i18n))

        editMetadataBtn : Ui.Element Msg
        editMetadataBtn =
            Ui.el
                [ Ui.Input.button GoEditMetadata
                , Ui.width Ui.fill
                , Ui.padding Theme.spacing.md
                , Ui.rounded Theme.rounding.md
                , Ui.background Theme.primary
                , Ui.Font.color Theme.white
                , Ui.Font.center
                , Ui.Font.bold
                , Ui.pointer
                ]
                (Ui.text (T.memberEditMetadataButton i18n))

        lifecycleBtn : Ui.Element Msg
        lifecycleBtn =
            if member.isRetired then
                Ui.el
                    [ Ui.Input.button Unretire
                    , Ui.width Ui.fill
                    , Ui.padding Theme.spacing.md
                    , Ui.rounded Theme.rounding.md
                    , Ui.background Theme.success
                    , Ui.Font.color Theme.white
                    , Ui.Font.center
                    , Ui.Font.bold
                    , Ui.pointer
                    ]
                    (Ui.text (T.memberUnretireButton i18n))

            else if member.rootId /= currentUserRootId then
                Ui.el
                    [ Ui.Input.button Retire
                    , Ui.width Ui.fill
                    , Ui.padding Theme.spacing.md
                    , Ui.rounded Theme.rounding.md
                    , Ui.background Theme.danger
                    , Ui.Font.color Theme.white
                    , Ui.Font.center
                    , Ui.Font.bold
                    , Ui.pointer
                    ]
                    (Ui.text (T.memberRetireButton i18n))

            else
                Ui.none
    in
    Ui.column [ Ui.spacing Theme.spacing.sm, Ui.width Ui.fill ]
        [ renameBtn
        , editMetadataBtn
        , lifecycleBtn
        ]
