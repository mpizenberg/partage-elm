module EditMemberMetadataFormTest exposing (suite)

import Domain.Member as Member
import Domain.PaymentMethod as PaymentMethod exposing (Method(..))
import Expect
import Field
import Form
import Form.EditMemberMetadata as MetadataForm
import Test exposing (Test, describe, test)


memberWith : List ( Method, String ) -> Member.Metadata
memberWith handles =
    let
        meta : Member.Metadata
        meta =
            Member.emptyMetadata
    in
    { meta
        | payment =
            List.foldl (\( method, value ) -> PaymentMethod.set method (Just value))
                PaymentMethod.empty
                handles
    }


{-| The handle as the form reports it: `Nothing` means the form has no opinion
about this method and the member's existing value stands, which is a different
outcome from `Just ( method, Nothing )` — an explicit clear.
-}
handleOf : Method -> MetadataForm.Form -> Maybe ( Method, Maybe String )
handleOf method form =
    Form.validateAsMaybe form
        |> Maybe.map .payment
        |> Maybe.withDefault []
        |> List.filter (\( m, _ ) -> m == method)
        |> List.head


suite : Test
suite =
    describe "member metadata form payment handles"
        [ test "a handle the member already had survives untouched" <|
            \_ ->
                MetadataForm.form
                    |> MetadataForm.initFromMember "Alice" (memberWith [ ( Iban, "FR7630001" ) ])
                    |> handleOf Iban
                    |> Expect.equal (Just ( Iban, Just "FR7630001" ))
        , test "editing a handle the member did not have reports the new value" <|
            \_ ->
                MetadataForm.form
                    |> MetadataForm.initFromMember "Alice" Member.emptyMetadata
                    |> Form.modify (MetadataForm.payment Revolut) (Field.setFromString "@alice")
                    |> handleOf Revolut
                    |> Expect.equal (Just ( Revolut, Just "@alice" ))
        , test "clearing a handle reports it as cleared, not as untouched" <|
            \_ ->
                MetadataForm.form
                    |> MetadataForm.initFromMember "Alice" (memberWith [ ( Iban, "FR7630001" ) ])
                    |> Form.modify (MetadataForm.payment Iban) (Field.setFromString "")
                    |> handleOf Iban
                    |> Expect.equal (Just ( Iban, Nothing ))
        , test "a method the form never touched is absent, leaving the member's value alone" <|
            \_ ->
                MetadataForm.form
                    |> MetadataForm.initFromMember "Alice" Member.emptyMetadata
                    |> handleOf Venmo
                    |> Expect.equal Nothing
        ]
