module Infra.ExchangeRate exposing (fetchRateCached, supports, xeComUrl)

{-| Automated currency exchange rates.

Fetches daily reference rates from the Frankfurter API (ECB-sourced, no API key,
CORS-enabled) and caches them in IndexedDB keyed by `{base}-{quote}-{YYYY-MM-DD}`.

Caching serves two purposes:

  - A rate already fetched today is reused without hitting the network, so a pair
    is fetched at most once per day.
  - When the network is unavailable, the most recent cached rate for the pair from
    the past `maxCacheAgeDays` days is used as an offline fallback. Entries older
    than that window are swept, bounding storage growth.

If neither a network fetch nor a recent cached rate is available, the error
surfaces and the form falls back to the manual xe.com link.

-}

import ConcurrentTask exposing (ConcurrentTask)
import ConcurrentTask.Http as Http
import Domain.Currency as Currency exposing (Currency(..))
import Domain.Date as Date exposing (Date)
import IndexedDb as Idb
import Infra.Storage as Storage
import Json.Decode as Decode


{-| Whether a currency is covered by the Frankfurter/ECB reference rates.
All supported app currencies are covered except ARS (Argentine Peso), which the
ECB does not publish — pairs involving it must be entered manually (xe.com link).
-}
supports : Currency -> Bool
supports currency =
    case currency of
        ARS ->
            False

        _ ->
            True


{-| Number of days a cached rate is kept before being swept.
-}
maxCacheAgeDays : Int
maxCacheAgeDays =
    3


{-| Fetch the rate to convert an amount in `base` into `quote`
(i.e. `1 base = rate quote`).

A rate already cached for today is returned without a network call. Otherwise it
queries Frankfurter and caches the result (storing and sweeping are best-effort,
so storage hiccups never discard a valid rate). If the network fetch fails, the
most recent cached rate for the pair within `maxCacheAgeDays` is used as an
offline fallback; if there is none, the network error is propagated.

-}
fetchRateCached : Idb.Db -> Date -> { base : Currency, quote : Currency } -> ConcurrentTask Http.Error Float
fetchRateCached db today { base, quote } =
    Storage.loadExchangeRate db (cacheKey base quote today)
        |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed Nothing)
        |> ConcurrentTask.andThen
            (\cached ->
                case cached of
                    Just rate ->
                        ConcurrentTask.succeed rate

                    Nothing ->
                        fetchAndCache db today base quote
                            |> ConcurrentTask.onError
                                (\httpError ->
                                    latestCachedRate db today base quote
                                        |> ConcurrentTask.andThen
                                            (\fallback ->
                                                case fallback of
                                                    Just rate ->
                                                        ConcurrentTask.succeed rate

                                                    Nothing ->
                                                        ConcurrentTask.fail httpError
                                            )
                                )
            )


{-| Fetch a fresh rate from Frankfurter, cache it under today's key, and sweep
stale entries (the latter two best-effort).
-}
fetchAndCache : Idb.Db -> Date -> Currency -> Currency -> ConcurrentTask Http.Error Float
fetchAndCache db today base quote =
    fetchRate base quote
        |> ConcurrentTask.andThen
            (\rate ->
                bestEffort (Storage.saveExchangeRate db (cacheKey base quote today) rate)
                    |> ConcurrentTask.andThenDo (bestEffort (sweepStale db today))
                    |> ConcurrentTask.andThenDo (ConcurrentTask.succeed rate)
            )


{-| Build the xe.com currency converter URL prefilled with the amount and pair,
as a manual fallback when auto-fetch isn't possible (unsupported pair, offline,
or request failure).
-}
xeComUrl : { base : Currency, quote : Currency, amountCents : Int } -> String
xeComUrl { base, quote, amountCents } =
    let
        amount : Float
        amount =
            if amountCents <= 0 then
                1

            else
                toFloat amountCents / toFloat (10 ^ Currency.precision base)
    in
    "https://www.xe.com/currencyconverter/convert/?Amount="
        ++ String.fromFloat amount
        ++ "&From="
        ++ Currency.currencyCode base
        ++ "&To="
        ++ Currency.currencyCode quote



-- INTERNAL


cacheKey : Currency -> Currency -> Date -> String
cacheKey base quote today =
    Currency.currencyCode base ++ "-" ++ Currency.currencyCode quote ++ "-" ++ Date.toString today


fetchRate : Currency -> Currency -> ConcurrentTask Http.Error Float
fetchRate base quote =
    let
        quoteCode : String
        quoteCode =
            Currency.currencyCode quote
    in
    Http.get
        { url =
            "https://api.frankfurter.dev/v1/latest?base="
                ++ Currency.currencyCode base
                ++ "&symbols="
                ++ quoteCode
        , headers = []
        , expect = Http.expectJson (Decode.at [ "rates", quoteCode ] Decode.float)
        , timeout = Just 10000
        }


{-| Most recent cached rate for the pair within the retention window, used as an
offline fallback when a fresh fetch fails. Keys share the `{base}-{quote}-` prefix
and end in an ISO date, so the lexicographically greatest matching key is newest.
Cache-read errors degrade to "no fallback" rather than masking the network error.
-}
latestCachedRate : Idb.Db -> Date -> Currency -> Currency -> ConcurrentTask Http.Error (Maybe Float)
latestCachedRate db today base quote =
    let
        prefix : String
        prefix =
            Currency.currencyCode base ++ "-" ++ Currency.currencyCode quote ++ "-"

        cutoff : String
        cutoff =
            Date.toString (Date.addDays -maxCacheAgeDays today)
    in
    Storage.exchangeRateKeys db
        |> ConcurrentTask.andThen
            (\keys ->
                let
                    fresh : List String
                    fresh =
                        List.filter (\k -> String.startsWith prefix k && String.right 10 k >= cutoff) keys
                in
                case List.maximum fresh of
                    Just key ->
                        Storage.loadExchangeRate db key

                    Nothing ->
                        ConcurrentTask.succeed Nothing
            )
        |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed Nothing)


{-| Delete cached rates whose date is older than the retention window.
ISO date strings compare lexicographically, so no parsing is needed.
-}
sweepStale : Idb.Db -> Date -> ConcurrentTask Idb.Error ()
sweepStale db today =
    let
        cutoff : String
        cutoff =
            Date.toString (Date.addDays -maxCacheAgeDays today)
    in
    Storage.exchangeRateKeys db
        |> ConcurrentTask.andThen
            (\keys ->
                case List.filter (\k -> String.right 10 k < cutoff) keys of
                    [] ->
                        ConcurrentTask.succeed ()

                    stale ->
                        Storage.deleteExchangeRates db stale
            )


bestEffort : ConcurrentTask x a -> ConcurrentTask y ()
bestEffort task =
    task
        |> ConcurrentTask.map (\_ -> ())
        |> ConcurrentTask.onError (\_ -> ConcurrentTask.succeed ())
