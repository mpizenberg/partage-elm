module Domain.GroupState exposing
    ( EntryState
    , GroupMetadata
    , GroupState
    , MemberState
    , RejectionReason(..)
    , activeEntries
    , activeMembers
    , applyEvent
    , applyEvents
    , empty
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
    { members : Dict Member.Id MemberState
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


{-| A member's computed state after applying all events,
including lifecycle flags and replacement chain info.
-}
type alias MemberState =
    { id : Member.Id
    , rootId : Member.Id
    , previousId : Maybe Member.Id
    , name : String
    , memberType : Member.Type
    , isRetired : Bool
    , isReplaced : Bool
    , isActive : Bool
    , metadata : Member.Metadata
    }


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


{-| Build a GroupState by sorting and replaying a list of events from scratch.
-}
applyEvents : List Envelope -> GroupState
applyEvents events =
    List.foldl applyEvent empty (Event.sortEvents events)


{-| Apply a single event to the group state.
Invalid or duplicate events are silently ignored.
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
                |> recomputeBalances

        EntryModified entry ->
            applyEntryUpsert entry state
                |> recomputeBalances

        EntryDeleted data ->
            applyEntryDeleted data state
                |> recomputeBalances

        EntryUndeleted data ->
            applyEntryUndeleted data state
                |> recomputeBalances

        GroupMetadataUpdated change ->
            applyGroupMetadataUpdated change state


recomputeBalances : GroupState -> GroupState
recomputeBalances state =
    { state | balances = Balance.computeBalances (resolveMemberRootId state) (activeEntries state) }



-- MEMBER HANDLERS


applyMemberCreated : { memberId : Member.Id, name : String, memberType : Member.Type, addedBy : Member.Id } -> GroupState -> GroupState
applyMemberCreated data state =
    if Dict.member data.memberId state.members then
        -- Member already exists, ignore
        state

    else
        let
            member =
                { id = data.memberId
                , rootId = data.memberId
                , previousId = Nothing
                , name = data.name
                , memberType = data.memberType
                , isRetired = False
                , isReplaced = False
                , isActive = True
                , metadata = Member.emptyMetadata
                }
        in
        { state | members = Dict.insert data.memberId member state.members }


applyMemberRenamed : { memberId : Member.Id, oldName : String, newName : String } -> GroupState -> GroupState
applyMemberRenamed data state =
    case Dict.get data.memberId state.members of
        Nothing ->
            state

        Just member ->
            let
                updated =
                    { member | name = data.newName }
            in
            { state | members = Dict.insert data.memberId updated state.members }


applyMemberRetired : { memberId : Member.Id } -> GroupState -> GroupState
applyMemberRetired data state =
    case Dict.get data.memberId state.members of
        Nothing ->
            state

        Just member ->
            if member.isActive then
                let
                    updated =
                        { member | isRetired = True, isActive = False }
                in
                { state | members = Dict.insert data.memberId updated state.members }

            else
                -- Already retired or replaced, ignore
                state


applyMemberUnretired : { memberId : Member.Id } -> GroupState -> GroupState
applyMemberUnretired data state =
    case Dict.get data.memberId state.members of
        Nothing ->
            state

        Just member ->
            if member.isRetired && not member.isReplaced then
                let
                    updated =
                        { member | isRetired = False, isActive = True }
                in
                { state | members = Dict.insert data.memberId updated state.members }

            else
                state


applyMemberReplaced : { previousId : Member.Id, newId : Member.Id } -> GroupState -> GroupState
applyMemberReplaced data state =
    if data.previousId == data.newId then
        -- Cannot replace self
        state

    else
        case Dict.get data.previousId state.members of
            Nothing ->
                state

            Just prevMember ->
                if not prevMember.isActive then
                    -- Already retired or replaced, ignore
                    state

                else
                    case Dict.get data.newId state.members of
                        Nothing ->
                            -- New member doesn't exist yet, ignore
                            state

                        Just newMember ->
                            let
                                updatedPrev =
                                    { prevMember | isReplaced = True, isActive = False }

                                updatedNew =
                                    { newMember
                                        | rootId = prevMember.rootId
                                        , previousId = Just data.previousId
                                    }
                            in
                            { state
                                | members =
                                    state.members
                                        |> Dict.insert data.previousId updatedPrev
                                        |> Dict.insert data.newId updatedNew
                            }


applyMemberMetadataUpdated : { memberId : Member.Id, metadata : Member.Metadata } -> GroupState -> GroupState
applyMemberMetadataUpdated data state =
    case Dict.get data.memberId state.members of
        Nothing ->
            state

        Just member ->
            let
                updated =
                    { member | metadata = data.metadata }
            in
            { state | members = Dict.insert data.memberId updated state.members }



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


{-| Resolve a member ID to its root ID, following replacement chains.
-}
resolveMemberRootId : GroupState -> Member.Id -> Member.Id
resolveMemberRootId state memberId =
    case Dict.get memberId state.members of
        Just member ->
            member.rootId

        Nothing ->
            memberId


{-| Get all active (non-retired, non-replaced) members.
-}
activeMembers : GroupState -> List MemberState
activeMembers state =
    Dict.values state.members
        |> List.filter .isActive


{-| Get all active (non-deleted) entries.
-}
activeEntries : GroupState -> List Entry
activeEntries state =
    Dict.values state.entries
        |> List.filter (not << .isDeleted)
        |> List.map .currentVersion
