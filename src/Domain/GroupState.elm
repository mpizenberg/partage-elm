module Domain.GroupState exposing
    ( EntryState
    , GroupMetadata
    , GroupState
    , RejectionReason(..)
    , activeEntries
    , activeMembers
    , applyEvents
    , empty
    , nextLinkSeq
    , resolveMemberName
    , resolveMemberRootId
    , summarize
    )

{-| Event replay engine that builds group state from a list of events.
-}

import Dict exposing (Dict)
import Domain.Activity as Activity exposing (Activity)
import Domain.Balance as Balance exposing (MemberBalance)
import Domain.Currency exposing (Currency(..))
import Domain.Entry as Entry exposing (Entry, Kind(..))
import Domain.Event as Event exposing (Envelope, Payload(..))
import Domain.Group as Group
import Domain.Member as Member
import Domain.Settlement as Settlement
import Time


{-| The full state of a group, computed by replaying events.

The `anchor*` fields support `Domain.StableSettlement`: they hold the entries
as of the most recent **anchor-mover** event (anything other than a Transfer).
The displayed settlement plan is derived from `anchorBalances` +
`settlementPreferences`, then perturbed by the per-member delta
`balances − anchorBalances` (the cumulative effect of post-anchor transfers).
Snapshotting at anchor-movers — and _not_ at transfer events — is what keeps
the plan visually stable between expense edits.

-}
type alias GroupState =
    { members : Dict Member.Id Member.State
    , deviceLinks : Dict Member.Id Member.DeviceLink
    , entries : Dict Entry.Id EntryState
    , balances : Dict Member.Id MemberBalance
    , expenseShares : Dict Member.Id Int
    , groupMeta : GroupMetadata
    , activities : List Activity
    , pendingActivities : List Activity
    , rejectedEntries : List ( Entry.Entry, RejectionReason )
    , settlementPreferences : List Settlement.Preference
    , anchorEntries : Dict Entry.Id EntryState
    , anchorBalances : Dict Member.Id MemberBalance
    }


{-| Reason why an entry was rejected during event replay.
-}
type RejectionReason
    = NewEntryHasPreviousVersion
    | DuplicateEntryId
    | RootEntryNotFound
    | ModificationMissingPreviousVersion
    | SelfReferencingPreviousVersion
    | DuplicateVersionId
    | PreviousVersionNotFound
    | InvalidDepth
    | IsDeletedMismatch
    | CreatedByMismatch
    | CreatedAtMismatch


{-| An entry's computed state, tracking all versions and deletion status.
-}
type alias EntryState =
    { rootId : Entry.Id
    , currentVersion : Entry
    , isDeleted : Bool
    , allVersions : Dict Entry.Id Entry
    }


{-| Descriptive metadata for a group (name, subtitle, description, links).
-}
type alias GroupMetadata =
    { name : String
    , subtitle : Maybe String
    , description : Maybe String
    , links : List Group.Link
    , defaultCurrency : Currency
    , createdAt : Time.Posix
    }


{-| An empty group state with no members, entries, or metadata.
-}
empty : GroupState
empty =
    { members = Dict.empty
    , deviceLinks = Dict.empty
    , entries = Dict.empty
    , balances = Dict.empty
    , expenseShares = Dict.empty
    , groupMeta =
        { name = ""
        , subtitle = Nothing
        , description = Nothing
        , links = []
        , defaultCurrency = EUR
        , createdAt = Time.millisToPosix 0
        }
    , activities = []
    , pendingActivities = []
    , rejectedEntries = []
    , settlementPreferences = []
    , anchorEntries = Dict.empty
    , anchorBalances = Dict.empty
    }



-- TODO: add argument of current id to extract user balance


summarize : Member.Id -> Group.Id -> GroupState -> Group.Summary
summarize memberId groupId state =
    { id = groupId
    , name = state.groupMeta.name
    , defaultCurrency = state.groupMeta.defaultCurrency
    , isSubscribed = False
    , isArchived = False
    , createdAt = state.groupMeta.createdAt
    , memberCount =
        -- TODO: maybe a more efficient way than recreate a dict would be better ^^
        Dict.filter (\_ m -> not m.isRetired) state.members
            |> Dict.size
    , myBalanceCents =
        resolveMemberRootId state memberId
            |> Maybe.andThen (\rootId -> Dict.get rootId state.balances)
            |> Maybe.map .netBalance
            |> Maybe.withDefault 0
    }


{-| Apply a list of events to a GroupState.
Events are sorted before application. Balances are recomputed after all events.
Can be used from scratch with `empty` or incrementally on an existing state.
New activities are accumulated in a buffer then merged in sorted order.
-}
applyEvents : List Envelope -> GroupState -> GroupState
applyEvents events state =
    let
        stateAfterFold : GroupState
        stateAfterFold =
            List.foldl applyEvent state (Event.sortEvents events)
    in
    { stateAfterFold
        | activities = mergeActivities stateAfterFold.pendingActivities stateAfterFold.activities
        , pendingActivities = []
    }
        |> recomputeBalances


{-| Recompute all member balances from the current active entries, plus the
matching `anchorBalances` from `anchorEntries`.
-}
recomputeBalances : GroupState -> GroupState
recomputeBalances state =
    let
        active : List Entry
        active =
            activeEntries state
    in
    { state
        | balances = Balance.computeBalances active
        , expenseShares = Balance.computeExpenseShares active
        , anchorBalances = Balance.computeBalances (activeEntriesFrom state.anchorEntries)
    }


{-| Apply a single event to the group state, without recomputing balances.
Builds an activity item from the state before the event is applied, then
mutates the state. New activities accumulate in pendingActivities (newest-first).
On an anchor-mover event the anchor cache is also snapshotted (see the
docstring on `GroupState` and `isAnchorMover` below).
Not exposed — use `applyEvents` which merges pending into activities after all events.
-}
applyEvent : Envelope -> GroupState -> GroupState
applyEvent envelope state =
    if not (isAuthorized state envelope) then
        state

    else
        let
            activity : Activity
            activity =
                Activity.fromEnvelope (activityContext state) envelope

            anchored : Bool
            anchored =
                isAnchorMover envelope.payload state

            newState : GroupState
            newState =
                applyPayload envelope state

            withSnapshot : GroupState
            withSnapshot =
                if anchored then
                    { newState | anchorEntries = newState.entries }

                else
                    newState
        in
        { withSnapshot | pendingActivities = activity :: withSnapshot.pendingActivities }


{-| Classify an event as an anchor-mover for the stable settlement cache.
Anchor-movers are events that change `balances` or `settlementPreferences`
_and_ are not Transfer events. The kind for delete/undelete is read from the
pre-event entry state (the event payload only carries the rootId); for
add/modify it comes from the new payload.

The user-level invariant is "transfers never anchor-move," so
a pre-anchor edit that retroactively shifts the balance is just folded into
the post-anchor delta and absorbed by the vector update. The displayed plan
stays correct either way; this choice keeps the cache simple (no per-entry
timestamps, no anchor timestamp) and avoids re-shuffling on transfer edits.

-}
isAnchorMover : Payload -> GroupState -> Bool
isAnchorMover payload state =
    case payload of
        EntryAdded entry ->
            not (isTransferEntry entry)

        EntryModified entry ->
            not (isTransferEntry entry)

        EntryDeleted { rootId } ->
            isKnownNonTransfer state rootId

        EntryUndeleted { rootId } ->
            isKnownNonTransfer state rootId

        SettlementPreferencesUpdated _ ->
            True

        MemberCreated _ ->
            False

        MemberRenamed _ ->
            False

        MemberRetired _ ->
            False

        MemberUnretired _ ->
            False

        MemberLinked _ ->
            False

        MemberMetadataUpdated _ ->
            False

        GroupCreated _ ->
            False

        GroupMetadataUpdated _ ->
            False


isTransferEntry : Entry -> Bool
isTransferEntry entry =
    case entry.kind of
        Transfer _ ->
            True

        _ ->
            False


isKnownNonTransfer : GroupState -> Entry.Id -> Bool
isKnownNonTransfer state rootId =
    case Dict.get rootId state.entries of
        Just es ->
            not (isTransferEntry es.currentVersion)

        Nothing ->
            False


{-| Check if an event's author is authorized to perform the action.
-}
isAuthorized : GroupState -> Envelope -> Bool
isAuthorized state envelope =
    case envelope.payload of
        GroupCreated _ ->
            True

        MemberCreated data ->
            data.memberId == envelope.triggeredBy || isMember state envelope.triggeredBy

        MemberLinked data ->
            data.deviceId == envelope.triggeredBy

        _ ->
            isMember state envelope.triggeredBy


{-| Check if an ID is a known member (root ID or linked device ID).
-}
isMember : GroupState -> Member.Id -> Bool
isMember state memberId =
    resolveMemberRootId state memberId /= Nothing


applyPayload : Envelope -> GroupState -> GroupState
applyPayload envelope state =
    let
        timestamp : Time.Posix
        timestamp =
            envelope.clientTimestamp
    in
    case envelope.payload of
        MemberCreated data ->
            applyMemberCreated timestamp data state

        MemberRenamed data ->
            applyMemberRenamed data state

        MemberRetired data ->
            applyMemberRetired data state

        MemberUnretired data ->
            applyMemberUnretired data state

        MemberLinked data ->
            applyMemberLinked timestamp envelope.id data state

        MemberMetadataUpdated data ->
            applyMemberMetadataUpdated data state

        EntryAdded entry ->
            applyEntryUpsert entry state

        EntryModified entry ->
            applyEntryUpsert entry state

        EntryDeleted data ->
            applyEntryDeleted data state

        EntryUndeleted data ->
            applyEntryUndeleted data state

        GroupCreated data ->
            applyGroupCreated timestamp data state

        GroupMetadataUpdated change ->
            applyGroupMetadataUpdated change state

        SettlementPreferencesUpdated data ->
            applySettlementPreferencesUpdated data state



-- MEMBER HANDLERS


applyMemberCreated : Time.Posix -> { memberId : Member.Id, name : String, memberType : Member.Type, addedBy : Member.Id, publicKey : String } -> GroupState -> GroupState
applyMemberCreated timestamp data state =
    if Dict.member data.memberId state.members then
        -- Member with this rootId already exists, ignore
        state

    else
        let
            member : Member.State
            member =
                { rootId = data.memberId
                , name = data.name
                , memberType = data.memberType
                , publicKey = data.publicKey
                , isRetired = False
                , joinedAt = timestamp
                , metadata = Member.emptyMetadata
                }
        in
        { state | members = Dict.insert data.memberId member state.members }


applyMemberRenamed : { rootId : Member.Id, oldName : String, newName : String } -> GroupState -> GroupState
applyMemberRenamed data state =
    case Dict.get data.rootId state.members of
        Nothing ->
            state

        Just member ->
            let
                updated : Member.State
                updated =
                    { member | name = data.newName }
            in
            { state | members = Dict.insert data.rootId updated state.members }


applyMemberRetired : { rootId : Member.Id } -> GroupState -> GroupState
applyMemberRetired data state =
    case Dict.get data.rootId state.members of
        Nothing ->
            state

        Just member ->
            if not member.isRetired then
                let
                    updated : Member.State
                    updated =
                        { member | isRetired = True }
                in
                { state | members = Dict.insert data.rootId updated state.members }

            else
                -- Already retired, ignore
                state


applyMemberUnretired : { rootId : Member.Id } -> GroupState -> GroupState
applyMemberUnretired data state =
    case Dict.get data.rootId state.members of
        Nothing ->
            state

        Just member ->
            if member.isRetired then
                let
                    updated : Member.State
                    updated =
                        { member | isRetired = False }
                in
                { state | members = Dict.insert data.rootId updated state.members }

            else
                state


{-| Apply a device's claim on a member root. Per device only the winning link
is kept (highest seq, timestamp, event id — see `Member.pickLink`), so a
losing claim changes nothing and application is order-independent. The
effective member type of the claimed root — and of the root the device
previously pointed at — is refreshed from the updated link map.
-}
applyMemberLinked : Time.Posix -> Event.Id -> { rootId : Member.Id, deviceId : Member.Id, publicKey : String, seq : Int } -> GroupState -> GroupState
applyMemberLinked timestamp eventId data state =
    if not (Dict.member data.rootId state.members) then
        state

    else
        let
            newLink : Member.DeviceLink
            newLink =
                { rootId = data.rootId
                , publicKey = data.publicKey
                , seq = data.seq
                , timestamp = timestamp
                , eventId = eventId
                }

            previousLink : Maybe Member.DeviceLink
            previousLink =
                Dict.get data.deviceId state.deviceLinks

            winner : Member.DeviceLink
            winner =
                previousLink
                    |> Maybe.map (\existing -> Member.pickLink existing newLink)
                    |> Maybe.withDefault newLink

            updatedLinks : Dict Member.Id Member.DeviceLink
            updatedLinks =
                Dict.insert data.deviceId winner state.deviceLinks

            affectedRoots : List Member.Id
            affectedRoots =
                winner.rootId
                    :: List.filterMap (Maybe.map .rootId) [ previousLink ]
        in
        { state
            | deviceLinks = updatedLinks
            , members = List.foldl (refreshEffectiveType updatedLinks) state.members affectedRoots
        }


{-| Recompute a root's effective member type from the device-link map:
Real when created real (it has a public key) or some device links to it.
-}
refreshEffectiveType : Dict Member.Id Member.DeviceLink -> Member.Id -> Dict Member.Id Member.State -> Dict Member.Id Member.State
refreshEffectiveType links rootId members =
    let
        isClaimed : Bool
        isClaimed =
            Dict.foldl (\_ link found -> found || link.rootId == rootId) False links

        effectiveType : Member.State -> Member.Type
        effectiveType member =
            if member.publicKey /= "" || isClaimed then
                Member.Real

            else
                Member.Virtual
    in
    Dict.update rootId
        (Maybe.map (\member -> { member | memberType = effectiveType member }))
        members


applyMemberMetadataUpdated : { rootId : Member.Id, metadata : Member.Metadata } -> GroupState -> GroupState
applyMemberMetadataUpdated data state =
    case Dict.get data.rootId state.members of
        Nothing ->
            state

        Just member ->
            let
                updated : Member.State
                updated =
                    { member | metadata = data.metadata }
            in
            { state | members = Dict.insert data.rootId updated state.members }



-- ENTRY HANDLERS


{-| Validate and insert an entry (new or modification) into the group state.
Invalid entries are silently ignored.
-}
applyEntryUpsert : Entry -> GroupState -> GroupState
applyEntryUpsert ({ meta } as entry) state =
    let
        reject : RejectionReason -> GroupState
        reject reason =
            { state | rejectedEntries = ( entry, reason ) :: state.rejectedEntries }
    in
    if meta.rootId == meta.id then
        -- New entry: previousVersionId must be Nothing
        if meta.previousVersionId /= Nothing then
            reject NewEntryHasPreviousVersion

        else if Dict.member meta.id state.entries then
            reject DuplicateEntryId

        else
            let
                entryState : EntryState
                entryState =
                    { rootId = meta.id
                    , currentVersion = entry
                    , isDeleted = meta.isDeleted
                    , allVersions = Dict.singleton meta.id entry
                    }
            in
            { state | entries = Dict.insert meta.id entryState state.entries }

    else
        -- Modification: validate against existing entry state
        case Dict.get meta.rootId state.entries of
            Nothing ->
                reject RootEntryNotFound

            Just entryState ->
                case meta.previousVersionId of
                    Nothing ->
                        reject ModificationMissingPreviousVersion

                    Just prevId ->
                        if prevId == meta.id then
                            reject SelfReferencingPreviousVersion

                        else if Dict.member meta.id entryState.allVersions then
                            reject DuplicateVersionId

                        else
                            case Dict.get prevId entryState.allVersions of
                                Nothing ->
                                    reject PreviousVersionNotFound

                                Just prev ->
                                    if meta.depth /= prev.meta.depth + 1 then
                                        reject InvalidDepth

                                    else if meta.isDeleted /= prev.meta.isDeleted then
                                        reject IsDeletedMismatch

                                    else if meta.createdBy /= prev.meta.createdBy then
                                        reject CreatedByMismatch

                                    else if meta.createdAt /= prev.meta.createdAt then
                                        reject CreatedAtMismatch

                                    else
                                        let
                                            updatedVersions : Dict Entry.Id Entry
                                            updatedVersions =
                                                Dict.insert meta.id entry entryState.allVersions

                                            current : Entry
                                            current =
                                                pickVersion entryState.currentVersion entry

                                            updatedEntryState : EntryState
                                            updatedEntryState =
                                                { entryState
                                                    | allVersions = updatedVersions
                                                    , currentVersion = current
                                                    , isDeleted = current.meta.isDeleted
                                                }
                                        in
                                        { state | entries = Dict.insert meta.rootId updatedEntryState state.entries }


{-| Pick the winning version between two entries.
Deeper version (longer replacement chain) wins. Entry id breaks ties.
-}
pickVersion : Entry -> Entry -> Entry
pickVersion a b =
    case compare a.meta.depth b.meta.depth of
        GT ->
            a

        LT ->
            b

        EQ ->
            if a.meta.id >= b.meta.id then
                a

            else
                b


applyEntryDeleted : { rootId : Entry.Id } -> GroupState -> GroupState
applyEntryDeleted data state =
    case Dict.get data.rootId state.entries of
        Nothing ->
            state

        Just entryState ->
            let
                updated : EntryState
                updated =
                    { entryState | isDeleted = True }
            in
            { state | entries = Dict.insert data.rootId updated state.entries }


applyEntryUndeleted : { rootId : Entry.Id } -> GroupState -> GroupState
applyEntryUndeleted data state =
    case Dict.get data.rootId state.entries of
        Nothing ->
            state

        Just entryState ->
            let
                updated : EntryState
                updated =
                    { entryState | isDeleted = False }
            in
            { state | entries = Dict.insert data.rootId updated state.entries }



-- GROUP METADATA


applyGroupCreated : Time.Posix -> { name : String, defaultCurrency : Currency } -> GroupState -> GroupState
applyGroupCreated timestamp data state =
    { state
        | groupMeta =
            { name = data.name
            , subtitle = Nothing
            , description = Nothing
            , links = []
            , defaultCurrency = data.defaultCurrency
            , createdAt = timestamp
            }
    }


applyGroupMetadataUpdated : Event.GroupMetadataChange -> GroupState -> GroupState
applyGroupMetadataUpdated change state =
    let
        meta : GroupMetadata
        meta =
            state.groupMeta

        updated : GroupMetadata
        updated =
            { meta
                | name = Maybe.withDefault meta.name change.name
                , subtitle = Maybe.withDefault meta.subtitle change.subtitle
                , description = Maybe.withDefault meta.description change.description
                , links = Maybe.withDefault meta.links change.links
            }
    in
    { state | groupMeta = updated }



-- SETTLEMENT PREFERENCES


applySettlementPreferencesUpdated : { memberRootId : Member.Id, preferredRecipients : List Member.Id } -> GroupState -> GroupState
applySettlementPreferencesUpdated data state =
    let
        updatedPreferences : List Settlement.Preference
        updatedPreferences =
            if List.isEmpty data.preferredRecipients then
                List.filter (\p -> p.memberRootId /= data.memberRootId) state.settlementPreferences

            else
                let
                    newPref : Settlement.Preference
                    newPref =
                        { memberRootId = data.memberRootId
                        , preferredRecipients = data.preferredRecipients
                        }
                in
                newPref :: List.filter (\p -> p.memberRootId /= data.memberRootId) state.settlementPreferences
    in
    { state | settlementPreferences = updatedPreferences }



-- ACTIVITY BUILDING


activityContext : GroupState -> Activity.StateContext
activityContext state =
    { resolveName = resolveMemberName state
    , memberMetadata =
        \rootId ->
            Dict.get rootId state.members
                |> Maybe.map .metadata
                |> Maybe.withDefault Member.emptyMetadata
    , entryDescription = lookupEntryDescription state
    , entryCurrentVersion = lookupEntryCurrentVersion state
    , previousVersion = lookupPreviousVersion state
    , groupMeta =
        { name = state.groupMeta.name
        , subtitle = state.groupMeta.subtitle
        , description = state.groupMeta.description
        , links = state.groupMeta.links
        }
    , settlementPreference = lookupSettlementPreference state
    }


lookupEntryCurrentVersion : GroupState -> Entry.Id -> Maybe Entry
lookupEntryCurrentVersion state rootId =
    Dict.get rootId state.entries
        |> Maybe.map .currentVersion


lookupPreviousVersion : GroupState -> Entry -> Maybe Entry
lookupPreviousVersion state entry =
    entry.meta.previousVersionId
        |> Maybe.andThen
            (\prevId ->
                Dict.get entry.meta.rootId state.entries
                    |> Maybe.andThen (\entryState -> Dict.get prevId entryState.allVersions)
            )


lookupEntryDescription : GroupState -> Entry.Id -> String
lookupEntryDescription state rootId =
    case Dict.get rootId state.entries of
        Just entryState ->
            case entryState.currentVersion.kind of
                Expense data ->
                    data.description

                Transfer _ ->
                    "Transfer"

                Income data ->
                    data.description

        Nothing ->
            rootId


lookupSettlementPreference : GroupState -> Member.Id -> List Member.Id
lookupSettlementPreference state memberRootId =
    state.settlementPreferences
        |> List.filter (\p -> p.memberRootId == memberRootId)
        |> List.head
        |> Maybe.map .preferredRecipients
        |> Maybe.withDefault []



-- QUERY FUNCTIONS


{-| Resolve a device or root ID to a root ID. The device-link map takes
precedence over root identity, so a device that joined as its own member but
later linked elsewhere resolves to the link target. Returns Nothing for
unknown IDs.
-}
resolveMemberRootId : GroupState -> Member.Id -> Maybe Member.Id
resolveMemberRootId state memberId =
    case Dict.get memberId state.deviceLinks of
        Just link ->
            Just link.rootId

        Nothing ->
            if Dict.member memberId state.members then
                Just memberId

            else
                Nothing


{-| The sequence number the next MemberLinked event from this device must
carry to beat the device's current winning link.
-}
nextLinkSeq : GroupState -> Member.Id -> Int
nextLinkSeq state deviceId =
    Dict.get deviceId state.deviceLinks
        |> Maybe.map (\link -> link.seq + 1)
        |> Maybe.withDefault 0


{-| Resolve a member ID (root or device) to a display name. Falls back to the raw ID if not found.
-}
resolveMemberName : GroupState -> Member.Id -> String
resolveMemberName state memberId =
    resolveMemberRootId state memberId
        |> Maybe.andThen (\rootId -> Dict.get rootId state.members)
        |> Maybe.map .name
        |> Maybe.withDefault memberId


{-| Merge new activities into existing ones, maintaining newest-first order.
Both lists must already be sorted newest-first. Tail-recursive.
-}
mergeActivities : List Activity -> List Activity -> List Activity
mergeActivities new existing =
    mergeActivitiesHelp new existing []


mergeActivitiesHelp : List Activity -> List Activity -> List Activity -> List Activity
mergeActivitiesHelp new existing acc =
    case ( new, existing ) of
        ( [], _ ) ->
            List.reverse acc ++ existing

        ( _, [] ) ->
            List.reverse acc ++ new

        ( n :: ns, e :: es ) ->
            if Time.posixToMillis n.timestamp >= Time.posixToMillis e.timestamp then
                mergeActivitiesHelp ns existing (n :: acc)

            else
                mergeActivitiesHelp new es (e :: acc)


{-| Get all active (non-retired) members.
-}
activeMembers : GroupState -> List Member.State
activeMembers state =
    Dict.values state.members
        |> List.filter (not << .isRetired)


{-| Get all active (non-deleted) entries.
-}
activeEntries : GroupState -> List Entry
activeEntries state =
    activeEntriesFrom state.entries


activeEntriesFrom : Dict Entry.Id EntryState -> List Entry
activeEntriesFrom entriesDict =
    Dict.values entriesDict
        |> List.filter (not << .isDeleted)
        |> List.map .currentVersion
