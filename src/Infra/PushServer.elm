module Infra.PushServer exposing (Error, NotifyContext, fetchVapidKey, notificationTranslations, notifyAffectedMembers, toggleGroupNotification, unsubscribeFromGroup)

{-| HTTP wrappers for push notification server communication.

Uses the same push server as the elm-pwa example: <https://push.dokploy.zidev.ovh>

-}

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Http as Http
import Dict exposing (Dict)
import Domain.Entry as Entry exposing (Kind(..))
import Domain.Event as Event exposing (Payload(..))
import Domain.Group as Group
import Domain.GroupState exposing (EntryState)
import Domain.Member as Member
import IndexedDb as Idb
import Infra.Storage as Storage
import Json.Decode as Decode
import Json.Encode as Encode
import Set
import Translations exposing (Language(..))


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
    , summary : Group.Summary
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
        unregister { topic = topic, subscription = subscription }
            |> ConcurrentTask.andThenDo (saveSummary db { summary | isSubscribed = False })
            |> ConcurrentTask.map (\_ -> False)

    else
        register { topic = topic, subscription = subscription }
            |> ConcurrentTask.andThenDo (saveSummary db { summary | isSubscribed = True })
            |> ConcurrentTask.map (\_ -> True)


{-| Unsubscribe from a group's push notification topic.
-}
unsubscribeFromGroup : { subscription : Encode.Value, groupId : String, memberRootId : Member.Id } -> ConcurrentTask Error ()
unsubscribeFromGroup { subscription, groupId, memberRootId } =
    unregister { topic = groupId ++ "-" ++ memberRootId, subscription = subscription }


{-| Context for sending push notifications after sync.
Only provided when there are events to push.
-}
type alias NotifyContext =
    { groupId : String
    , groupName : String
    , actorRootId : Member.Id
    , actorName : String
    , entries : Dict Entry.Id EntryState
    , url : String
    }


{-| Send push notifications to all affected members of pushed events.
Extracts involved member rootIds from each event, deduplicates, removes the actor,
and notifies each topic.
-}
notifyAffectedMembers : NotifyContext -> List Event.Envelope -> ConcurrentTask Error ()
notifyAffectedMembers { groupId, groupName, actorRootId, actorName, entries, url } events =
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

        { body, templateData } =
            notificationBodyAndData actorName (List.map .payload events)
    in
    affectedIds
        |> List.map
            (\memberId ->
                notifyTopic (groupId ++ "-" ++ memberId)
                    { title = groupName
                    , body = body
                    , tag = groupId
                    , icon = "/icon-192.png"
                    , url = url
                    , templateData = templateData
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

    -- template key and params for SW-based i18n (carried in data alongside url)
    , templateData : List ( String, Encode.Value )
    }


{-| Send a push notification to all subscribers of a topic.
Uses legacy mode to ensure the service worker handles the notification
(required for SW-based i18n transform).
-}
notifyTopic : String -> NotificationPayload -> ConcurrentTask Error ()
notifyTopic topic { title, body, url, tag, icon, templateData } =
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
                    , ( "legacy", Encode.bool True )
                    , ( "data"
                      , Encode.object
                            (( "url", Encode.string url ) :: templateData)
                      )
                    ]
                )
        , expect = Http.expectWhatever
        , timeout = Nothing
        }


{-| Notification translations for the service worker to resolve template keys.
Stored in IndexedDB so the SW can display localized push notifications.
-}
notificationTranslations : Language -> Encode.Value
notificationTranslations lang =
    case lang of
        En ->
            Encode.object
                [ ( "new_activity", Encode.string "New activity" )
                , ( "expense_added", Encode.string "{name} added an expense" )
                , ( "transfer_added", Encode.string "{name} added a transfer" )
                , ( "member_joined", Encode.string "{name} joined the group" )
                ]

        Fr ->
            Encode.object
                [ ( "new_activity", Encode.string "Nouvelle activité" )
                , ( "expense_added", Encode.string "{name} a ajouté une dépense" )
                , ( "transfer_added", Encode.string "{name} a ajouté un transfert" )
                , ( "member_joined", Encode.string "{name} a rejoint le groupe" )
                ]



-- Internal


{-| Build an English fallback body and structured template data from event payloads.
The body is a readable English string (shown if the SW transform doesn't run).
The templateData carries the template key and params in the data field for the SW.
-}
notificationBodyAndData : String -> List Event.Payload -> { body : String, templateData : List ( String, Encode.Value ) }
notificationBodyAndData actorName payloads =
    let
        result : String -> String -> { body : String, templateData : List ( String, Encode.Value ) }
        result key englishBody =
            { body = englishBody
            , templateData =
                [ ( "key", Encode.string key )
                , ( "name", Encode.string actorName )
                ]
            }
    in
    case payloads of
        [ EntryAdded entry ] ->
            case entry.kind of
                Expense _ ->
                    result "expense_added" (actorName ++ " added an expense")

                Transfer _ ->
                    result "transfer_added" (actorName ++ " added a transfer")

        [ MemberCreated data ] ->
            if data.memberType == Member.Real then
                result "member_joined" (actorName ++ " joined the group")

            else
                result "new_activity" "New activity"

        [ MemberReplaced _ ] ->
            result "member_joined" (actorName ++ " joined the group")

        _ ->
            result "new_activity" "New activity"


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


unregister : { topic : String, subscription : Encode.Value } -> ConcurrentTask Error ()
unregister { topic, subscription } =
    Http.request
        { url = pushServerUrl ++ "/subscriptions"
        , method = "DELETE"
        , headers = []
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "endpoint", Encode.string (unregisterEndpoint subscription) )
                    , ( "topic", Encode.string topic )
                    ]
                )
        , expect = Http.expectWhatever
        , timeout = Nothing
        }


unregisterEndpoint : Encode.Value -> String
unregisterEndpoint subscription =
    subscription
        |> Decode.decodeValue (Decode.field "endpoint" Decode.string)
        |> Result.withDefault ""


saveSummary : Idb.Db -> Group.Summary -> ConcurrentTask Error ()
saveSummary db summary =
    Storage.saveGroupSummary db summary
        |> ConcurrentTask.map (\_ -> ())
        |> ConcurrentTask.mapError (\_ -> Http.NetworkError)
