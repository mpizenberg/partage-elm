module Domain.Balance exposing (MemberBalance, Status(..), computeBalances, status)

{-| Balance computation from ledger entries with integer arithmetic.
-}

import Dict exposing (Dict)
import Domain.Entry as Entry exposing (Beneficiary(..), Entry, Kind(..))
import Domain.Member as Member
import Time


{-| Accumulated balance for a member (identified by rootId),
with total paid, total owed, and net balance in the group's default currency.
-}
type alias MemberBalance =
    { memberRootId : Member.Id
    , totalPaid : Int
    , totalOwed : Int
    , netBalance : Int
    }


{-| Whether a member is owed money, owes money, or is settled.
-}
type Status
    = Creditor
    | Debtor
    | Settled


{-| Determine the balance status of a member from their net balance.
-}
status : MemberBalance -> Status
status balance =
    if balance.netBalance > 0 then
        Creditor

    else if balance.netBalance < 0 then
        Debtor

    else
        Settled


{-| Compute balances for all members from active entries.
Takes a rootId resolver (member id -> root id) and a list of active entries.
-}
computeBalances : (Member.Id -> Member.Id) -> List Entry -> List MemberBalance
computeBalances resolveRootId entries =
    let
        emptyAccum =
            { paid = 0, owed = 0 }

        accumulate : Entry -> Dict Member.Id { paid : Int, owed : Int } -> Dict Member.Id { paid : Int, owed : Int }
        accumulate entry acc =
            let
                paidUpdates =
                    computeEntryPaid resolveRootId entry

                owedUpdates =
                    computeEntryOwed resolveRootId entry

                addPaid ( memberId, amount ) d =
                    Dict.update memberId
                        (\mv ->
                            let
                                cur =
                                    Maybe.withDefault emptyAccum mv
                            in
                            Just { cur | paid = cur.paid + amount }
                        )
                        d

                addOwed ( memberId, amount ) d =
                    Dict.update memberId
                        (\mv ->
                            let
                                cur =
                                    Maybe.withDefault emptyAccum mv
                            in
                            Just { cur | owed = cur.owed + amount }
                        )
                        d
            in
            acc
                |> (\a -> List.foldl addPaid a paidUpdates)
                |> (\a -> List.foldl addOwed a owedUpdates)

        accumulated =
            List.foldl accumulate Dict.empty entries
    in
    Dict.toList accumulated
        |> List.map
            (\( memberId, { paid, owed } ) ->
                { memberRootId = memberId
                , totalPaid = paid
                , totalOwed = owed
                , netBalance = paid - owed
                }
            )


{-| Compute what each member paid for an entry, resolved to root IDs.
Returns list of (rootMemberId, amount) pairs.
For multi-currency entries, payer amounts are converted proportionally.
-}
computeEntryPaid : (Member.Id -> Member.Id) -> Entry -> List ( Member.Id, Int )
computeEntryPaid resolveRootId entry =
    let
        totalAmount =
            entryDefaultCurrencyAmount entry
    in
    case entry.kind of
        Expense data ->
            let
                payerTotal =
                    List.foldl (\p acc -> acc + p.amount) 0 data.payers
            in
            if data.defaultCurrencyAmount /= Nothing && payerTotal > 0 then
                -- Multi-currency: proportional conversion
                distributeProportionally resolveRootId
                    totalAmount
                    (List.map (\p -> ( p.memberId, p.amount )) data.payers)
                    payerTotal

            else
                -- Same currency: direct amounts
                List.map
                    (\p -> ( resolveRootId p.memberId, p.amount ))
                    data.payers

        Transfer data ->
            [ ( resolveRootId data.from, totalAmount ) ]


{-| Compute what each member owes for an entry, resolved to root IDs.
-}
computeEntryOwed : (Member.Id -> Member.Id) -> Entry -> List ( Member.Id, Int )
computeEntryOwed resolveRootId entry =
    let
        totalAmount =
            entryDefaultCurrencyAmount entry
    in
    case entry.kind of
        Expense data ->
            computeBeneficiarySplit resolveRootId totalAmount data.beneficiaries

        Transfer data ->
            [ ( resolveRootId data.to, totalAmount ) ]


{-| Get the amount in default currency for an entry.
-}
entryDefaultCurrencyAmount : Entry -> Int
entryDefaultCurrencyAmount entry =
    case entry.kind of
        Expense data ->
            Maybe.withDefault data.amount data.defaultCurrencyAmount

        Transfer data ->
            Maybe.withDefault data.amount data.defaultCurrencyAmount


{-| Split beneficiary amounts using shares-based or exact split.
-}
computeBeneficiarySplit : (Member.Id -> Member.Id) -> Int -> List Beneficiary -> List ( Member.Id, Int )
computeBeneficiarySplit resolveRootId totalAmount beneficiaries =
    case beneficiaries of
        [] ->
            []

        (ExactBeneficiary _) :: _ ->
            -- Exact split: use exact amounts, but normalize to default currency proportionally
            let
                exactTotal =
                    List.foldl
                        (\b acc ->
                            case b of
                                ExactBeneficiary { amount } ->
                                    acc + amount

                                ShareBeneficiary _ ->
                                    acc
                        )
                        0
                        beneficiaries

                items =
                    List.filterMap
                        (\b ->
                            case b of
                                ExactBeneficiary { memberId, amount } ->
                                    Just ( memberId, amount )

                                ShareBeneficiary _ ->
                                    Nothing
                        )
                        beneficiaries
            in
            if exactTotal > 0 && exactTotal /= totalAmount then
                distributeProportionally resolveRootId totalAmount items exactTotal

            else
                List.map (\( mid, amt ) -> ( resolveRootId mid, amt )) items

        (ShareBeneficiary _) :: _ ->
            computeSharesSplit resolveRootId totalAmount beneficiaries


{-| Shares-based split with deterministic remainder distribution.
Remainder cents distributed to beneficiaries sorted by rootId,
with max N remainder cents per member (N = their share count).
-}
computeSharesSplit : (Member.Id -> Member.Id) -> Int -> List Beneficiary -> List ( Member.Id, Int )
computeSharesSplit resolveRootId totalAmount beneficiaries =
    let
        shareItems =
            List.filterMap
                (\b ->
                    case b of
                        ShareBeneficiary { memberId, shares } ->
                            Just ( resolveRootId memberId, shares )

                        ExactBeneficiary _ ->
                            Nothing
                )
                beneficiaries

        totalShares =
            List.foldl (\( _, s ) acc -> acc + s) 0 shareItems

        basePerShare =
            if totalShares > 0 then
                totalAmount // totalShares

            else
                0

        baseAllocated =
            List.map (\( mid, s ) -> ( mid, s, basePerShare * s )) shareItems

        baseTotal =
            List.foldl (\( _, _, amt ) acc -> acc + amt) 0 baseAllocated

        remainder =
            totalAmount - baseTotal

        -- Sort by rootId for deterministic remainder distribution
        sorted =
            List.sortBy (\( mid, _, _ ) -> mid) baseAllocated
    in
    if totalShares == 0 then
        []

    else
        distributeRemainder remainder sorted []


distributeRemainder : Int -> List ( Member.Id, Int, Int ) -> List ( Member.Id, Int ) -> List ( Member.Id, Int )
distributeRemainder rem items acc =
    case items of
        [] ->
            List.reverse acc

        ( mid, shares, amt ) :: rest ->
            let
                extra =
                    min shares rem
            in
            distributeRemainder (rem - extra) rest (( mid, amt + extra ) :: acc)


{-| Distribute totalAmount proportionally among items, with remainder distribution.
-}
distributeProportionally : (Member.Id -> Member.Id) -> Int -> List ( Member.Id, Int ) -> Int -> List ( Member.Id, Int )
distributeProportionally resolveRootId totalAmount items itemTotal =
    let
        baseAllocated =
            List.map
                (\( mid, amt ) ->
                    ( resolveRootId mid, (amt * totalAmount) // itemTotal )
                )
                items

        baseTotal =
            List.foldl (\( _, amt ) acc -> acc + amt) 0 baseAllocated

        remainder =
            totalAmount - baseTotal

        sorted =
            List.sortBy Tuple.first baseAllocated
    in
    distributeExtra remainder sorted []


distributeExtra : Int -> List ( Member.Id, Int ) -> List ( Member.Id, Int ) -> List ( Member.Id, Int )
distributeExtra rem xs acc =
    case xs of
        [] ->
            List.reverse acc

        ( mid, amt ) :: rest ->
            if rem > 0 then
                distributeExtra (rem - 1) rest (( mid, amt + 1 ) :: acc)

            else
                distributeExtra 0 rest (( mid, amt ) :: acc)
