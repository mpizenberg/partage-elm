module DiagnosticsTest exposing (suite)

import Domain.Event exposing (Payload(..))
import Expect
import Page.Group.Diagnostics as Diagnostics
import Test exposing (Test, describe, test)
import TestHelpers exposing (bootstrapMembers, makeEnvelope)


suite : Test
suite =
    describe "Diagnostics"
        [ describe "histogram"
            [ test "counts events per payload type, most frequent first" <|
                \_ ->
                    (bootstrapMembers
                        ++ [ makeEnvelope "ret-1" 3 "admin" (MemberRetired { rootId = "bob" }) ]
                    )
                        |> Diagnostics.histogram
                        |> Expect.equal [ ( "MemberCreated", 3 ), ( "MemberRetired", 1 ) ]
            , test "empty log yields an empty histogram" <|
                \_ ->
                    Diagnostics.histogram []
                        |> Expect.equal []
            , test "breaks count ties alphabetically" <|
                \_ ->
                    [ makeEnvelope "ret-1" 0 "admin" (MemberRetired { rootId = "bob" })
                    , makeEnvelope "del-1" 1 "admin" (EntryDeleted { rootId = "e1" })
                    ]
                        |> Diagnostics.histogram
                        |> Expect.equal [ ( "EntryDeleted", 1 ), ( "MemberRetired", 1 ) ]
            ]
        , describe "median"
            [ test "odd length takes the middle value" <|
                \_ ->
                    Diagnostics.median [ 30, 10, 20 ]
                        |> Expect.equal 20
            , test "even length takes the lower middle value" <|
                \_ ->
                    Diagnostics.median [ 40, 10, 30, 20 ]
                        |> Expect.equal 20
            , test "empty list yields 0" <|
                \_ ->
                    Diagnostics.median []
                        |> Expect.equal 0
            ]
        , describe "formatBytes"
            [ test "bytes below 1000 are shown as-is" <|
                \_ ->
                    Diagnostics.formatBytes 532
                        |> Expect.equal "532 B"
            , test "kilobytes keep one decimal when non-zero" <|
                \_ ->
                    Diagnostics.formatBytes 1437
                        |> Expect.equal "1.4 kB"
            , test "round kilobyte values drop the decimal" <|
                \_ ->
                    Diagnostics.formatBytes 2996
                        |> Expect.equal "3 kB"
            , test "megabytes" <|
                \_ ->
                    Diagnostics.formatBytes 2340000
                        |> Expect.equal "2.3 MB"
            ]
        ]
