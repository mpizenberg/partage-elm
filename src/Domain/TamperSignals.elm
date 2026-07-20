module Domain.TamperSignals exposing
    ( TamperSignals
    , bannerWorthy
    , decoder
    , empty
    , encode
    , forgedCount
    , isClean
    , recordForgedAuthors
    , recordManifestMismatch
    , recordRateLimitHit
    , recordResetWithLoss
    )

{-| Per-group compromise-detection counters (spec §11.7).

Four signals feed a per-group tamper indicator. Two are high-confidence and
raise the user-facing warning banner: an envelope that fails signature
verification against the immutable key map (only forgery or corruption does),
and a push rejected by the relay's monthly rate cap (which sits orders of
magnitude above honest volume). The other two are advisory — a cursor reset
that dropped history this client held (also produced by a benign TTL
resurrection) and a compaction-manifest disagreement (also produced by benign
concurrent interleaving). Advisory signals are counted and shown in the
diagnostics detail but never alarm on their own; only a climbing count, read
there, distinguishes active interference from a one-off.

Forged envelopes are tallied by their _claimed_ author id (`triggeredBy`), so
the diagnostics detail can attribute the forgery attempts — informing, not
proving, who to distrust when migrating.

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Time


type alias TamperSignals =
    { forgedAuthors : Dict String Int
    , rateLimitHits : Int
    , resetsWithLoss : Int
    , manifestMismatches : Int
    , lastDetectedAt : Maybe Time.Posix
    }


empty : TamperSignals
empty =
    { forgedAuthors = Dict.empty
    , rateLimitHits = 0
    , resetsWithLoss = 0
    , manifestMismatches = 0
    , lastDetectedAt = Nothing
    }


{-| Total envelopes dropped by signature verification across all claimed authors.
-}
forgedCount : TamperSignals -> Int
forgedCount s =
    Dict.foldl (\_ n acc -> acc + n) 0 s.forgedAuthors


{-| No signal has ever fired (or the counters were dismissed).
-}
isClean : TamperSignals -> Bool
isClean s =
    Dict.isEmpty s.forgedAuthors && s.rateLimitHits == 0 && s.resetsWithLoss == 0 && s.manifestMismatches == 0


{-| Whether the high-confidence signals warrant the user-facing banner. The
advisory signals (reset-with-loss, manifest mismatch) never raise it — their
benign causes would make it cry wolf.
-}
bannerWorthy : TamperSignals -> Bool
bannerWorthy s =
    not (Dict.isEmpty s.forgedAuthors) || s.rateLimitHits > 0


{-| Tally envelopes dropped by signature verification, keyed by their claimed
author id, stamping the detection time. An empty list leaves the record (and
its timestamp) untouched.
-}
recordForgedAuthors : List String -> Time.Posix -> TamperSignals -> TamperSignals
recordForgedAuthors authors at s =
    case authors of
        [] ->
            s

        _ ->
            { s
                | forgedAuthors =
                    List.foldl (\a d -> Dict.update a (\c -> Just (Maybe.withDefault 0 c + 1)) d) s.forgedAuthors authors
                , lastDetectedAt = Just at
            }


recordRateLimitHit : Time.Posix -> TamperSignals -> TamperSignals
recordRateLimitHit at s =
    { s | rateLimitHits = s.rateLimitHits + 1, lastDetectedAt = Just at }


recordResetWithLoss : Time.Posix -> TamperSignals -> TamperSignals
recordResetWithLoss at s =
    { s | resetsWithLoss = s.resetsWithLoss + 1, lastDetectedAt = Just at }


recordManifestMismatch : Time.Posix -> TamperSignals -> TamperSignals
recordManifestMismatch at s =
    { s | manifestMismatches = s.manifestMismatches + 1, lastDetectedAt = Just at }


encode : TamperSignals -> Encode.Value
encode s =
    Encode.object
        ([ ( "fa", Encode.dict identity Encode.int s.forgedAuthors )
         , ( "rl", Encode.int s.rateLimitHits )
         , ( "rw", Encode.int s.resetsWithLoss )
         , ( "mm", Encode.int s.manifestMismatches )
         ]
            ++ (case s.lastDetectedAt of
                    Just t ->
                        [ ( "at", Encode.int (Time.posixToMillis t) ) ]

                    Nothing ->
                        []
               )
        )


decoder : Decode.Decoder TamperSignals
decoder =
    Decode.map5 TamperSignals
        (optional "fa" (Decode.dict Decode.int) Dict.empty)
        (optional "rl" Decode.int 0)
        (optional "rw" Decode.int 0)
        (optional "mm" Decode.int 0)
        (Decode.maybe (Decode.field "at" Decode.int |> Decode.map Time.millisToPosix))


optional : String -> Decode.Decoder a -> a -> Decode.Decoder a
optional key inner fallback =
    Decode.oneOf [ Decode.field key inner, Decode.succeed fallback ]
