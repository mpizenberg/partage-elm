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
    )

{-| Event replay engine that builds group state from a list of events.
-}

import Dict exposing (Dict)
import Domain.Balance as Balance exposing (MemberBalance)
import Domain.Entry as Entry exposing (Entry)
import Domain.Event as Event exposing (Envelope, Payload(..))
import Domain.Group as Group
import Domain.Member as Member


{-| The full state of a group, computed by replaying events.
-}
type alias GroupState =
    { members : Dict Member.Id Member.ChainState
    , entries : Dict Entry.Id EntryState
    , balances : Dict Member.Id MemberBalance
    , groupMeta : GroupMetadata
    , rejectedEntries : List ( Entry.Entry, RejectionReason )
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
        }
    , rejectedEntries = []
    }


{-| Apply a list of events to a GroupState.
Events are sorted before application. Balances are recomputed after all events.
Can be used from scratch with `empty` or incrementally on an existing state.
-}
applyEvents : List Envelope -> GroupState -> GroupState
applyEvents events state =
    List.foldl applyEvent state (Event.sortEvents events)
        |> recomputeBalances


{-| Recompute all member balances from the current active entries.
-}
recomputeBalances : GroupState -> GroupState
recomputeBalances state =
    { state | balances = Balance.computeBalances (activeEntries state) }


{-| Apply a single event to the group state, without recomputing balances.
Invalid or duplicate events are silently ignored.
Not exposed — use `applyEvents` which recomputes balances after all events.
-}
applyEvent : Envelope -> GroupState -> GroupState
applyEvent envelope state =
    case envelope.payload of
        MemberCreated data ->
            applyMemberCreated data state

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

        GroupMetadataUpdated change ->
            applyGroupMetadataUpdated change state



-- MEMBER HANDLERS


applyMemberCreated : { memberId : Member.Id, name : String, memberType : Member.Type, addedBy : Member.Id } -> GroupState -> GroupState
applyMemberCreated data state =
    if Dict.member data.memberId state.members then
        -- Chain with this rootId already exists, ignore
        state

    else
        let
            memberInfo =
                { id = data.memberId
                , previousId = Nothing
                , depth = 0
                , memberType = data.memberType
                }

            chain =
                { rootId = data.memberId
                , name = data.name
                , isRetired = False
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
                                newMemberInfo =
                                    { id = data.newId
                                    , previousId = Just data.previousId
                                    , depth = prev.depth + 1
                                    , memberType = Member.Real
                                    }

                                updatedAllMembers =
                                    Dict.insert data.newId newMemberInfo chain.allMembers

                                current =
                                    Member.pickCurrent chain.currentMember newMemberInfo

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
                                            updatedVersions =
                                                Dict.insert meta.id entry entryState.allVersions

                                            current =
                                                pickVersion entryState.currentVersion entry

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
                updated =
                    { entryState | isDeleted = False }
            in
            { state | entries = Dict.insert data.rootId updated state.entries }



-- GROUP METADATA


applyGroupMetadataUpdated : Event.GroupMetadataChange -> GroupState -> GroupState
applyGroupMetadataUpdated change state =
    let
        meta =
            state.groupMeta

        updated =
            { meta
                | name = Maybe.withDefault meta.name change.name
                , subtitle = Maybe.withDefault meta.subtitle change.subtitle
                , description = Maybe.withDefault meta.description change.description
                , links = Maybe.withDefault meta.links change.links
            }
    in
    { state | groupMeta = updated }



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


{-| Resolve a member root ID to a display name. Falls back to the raw ID if not found.
-}
resolveMemberName : GroupState -> Member.Id -> String
resolveMemberName state memberId =
    case Dict.get memberId state.members of
        Just chain ->
            chain.name

        Nothing ->
            memberId


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
