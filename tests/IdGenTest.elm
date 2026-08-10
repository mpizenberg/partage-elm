module IdGenTest exposing (suite)

import Expect
import Infra.IdGen as IdGen
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "ID generation state"
        [ test "initialization gives Main and Page.Group different streams" <|
            \_ ->
                let
                    ( mainState, groupState ) =
                        IdGen.init entropy

                    ( mainId, _ ) =
                        IdGen.v4 mainState

                    ( groupId, _ ) =
                        IdGen.v4 groupState
                in
                groupId |> Expect.notEqual mainId
        , test "group IDs keep the invite URL format" <|
            \_ ->
                let
                    ( state, _ ) =
                        IdGen.init entropy

                    ( id, _ ) =
                        IdGen.groupId state
                in
                Expect.all
                    [ String.length >> Expect.equal 15
                    , String.all Char.isAlphaNum >> Expect.equal True
                    ]
                    id
        , test "v4 batches advance the stream like repeated generation" <|
            \_ ->
                let
                    ( state0, _ ) =
                        IdGen.init entropy

                    ( batchIds, stateAfterBatch ) =
                        IdGen.v4batch 3 state0

                    ( first, state1 ) =
                        IdGen.v4 state0

                    ( second, state2 ) =
                        IdGen.v4 state1

                    ( third, stateAfterRepeated ) =
                        IdGen.v4 state2

                    ( nextAfterBatch, _ ) =
                        IdGen.v4 stateAfterBatch

                    ( nextAfterRepeated, _ ) =
                        IdGen.v4 stateAfterRepeated
                in
                ( batchIds, nextAfterBatch )
                    |> Expect.equal ( [ first, second, third ], nextAfterRepeated )
        ]


entropy : IdGen.Entropy
entropy =
    { seed1 = 12345
    , seed2 = 67890
    , seed3 = 13579
    , seed4 = 24680
    }
