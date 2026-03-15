module Infra.UsageStats exposing
    ( CostBreakdown
    , StorageEstimate
    , UsageStats
    , calculateCosts
    , decoder
    , defaultStats
    , encode
    , estimateStorage
    , formatDollars
    , updateStorageCost
    )

import ConcurrentTask exposing (ConcurrentTask)
import Domain.Date as Date
import Json.Decode as Decode
import Json.Encode as Encode
import Time


{-| Local usage statistics for cost estimation (never sent to server).
-}
type alias UsageStats =
    { trackingStartDate : Time.Posix
    , totalBytesTransferred : Int
    , storageBytes : Int
    , storageLastCheckedDate : String
    , storageCostAccumulatorCentNanos : Int
    }


type alias StorageEstimate =
    { usage : Int
    , quota : Int
    }


type alias CostBreakdown =
    { baseCostCents : Float
    , storageCostCents : Float
    , computeCostCents : Float
    , networkCostCents : Float
    , totalCostCents : Float
    , monthsTracked : Float
    , avgPerMonthCents : Float
    }



-- Rates from SPECIFICATION.md Section 17.2


baseCostCentsPerMonth : Float
baseCostCentsPerMonth =
    10.0


storageCentsPerGbPerMonth : Float
storageCentsPerGbPerMonth =
    10.0


bandwidthCentsPerGb : Float
bandwidthCentsPerGb =
    10.0


computeMultiplier : Float
computeMultiplier =
    5.0


bytesPerGb : Float
bytesPerGb =
    1.0e9



-- ConcurrentTask for navigator.storage.estimate()


estimateStorage : ConcurrentTask Never StorageEstimate
estimateStorage =
    ConcurrentTask.define
        { function = "usageStats:estimateStorage"
        , expect =
            ConcurrentTask.expectJson
                (Decode.map2 StorageEstimate
                    (Decode.field "usage" Decode.int)
                    (Decode.field "quota" Decode.int)
                )
        , errors = ConcurrentTask.expectNoErrors
        , args = Encode.null
        }



-- Cost calculation


calculateCosts : Time.Posix -> UsageStats -> CostBreakdown
calculateCosts now stats =
    let
        daysBetween : Float
        daysBetween =
            toFloat (Time.posixToMillis now - Time.posixToMillis stats.trackingStartDate)
                / (1000 * 60 * 60 * 24)

        monthsTracked : Float
        monthsTracked =
            max 0 (daysBetween / 30.44)

        baseCostCents : Float
        baseCostCents =
            monthsTracked * baseCostCentsPerMonth

        storageCostCents : Float
        storageCostCents =
            toFloat stats.storageCostAccumulatorCentNanos / 1.0e9

        computeCostCents : Float
        computeCostCents =
            storageCostCents * computeMultiplier

        networkCostCents : Float
        networkCostCents =
            toFloat stats.totalBytesTransferred / bytesPerGb * bandwidthCentsPerGb

        totalCostCents : Float
        totalCostCents =
            baseCostCents + storageCostCents + computeCostCents + networkCostCents

        avgPerMonthCents : Float
        avgPerMonthCents =
            if monthsTracked > 0 then
                totalCostCents / monthsTracked

            else
                totalCostCents
    in
    { baseCostCents = baseCostCents
    , storageCostCents = storageCostCents
    , computeCostCents = computeCostCents
    , networkCostCents = networkCostCents
    , totalCostCents = totalCostCents
    , monthsTracked = monthsTracked
    , avgPerMonthCents = avgPerMonthCents
    }


{-| Update storage cost accumulator if the last check was more than 1 day ago.
Returns the updated stats with new storage bytes and accumulated cost.
-}
updateStorageCost : Time.Posix -> Int -> UsageStats -> UsageStats
updateStorageCost now storageUsageBytes stats =
    let
        todayDate : Date.Date
        todayDate =
            Date.posixToDate now

        todayStr : String
        todayStr =
            Date.toString todayDate
    in
    if stats.storageLastCheckedDate == "" then
        { stats
            | storageBytes = storageUsageBytes
            , storageLastCheckedDate = todayStr
        }

    else
        let
            lastDate : Date.Date
            lastDate =
                parseDateString stats.storageLastCheckedDate

            lastComparable : Int
            lastComparable =
                Date.toComparable lastDate

            todayComparable : Int
            todayComparable =
                Date.toComparable todayDate
        in
        if todayComparable > lastComparable then
            let
                daysSince : Float
                daysSince =
                    toFloat (Time.posixToMillis now - dateToApproxMillis lastDate)
                        / (1000 * 60 * 60 * 24)

                dailyStorageCostCentNanos : Float
                dailyStorageCostCentNanos =
                    toFloat stats.storageBytes
                        / bytesPerGb
                        * storageCentsPerGbPerMonth
                        / 30.44
                        * 1.0e9

                additionalCentNanos : Int
                additionalCentNanos =
                    round (daysSince * dailyStorageCostCentNanos)
            in
            { stats
                | storageBytes = storageUsageBytes
                , storageLastCheckedDate = todayStr
                , storageCostAccumulatorCentNanos = stats.storageCostAccumulatorCentNanos + additionalCentNanos
            }

        else
            { stats | storageBytes = storageUsageBytes }


defaultStats : Time.Posix -> UsageStats
defaultStats now =
    { trackingStartDate = now
    , totalBytesTransferred = 0
    , storageBytes = 0
    , storageLastCheckedDate = ""
    , storageCostAccumulatorCentNanos = 0
    }


formatDollars : Float -> String
formatDollars cents =
    let
        dollars : Float
        dollars =
            cents / 100.0

        rounded : Int
        rounded =
            round (dollars * 100)

        whole : Int
        whole =
            rounded // 100

        frac : Int
        frac =
            abs (remainderBy 100 rounded)
    in
    "$" ++ String.fromInt whole ++ "." ++ String.padLeft 2 '0' (String.fromInt frac)



-- Codecs


encode : UsageStats -> Encode.Value
encode stats =
    Encode.object
        [ ( "trackingStartDate", Encode.int (Time.posixToMillis stats.trackingStartDate) )
        , ( "totalBytesTransferred", Encode.int stats.totalBytesTransferred )
        , ( "storageBytes", Encode.int stats.storageBytes )
        , ( "storageLastCheckedDate", Encode.string stats.storageLastCheckedDate )
        , ( "storageCostAccumulatorCentNanos", Encode.int stats.storageCostAccumulatorCentNanos )
        ]


decoder : Decode.Decoder UsageStats
decoder =
    Decode.map5 UsageStats
        (Decode.field "trackingStartDate" (Decode.map Time.millisToPosix Decode.int))
        (Decode.field "totalBytesTransferred" Decode.int)
        (Decode.field "storageBytes" Decode.int)
        (Decode.field "storageLastCheckedDate" Decode.string)
        (Decode.field "storageCostAccumulatorCentNanos" Decode.int)



-- Internal helpers


parseDateString : String -> Date.Date
parseDateString str =
    case String.split "-" str |> List.filterMap String.toInt of
        [ y, m, d ] ->
            { year = y, month = m, day = d }

        _ ->
            { year = 2000, month = 1, day = 1 }


dateToApproxMillis : Date.Date -> Int
dateToApproxMillis date =
    let
        -- Approximate: days since epoch
        yearDays : Int
        yearDays =
            (date.year - 1970) * 365 + ((date.year - 1969) // 4)

        monthDays : Int
        monthDays =
            List.sum (List.map (daysInMonth date.year) (List.range 1 (date.month - 1)))
    in
    (yearDays + monthDays + date.day - 1) * 86400000


daysInMonth : Int -> Int -> Int
daysInMonth year month =
    case month of
        2 ->
            if isLeapYear year then
                29

            else
                28

        4 ->
            30

        6 ->
            30

        9 ->
            30

        11 ->
            30

        _ ->
            31


isLeapYear : Int -> Bool
isLeapYear year =
    (remainderBy 4 year == 0) && (remainderBy 100 year /= 0 || remainderBy 400 year == 0)
