module Infra.IdGen exposing (Entropy, State, groupId, init, v4, v4batch, v7, v7batch)

{-| ID generation state and helpers wrapping elm-uuid, plus short group IDs.
-}

import Random
import Time
import UUID


type alias Entropy =
    { seed1 : Int
    , seed2 : Int
    , seed3 : Int
    , seed4 : Int
    }


type State
    = State
        { groupIdSeed : Random.Seed
        , v4Seeds : UUID.Seeds
        , v7State : UUID.V7State
        }


{-| Initialize two independent ID streams from four browser-generated entropy
values. Main and the group page own one stream each, so their update paths do
not need to exchange generator state.
-}
init : Entropy -> ( State, State )
init entropy =
    let
        ( mainSeed1, groupSeed1 ) =
            splitInitialSeed entropy.seed1

        ( mainSeed2, groupSeed2 ) =
            splitInitialSeed entropy.seed2

        ( mainSeed3, groupSeed3 ) =
            splitInitialSeed entropy.seed3

        ( mainSeed4, groupSeed4 ) =
            splitInitialSeed entropy.seed4
    in
    ( fromSeeds mainSeed1 mainSeed2 mainSeed3 mainSeed4
    , fromSeeds groupSeed1 groupSeed2 groupSeed3 groupSeed4
    )


splitInitialSeed : Int -> ( Random.Seed, Random.Seed )
splitInitialSeed value =
    Random.step Random.independentSeed (Random.initialSeed value)


fromSeeds : Random.Seed -> Random.Seed -> Random.Seed -> Random.Seed -> State
fromSeeds seed1 seed2 seed3 seed4 =
    let
        ( groupIdSeed, v4Seed1 ) =
            Random.step Random.independentSeed seed1

        ( v7Seed, v4Seed2 ) =
            Random.step Random.independentSeed seed2

        ( v7State, _ ) =
            Random.step UUID.initialV7State v7Seed
    in
    State
        { groupIdSeed = groupIdSeed
        , v4Seeds =
            { seed1 = v4Seed1
            , seed2 = v4Seed2
            , seed3 = seed3
            , seed4 = seed4
            }
        , v7State = v7State
        }


{-| Generate a 15-character alphanumeric group ID (short enough for invite URLs).
-}
groupId : State -> ( String, State )
groupId (State state) =
    let
        ( id, nextSeed ) =
            Random.step groupIdGenerator state.groupIdSeed
    in
    ( id, State { state | groupIdSeed = nextSeed } )


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
v4 : State -> ( String, State )
v4 (State state) =
    let
        ( uuid, nextSeeds ) =
            UUID.step state.v4Seeds
    in
    ( UUID.toString uuid, State { state | v4Seeds = nextSeeds } )


{-| Generate n v4 UUID strings.
-}
v4batch : Int -> State -> ( List String, State )
v4batch count =
    batch count v4


{-| Generate a single v7 UUID string.
-}
v7 : Time.Posix -> State -> ( String, State )
v7 time (State state) =
    let
        ( uuid, nextV7State ) =
            UUID.stepV7 time state.v7State
    in
    ( UUID.toString uuid, State { state | v7State = nextV7State } )


{-| Generate n v7 UUID strings.
-}
v7batch : Int -> Time.Posix -> State -> ( List String, State )
v7batch count time =
    batch count (v7 time)


batch : Int -> (State -> ( String, State )) -> State -> ( List String, State )
batch count generate state =
    batchHelp count generate state []


batchHelp : Int -> (State -> ( String, State )) -> State -> List String -> ( List String, State )
batchHelp remaining generate state acc =
    if remaining <= 0 then
        ( List.reverse acc, state )

    else
        let
            ( id, nextState ) =
                generate state
        in
        batchHelp (remaining - 1) generate nextState (id :: acc)
