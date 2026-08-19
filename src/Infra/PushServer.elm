module Infra.PushServer exposing
    ( Error
    , NotifyContext
    , fetchVapidKey
    , notificationBundle
    , notifyAffectedMembers
    , setGroupNotification
    )

{-| HTTP wrappers for push notification server communication.

The push-server base URL is supplied per call from deployment configuration
(`PUSH_SERVER_URL`); an empty value means the deployment ships without push and
these functions are never reached.

Notification content never reaches the push server in cleartext: the outer
payload is constant apart from an AES-256-GCM blob encrypted with the group
key, which the recipient's service worker decrypts and localizes. The
plaintext is padded to fixed-size buckets so its length reveals nothing.

-}

import ActivityPhrase
import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Http as Http
import Domain.Activity as Activity
import Domain.Currency as Currency
import Domain.Event as Event
import Domain.Member as Member
import Format
import Infra.Crypto as Crypto
import Json.Decode as Decode
import Json.Encode as Encode
import Set
import Translations as T exposing (Language(..))
import WebCrypto.Symmetric as Symmetric


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


{-| Set a topic's remote push notification subscription to an absolute state.
The topic is opaque here: callers derive it with `Infra.Crypto.deriveNotifyTopic`,
so this module never sees group or member identifiers. Local persistence is
owned by the caller so stale requests cannot write.
-}
setGroupNotification :
    { pushServerUrl : String
    , topic : String
    , subscription : Encode.Value
    , isSubscribed : Bool
    }
    -> ConcurrentTask Error ()
setGroupNotification { pushServerUrl, topic, subscription, isSubscribed } =
    if isSubscribed then
        register pushServerUrl { topic = topic, subscription = subscription }

    else
        unregister pushServerUrl { topic = topic, subscription = subscription }


{-| Context for sending push notifications after sync.
Only provided when there are events to push.
-}
type alias NotifyContext =
    { pushServerUrl : String
    , groupName : String
    , actorRootId : Member.Id
    , actorName : String
    , stateContext : Activity.StateContext
    , groupKey : Symmetric.Key
    , url : String
    }


{-| Send push notifications to all affected members of pushed events.
Extracts involved member rootIds from each event, deduplicates, removes the
actor, encrypts the content once with the group key, and notifies each topic.
Notifications are best-effort: any failure is swallowed so it can never fail
the sync that triggered it.
-}
notifyAffectedMembers : NotifyContext -> List Event.Envelope -> ConcurrentTask x ()
notifyAffectedMembers ctx events =
    let
        affectedIds : List Member.Id
        affectedIds =
            events
                |> List.concatMap (\e -> Event.involvedMembers ctx.stateContext.entryCurrentVersion e.payload)
                |> Set.fromList
                |> Set.remove ctx.actorRootId
                |> Set.toList
    in
    if List.isEmpty affectedIds then
        ConcurrentTask.succeed ()

    else
        Symmetric.encryptString ctx.groupKey (paddedPlaintext ctx events)
            |> ConcurrentTask.mapError (\_ -> ())
            |> ConcurrentTask.andThen
                (\encrypted ->
                    affectedIds
                        |> List.map
                            (\memberId ->
                                Crypto.deriveNotifyTopic ctx.groupKey memberId
                                    |> ConcurrentTask.mapError (\_ -> ())
                                    |> ConcurrentTask.andThen
                                        (\topic ->
                                            notifyTopic ctx.pushServerUrl topic encrypted
                                                |> ConcurrentTask.mapError (\_ -> ())
                                        )
                            )
                        |> ConcurrentTask.batch
                        |> ConcurrentTask.map (\_ -> ())
                )
            |> ConcurrentTask.onError (\() -> ConcurrentTask.succeed ())


{-| Send an encrypted push notification to all subscribers of a topic. Every
cleartext field is constant across all notifications of all groups, except
the tag and the fallback click URL, which both repeat the topic from the
request's own URL: the tag restores per-group stacking without naming the
group, and the URL carries the topic in its fragment — never sent to the
origin — so a click on an undecrypted fallback can still resolve to the right
group locally. Legacy mode keeps delivery on the service-worker path so the
transform can decrypt (declarative rendering could only ever show the
cleartext).
-}
notifyTopic : String -> String -> Symmetric.EncryptedData -> ConcurrentTask Http.Error ()
notifyTopic pushServerUrl topic encrypted =
    Http.post
        { url = pushServerUrl ++ "/topics/" ++ topic ++ "/notify"
        , headers = []
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "title", Encode.string (T.shellPartage (T.init En)) )
                    , ( "body", Encode.string fallbackBody )
                    , ( "tag", Encode.string topic )
                    , ( "icon", Encode.string "/icon-192.png" )
                    , ( "legacy", Encode.bool True )
                    , ( "data"
                      , Encode.object
                            [ ( "v", Encode.int 1 )
                            , ( "iv", Encode.string encrypted.iv )
                            , ( "ct", Encode.string encrypted.ciphertext )
                            , ( "url", Encode.string ("/groups#n=" ++ topic) )
                            ]
                      )
                    ]
                )
        , expect = Http.expectWhatever
        , timeout = Nothing
        }


{-| The constant cleartext body, shown when the service worker cannot decrypt.
The sender cannot know the recipient's language and localizing the cleartext
would leak a per-topic hint, so it joins every shipped language.
-}
fallbackBody : String
fallbackBody =
    T.languages
        |> List.map (\lang -> T.notificationGeneric (T.init lang))
        |> String.join " · "


{-| The bundle the service worker assembles notifications from, stored in
IndexedDB and refreshed on language change: phrase templates with `{param}`
placeholders (`t`) and the locale's number formatting (`n`), so no locale
knowledge lives in JavaScript.
-}
notificationBundle : Language -> Encode.Value
notificationBundle lang =
    let
        i18n : T.I18n
        i18n =
            T.init lang

        cfg : Format.LocaleConfig
        cfg =
            Format.localeConfig lang

        wrappers : List ( String, String )
        wrappers =
            [ ( "activityAmountSuffix", T.activityAmountSuffix { text = "{text}", amount = "{amount}" } i18n )
            , ( "notificationLine", T.notificationLine { actor = "{actor}", phrase = "{phrase}" } i18n )
            , ( "notificationGeneric", T.notificationGeneric i18n )
            ]
    in
    Encode.object
        [ ( "t"
          , (ActivityPhrase.templates i18n ++ wrappers)
                |> List.map (Tuple.mapSecond Encode.string)
                |> Encode.object
          )
        , ( "n"
          , Encode.object
                [ ( "decimal", Encode.string cfg.decimal )
                , ( "group", Encode.string cfg.group )
                , ( "pos"
                  , Encode.string
                        (case cfg.symbolPosition of
                            Format.Prefix ->
                                "prefix"

                            Format.SuffixWithSpace ->
                                "suffix"
                        )
                  )
                ]
          )
        ]



-- Internal


{-| The encrypted notification content, serialized and padded to a fixed-size
bucket so the ciphertext length reveals nothing about the description or group
name. Carries the group name (`t`), the last visible event's phrase key (`k`)
and parameters (`p`, actor included), its amount (`a`), the count of further
events in the batch (`n`) and the target route (`u`).
-}
paddedPlaintext : NotifyContext -> List Event.Envelope -> String
paddedPlaintext ctx events =
    let
        phrases : List ( ActivityPhrase.Phrase, Maybe ActivityPhrase.Amount )
        phrases =
            events
                |> List.filterMap (Activity.fromEnvelope ctx.stateContext)
                |> List.map (\a -> ActivityPhrase.phrase a.detail)

        ( keyAndParams, amount, extraCount ) =
            case List.reverse phrases of
                ( p, a ) :: rest ->
                    ( ( ActivityPhrase.key p, ActivityPhrase.params p ), a, List.length rest )

                [] ->
                    ( ( "notificationGeneric", [] ), Nothing, 0 )

        ( key, params ) =
            keyAndParams

        paramFields : List ( String, Encode.Value )
        paramFields =
            (( "actor", ctx.actorName ) :: params)
                |> List.map (\( name, value ) -> ( name, Encode.string (truncateParam value) ))

        json : String
        json =
            Encode.encode 0
                (Encode.object
                    ([ ( "t", Encode.string ctx.groupName )
                     , ( "k", Encode.string key )
                     , ( "p", Encode.object paramFields )
                     ]
                        ++ (case amount of
                                Just a ->
                                    [ ( "a"
                                      , Encode.object
                                            [ ( "v", Encode.int a.cents )
                                            , ( "sym", Encode.string (Currency.currencySymbol a.currency) )
                                            , ( "prec", Encode.int (Currency.precision a.currency) )
                                            ]
                                      )
                                    ]

                                Nothing ->
                                    []
                           )
                        ++ (if extraCount > 0 then
                                [ ( "n", Encode.int extraCount ) ]

                            else
                                []
                           )
                        ++ [ ( "u", Encode.string ctx.url ) ]
                    )
                )

        size : Int
        size =
            utf8Length json

        bucket : Int
        bucket =
            ((size + 511) // 512) * 512
    in
    json ++ String.repeat (bucket - size) " "


truncateParam : String -> String
truncateParam value =
    if String.length value > 80 then
        String.left 79 value ++ "…"

    else
        value


utf8Length : String -> Int
utf8Length s =
    String.foldl (\c acc -> acc + codePointUtf8Length (Char.toCode c)) 0 s


codePointUtf8Length : Int -> Int
codePointUtf8Length code =
    if code < 0x80 then
        1

    else if code < 0x0800 then
        2

    else if code < 0x00010000 then
        3

    else
        4


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
