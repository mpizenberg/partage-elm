module Domain.FeedbackMoment exposing
    ( Trigger(..), detect
    , History, empty, allow, record
    , encode, decoder
    )

{-| Moments worth asking a group's members for feedback, and the pacing that
keeps the asking rare.

Being asked is a cost the user pays for the project's benefit, so the rules are
deliberately strict: at most one prompt a week whatever the trigger, at most one
of any single trigger a month, and never the same question twice about the same
group. The windows are short while the app is young; they grow, not shrink.


# Triggers

@docs Trigger, detect


# What has already been asked

@docs History, empty, allow, record
@docs encode, decoder

-}

import Dict exposing (Dict)
import Domain.Entry exposing (Entry)
import Domain.Group as Group
import Domain.GroupState as GroupState exposing (GroupState)
import Domain.Member as Member
import Domain.StableSettlement as StableSettlement
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Set exposing (Set)
import Time


{-| The three questions worth interrupting someone for.

  - `Concluded` — a group that just settled up: did the plan work?
  - `Prolific` — the member carrying a large group: what is the app costing them?
  - `Refusal` — a creator whose group never fully joined: who said no, and why?

-}
type Trigger
    = Concluded
    | Prolific
    | Refusal


{-| The moment this group is at, if it is at one worth interrupting for.

Every trigger needs a group that is still alive: the newest entry has to be
days old, not months, or the answers describe an app the user barely remembers.
The asker also has to still be an active member — nobody who left a group is
asked anything about it.

`justAddedTransfer` is the one thing the state cannot tell us: `Concluded` is
about the person who just settled up, not about anyone who opens the group
afterwards.

-}
detect :
    { now : Time.Posix, selfRootId : Member.Id, justAddedTransfer : Bool }
    -> GroupState
    -> Maybe Trigger
detect { now, selfRootId, justAddedTransfer } state =
    let
        entries : List Entry
        entries =
            GroupState.activeEntries state

        members : List Member.State
        members =
            GroupState.activeMembers state
    in
    if not (List.any (\member -> member.rootId == selfRootId) members) || not (isFresh now entries) then
        Nothing

    else
        let
            claimed : Int
            claimed =
                List.length (List.filter (\member -> member.memberType == Member.Real) members)

            entryCount : Int
            entryCount =
                List.length entries

            plan : Int
            plan =
                List.length
                    (StableSettlement.stablePlan
                        state.anchorBalances
                        state.settlementPreferences
                        state.balances
                    )

            isCreator : Bool
            isCreator =
                (state.createdBy |> Maybe.andThen (GroupState.resolveMemberRootId state))
                    == Just selfRootId
        in
        if isCreator && claimed >= 4 && entryCount >= 10 && plan == 0 && List.any (\member -> member.memberType == Member.Virtual) members then
            Just Refusal

        else if justAddedTransfer && claimed >= 5 && entryCount >= 10 && plan <= (claimed + 4) // 5 then
            Just Concluded

        else if claimed >= 5 && entryCount >= 100 && topAuthor state entries == Just selfRootId then
            Just Prolific

        else
            Nothing


{-| A group nobody has written to in a week has nothing current to say.
-}
isFresh : Time.Posix -> List Entry -> Bool
isFresh now entries =
    entries
        |> List.map (.meta >> .createdAt >> Time.posixToMillis)
        |> List.maximum
        |> Maybe.map (\newest -> Time.posixToMillis now - newest <= 7 * dayMs)
        |> Maybe.withDefault False


{-| The member who wrote strictly more entries than anyone else. A tie has no
answer, so it asks nobody.
-}
topAuthor : GroupState -> List Entry -> Maybe Member.Id
topAuthor state entries =
    let
        counts : List ( Member.Id, Int )
        counts =
            entries
                |> List.foldl
                    (\entry acc ->
                        case GroupState.resolveMemberRootId state entry.meta.createdBy of
                            Just rootId ->
                                Dict.update rootId (\count -> Just (Maybe.withDefault 0 count + 1)) acc

                            Nothing ->
                                acc
                    )
                    Dict.empty
                |> Dict.toList
                |> List.sortBy (Tuple.second >> negate)
    in
    case counts of
        ( winner, count ) :: ( _, runnerUp ) :: _ ->
            if count > runnerUp then
                Just winner

            else
                Nothing

        [ ( winner, _ ) ] ->
            Just winner

        [] ->
            Nothing


{-| What this device has already asked, and when. Device-local by design: a
synced marker would tell a whole group who was asked for feedback.
-}
type History
    = History
        { shownAt : Dict String Time.Posix
        , asked : Set ( Group.Id, String )
        }


empty : History
empty =
    History { shownAt = Dict.empty, asked = Set.empty }


dayMs : Int
dayMs =
    24 * 60 * 60 * 1000


{-| Whether this trigger may be shown for this group right now.
-}
allow : Time.Posix -> Group.Id -> Trigger -> History -> Bool
allow now groupId trigger (History history) =
    let
        elapsedSince : Time.Posix -> Int
        elapsedSince shown =
            Time.posixToMillis now - Time.posixToMillis shown

        quietFor : Int -> Time.Posix -> Bool
        quietFor days shown =
            elapsedSince shown >= days * dayMs
    in
    not (Set.member ( groupId, triggerKey trigger ) history.asked)
        && List.all (quietFor 7) (Dict.values history.shownAt)
        && (Dict.get (triggerKey trigger) history.shownAt
                |> Maybe.map (quietFor 30)
                |> Maybe.withDefault True
           )


{-| Charge a shown prompt against every window at once. Dismissing and opening
cost the same: what the user paid for is the interruption.
-}
record : Time.Posix -> Group.Id -> Trigger -> History -> History
record now groupId trigger (History history) =
    History
        { shownAt = Dict.insert (triggerKey trigger) now history.shownAt
        , asked = Set.insert ( groupId, triggerKey trigger ) history.asked
        }


triggerKey : Trigger -> String
triggerKey trigger =
    case trigger of
        Concluded ->
            "concluded"

        Prolific ->
            "prolific"

        Refusal ->
            "refusal"


encode : History -> Encode.Value
encode (History history) =
    Encode.object
        [ ( "shownAt"
          , Encode.dict identity (Time.posixToMillis >> Encode.int) history.shownAt
          )
        , ( "asked"
          , Encode.set
                (\( groupId, key ) -> Encode.list Encode.string [ groupId, key ])
                history.asked
          )
        ]


decoder : Decoder History
decoder =
    Decode.map2
        (\shownAt asked -> History { shownAt = shownAt, asked = asked })
        (Decode.field "shownAt" (Decode.dict (Decode.map Time.millisToPosix Decode.int)))
        (Decode.field "asked"
            (Decode.list
                (Decode.map2 Tuple.pair
                    (Decode.index 0 Decode.string)
                    (Decode.index 1 Decode.string)
                )
                |> Decode.map Set.fromList
            )
        )
