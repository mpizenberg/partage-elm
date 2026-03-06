module ConcurrentTaskExtra exposing
    ( AttemptBatch, andAttempt, batchAttempt, initAttemptBatch
    , TaskRunner, initTaskRunner, andRun
    )

{-| Helpers for working with `ConcurrentTask`.


## Batch Attempt

Start multiple tasks with different response types in one go,
threading the pool through each attempt automatically.

    initAttemptBatch pool send
        |> andAttempt OnTask1Complete task1
        |> andAttempt OnTask2Complete task2
        |> andAttempt OnTask3Complete task3
        |> batchAttempt

@docs AttemptBatch, initAttemptBatch, andAttempt, batchAttempt


## Task Runner

A pipeline-friendly wrapper around `ConcurrentTask.Pool` and the send port.
Thread a `( TaskRunner msg, Cmd msg )` tuple through multiple task attempts.

    ( model.runner, otherCmd )
        |> andRun OnTask1Complete task1
        |> andRun OnTask2Complete task2
        |> Tuple.mapFirst (\r -> { model | runner = r })

@docs TaskRunner, initTaskRunner, andRun

-}

import ConcurrentTask exposing (ConcurrentTask, Pool, Response)
import Json.Decode as Decode


{-| An opaque builder that accumulates tasks to attempt on a shared pool.
-}
type AttemptBatch msg
    = AttemptBatch (Pool msg) (Decode.Value -> Cmd msg) (List (Cmd msg))


{-| Start building a batch of attempts from a pool and a send function.
-}
initAttemptBatch : Pool msg -> (Decode.Value -> Cmd msg) -> AttemptBatch msg
initAttemptBatch pool send =
    AttemptBatch pool send []


{-| Add a task to the batch with its own completion handler.
Each task can have different error and success types.
-}
andAttempt : (Response x a -> msg) -> ConcurrentTask x a -> AttemptBatch msg -> AttemptBatch msg
andAttempt onComplete task (AttemptBatch pool send cmds) =
    let
        ( nextPool, cmd ) =
            ConcurrentTask.attempt
                { pool = pool
                , send = send
                , onComplete = onComplete
                }
                task
    in
    AttemptBatch nextPool send (cmd :: cmds)


{-| Finalize the batch, returning the updated pool and a single batched command.
-}
batchAttempt : AttemptBatch msg -> ( Pool msg, Cmd msg )
batchAttempt (AttemptBatch pool _ cmds) =
    ( pool, Cmd.batch cmds )


{-| An opaque wrapper around a task pool and its send port.
-}
type TaskRunner msg
    = TaskRunner (Pool msg) (Decode.Value -> Cmd msg)


{-| Create a task runner from a send port. Initializes a fresh pool internally.
-}
initTaskRunner : (Decode.Value -> Cmd msg) -> TaskRunner msg
initTaskRunner send =
    TaskRunner ConcurrentTask.pool send


{-| Run a task, threading the runner and accumulating commands.
-}
andRun : (Response x a -> msg) -> ConcurrentTask x a -> ( TaskRunner msg, Cmd msg ) -> ( TaskRunner msg, Cmd msg )
andRun onComplete task ( TaskRunner pool send, cmd ) =
    let
        ( nextPool, newCmd ) =
            ConcurrentTask.attempt
                { pool = pool
                , send = send
                , onComplete = onComplete
                }
                task
    in
    ( TaskRunner nextPool send, Cmd.batch [ cmd, newCmd ] )
