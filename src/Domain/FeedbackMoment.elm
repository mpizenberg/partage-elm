module Domain.FeedbackMoment exposing
    ( Trigger(..)
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

@docs Trigger


# What has already been asked

@docs History, empty, allow, record
@docs encode, decoder

-}

import Dict exposing (Dict)
import Domain.Group as Group
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
