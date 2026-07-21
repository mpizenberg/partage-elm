module Domain.MigrationCuration exposing (Identity, Preview, curateEvents, identities, preview)

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

`identities` surfaces who authored what so the migrator can spot injected
identities at flood scale; `preview` replays a candidate selection to show the
resulting group.

-}

import Dict
import Domain.Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Set exposing (Set)


curateEvents : Set Member.Id -> List Envelope -> List Envelope
curateEvents excluded events =
    List.filter (\envelope -> not (Set.member envelope.triggeredBy excluded)) events


{-| A signing identity that authored events, with the stats a migrator needs to
judge whether it belongs. `excludable` is False for the migrator and the group
creator — dropping either would gut the group, so they can't be toggled off.
-}
type alias Identity =
    { id : Member.Id
    , label : String
    , eventCount : Int
    , isDevice : Bool
    , excludable : Bool
    }


{-| One entry per author id in the history, heaviest first so a flood floats to
the top. `selfRoot` is the migrator's root id: any identity resolving to it is
non-excludable (dropping your own devices would corrupt your own history).
-}
identities : Member.Id -> GroupState -> List Envelope -> List Identity
identities selfRoot state events =
    let
        creator : Member.Id
        creator =
            events
                |> List.filter isGenesis
                |> List.head
                |> Maybe.map .triggeredBy
                |> Maybe.withDefault ""

        toIdentity : Member.Id -> Int -> Identity
        toIdentity id count =
            { id = id
            , label = GroupState.resolveMemberName state id
            , eventCount = count
            , isDevice = Dict.member id state.deviceLinks
            , excludable = GroupState.resolveMemberRootId state id /= Just selfRoot && id /= creator
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


{-| The new group a curated re-home would produce: how many events survive, how
many are dropped, and the resulting active-member/entry counts and the migrator's
own balance. A full replay — computed on demand, not per keystroke.
-}
type alias Preview =
    { carried : Int
    , dropped : Int
    , members : Int
    , entries : Int
    , myBalanceCents : Int
    }


preview : Member.Id -> Set Member.Id -> List Envelope -> Preview
preview self excluded events =
    let
        kept : List Envelope
        kept =
            curateEvents excluded events

        state : GroupState
        state =
            GroupState.applyEvents kept GroupState.empty
    in
    { carried = List.length kept
    , dropped = List.length events - List.length kept
    , members = Dict.filter (\_ member -> not member.isRetired) state.members |> Dict.size
    , entries = Dict.filter (\_ entry -> not entry.isDeleted) state.entries |> Dict.size
    , myBalanceCents =
        GroupState.resolveMemberRootId state self
            |> Maybe.andThen (\rootId -> Dict.get rootId state.balances)
            |> Maybe.map .netBalance
            |> Maybe.withDefault 0
    }
