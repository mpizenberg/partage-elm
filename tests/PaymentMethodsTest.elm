module PaymentMethodsTest exposing (suite)

import Domain.PaymentMethod as PaymentMethod exposing (Method(..))
import Expect
import Test exposing (Test, describe, test)
import Translations as T
import UI.PaymentMethods as PaymentMethods


linkFor : Method -> String -> Maybe String
linkFor method value =
    PaymentMethod.set method (Just value) PaymentMethod.empty
        |> PaymentMethods.handles (T.init T.En)
        |> List.head
        |> Maybe.andThen .url


suite : Test
suite =
    describe "payment methods"
        [ -- `all` is unfolded from `next`, whose exhaustiveness only forces each
          -- method to name a successor: a method nothing points at compiles and
          -- silently never renders. This pins the whole chain instead.
          test "every known method appears in display order" <|
            \_ ->
                PaymentMethods.all
                    |> Expect.equal [ Iban, Wero, Lydia, Revolut, Paypal, Venmo, Cashapp, Btc, Ada ]
        , test "a handle typed with its sigil does not double it up" <|
            \_ ->
                ( linkFor Cashapp "$alice", linkFor Revolut "@alice" )
                    |> Expect.equal
                        ( Just "https://cash.app/$alice", Just "https://revolut.me/alice" )
        , test "a handle typed bare gets the sigil the link needs" <|
            \_ ->
                linkFor Cashapp "alice"
                    |> Expect.equal (Just "https://cash.app/$alice")
        , test "a handle already pasted as a full link is left alone" <|
            \_ ->
                linkFor Cashapp "https://cash.app/$alice"
                    |> Expect.equal (Just "https://cash.app/$alice")
        ]
