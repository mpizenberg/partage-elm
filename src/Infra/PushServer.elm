module Infra.PushServer exposing (Error, NotifyContext, fetchVapidKey, notificationKey, notificationTranslations, notifyAffectedMembers, templates, toggleGroupNotification, unsubscribeFromGroup)

{-| HTTP wrappers for push notification server communication.

The push-server base URL is supplied per call from deployment configuration
(`PUSH_SERVER_URL`); an empty value means the deployment ships without push and
these functions are never reached.

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


{-| Fetch the VAPID public key from the push server.
-}
fetchVapidKey : String -> ConcurrentTask Error String
fetchVapidKey pushServerUrl =
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
    { pushServerUrl : String
    , db : Idb.Db
    , summary : Group.Summary
    , subscription : Encode.Value
    , memberRootId : Member.Id
    }
    -> ConcurrentTask Error Bool
toggleGroupNotification { pushServerUrl, db, summary, subscription, memberRootId } =
    let
        topic : String
        topic =
            summary.id ++ "-" ++ memberRootId
    in
    if summary.isSubscribed then
        unregister pushServerUrl { topic = topic, subscription = subscription }
            |> ConcurrentTask.andThenDo (saveSummary db { summary | isSubscribed = False })
            |> ConcurrentTask.map (\_ -> False)

    else
        register pushServerUrl { topic = topic, subscription = subscription }
            |> ConcurrentTask.andThenDo (saveSummary db { summary | isSubscribed = True })
            |> ConcurrentTask.map (\_ -> True)


{-| Unsubscribe from a group's push notification topic.
-}
unsubscribeFromGroup : { pushServerUrl : String, subscription : Encode.Value, groupId : String, memberRootId : Member.Id } -> ConcurrentTask Error ()
unsubscribeFromGroup { pushServerUrl, subscription, groupId, memberRootId } =
    unregister pushServerUrl { topic = groupId ++ "-" ++ memberRootId, subscription = subscription }


{-| Context for sending push notifications after sync.
Only provided when there are events to push.
-}
type alias NotifyContext =
    { pushServerUrl : String
    , groupId : String
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
notifyAffectedMembers { pushServerUrl, groupId, groupName, actorRootId, actorName, entries, url } events =
    let
        entryCurrentVersion : Entry.Id -> Maybe Entry.Entry
        entryCurrentVersion rootId =
            Dict.get rootId entries |> Maybe.map .currentVersion

        affectedIds : List Member.Id
        affectedIds =
            events
                |> List.concatMap (\e -> Event.involvedMembers entryCurrentVersion e.payload)
                |> Set.fromList
                |> Set.remove actorRootId
                |> Set.toList

        { body, templateData } =
            notificationBodyAndData actorName (List.map .payload events)
    in
    affectedIds
        |> List.map
            (\memberId ->
                notifyTopic pushServerUrl
                    (groupId ++ "-" ++ memberId)
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
notifyTopic : String -> String -> NotificationPayload -> ConcurrentTask Error ()
notifyTopic pushServerUrl topic { title, body, url, tag, icon, templateData } =
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


{-| Notification templates for the service worker to resolve template keys.
Stored in IndexedDB so the SW can display localized push notifications.
-}
notificationTranslations : Language -> Encode.Value
notificationTranslations lang =
    templates lang
        |> Dict.toList
        |> List.map (Tuple.mapSecond Encode.string)
        |> Encode.object


{-| The push-notification message templates keyed by event type, per language.
The service worker interpolates `{name}` at display time; the English set also
backs the fallback body sent with each notification.
-}
templates : Language -> Dict String String
templates lang =
    Dict.fromList <|
        case lang of
            En ->
                [ ( "new_activity", "New activity" )
                , ( "expense_added", "{name} added an expense" )
                , ( "transfer_added", "{name} added a transfer" )
                , ( "income_added", "{name} added an income" )
                , ( "expense_modified", "{name} edited an expense" )
                , ( "transfer_modified", "{name} edited a transfer" )
                , ( "income_modified", "{name} edited an income" )
                , ( "entry_deleted", "{name} deleted an entry" )
                , ( "member_joined", "{name} joined the group" )
                ]

            Fr ->
                [ ( "new_activity", "Nouvelle activité" )
                , ( "expense_added", "{name} a ajouté une dépense" )
                , ( "transfer_added", "{name} a ajouté un transfert" )
                , ( "income_added", "{name} a ajouté un revenu" )
                , ( "expense_modified", "{name} a modifié une dépense" )
                , ( "transfer_modified", "{name} a modifié un transfert" )
                , ( "income_modified", "{name} a modifié un revenu" )
                , ( "entry_deleted", "{name} a supprimé une entrée" )
                , ( "member_joined", "{name} a rejoint le groupe" )
                ]



-- Internal


{-| Build the outgoing notification body and template data for a batch of pushed
payloads. The body is a readable English fallback (shown only if the SW can't
read the stored translations); the template data carries the key and `{name}`
for the SW to localize.
-}
notificationBodyAndData : String -> List Event.Payload -> { body : String, templateData : List ( String, Encode.Value ) }
notificationBodyAndData actorName payloads =
    let
        key : String
        key =
            notificationKey payloads

        body : String
        body =
            Dict.get key (templates En)
                |> Maybe.withDefault "New activity"
                |> String.replace "{name}" actorName
    in
    { body = body
    , templateData =
        [ ( "key", Encode.string key )
        , ( "name", Encode.string actorName )
        ]
    }


{-| The notification template key for a batch of pushed payloads. A single added,
edited, or deleted entry, or a joining member, gets its specific key; anything
else — a mixed batch, an undelete, a metadata change — is generic activity.
-}
notificationKey : List Event.Payload -> String
notificationKey payloads =
    case payloads of
        [ EntryAdded entry ] ->
            case entry.kind of
                Expense _ ->
                    "expense_added"

                Transfer _ ->
                    "transfer_added"

                Income _ ->
                    "income_added"

        [ EntryModified entry ] ->
            case entry.kind of
                Expense _ ->
                    "expense_modified"

                Transfer _ ->
                    "transfer_modified"

                Income _ ->
                    "income_modified"

        [ EntryDeleted _ ] ->
            "entry_deleted"

        [ MemberCreated data ] ->
            if data.memberType == Member.Real then
                "member_joined"

            else
                "new_activity"

        [ MemberLinked _ ] ->
            "member_joined"

        _ ->
            "new_activity"


register : String -> { topic : String, subscription : Encode.Value } -> ConcurrentTask Error ()
register pushServerUrl { topic, subscription } =
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


unregister : String -> { topic : String, subscription : Encode.Value } -> ConcurrentTask Error ()
unregister pushServerUrl { topic, subscription } =
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
