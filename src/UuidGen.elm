module UuidGen exposing (v4, v4batch, v7, v7batch)

{-| UUID generation helpers wrapping elm-uuid.
-}

import Random
import Time
import UUID


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
        ( acc, seed )

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
    -- TODO later:
    -- This function will lead to invalid UUIDs.
    -- Because stepV7 always increment the counter, for a new time,
    -- we may start with the counter very close to the wrapping limit,
    -- and calling it again will wrap the counter to 0,
    -- invalidating the monotonic order guarantees.
    -- Maybe the V7State should keep the time,
    -- and reset the counter to 0 if the stepV7 calls it with a new time.
    -- In any case, let's make sure our Time.Posix value don't get stale for too long.
    -- There are probably a few relevant places where we can bundle
    -- ConcurrentTask.Time.now with another message to update the model time.
    Tuple.mapFirst UUID.toString (UUID.stepV7 time state)


{-| Generate n v7 UUID strings.
-}
v7batch : Int -> Time.Posix -> UUID.V7State -> ( List String, UUID.V7State )
v7batch n time state =
    v7batchHelp n time state []


v7batchHelp : Int -> Time.Posix -> UUID.V7State -> List String -> ( List String, UUID.V7State )
v7batchHelp remaining time state acc =
    if remaining <= 0 then
        ( acc, state )

    else
        let
            ( uuid, nextState ) =
                UUID.stepV7 time state
        in
        v7batchHelp (remaining - 1) time nextState (UUID.toString uuid :: acc)
