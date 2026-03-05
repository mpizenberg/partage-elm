module PushServer exposing (Error, NotifyContext, fetchVapidKey, notifyAffectedMembers, toggleGroupNotification)

{-| HTTP wrappers for push notification server communication.

Uses the same push server as the elm-pwa example: <https://push.dokploy.zidev.ovh>

-}

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Http as Http
import Dict exposing (Dict)
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.GroupState exposing (EntryState)
import Domain.Member as Member
import IndexedDb as Idb
import Json.Decode as Decode
import Json.Encode as Encode
import Set
import Storage exposing (GroupSummary)


type alias Error =
    Http.Error


pushServerUrl : String
pushServerUrl =
    "https://push.dokploy.zidev.ovh"


{-| Fetch the VAPID public key from the push server.
-}
fetchVapidKey : ConcurrentTask Error String
fetchVapidKey =
    Http.get
        { url = pushServerUrl ++ "/vapid-public-key"
        , headers = []
        , expect = Http.expectJson (Decode.field "vapidPublicKey" Decode.string)
        , timeout = Nothing
        }


{-| Toggle push notification subscription for a group.
Returns the new isSubscribed value (True if subscribed, False if unsubscribed).
-}
toggleGroupNotification :
    { db : Idb.Db
    , summary : GroupSummary
    , subscription : Encode.Value
    , memberRootId : Member.Id
    }
    -> ConcurrentTask Error Bool
toggleGroupNotification { db, summary, subscription, memberRootId } =
    let
        topic : String
        topic =
            summary.id ++ "-" ++ memberRootId
    in
    if summary.isSubscribed then
        let
            endpoint : String
            endpoint =
                subscription
                    |> Decode.decodeValue (Decode.field "endpoint" Decode.string)
                    |> Result.withDefault ""
        in
        unregister { endpoint = endpoint, topic = topic }
            |> ConcurrentTask.andThenDo (saveSummary db { summary | isSubscribed = False })
            |> ConcurrentTask.map (\_ -> False)

    else
        register { topic = topic, subscription = subscription }
            |> ConcurrentTask.andThenDo (saveSummary db { summary | isSubscribed = True })
            |> ConcurrentTask.map (\_ -> True)


{-| Context for sending push notifications after sync.
Only provided when there are events to push.
-}
type alias NotifyContext =
    { groupId : String
    , groupName : String
    , actorRootId : Member.Id
    , entries : Dict Entry.Id EntryState
    , url : String
    }


{-| Send push notifications to all affected members of pushed events.
Extracts involved member rootIds from each event, deduplicates, removes the actor,
and notifies each topic.
-}
notifyAffectedMembers : NotifyContext -> List Event.Envelope -> ConcurrentTask Error ()
notifyAffectedMembers { groupId, groupName, actorRootId, entries, url } events =
    let
        entryCurrentVersion : Entry.Id -> Maybe Entry.Entry
        entryCurrentVersion rootId =
            Dict.get rootId entries |> Maybe.map .currentVersion

        affectedIds : List Member.Id
        affectedIds =
            events
                |> List.concatMap (\e -> involvedMembers entryCurrentVersion e.payload)
                |> Set.fromList
                |> Set.remove actorRootId
                |> Set.toList
    in
    affectedIds
        |> List.map
            (\memberId ->
                notifyTopic (groupId ++ "-" ++ memberId)
                    { title = groupName
                    , body = "New activity"
                    , tag = groupId
                    , icon = "/icon-192.png"
                    , url = url
                    }
            )
        |> ConcurrentTask.batch
        |> ConcurrentTask.map (\_ -> ())


type alias NotificationPayload =
    { title : String
    , body : String

    -- same "tag" would replace notification instead of stacking multiple
    , tag : String

    -- use same origin path to the 192p icon
    , icon : String

    -- url useful to redirect to the correct page on opening
    , url : String
    }


{-| Send a push notification to all subscribers of a topic.
-}
notifyTopic : String -> NotificationPayload -> ConcurrentTask Error ()
notifyTopic topic { title, body, url, tag, icon } =
    Http.post
        { url = pushServerUrl ++ "/topics/" ++ topic ++ "/notify"
        , headers = []
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "title", Encode.string title )
                    , ( "body", Encode.string body )
                    , ( "tag", Encode.string tag )
                    , ( "icon", Encode.string icon )
                    , ( "data", Encode.object [ ( "url", Encode.string url ) ] )
                    ]
                )
        , expect = Http.expectWhatever
        , timeout = Nothing
        }



-- Internal


{-| Extract involved member IDs from an event payload.
Similar to Activity.involvedMembers but without full StateContext dependency.
-}
involvedMembers : (Entry.Id -> Maybe Entry.Entry) -> Event.Payload -> List Member.Id
involvedMembers entryCurrentVersion payload =
    case payload of
        EntryAdded entry ->
            entryInvolvedMembers entry

        EntryModified entry ->
            entryInvolvedMembers entry

        EntryDeleted { rootId } ->
            case entryCurrentVersion rootId of
                Just entry ->
                    entryInvolvedMembers entry

                Nothing ->
                    []

        EntryUndeleted { rootId } ->
            case entryCurrentVersion rootId of
                Just entry ->
                    entryInvolvedMembers entry

                Nothing ->
                    []

        MemberCreated data ->
            [ data.memberId ]

        MemberReplaced data ->
            [ data.rootId ]

        MemberRenamed data ->
            [ data.rootId ]

        MemberRetired data ->
            [ data.rootId ]

        MemberUnretired data ->
            [ data.rootId ]

        MemberMetadataUpdated data ->
            [ data.rootId ]

        GroupCreated _ ->
            []

        GroupMetadataUpdated _ ->
            []

        SettlementPreferencesUpdated data ->
            [ data.memberRootId ]


entryInvolvedMembers : Entry.Entry -> List Member.Id
entryInvolvedMembers entry =
    case entry.kind of
        Expense data ->
            List.map .memberId data.payers
                ++ List.map beneficiaryMemberId data.beneficiaries

        Transfer data ->
            [ data.from, data.to ]


beneficiaryMemberId : Entry.Beneficiary -> Member.Id
beneficiaryMemberId beneficiary =
    case beneficiary of
        Entry.ShareBeneficiary data ->
            data.memberId

        Entry.ExactBeneficiary data ->
            data.memberId


register : { topic : String, subscription : Encode.Value } -> ConcurrentTask Error ()
register { topic, subscription } =
    Http.post
        { url = pushServerUrl ++ "/subscriptions"
        , headers = []
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "subscription", subscription )
                    , ( "topic", Encode.string topic )
                    ]
                )
        , expect = Http.expectWhatever
        , timeout = Nothing
        }


unregister : { endpoint : String, topic : String } -> ConcurrentTask Error ()
unregister { endpoint, topic } =
    Http.request
        { url = pushServerUrl ++ "/subscriptions"
        , method = "DELETE"
        , headers = []
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "endpoint", Encode.string endpoint )
                    , ( "topic", Encode.string topic )
                    ]
                )
        , expect = Http.expectWhatever
        , timeout = Nothing
        }


saveSummary : Idb.Db -> GroupSummary -> ConcurrentTask Error ()
saveSummary db summary =
    Storage.saveGroupSummary db summary
        |> ConcurrentTask.map (\_ -> ())
        |> ConcurrentTask.mapError (\_ -> Http.NetworkError)
