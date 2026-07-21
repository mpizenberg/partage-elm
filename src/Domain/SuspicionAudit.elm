module Domain.SuspicionAudit exposing (Finding, Kind(..), audit, dismissKey)

{-| Flag attacker-shaped activity in a group's history (spec §11.7).

A group-key holder authors validly-signed events, so signature verification
never drops them and the high-confidence tamper signals stay silent. Two shapes
are caught here instead, recomputed from the current history:

  - **ForeignPaymentEdit** — a `MemberMetadataUpdated` that rewrites a
    self-present member's `payment` sub-record, authored by a different root:
    redirecting that member's settlements. Edits to a member who never authored
    anything (a virtual placeholder) are the normal way to fill one in and are
    not flagged.
  - **GraftedDeviceTamper** — a device whose root was also authored-for by
    another identity (so it is a second device grafted onto an established
    member, not a first-device join) and whose entire footprint alters existing
    entries or payment info. `MemberLinked` needs no root consent (it is the
    device-recovery path), so this is the signature of a device linked to tamper.

Presence is read from **authorship**, never from `deviceLinks` alone: a group
creator authors under their root id with no self-link, so counting device links
would miss them as a victim. Authorship order is irrelevant to both rules, so a
back-dated `clientTimestamp` cannot hide a finding.

A finding is suppressed on the very device it implicates (`culprit`, matched
against the viewer's own author id) so an attacker running the app sees no sign
they were detected; suppression is by authoring device id, not root, so the
victim of a graft — same root, a different device — still sees it.

-}

import Dict exposing (Dict)
import Domain.Event as Event exposing (Envelope, Payload(..))
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Set exposing (Set)


type Kind
    = ForeignPaymentEdit { target : Member.Id }
    | GraftedDeviceTamper { root : Member.Id, graftSeq : Int }


{-| `culprit` is the implicated authoring device id (also the suppression and
migration-exclusion key); `eventIds` are the offending events, earliest first.
-}
type alias Finding =
    { culprit : Member.Id
    , culpritLabel : String
    , kind : Kind
    , eventIds : List Event.Id
    }


{-| The suspicious activity in a group's history, minus anything implicating the
viewer's own device. `viewer` is the viewer's author id (`identity.publicKeyHash`).
-}
audit : Member.Id -> GroupState -> List Envelope -> List Finding
audit viewer state events =
    let
        ordered : List Envelope
        ordered =
            Event.sortEvents events

        authorsByRoot : Dict Member.Id (Set Member.Id)
        authorsByRoot =
            List.foldl
                (\e acc ->
                    case GroupState.resolveMemberRootId state e.triggeredBy of
                        Just root ->
                            Dict.update root (Maybe.withDefault Set.empty >> Set.insert e.triggeredBy >> Just) acc

                        Nothing ->
                            acc
                )
                Dict.empty
                ordered
    in
    foreignPaymentFindings state authorsByRoot ordered
        ++ graftedDeviceFindings state authorsByRoot ordered
        |> List.filter (\f -> f.culprit /= viewer)


foreignPaymentFindings : GroupState -> Dict Member.Id (Set Member.Id) -> List Envelope -> List Finding
foreignPaymentFindings state authorsByRoot ordered =
    let
        selfPresent : Set Member.Id
        selfPresent =
            Dict.keys authorsByRoot |> Set.fromList

        step : Envelope -> ( Dict Member.Id (Maybe Member.PaymentInfo), List Finding ) -> ( Dict Member.Id (Maybe Member.PaymentInfo), List Finding )
        step e ( prior, acc ) =
            case e.payload of
                MemberMetadataUpdated data ->
                    let
                        newPayment : Maybe Member.PaymentInfo
                        newPayment =
                            data.metadata.payment

                        foreign : Bool
                        foreign =
                            GroupState.resolveMemberRootId state e.triggeredBy /= Just data.rootId

                        flagged : Bool
                        flagged =
                            newPayment
                                /= (Dict.get data.rootId prior |> Maybe.withDefault Nothing)
                                && foreign
                                && Set.member data.rootId selfPresent
                    in
                    ( Dict.insert data.rootId newPayment prior
                    , if flagged then
                        { culprit = e.triggeredBy
                        , culpritLabel = GroupState.resolveMemberName state e.triggeredBy
                        , kind = ForeignPaymentEdit { target = data.rootId }
                        , eventIds = [ e.id ]
                        }
                            :: acc

                      else
                        acc
                    )

                _ ->
                    ( prior, acc )
    in
    List.foldl step ( Dict.empty, [] ) ordered
        |> Tuple.second
        |> List.reverse


graftedDeviceFindings : GroupState -> Dict Member.Id (Set Member.Id) -> List Envelope -> List Finding
graftedDeviceFindings state authorsByRoot ordered =
    let
        eventsByAuthor : Dict Member.Id (List Envelope)
        eventsByAuthor =
            List.foldl (\e -> Dict.update e.triggeredBy (Maybe.withDefault [] >> (::) e >> Just)) Dict.empty ordered

        toFinding : Member.Id -> Member.DeviceLink -> Maybe Finding
        toFinding deviceId link =
            let
                others : Set Member.Id
                others =
                    Dict.get link.rootId authorsByRoot
                        |> Maybe.withDefault Set.empty
                        |> Set.remove deviceId

                footprint : List Envelope
                footprint =
                    Dict.get deviceId eventsByAuthor
                        |> Maybe.withDefault []
                        |> List.filter (.payload >> isLink >> not)
                        |> List.reverse
            in
            if Set.isEmpty others || List.isEmpty footprint || not (List.all (.payload >> isTamperKind) footprint) then
                Nothing

            else
                Just
                    { culprit = deviceId
                    , culpritLabel = GroupState.resolveMemberName state deviceId
                    , kind = GraftedDeviceTamper { root = link.rootId, graftSeq = link.seq }
                    , eventIds = List.map .id footprint
                    }
    in
    Dict.toList state.deviceLinks
        |> List.filterMap (\( deviceId, link ) -> toFinding deviceId link)


isLink : Payload -> Bool
isLink payload =
    case payload of
        MemberLinked _ ->
            True

        _ ->
            False


isTamperKind : Payload -> Bool
isTamperKind payload =
    case payload of
        EntryModified _ ->
            True

        EntryDeleted _ ->
            True

        EntryUndeleted _ ->
            True

        MemberMetadataUpdated _ ->
            True

        _ ->
            False


{-| A stable identity for a finding, so a dismissal persists across replays yet a
new offending event yields a new key that re-alarms.
-}
dismissKey : Finding -> String
dismissKey finding =
    let
        tag : String
        tag =
            case finding.kind of
                ForeignPaymentEdit { target } ->
                    "fpe:" ++ target

                GraftedDeviceTamper { root } ->
                    "gdt:" ++ root
    in
    String.join ":" [ tag, finding.culprit, String.join "," (List.sort finding.eventIds) ]
