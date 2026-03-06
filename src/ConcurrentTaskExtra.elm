module ConcurrentTaskExtra exposing
    ( AttemptBatch, initAttemptBatch, andAttempt, batchAttempt
    , TaskRunner, initTaskRunner, initTaskRunnerWithPool, andRun, onProgress
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

@docs TaskRunner, initTaskRunner, initTaskRunnerWithPool, andRun, onProgress

-}

import ConcurrentTask exposing (ConcurrentTask, Pool, Response)
import Json.Decode as Decode
import Json.Encode as Encode


{-| An opaque builder that accumulates tasks to attempt on a shared pool.
-}
type AttemptBatch msg
    = AttemptBatch (Pool msg) (Decode.Value -> Cmd msg) (List (Cmd msg))


{-| Start building a batch of attempts from a pool and a send function.
-}
initAttemptBatch : Pool msg -> (Decode.Value -> Cmd msg) -> AttemptBatch msg
initAttemptBatch p s =
    AttemptBatch p s []


{-| Add a task to the batch with its own completion handler.
Each task can have different error and success types.
-}
andAttempt : (Response x a -> msg) -> ConcurrentTask x a -> AttemptBatch msg -> AttemptBatch msg
andAttempt onComplete task (AttemptBatch p s cmds) =
    let
        ( nextPool, cmd ) =
            ConcurrentTask.attempt
                { pool = p
                , send = s
                , onComplete = onComplete
                }
                task
    in
    AttemptBatch nextPool s (cmd :: cmds)


{-| Finalize the batch, returning the updated pool and a single batched command.
-}
batchAttempt : AttemptBatch msg -> ( Pool msg, Cmd msg )
batchAttempt (AttemptBatch p _ cmds) =
    ( p, Cmd.batch cmds )


{-| An opaque wrapper around a task pool and its send port.
-}
type TaskRunner msg
    = TaskRunner (Pool msg) (Encode.Value -> Cmd msg)


{-| Create a task runner from a send port. Initializes a fresh pool internally.
-}
initTaskRunner : (Encode.Value -> Cmd msg) -> TaskRunner msg
initTaskRunner s =
    TaskRunner ConcurrentTask.pool s


{-| Create a task runner from an existing pool and a send port.
Useful when the pool has a custom pool ID (e.g. `ConcurrentTask.withPoolId 1`).
-}
initTaskRunnerWithPool : Pool msg -> (Encode.Value -> Cmd msg) -> TaskRunner msg
initTaskRunnerWithPool p s =
    TaskRunner p s


{-| Run a task, threading the runner and accumulating commands.
-}
andRun : (Response x a -> msg) -> ConcurrentTask x a -> ( TaskRunner msg, Cmd msg ) -> ( TaskRunner msg, Cmd msg )
andRun onComplete task ( TaskRunner p s, cmd ) =
    let
        ( nextPool, newCmd ) =
            ConcurrentTask.attempt
                { pool = p
                , send = s
                , onComplete = onComplete
                }
                task
    in
    ( TaskRunner nextPool s, Cmd.batch [ cmd, newCmd ] )


{-| Subscribe to task progress events. Use in your `subscriptions`.
-}
onProgress :
    { receive : (Decode.Value -> msg) -> Sub msg
    , onProgress : ( TaskRunner msg, Cmd msg ) -> msg
    }
    -> TaskRunner msg
    -> Sub msg
onProgress config (TaskRunner p s) =
    ConcurrentTask.onProgress
        { send = s
        , receive = config.receive
        , onProgress = \( newPool, cmd ) -> config.onProgress ( TaskRunner newPool s, cmd )
        }
        p
