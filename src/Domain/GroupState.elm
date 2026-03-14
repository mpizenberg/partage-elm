module Domain.GroupState exposing
    ( EntryState
    , GroupMetadata
    , GroupState
    , RejectionReason(..)
    , activeEntries
    , activeMembers
    , applyEvents
    , empty
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
-}
type alias GroupState =
    { members : Dict Member.Id Member.ChainState
    , entries : Dict Entry.Id EntryState
    , balances : Dict Member.Id MemberBalance
    , groupMeta : GroupMetadata
    , activities : List Activity
    , pendingActivities : List Activity
    , rejectedEntries : List ( Entry.Entry, RejectionReason )
    , settlementPreferences : List Settlement.Preference
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
    , entries = Dict.empty
    , balances = Dict.empty
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
    }



-- TODO: add argument of current id to extract user balance


summarize : Member.Id -> Group.Id -> GroupState -> Group.Summary
summarize memberId groupId state =
    { id = groupId
    , name = state.groupMeta.name
    , defaultCurrency = state.groupMeta.defaultCurrency
    , isSubscribed = False
    , createdAt = state.groupMeta.createdAt
    , memberCount =
        -- TODO: maybe a more efficient way than recreate a dict would be better ^^
        Dict.filter (\_ m -> not m.isRetired) state.members
            |> Dict.size
    , myBalanceCents =
        Dict.get (resolveMemberRootId state memberId) state.balances
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


{-| Recompute all member balances from the current active entries.
-}
recomputeBalances : GroupState -> GroupState
recomputeBalances state =
    { state | balances = Balance.computeBalances (activeEntries state) }


{-| Apply a single event to the group state, without recomputing balances.
Builds an activity item from the state before the event is applied, then
mutates the state. New activities accumulate in pendingActivities (newest-first).
Not exposed — use `applyEvents` which merges pending into activities after all events.
-}
applyEvent : Envelope -> GroupState -> GroupState
applyEvent envelope state =
    let
        activity : Activity
        activity =
            Activity.fromEnvelope (activityContext state) envelope

        newState : GroupState
        newState =
            applyPayload envelope.clientTimestamp envelope.payload state
    in
    { newState | pendingActivities = activity :: newState.pendingActivities }


applyPayload : Time.Posix -> Payload -> GroupState -> GroupState
applyPayload timestamp payload state =
    case payload of
        MemberCreated data ->
            applyMemberCreated timestamp data state

        MemberRenamed data ->
            applyMemberRenamed data state

        MemberRetired data ->
            applyMemberRetired data state

        MemberUnretired data ->
            applyMemberUnretired data state

        MemberReplaced data ->
            applyMemberReplaced data state

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


applyMemberCreated : Time.Posix -> { memberId : Member.Id, name : String, memberType : Member.Type, addedBy : Member.Id } -> GroupState -> GroupState
applyMemberCreated timestamp data state =
    if Dict.member data.memberId state.members then
        -- Chain with this rootId already exists, ignore
        state

    else
        let
            memberInfo : Member.Info
            memberInfo =
                { id = data.memberId
                , previousId = Nothing
                , depth = 0
                , memberType = data.memberType
                }

            chain : Member.ChainState
            chain =
                { rootId = data.memberId
                , name = data.name
                , isRetired = False
                , joinedAt = timestamp
                , metadata = Member.emptyMetadata
                , currentMember = memberInfo
                , allMembers = Dict.singleton data.memberId memberInfo
                }
        in
        { state | members = Dict.insert data.memberId chain state.members }


applyMemberRenamed : { rootId : Member.Id, oldName : String, newName : String } -> GroupState -> GroupState
applyMemberRenamed data state =
    case Dict.get data.rootId state.members of
        Nothing ->
            state

        Just chain ->
            let
                updated : Member.ChainState
                updated =
                    { chain | name = data.newName }
            in
            { state | members = Dict.insert data.rootId updated state.members }


applyMemberRetired : { rootId : Member.Id } -> GroupState -> GroupState
applyMemberRetired data state =
    case Dict.get data.rootId state.members of
        Nothing ->
            state

        Just chain ->
            if not chain.isRetired then
                let
                    updated : Member.ChainState
                    updated =
                        { chain | isRetired = True }
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

        Just chain ->
            if chain.isRetired then
                let
                    updated : Member.ChainState
                    updated =
                        { chain | isRetired = False }
                in
                { state | members = Dict.insert data.rootId updated state.members }

            else
                state


applyMemberReplaced : { rootId : Member.Id, previousId : Member.Id, newId : Member.Id } -> GroupState -> GroupState
applyMemberReplaced data state =
    if data.previousId == data.newId then
        -- Cannot replace self
        state

    else
        case Dict.get data.rootId state.members of
            Nothing ->
                -- Chain doesn't exist
                state

            Just chain ->
                case Dict.get data.previousId chain.allMembers of
                    Nothing ->
                        -- previousId not in chain
                        state

                    Just prev ->
                        if Dict.member data.newId chain.allMembers then
                            -- Duplicate newId in chain
                            state

                        else
                            let
                                newMemberInfo : Member.Info
                                newMemberInfo =
                                    { id = data.newId
                                    , previousId = Just data.previousId
                                    , depth = prev.depth + 1
                                    , memberType = Member.Real
                                    }

                                updatedAllMembers : Dict Member.Id Member.Info
                                updatedAllMembers =
                                    Dict.insert data.newId newMemberInfo chain.allMembers

                                current : Member.Info
                                current =
                                    Member.pickCurrent chain.currentMember newMemberInfo

                                updatedChain : Member.ChainState
                                updatedChain =
                                    { chain
                                        | allMembers = updatedAllMembers
                                        , currentMember = current
                                    }
                            in
                            { state | members = Dict.insert data.rootId updatedChain state.members }


applyMemberMetadataUpdated : { rootId : Member.Id, metadata : Member.Metadata } -> GroupState -> GroupState
applyMemberMetadataUpdated data state =
    case Dict.get data.rootId state.members of
        Nothing ->
            state

        Just chain ->
            let
                updated : Member.ChainState
                updated =
                    { chain | metadata = data.metadata }
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


{-| Resolve a device member ID to its root ID.
First checks if it's a root ID directly, then scans allMembers dicts.
-}
resolveMemberRootId : GroupState -> Member.Id -> Member.Id
resolveMemberRootId state deviceId =
    if Dict.member deviceId state.members then
        deviceId

    else
        -- Scan allMembers dicts to find which chain contains this device ID
        Dict.foldl
            (\rootId chain found ->
                case found of
                    Just _ ->
                        found

                    Nothing ->
                        if Dict.member deviceId chain.allMembers then
                            Just rootId

                        else
                            Nothing
            )
            Nothing
            state.members
            |> Maybe.withDefault deviceId


{-| Resolve a member ID (root or device) to a display name. Falls back to the raw ID if not found.
-}
resolveMemberName : GroupState -> Member.Id -> String
resolveMemberName state memberId =
    let
        rootId : Member.Id
        rootId =
            resolveMemberRootId state memberId
    in
    case Dict.get rootId state.members of
        Just chain ->
            chain.name

        Nothing ->
            memberId


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
activeMembers : GroupState -> List Member.ChainState
activeMembers state =
    Dict.values state.members
        |> List.filter (not << .isRetired)


{-| Get all active (non-deleted) entries.
-}
activeEntries : GroupState -> List Entry
activeEntries state =
    Dict.values state.entries
        |> List.filter (not << .isDeleted)
        |> List.map .currentVersion
