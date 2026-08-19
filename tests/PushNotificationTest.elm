module PushNotificationTest exposing (suite)

import ActivityPhrase exposing (Phrase(..))
import Domain.Activity exposing (Detail(..))
import Domain.Currency exposing (Currency(..))
import Domain.Member as Member
import Expect
import Set
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
import Translations as T exposing (Language(..))


suite : Test
suite =
    describe "push notifications"
        [ describe "phrase maps activity details to wire keys and parameters"
            [ test "added expense carries description and amount" <|
                \_ ->
                    ActivityPhrase.phrase (EntryAddedDetail { entry = makeExpenseEntry "e1" 0 defaultExpenseData })
                        |> Expect.equal ( EntryAdded "Test expense", Just { cents = 1000, currency = EUR } )
            , test "added transfer carries only the amount" <|
                \_ ->
                    ActivityPhrase.phrase (TransferAddedDetail { entry = makeTransferEntry "e1" 0 defaultTransferData })
                        |> Expect.equal ( TransferAdded, Just { cents = defaultTransferData.amount, currency = defaultTransferData.currency } )
            , test "added income carries description and amount" <|
                \_ ->
                    ActivityPhrase.phrase (EntryAddedDetail { entry = makeIncomeEntry "e1" 0 defaultIncomeData })
                        |> Expect.equal ( IncomeAdded defaultIncomeData.description, Just { cents = defaultIncomeData.amount, currency = defaultIncomeData.currency } )
            , test "modified expense keeps the changes out of the phrase" <|
                \_ ->
                    ActivityPhrase.phrase
                        (EntryModifiedDetail
                            { entry = makeExpenseEntry "e1" 1 defaultExpenseData
                            , previousEntry = Nothing
                            , changes = []
                            }
                        )
                        |> Tuple.first
                        |> Expect.equal (EntryModified "Test expense")
            , test "deleted entry has no amount" <|
                \_ ->
                    ActivityPhrase.phrase (EntryDeletedDetail { entryDescription = "Old", entry = Nothing })
                        |> Expect.equal ( EntryDeleted "Old", Nothing )
            , test "real member joined" <|
                \_ ->
                    ActivityPhrase.phrase (MemberCreatedDetail { name = "Mia", memberType = Member.Real })
                        |> Expect.equal ( MemberCreated "Mia", Nothing )
            , test "virtual member is created, not joined" <|
                \_ ->
                    ActivityPhrase.phrase (MemberCreatedDetail { name = "Cat", memberType = Member.Virtual })
                        |> Expect.equal ( MemberCreatedVirtual "Cat", Nothing )
            , test "rename carries both names" <|
                \_ ->
                    ActivityPhrase.phrase (MemberRenamedDetail { oldName = "Paul", newName = "Paul D.", rootId = "m1" })
                        |> Expect.equal ( MemberRenamed { oldName = "Paul", newName = "Paul D." }, Nothing )
            ]
        , describe "samples cover the wire vocabulary consistently"
            [ test "every sample argument is the placeholder of its parameter name" <|
                \_ ->
                    ActivityPhrase.samples
                        |> List.concatMap ActivityPhrase.params
                        |> List.filter (\( name, value ) -> value /= "{" ++ name ++ "}")
                        |> Expect.equalLists []
            , test "sample keys are unique" <|
                \_ ->
                    ActivityPhrase.samples
                        |> List.map ActivityPhrase.key
                        |> (\keys -> Set.size (Set.fromList keys) |> Expect.equal (List.length keys))
            ]
        , describe "every template renders with its placeholders intact"
            (List.map templatesContainPlaceholders [ En, Fr ])
        , describe "renderLine appends the localized amount"
            [ test "English prefix symbol" <|
                \_ ->
                    ActivityPhrase.renderLine (T.init En) ( EntryAdded "Groceries", Just { cents = 4250, currency = EUR } )
                        |> Expect.equal "added \"Groceries\" (€42.50)"
            , test "French suffix symbol" <|
                \_ ->
                    ActivityPhrase.renderLine (T.init Fr) ( EntryAdded "Courses", Just { cents = 4250, currency = EUR } )
                        |> Expect.equal "a ajouté « Courses » (42,50\u{00A0}€)"
            , test "no amount renders the bare phrase" <|
                \_ ->
                    ActivityPhrase.renderLine (T.init En) ( MemberRetired "Paul", Nothing )
                        |> Expect.equal "retired Paul"
            ]
        ]


{-| A missing placeholder in one language's template would silently drop a
parameter on the lock screen; a missing or empty template would drop the
whole phrase.
-}
templatesContainPlaceholders : Language -> Test
templatesContainPlaceholders lang =
    describe (T.languageToString lang)
        (ActivityPhrase.samples
            |> List.map
                (\sample ->
                    test (ActivityPhrase.key sample) <|
                        \_ ->
                            let
                                rendered : String
                                rendered =
                                    ActivityPhrase.render (T.init lang) sample
                            in
                            if String.isEmpty rendered then
                                Expect.fail "empty template"

                            else
                                ActivityPhrase.params sample
                                    |> List.filter (\( _, placeholder ) -> not (String.contains placeholder rendered))
                                    |> Expect.equalLists []
                )
        )
