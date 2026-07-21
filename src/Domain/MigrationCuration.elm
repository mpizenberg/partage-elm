module Domain.MigrationCuration exposing (BalanceRow, Bound(..), Boundary, Identity, Preview, curateEvents, identities, preview)

{-| Drop events authored by excluded identities when re-homing a group during
migration (spec §11.7).

A group-key holder can inject validly-signed events — including as an existing
member, by self-linking a device (`MemberLinked` is not gated on the root's
consent, because self-linking is the device-recovery path). Such events pass
signature verification, so the re-key alone can't shed them; the migrator excises
them here by author. Excluding an author id removes everything it authored: a
self-created attacker member and its `MemberCreated`, or a grafted device and its
self-authored `MemberLinked`. What survives replays to a consistent state —
dangling modifications of a dropped entry are rejected on replay, reverting the
entry to its pre-attack form.

Exclusion is per-identity with an optional boundary. `All` drops everything the
identity authored; `After s` keeps only what it authored up to server batch `s`
and drops the rest — the leaked-legitimate-key case, where a real member's early
history is genuine but a later flood rode in on the stolen key. The boundary is
the relay's ingestion order (`ServerEventRecord.seq`), never the payload's
`clientTimestamp`, which the attacker sets and can back-date. An event whose seq
is unknown (not in the fetched order) is always kept, since it can't be placed.

`identities` surfaces who authored what — with the seq boundaries at which their
history can be split — so the migrator can spot injected identities and floods at
scale; `preview` replays a candidate selection to show the resulting group.

-}

import Dict exposing (Dict)
import Domain.Event as Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Set
import Time


{-| How much of an excluded identity's history to drop.
-}
type Bound
    = All
    | After Int


curateEvents : Dict Event.Id Int -> Dict Member.Id Bound -> List Envelope -> List Envelope
curateEvents order selection events =
    List.filter (keep order selection) events


keep : Dict Event.Id Int -> Dict Member.Id Bound -> Envelope -> Bool
keep order selection envelope =
    case Dict.get envelope.triggeredBy selection of
        Nothing ->
            True

        Just All ->
            False

        Just (After boundary) ->
            case Dict.get envelope.id order of
                Just seq ->
                    seq <= boundary

                Nothing ->
                    True


{-| A server-order split point for one identity: keep everything it authored up
to and including batch `seq`, drop the rest. `kept` is how many of the identity's
events survive the split — the count the migrator weighs against the flood.
-}
type alias Boundary =
    { seq : Int
    , kept : Int
    }


{-| A signing identity that authored events, with the stats a migrator needs to
judge whether it belongs. `excludable` is False for the migrator and the group
creator — dropping either would gut the group, so they can't be toggled off.
`isSelf` marks the migrator's own identities (so the UI can say "you" rather than
just "can't be removed"). `linkedAt` is the device's link timestamp when this
identity is a linked device, so the migrator can tell an expected device from one
that appeared alongside the flood. `boundaries` are the seq split points, earliest
first, at which the identity's history can be partially dropped (empty when it
authored in a single batch, so only a whole-identity drop makes sense).
-}
type alias Identity =
    { id : Member.Id
    , label : String
    , eventCount : Int
    , isDevice : Bool
    , isSelf : Bool
    , excludable : Bool
    , linkedAt : Maybe Time.Posix
    , boundaries : List Boundary
    }


{-| One entry per author id in the history, heaviest first so a flood floats to
the top. `selfRoot` is the migrator's root id: any identity resolving to it is
non-excludable (dropping your own devices would corrupt your own history).
`order` is the fetched `id → seq` map; without it the boundaries are empty and
only whole-identity exclusion is offered.
-}
identities : Dict Event.Id Int -> Member.Id -> GroupState -> List Envelope -> List Identity
identities order selfRoot state events =
    let
        creator : Member.Id
        creator =
            events
                |> List.filter isGenesis
                |> List.head
                |> Maybe.map .triggeredBy
                |> Maybe.withDefault ""

        seqsByAuthor : Dict Member.Id (List Int)
        seqsByAuthor =
            List.foldl
                (\envelope acc ->
                    case Dict.get envelope.id order of
                        Just seq ->
                            Dict.update envelope.triggeredBy (\ms -> Just (seq :: Maybe.withDefault [] ms)) acc

                        Nothing ->
                            acc
                )
                Dict.empty
                events

        boundariesFor : Member.Id -> Int -> List Boundary
        boundariesFor id count =
            let
                seqs : List Int
                seqs =
                    Dict.get id seqsByAuthor |> Maybe.withDefault []

                noSeqCount : Int
                noSeqCount =
                    count - List.length seqs

                distinct : List Int
                distinct =
                    seqs |> Set.fromList |> Set.toList
            in
            distinct
                |> List.take (max 0 (List.length distinct - 1))
                |> List.map (\b -> { seq = b, kept = noSeqCount + List.length (List.filter (\s -> s <= b) seqs) })

        toIdentity : Member.Id -> Int -> Identity
        toIdentity id count =
            let
                root : Maybe Member.Id
                root =
                    GroupState.resolveMemberRootId state id
            in
            { id = id
            , label = GroupState.resolveMemberName state id
            , eventCount = count
            , isDevice = Dict.member id state.deviceLinks
            , isSelf = root == Just selfRoot
            , excludable = root /= Just selfRoot && id /= creator
            , linkedAt = Dict.get id state.deviceLinks |> Maybe.map .timestamp
            , boundaries = boundariesFor id count
            }
    in
    List.foldl (\envelope -> Dict.update envelope.triggeredBy (Maybe.withDefault 0 >> (+) 1 >> Just)) Dict.empty events
        |> Dict.map toIdentity
        |> Dict.values
        |> List.sortBy (\identity -> -identity.eventCount)


isGenesis : Envelope -> Bool
isGenesis envelope =
    case envelope.payload of
        GroupCreated _ ->
            True

        _ ->
            False


{-| A resulting member balance and how much the cut moved it from the
keep-everything baseline. `isSelf` marks the migrator's own row.
-}
type alias BalanceRow =
    { id : Member.Id
    , label : String
    , balanceCents : Int
    , deltaCents : Int
    , isSelf : Bool
    }


{-| The new group a curated re-home would produce: how many events survive, how
many are dropped, the resulting active-member/entry counts, and the balances the
cut changes (plus the migrator's own row, always). Deltas are against the
keep-everything baseline — how much dropping the injected events restores. A full
replay — computed on demand, not per keystroke.
-}
type alias Preview =
    { carried : Int
    , dropped : Int
    , members : Int
    , entries : Int
    , balances : List BalanceRow
    }


preview : Dict Event.Id Int -> Member.Id -> Dict Member.Id Bound -> List Envelope -> Preview
preview order self selection events =
    let
        kept : List Envelope
        kept =
            curateEvents order selection events

        state : GroupState
        state =
            GroupState.applyEvents kept GroupState.empty

        baseline : GroupState
        baseline =
            GroupState.applyEvents events GroupState.empty

        selfRoot : Maybe Member.Id
        selfRoot =
            GroupState.resolveMemberRootId state self

        netOf : GroupState -> Member.Id -> Int
        netOf st rootId =
            Dict.get rootId st.balances |> Maybe.map .netBalance |> Maybe.withDefault 0

        rows : List BalanceRow
        rows =
            state.members
                |> Dict.filter (\_ member -> not member.isRetired)
                |> Dict.toList
                |> List.filterMap
                    (\( rootId, _ ) ->
                        let
                            delta : Int
                            delta =
                                netOf state rootId - netOf baseline rootId

                            isSelf : Bool
                            isSelf =
                                Just rootId == selfRoot
                        in
                        if delta /= 0 || isSelf then
                            Just
                                { id = rootId
                                , label = GroupState.resolveMemberName state rootId
                                , balanceCents = netOf state rootId
                                , deltaCents = delta
                                , isSelf = isSelf
                                }

                        else
                            Nothing
                    )
                |> List.sortBy
                    (\row ->
                        ( if row.isSelf then
                            0

                          else
                            1
                        , negate (abs row.deltaCents)
                        )
                    )
    in
    { carried = List.length kept
    , dropped = List.length events - List.length kept
    , members = Dict.filter (\_ member -> not member.isRetired) state.members |> Dict.size
    , entries = Dict.filter (\_ entry -> not entry.isDeleted) state.entries |> Dict.size
    , balances = rows
    }
