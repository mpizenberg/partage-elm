module PushNotificationTest exposing (suite)

import Dict
import Domain.Event exposing (Payload(..))
import Domain.Member as Member
import Expect
import Infra.PushServer as PushServer
import Test exposing (Test, describe, test)
import TestHelpers
    exposing
        ( defaultExpenseData
        , defaultIncomeData
        , defaultTransferData
        , makeExpenseEntry
        , makeIncomeEntry
        , makeTransferEntry
        )
import Translations exposing (Language(..))


suite : Test
suite =
    describe "push notifications"
        [ describe "notificationKey maps each documented event to its template key"
            [ test "added expense" <|
                \_ ->
                    PushServer.notificationKey [ EntryAdded (makeExpenseEntry "e1" 0 defaultExpenseData) ]
                        |> Expect.equal "expense_added"
            , test "added transfer" <|
                \_ ->
                    PushServer.notificationKey [ EntryAdded (makeTransferEntry "e1" 0 defaultTransferData) ]
                        |> Expect.equal "transfer_added"
            , test "added income" <|
                \_ ->
                    PushServer.notificationKey [ EntryAdded (makeIncomeEntry "e1" 0 defaultIncomeData) ]
                        |> Expect.equal "income_added"
            , test "edited expense" <|
                \_ ->
                    PushServer.notificationKey [ EntryModified (makeExpenseEntry "e1" 0 defaultExpenseData) ]
                        |> Expect.equal "expense_modified"
            , test "edited transfer" <|
                \_ ->
                    PushServer.notificationKey [ EntryModified (makeTransferEntry "e1" 0 defaultTransferData) ]
                        |> Expect.equal "transfer_modified"
            , test "edited income" <|
                \_ ->
                    PushServer.notificationKey [ EntryModified (makeIncomeEntry "e1" 0 defaultIncomeData) ]
                        |> Expect.equal "income_modified"
            , test "deleted entry" <|
                \_ ->
                    PushServer.notificationKey [ EntryDeleted { rootId = "e1" } ]
                        |> Expect.equal "entry_deleted"
            , test "real member joined" <|
                \_ ->
                    PushServer.notificationKey [ MemberCreated { memberId = "m1", name = "Mia", memberType = Member.Real, addedBy = "admin" } ]
                        |> Expect.equal "member_joined"
            , test "linked member joined" <|
                \_ ->
                    PushServer.notificationKey [ MemberLinked { rootId = "m1", deviceId = "d1", seq = 0 } ]
                        |> Expect.equal "member_joined"
            ]
        , describe "notificationKey falls back to generic activity"
            [ test "a virtual member is created, not joined" <|
                \_ ->
                    PushServer.notificationKey [ MemberCreated { memberId = "v1", name = "Cat", memberType = Member.Virtual, addedBy = "admin" } ]
                        |> Expect.equal "new_activity"
            , test "an undelete has no documented template" <|
                \_ ->
                    PushServer.notificationKey [ EntryUndeleted { rootId = "e1" } ]
                        |> Expect.equal "new_activity"
            , test "an empty batch" <|
                \_ ->
                    PushServer.notificationKey []
                        |> Expect.equal "new_activity"
            , test "a mixed batch" <|
                \_ ->
                    PushServer.notificationKey
                        [ EntryAdded (makeExpenseEntry "e1" 0 defaultExpenseData)
                        , EntryDeleted { rootId = "e2" }
                        ]
                        |> Expect.equal "new_activity"
            ]
        , describe "every template key is localized with an interpolation slot"
            (List.map keyTranslated allKeys)
        ]


{-| Every key `notificationKey` can emit, plus the generic fallback.
-}
allKeys : List String
allKeys =
    [ "new_activity"
    , "expense_added"
    , "transfer_added"
    , "income_added"
    , "expense_modified"
    , "transfer_modified"
    , "income_modified"
    , "entry_deleted"
    , "member_joined"
    ]


keyTranslated : String -> Test
keyTranslated key =
    describe key
        [ test "English" <| \_ -> expectTemplate key (Dict.get key (PushServer.templates En))
        , test "French" <| \_ -> expectTemplate key (Dict.get key (PushServer.templates Fr))
        ]


{-| A key must resolve to a template, and every key except the generic fallback
must carry the `{name}` slot the service worker interpolates.
-}
expectTemplate : String -> Maybe String -> Expect.Expectation
expectTemplate key maybeTemplate =
    case maybeTemplate of
        Nothing ->
            Expect.fail ("no template for key " ++ key)

        Just template ->
            if key == "new_activity" || String.contains "{name}" template then
                Expect.pass

            else
                Expect.fail ("template for " ++ key ++ " lacks a {name} slot: " ++ template)
