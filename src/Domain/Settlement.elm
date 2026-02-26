module Domain.Settlement exposing (Preference, Transaction, computeSettlement)

{-| Settlement algorithm that computes who pays whom to settle debts.
-}

import Dict exposing (Dict)
import Domain.Balance exposing (MemberBalance, Status(..))
import Domain.Member as Member


{-| A settlement payment from one member to another.
-}
type alias Transaction =
    { from : Member.Id
    , to : Member.Id
    , amount : Int
    }


{-| A member's preferred recipients for settlement payments,
tried in priority order before falling back to the greedy algorithm.
-}
type alias Preference =
    { memberRootId : Member.Id
    , preferredRecipients : List Member.Id
    }


{-| Compute settlement transactions from member balances and preferences.
Two-pass algorithm:

  - Pass 1 (preference-aware): Debtors with preferences sorted smallest-first,
    matched to preferred creditors in priority order.
  - Pass 2 (greedy): Remaining debtors sorted largest-first,
    matched to creditors greedily.

-}
computeSettlement : Dict Member.Id MemberBalance -> List Preference -> List Transaction
computeSettlement balances preferences =
    let
        balanceList =
            Dict.values balances

        -- Build debtor/creditor lists (amounts are absolute values)
        debtors =
            balanceList
                |> List.filterMap
                    (\b ->
                        if b.netBalance < 0 then
                            Just ( b.memberRootId, abs b.netBalance )

                        else
                            Nothing
                    )

        creditors =
            balanceList
                |> List.filterMap
                    (\b ->
                        if b.netBalance > 0 then
                            Just ( b.memberRootId, b.netBalance )

                        else
                            Nothing
                    )

        prefMap =
            List.foldl
                (\p acc ->
                    ( p.memberRootId, p.preferredRecipients ) :: acc
                )
                []
                preferences

        -- Pass 1: preference-aware (smallest debtors first)
        debtorsWithPrefs =
            debtors
                |> List.filter (\( mid, _ ) -> List.any (\p -> p.memberRootId == mid) preferences)
                |> List.sortBy Tuple.second

        debtorsWithoutPrefs =
            debtors
                |> List.filter (\( mid, _ ) -> not (List.any (\p -> p.memberRootId == mid) preferences))

        ( pass1Transactions, remainingDebtors1, remainingCreditors1 ) =
            processPreferencePass debtorsWithPrefs creditors prefMap

        -- Pass 2: greedy (largest debtors first)
        allRemainingDebtors =
            (remainingDebtors1 ++ debtorsWithoutPrefs)
                |> List.sortBy Tuple.second
                |> List.reverse

        ( pass2Transactions, _, _ ) =
            processGreedyPass allRemainingDebtors remainingCreditors1
    in
    pass1Transactions ++ pass2Transactions


processPreferencePass :
    List ( Member.Id, Int )
    -> List ( Member.Id, Int )
    -> List ( Member.Id, List Member.Id )
    -> ( List Transaction, List ( Member.Id, Int ), List ( Member.Id, Int ) )
processPreferencePass debtors creditors prefMap =
    case debtors of
        [] ->
            ( [], [], creditors )

        ( debtorId, debtorAmt ) :: restDebtors ->
            let
                preferredIds =
                    List.foldl
                        (\( mid, prefs ) acc ->
                            if mid == debtorId then
                                prefs

                            else
                                acc
                        )
                        []
                        prefMap

                ( transactions, remainingAmt, updatedCreditors ) =
                    matchWithPreferred debtorId debtorAmt preferredIds creditors

                ( restTransactions, remainingDebtors, finalCreditors ) =
                    processPreferencePass restDebtors updatedCreditors prefMap

                allRemainingDebtors =
                    if remainingAmt > 0 then
                        ( debtorId, remainingAmt ) :: remainingDebtors

                    else
                        remainingDebtors
            in
            ( transactions ++ restTransactions, allRemainingDebtors, finalCreditors )


matchWithPreferred :
    Member.Id
    -> Int
    -> List Member.Id
    -> List ( Member.Id, Int )
    -> ( List Transaction, Int, List ( Member.Id, Int ) )
matchWithPreferred debtorId debtorAmt preferredIds creditors =
    case preferredIds of
        [] ->
            ( [], debtorAmt, creditors )

        prefId :: restPrefs ->
            if debtorAmt <= 0 then
                ( [], 0, creditors )

            else
                case findCreditor prefId creditors of
                    Nothing ->
                        matchWithPreferred debtorId debtorAmt restPrefs creditors

                    Just creditorAmt ->
                        let
                            transferAmt =
                                min debtorAmt creditorAmt

                            transaction =
                                { from = debtorId, to = prefId, amount = transferAmt }

                            newDebtorAmt =
                                debtorAmt - transferAmt

                            newCreditorAmt =
                                creditorAmt - transferAmt

                            updatedCreditors =
                                if newCreditorAmt > 0 then
                                    updateCreditor prefId newCreditorAmt creditors

                                else
                                    removeCreditor prefId creditors

                            ( restTransactions, finalAmt, finalCreditors ) =
                                matchWithPreferred debtorId newDebtorAmt restPrefs updatedCreditors
                        in
                        ( transaction :: restTransactions, finalAmt, finalCreditors )


processGreedyPass :
    List ( Member.Id, Int )
    -> List ( Member.Id, Int )
    -> ( List Transaction, List ( Member.Id, Int ), List ( Member.Id, Int ) )
processGreedyPass debtors creditors =
    case debtors of
        [] ->
            ( [], [], creditors )

        ( debtorId, debtorAmt ) :: restDebtors ->
            if debtorAmt <= 0 then
                processGreedyPass restDebtors creditors

            else
                -- Find the largest creditor
                case largestCreditor creditors of
                    Nothing ->
                        ( [], debtors, [] )

                    Just ( creditorId, creditorAmt ) ->
                        let
                            transferAmt =
                                min debtorAmt creditorAmt

                            transaction =
                                { from = debtorId, to = creditorId, amount = transferAmt }

                            newDebtorAmt =
                                debtorAmt - transferAmt

                            newCreditorAmt =
                                creditorAmt - transferAmt

                            updatedCreditors =
                                if newCreditorAmt > 0 then
                                    updateCreditor creditorId newCreditorAmt creditors

                                else
                                    removeCreditor creditorId creditors

                            updatedDebtors =
                                if newDebtorAmt > 0 then
                                    ( debtorId, newDebtorAmt ) :: restDebtors

                                else
                                    restDebtors
                        in
                        let
                            ( restTransactions, finalDebtors, finalCreditors ) =
                                processGreedyPass updatedDebtors updatedCreditors
                        in
                        ( transaction :: restTransactions, finalDebtors, finalCreditors )



-- HELPERS


findCreditor : Member.Id -> List ( Member.Id, Int ) -> Maybe Int
findCreditor targetId creditors =
    case creditors of
        [] ->
            Nothing

        ( cid, amt ) :: rest ->
            if cid == targetId then
                Just amt

            else
                findCreditor targetId rest


updateCreditor : Member.Id -> Int -> List ( Member.Id, Int ) -> List ( Member.Id, Int )
updateCreditor targetId newAmt creditors =
    List.map
        (\( cid, amt ) ->
            if cid == targetId then
                ( cid, newAmt )

            else
                ( cid, amt )
        )
        creditors


removeCreditor : Member.Id -> List ( Member.Id, Int ) -> List ( Member.Id, Int )
removeCreditor targetId creditors =
    List.filter (\( cid, _ ) -> cid /= targetId) creditors


largestCreditor : List ( Member.Id, Int ) -> Maybe ( Member.Id, Int )
largestCreditor creditors =
    List.foldl
        (\( cid, amt ) acc ->
            case acc of
                Nothing ->
                    Just ( cid, amt )

                Just ( _, bestAmt ) ->
                    if amt > bestAmt then
                        Just ( cid, amt )

                    else
                        acc
        )
        Nothing
        creditors
