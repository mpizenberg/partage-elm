module PaymentMethodsTest exposing (suite)

import Domain.PaymentMethod exposing (Method(..))
import Expect
import Test exposing (Test, test)
import UI.PaymentMethods as PaymentMethods


{-| `all` is unfolded from `next`, whose exhaustiveness only forces each method
to name a successor — a method nothing points at compiles and silently never
renders. This pins the whole chain instead.
-}
suite : Test
suite =
    test "every known payment method appears in display order" <|
        \_ ->
            PaymentMethods.all
                |> Expect.equal [ Iban, Wero, Lydia, Revolut, Paypal, Venmo, Btc, Ada ]
