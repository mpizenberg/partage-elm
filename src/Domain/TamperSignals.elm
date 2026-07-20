module Domain.TamperSignals exposing
    ( TamperSignals
    , bannerWorthy
    , decoder
    , empty
    , encode
    , isClean
    , recordForgedSignatures
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

-}

import Json.Decode as Decode
import Json.Encode as Encode
import Time


type alias TamperSignals =
    { forgedSignatures : Int
    , rateLimitHits : Int
    , resetsWithLoss : Int
    , manifestMismatches : Int
    , lastDetectedAt : Maybe Time.Posix
    }


empty : TamperSignals
empty =
    { forgedSignatures = 0
    , rateLimitHits = 0
    , resetsWithLoss = 0
    , manifestMismatches = 0
    , lastDetectedAt = Nothing
    }


{-| No signal has ever fired (or the counters were dismissed).
-}
isClean : TamperSignals -> Bool
isClean s =
    s.forgedSignatures == 0 && s.rateLimitHits == 0 && s.resetsWithLoss == 0 && s.manifestMismatches == 0


{-| Whether the high-confidence signals warrant the user-facing banner. The
advisory signals (reset-with-loss, manifest mismatch) never raise it — their
benign causes would make it cry wolf.
-}
bannerWorthy : TamperSignals -> Bool
bannerWorthy s =
    s.forgedSignatures > 0 || s.rateLimitHits > 0


{-| Add `n` envelopes dropped by signature verification, stamping the detection
time. A non-positive count leaves the record (and its timestamp) untouched.
-}
recordForgedSignatures : Int -> Time.Posix -> TamperSignals -> TamperSignals
recordForgedSignatures n at s =
    if n <= 0 then
        s

    else
        { s | forgedSignatures = s.forgedSignatures + n, lastDetectedAt = Just at }


encode : TamperSignals -> Encode.Value
encode s =
    Encode.object
        ([ ( "fs", Encode.int s.forgedSignatures )
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
        (optionalInt "fs")
        (optionalInt "rl")
        (optionalInt "rw")
        (optionalInt "mm")
        (Decode.maybe (Decode.field "at" Decode.int |> Decode.map Time.millisToPosix))


optionalInt : String -> Decode.Decoder Int
optionalInt key =
    Decode.oneOf [ Decode.field key Decode.int, Decode.succeed 0 ]
