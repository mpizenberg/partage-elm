module Domain.GroupState exposing
    ( EntryState
    , GroupMetadata
    , GroupState
    , MemberState
    , activeEntries
    , activeMembers
    , applyEvent
    , applyEvents
    , empty
    , resolveMemberRootId
    )

import Dict exposing (Dict)
import Domain.Entry as Entry exposing (Entry)
import Domain.Event as Event exposing (Envelope, Payload(..))
import Domain.Group as Group
import Domain.Member as Member
import Time


type alias GroupState =
    { members : Dict Member.Id MemberState
    , entries : Dict Entry.Id EntryState
    , groupMeta : GroupMetadata
    , replacedBy : Dict Member.Id Member.Id
    }


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


type alias EntryState =
    { rootId : Entry.Id
    , currentVersion : Entry
    , isDeleted : Bool
    , allVersions : Dict Entry.Id Entry
    }


type alias GroupMetadata =
    { name : String
    , subtitle : Maybe String
    , description : Maybe String
    , links : List Group.Link
    }


empty : GroupState
empty =
    { members = Dict.empty
    , entries = Dict.empty
    , groupMeta =
        { name = ""
        , subtitle = Nothing
        , description = Nothing
        , links = []
        }
    , replacedBy = Dict.empty
    }


applyEvents : List Envelope -> GroupState
applyEvents events =
    List.foldl applyEvent empty (Event.sortEvents events)


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
            applyEntryAdded entry state

        EntryModified entry ->
            applyEntryModified entry state

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
                                , replacedBy =
                                    Dict.insert data.previousId data.newId state.replacedBy
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


applyEntryAdded : Entry -> GroupState -> GroupState
applyEntryAdded entry state =
    let
        rootId =
            entry.meta.rootId

        entryState =
            { rootId = rootId
            , currentVersion = entry
            , isDeleted = entry.meta.isDeleted
            , allVersions = Dict.singleton entry.meta.id entry
            }
    in
    { state | entries = Dict.insert rootId entryState state.entries }


applyEntryModified : Entry -> GroupState -> GroupState
applyEntryModified entry state =
    let
        rootId =
            entry.meta.rootId
    in
    case Dict.get rootId state.entries of
        Nothing ->
            -- Root entry doesn't exist, ignore
            state

        Just entryState ->
            let
                updatedVersions =
                    Dict.insert entry.meta.id entry entryState.allVersions

                resolved =
                    resolveCurrentVersion entry updatedVersions

                updatedEntryState =
                    { entryState
                        | allVersions = updatedVersions
                        , currentVersion = resolved
                        , isDeleted = resolved.meta.isDeleted
                    }
            in
            { state | entries = Dict.insert rootId updatedEntryState state.entries }


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


{-| Among all versions for a rootId, pick non-deleted with latest timestamp
(entry id as tiebreaker). Takes a fallback entry for the impossible empty case.
-}
resolveCurrentVersion : Entry -> Dict Entry.Id Entry -> Entry
resolveCurrentVersion fallback versions =
    let
        allEntries =
            Dict.values versions

        nonDeleted =
            List.filter (\e -> not e.meta.isDeleted) allEntries

        candidates =
            if List.isEmpty nonDeleted then
                allEntries

            else
                nonDeleted

        pickLatest a b =
            let
                ta =
                    Time.posixToMillis a.meta.createdAt

                tb =
                    Time.posixToMillis b.meta.createdAt
            in
            case compare ta tb of
                GT ->
                    a

                LT ->
                    b

                EQ ->
                    if a.meta.id >= b.meta.id then
                        a

                    else
                        b
    in
    case candidates of
        [] ->
            fallback

        first :: rest ->
            List.foldl pickLatest first rest



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
