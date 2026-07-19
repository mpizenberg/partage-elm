module Domain.MemberMerge exposing
    ( Action(..)
    , Plan
    , plan
    )

{-| Pure helpers to compute what happens when one member is merged into another.

The "source" member is retired; all of their entries and settlement preferences
are rewritten to reference the "target" member instead. Shares and amounts are
combined when both members already appeared on the same entry. Transfers that
become self-to-self after rewriting are deleted rather than modified.


# Design trade-off: helper, not a domain event

This module does NOT introduce a new `Event.Payload.MergeMembers` variant.
Instead it computes a list of regular events (`EntryModified`,
`EntryDeleted`, `SettlementPreferencesUpdated`, `MemberRetired`) that the
caller submits one by one — exactly what a user could do by hand from the UI.

The reason is backward compatibility: a new payload variant would either fail
to decode on older clients still in the wild, or be silently ignored, causing
permanent divergence between devices. Submitting only events that every
released version already understands keeps the log convergent.

Consequences worth knowing:

  - **Not atomic.** If the user closes the tab mid-submit, or one storage
    write fails, the merge can land partially. There is no rollback.
  - **Snapshot in time.** Only entries and preferences known to this device at
    submission time are rewritten. If another device is offline and creates a
    new entry referencing the source after this merge runs, that entry will
    sync back unrewritten and the user will need to fix it manually.
  - **Authorship is replaced.** Each rewritten entry is re-signed by the
    merging user, replacing the original author in the audit trail.

When the next breaking change of the app ships, it's worth revisiting this and
moving to a single `Event.Payload.MergeMembers` payload interpreted at
projection time in `GroupState`. That would give atomicity, retroactive
rewriting of late-arriving events, and a single audit entry per merge.


# Member ids

All ids accepted by this module MUST be member _root_ ids
(`Member.State.rootId`). Entries and settlement preferences in
`GroupState` only ever store root ids, so matching is by exact equality.
Passing a device id would silently match nothing.

-}

import Dict
import Domain.Entry exposing (Beneficiary(..), Entry, Kind(..), Payer)
import Domain.GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.Settlement as Settlement


{-| A single effect of the merge. Each maps to one event payload at submission.
-}
type Action
    = ModifyEntry { original : Entry, rewritten : Entry }
    | DeleteSelfTransfer { original : Entry }
    | UpdateSettlementPref Settlement.Preference
    | RetireSource


type alias Plan =
    List Action


{-| Compute the ordered list of actions to perform for the merge.
The retire action is always last, after all rewrites are recorded.

Both `sourceRootId` and `targetRootId` MUST be member root ids.

-}
plan : Member.Id -> Member.Id -> GroupState -> Plan
plan sourceRootId targetRootId state =
    if sourceRootId == targetRootId then
        []

    else
        let
            entryActions : List Action
            entryActions =
                Dict.values state.entries
                    |> List.filter (not << .isDeleted)
                    |> List.filterMap
                        (\es ->
                            rewriteEntry sourceRootId targetRootId es.currentVersion
                                |> Maybe.map (toEntryAction es.currentVersion)
                        )

            prefActions : List Action
            prefActions =
                rewriteSettlementPrefs sourceRootId targetRootId state.settlementPreferences
        in
        entryActions ++ prefActions ++ [ RetireSource ]


toEntryAction : Entry -> RewriteResult -> Action
toEntryAction original result =
    case result of
        Rewritten newEntry ->
            ModifyEntry { original = original, rewritten = newEntry }

        SelfTransfer ->
            DeleteSelfTransfer { original = original }


{-| True if the entry's current version references the given root id in any role.
The `memberRootId` argument MUST be a root id.
-}
isAffectedEntry : Member.Id -> Entry -> Bool
isAffectedEntry memberRootId entry =
    case entry.kind of
        Expense data ->
            List.any (\p -> p.memberId == memberRootId) data.payers
                || List.any (beneficiaryHas memberRootId) data.beneficiaries

        Transfer data ->
            data.from == memberRootId || data.to == memberRootId

        Income data ->
            data.receivedBy
                == memberRootId
                || List.any (beneficiaryHas memberRootId) data.beneficiaries


beneficiaryHas : Member.Id -> Beneficiary -> Bool
beneficiaryHas memberRootId b =
    case b of
        ShareBeneficiary d ->
            d.memberId == memberRootId

        ExactBeneficiary d ->
            d.memberId == memberRootId


type RewriteResult
    = Rewritten Entry
    | SelfTransfer


{-| Rewrite an entry, replacing references to `sourceRootId` with `targetRootId`.
Returns Nothing when the entry doesn't reference `sourceRootId` (no event needed).
Returns SelfTransfer when the rewrite would produce a transfer from a member
to themselves, signalling that the entry must be deleted instead.

Both `sourceRootId` and `targetRootId` MUST be root ids.

-}
rewriteEntry : Member.Id -> Member.Id -> Entry -> Maybe RewriteResult
rewriteEntry sourceRootId targetRootId entry =
    if not (isAffectedEntry sourceRootId entry) then
        Nothing

    else
        case entry.kind of
            Expense data ->
                Just
                    (Rewritten
                        { entry
                            | kind =
                                Expense
                                    { data
                                        | payers = rewritePayers sourceRootId targetRootId data.payers
                                        , beneficiaries = rewriteBeneficiaries sourceRootId targetRootId data.beneficiaries
                                    }
                        }
                    )

            Transfer data ->
                let
                    newFrom : Member.Id
                    newFrom =
                        if data.from == sourceRootId then
                            targetRootId

                        else
                            data.from

                    newTo : Member.Id
                    newTo =
                        if data.to == sourceRootId then
                            targetRootId

                        else
                            data.to
                in
                if newFrom == newTo then
                    Just SelfTransfer

                else
                    Just
                        (Rewritten
                            { entry | kind = Transfer { data | from = newFrom, to = newTo } }
                        )

            Income data ->
                let
                    newReceivedBy : Member.Id
                    newReceivedBy =
                        if data.receivedBy == sourceRootId then
                            targetRootId

                        else
                            data.receivedBy
                in
                Just
                    (Rewritten
                        { entry
                            | kind =
                                Income
                                    { data
                                        | receivedBy = newReceivedBy
                                        , beneficiaries = rewriteBeneficiaries sourceRootId targetRootId data.beneficiaries
                                    }
                        }
                    )


rewritePayers : Member.Id -> Member.Id -> List Payer -> List Payer
rewritePayers sourceRootId targetRootId payers =
    let
        sourceIsPayer : Bool
        sourceIsPayer =
            List.any (\p -> p.memberId == sourceRootId) payers
    in
    if not sourceIsPayer then
        payers

    else
        let
            combinedAmount : Int
            combinedAmount =
                List.foldl
                    (\p acc ->
                        if p.memberId == sourceRootId || p.memberId == targetRootId then
                            acc + p.amount

                        else
                            acc
                    )
                    0
                    payers
        in
        emitCombinedOnce
            (\p -> p.memberId == sourceRootId || p.memberId == targetRootId)
            { memberId = targetRootId, amount = combinedAmount }
            payers


rewriteBeneficiaries : Member.Id -> Member.Id -> List Beneficiary -> List Beneficiary
rewriteBeneficiaries sourceRootId targetRootId beneficiaries =
    let
        afterShareRewrite : List Beneficiary
        afterShareRewrite =
            if List.any (matchShareSource sourceRootId) beneficiaries then
                let
                    shareTotal : Int
                    shareTotal =
                        sumBeneficiaries
                            (\b ->
                                case b of
                                    ShareBeneficiary d ->
                                        if d.memberId == sourceRootId || d.memberId == targetRootId then
                                            Just d.shares

                                        else
                                            Nothing

                                    _ ->
                                        Nothing
                            )
                            beneficiaries
                in
                emitCombinedOnce
                    (matchShareSourceOrTarget sourceRootId targetRootId)
                    (ShareBeneficiary { memberId = targetRootId, shares = shareTotal })
                    beneficiaries

            else
                beneficiaries
    in
    if List.any (matchExactSource sourceRootId) beneficiaries then
        let
            exactTotal : Int
            exactTotal =
                sumBeneficiaries
                    (\b ->
                        case b of
                            ExactBeneficiary d ->
                                if d.memberId == sourceRootId || d.memberId == targetRootId then
                                    Just d.amount

                                else
                                    Nothing

                            _ ->
                                Nothing
                    )
                    beneficiaries
        in
        emitCombinedOnce
            (matchExactSourceOrTarget sourceRootId targetRootId)
            (ExactBeneficiary { memberId = targetRootId, amount = exactTotal })
            afterShareRewrite

    else
        afterShareRewrite


matchShareSource : Member.Id -> Beneficiary -> Bool
matchShareSource sourceRootId b =
    case b of
        ShareBeneficiary d ->
            d.memberId == sourceRootId

        _ ->
            False


matchExactSource : Member.Id -> Beneficiary -> Bool
matchExactSource sourceRootId b =
    case b of
        ExactBeneficiary d ->
            d.memberId == sourceRootId

        _ ->
            False


matchShareSourceOrTarget : Member.Id -> Member.Id -> Beneficiary -> Bool
matchShareSourceOrTarget sourceRootId targetRootId b =
    case b of
        ShareBeneficiary d ->
            d.memberId == sourceRootId || d.memberId == targetRootId

        _ ->
            False


matchExactSourceOrTarget : Member.Id -> Member.Id -> Beneficiary -> Bool
matchExactSourceOrTarget sourceRootId targetRootId b =
    case b of
        ExactBeneficiary d ->
            d.memberId == sourceRootId || d.memberId == targetRootId

        _ ->
            False


sumBeneficiaries : (Beneficiary -> Maybe Int) -> List Beneficiary -> Int
sumBeneficiaries pick beneficiaries =
    List.foldl
        (\b acc ->
            case pick b of
                Just n ->
                    acc + n

                Nothing ->
                    acc
        )
        0
        beneficiaries


{-| Walk the list, replacing the first element that matches `pred` with `replacement`
and dropping all subsequent matches. Elements that don't match are kept in order.
-}
emitCombinedOnce : (a -> Bool) -> a -> List a -> List a
emitCombinedOnce pred replacement items =
    let
        ( _, acc ) =
            List.foldl
                (\item ( emitted, out ) ->
                    if pred item then
                        if emitted then
                            ( True, out )

                        else
                            ( True, replacement :: out )

                    else
                        ( emitted, item :: out )
                )
                ( False, [] )
                items
    in
    List.reverse acc


{-| Compute the settlement-preference updates required by the merge.

Single pass over all preferences:

  - The source's own preference row is left untouched. The source is being
    retired and its preferences are irrelevant going forward.
  - The target's row absorbs the source's preferred recipients (if any) and
    has `sourceRootId` rewritten to `targetRootId` in the combined recipient
    list. `targetRootId` itself is filtered out (no self-recommendation).
  - Every other preference whose recipient list mentions `sourceRootId` is
    rewritten so the recipient list points to `targetRootId` instead.

Both `sourceRootId` and `targetRootId` MUST be root ids.

-}
rewriteSettlementPrefs : Member.Id -> Member.Id -> List Settlement.Preference -> List Action
rewriteSettlementPrefs sourceRootId targetRootId prefs =
    let
        sourcePref : Maybe Settlement.Preference
        sourcePref =
            firstMatching (\p -> p.memberRootId == sourceRootId) prefs

        targetPref : Maybe Settlement.Preference
        targetPref =
            firstMatching (\p -> p.memberRootId == targetRootId) prefs

        sourceRecipients : List Member.Id
        sourceRecipients =
            sourcePref |> Maybe.map .preferredRecipients |> Maybe.withDefault []

        targetRecipients : List Member.Id
        targetRecipients =
            targetPref |> Maybe.map .preferredRecipients |> Maybe.withDefault []

        rewriteRecipientList : Member.Id -> List Member.Id -> List Member.Id
        rewriteRecipientList ownerId ids =
            ids
                |> List.map
                    (\id ->
                        if id == sourceRootId then
                            targetRootId

                        else
                            id
                    )
                |> List.filter ((/=) ownerId)
                |> dedupeKeepFirst

        targetMergedRecipients : List Member.Id
        targetMergedRecipients =
            rewriteRecipientList targetRootId (targetRecipients ++ sourceRecipients)

        targetAction : List Action
        targetAction =
            case ( sourcePref, targetPref ) of
                ( Nothing, Nothing ) ->
                    []

                ( Nothing, Just tp ) ->
                    if targetMergedRecipients /= tp.preferredRecipients then
                        [ UpdateSettlementPref
                            { memberRootId = targetRootId
                            , preferredRecipients = targetMergedRecipients
                            }
                        ]

                    else
                        []

                _ ->
                    [ UpdateSettlementPref
                        { memberRootId = targetRootId
                        , preferredRecipients = targetMergedRecipients
                        }
                    ]

        otherActions : List Action
        otherActions =
            prefs
                |> List.filter (\p -> p.memberRootId /= sourceRootId && p.memberRootId /= targetRootId)
                |> List.filterMap
                    (\p ->
                        if List.member sourceRootId p.preferredRecipients then
                            Just
                                (UpdateSettlementPref
                                    { memberRootId = p.memberRootId
                                    , preferredRecipients = rewriteRecipientList p.memberRootId p.preferredRecipients
                                    }
                                )

                        else
                            Nothing
                    )
    in
    targetAction ++ otherActions


firstMatching : (a -> Bool) -> List a -> Maybe a
firstMatching pred items =
    case items of
        [] ->
            Nothing

        x :: rest ->
            if pred x then
                Just x

            else
                firstMatching pred rest


dedupeKeepFirst : List Member.Id -> List Member.Id
dedupeKeepFirst ids =
    let
        ( _, acc ) =
            List.foldl
                (\id ( seen, out ) ->
                    if List.member id seen then
                        ( seen, out )

                    else
                        ( id :: seen, id :: out )
                )
                ( [], [] )
                ids
    in
    List.reverse acc
