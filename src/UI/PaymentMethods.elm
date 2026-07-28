module UI.PaymentMethods exposing (Handle, Presentation, all, handles, presentation)

{-| Display order and presentation for the payment methods this version knows.

Order lives in `next` rather than in a literal list, so a method added to
`PaymentMethod.Method` fails to compile until it has been given a position.

-}

import Domain.PaymentMethod as PaymentMethod exposing (Method(..), PaymentInfo)
import FeatherIcons
import Translations as T exposing (I18n)


{-| A handle a member has published, ready to render.
-}
type alias Handle =
    { icon : FeatherIcons.Icon
    , label : String
    , value : String
    , url : Maybe String
    }


{-| The handles present in `info`, in display order.
-}
handles : I18n -> PaymentInfo -> List Handle
handles i18n info =
    List.filterMap (\method -> Maybe.map (toHandle i18n method) (PaymentMethod.get method info)) all


toHandle : I18n -> Method -> String -> Handle
toHandle i18n method value =
    let
        shown : Presentation
        shown =
            presentation method
    in
    { icon = shown.icon
    , label = shown.label i18n
    , value = value
    , url = Maybe.map (\toUrl -> toUrl value) shown.url
    }


all : List Method
all =
    unfold Iban []


unfold : Method -> List Method -> List Method
unfold method acc =
    case next method of
        Just following ->
            unfold following (method :: acc)

        Nothing ->
            List.reverse (method :: acc)


next : Method -> Maybe Method
next method =
    case method of
        Iban ->
            Just Wero

        Wero ->
            Just Lydia

        Lydia ->
            Just Revolut

        Revolut ->
            Just Paypal

        Paypal ->
            Just Venmo

        Venmo ->
            Just Cashapp

        Cashapp ->
            Just Btc

        Btc ->
            Just Ada

        Ada ->
            Nothing


{-| `domId` is a stable name for the method in the DOM; it is deliberately not
the wire key, which stays inside `Domain.PaymentMethod`.
-}
type alias Presentation =
    { icon : FeatherIcons.Icon
    , label : I18n -> String
    , placeholder : String
    , domId : String
    , url : Maybe (String -> String)
    }


presentation : Method -> Presentation
presentation method =
    case method of
        Iban ->
            { icon = FeatherIcons.creditCard
            , label = T.memberMetadataIban
            , placeholder = "FR76 1234 5678 9012 3456 7890 123"
            , domId = "iban"
            , url = Nothing
            }

        Wero ->
            { icon = FeatherIcons.smartphone
            , label = T.memberMetadataWero
            , placeholder = "+33 6 12 34 56 78"
            , domId = "wero"
            , url = Nothing
            }

        Lydia ->
            { icon = FeatherIcons.dollarSign
            , label = T.memberMetadataLydia
            , placeholder = "antoniop6hcr"
            , domId = "lydia"
            , url = Just (normalizeHandle "https://pay.lydia.me/l?t=")
            }

        Revolut ->
            { icon = FeatherIcons.dollarSign
            , label = T.memberMetadataRevolut
            , placeholder = "@username"
            , domId = "revolut"
            , url = Just (normalizeHandle "https://revolut.me/")
            }

        Paypal ->
            { icon = FeatherIcons.dollarSign
            , label = T.memberMetadataPaypal
            , placeholder = "rogerfed"
            , domId = "paypal"
            , url = Just (normalizeHandle "https://paypal.me/")
            }

        Venmo ->
            { icon = FeatherIcons.dollarSign
            , label = T.memberMetadataVenmo
            , placeholder = "@username"
            , domId = "venmo"
            , url = Just (normalizeHandle "https://venmo.com/")
            }

        Cashapp ->
            { icon = FeatherIcons.dollarSign
            , label = T.memberMetadataCashapp
            , placeholder = "$cashtag"
            , domId = "cashapp"
            , url = Just (normalizeHandle "https://cash.app/$")
            }

        Btc ->
            { icon = FeatherIcons.key
            , label = T.memberMetadataBtc
            , placeholder = "bc1q..."
            , domId = "btc"
            , url = Just (\value -> "bitcoin:" ++ value)
            }

        Ada ->
            { icon = FeatherIcons.key
            , label = T.memberMetadataAda
            , placeholder = "addr1..."
            , domId = "ada"
            , url = Nothing
            }


{-| Build a profile link from a handle typed bare, with its sigil, or already as
the full URL. The sigil belongs to the prefix, so a handle carrying one is not
allowed to double it up.
-}
normalizeHandle : String -> String -> String
normalizeHandle prefix value =
    let
        trimmed : String
        trimmed =
            String.trim value
    in
    if String.startsWith prefix trimmed then
        trimmed

    else if String.startsWith "@" trimmed || String.startsWith "$" trimmed then
        prefix ++ String.dropLeft 1 trimmed

    else
        prefix ++ trimmed
