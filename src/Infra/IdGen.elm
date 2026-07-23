module Infra.IdGen exposing (groupId, v4, v4batch, v7, v7batch)

{-| ID generation helpers wrapping elm-uuid, plus short group IDs.
-}

import Random
import Time
import UUID


{-| Generate a 15-character alphanumeric group ID (short enough for invite URLs).
-}
groupId : Random.Seed -> ( String, Random.Seed )
groupId seed =
    Random.step groupIdGenerator seed


groupIdGenerator : Random.Generator String
groupIdGenerator =
    Random.list 15 idCharGenerator
        |> Random.map String.fromList


idCharGenerator : Random.Generator Char
idCharGenerator =
    Random.uniform 'a'
        [ 'b'
        , 'c'
        , 'd'
        , 'e'
        , 'f'
        , 'g'
        , 'h'
        , 'i'
        , 'j'
        , 'k'
        , 'l'
        , 'm'
        , 'n'
        , 'o'
        , 'p'
        , 'q'
        , 'r'
        , 's'
        , 't'
        , 'u'
        , 'v'
        , 'w'
        , 'x'
        , 'y'
        , 'z'
        , '0'
        , '1'
        , '2'
        , '3'
        , '4'
        , '5'
        , '6'
        , '7'
        , '8'
        , '9'
        ]


{-| Generate a single v4 UUID string.
-}
v4 : Random.Seed -> ( String, Random.Seed )
v4 seed =
    -- TODO later: use UUID.step instead for better randomness
    Tuple.mapFirst UUID.toString (Random.step UUID.generator seed)


{-| Generate n v4 UUID strings.
-}
v4batch : Int -> Random.Seed -> ( List String, Random.Seed )
v4batch n seed =
    -- TODO later: use UUID.step instead for better randomness
    v4batchHelp n seed []


v4batchHelp : Int -> Random.Seed -> List String -> ( List String, Random.Seed )
v4batchHelp remaining seed acc =
    if remaining <= 0 then
        ( List.reverse acc, seed )

    else
        let
            ( uuid, nextSeed ) =
                Random.step UUID.generator seed
        in
        v4batchHelp (remaining - 1) nextSeed (UUID.toString uuid :: acc)


{-| Generate a single v7 UUID string.
-}
v7 : Time.Posix -> UUID.V7State -> ( String, UUID.V7State )
v7 time state =
    Tuple.mapFirst UUID.toString (UUID.stepV7 time state)


{-| Generate n v7 UUID strings.
-}
v7batch : Int -> Time.Posix -> UUID.V7State -> ( List String, UUID.V7State )
v7batch n time state =
    v7batchHelp n time state []


v7batchHelp : Int -> Time.Posix -> UUID.V7State -> List String -> ( List String, UUID.V7State )
v7batchHelp remaining time state acc =
    if remaining <= 0 then
        ( List.reverse acc, state )

    else
        let
            ( uuid, nextState ) =
                UUID.stepV7 time state
        in
        v7batchHelp (remaining - 1) time nextState (UUID.toString uuid :: acc)
