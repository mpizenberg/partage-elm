module ConcurrentTaskExtra exposing
    ( AttemptBatch, initAttemptBatch, andAttempt, batchAttempt
    , TaskRunner, TaskRunnerConfig, initTaskRunner, andRun, subscription
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

@docs TaskRunner, TaskRunnerConfig, initTaskRunner, andRun, subscription

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


{-| Configuration to initialize a TaskRunner.
-}
type alias TaskRunnerConfig msg =
    { pool : Pool msg
    , send : Encode.Value -> Cmd msg
    , receive : (Decode.Value -> msg) -> Sub msg
    , onProgress : ( TaskRunner msg, Cmd msg ) -> msg
    }


{-| An opaque wrapper around a task pool, send/receive ports, and progress handler.
-}
type TaskRunner msg
    = TaskRunner (TaskRunnerConfig msg)


{-| Create a task runner from a pool, ports, and a progress handler.
-}
initTaskRunner : TaskRunnerConfig msg -> TaskRunner msg
initTaskRunner config =
    TaskRunner config


{-| Run a task, threading the runner and accumulating commands.
-}
andRun : (Response x a -> msg) -> ConcurrentTask x a -> ( TaskRunner msg, Cmd msg ) -> ( TaskRunner msg, Cmd msg )
andRun onComplete task ( TaskRunner r, cmd ) =
    let
        ( nextPool, newCmd ) =
            ConcurrentTask.attempt
                { pool = r.pool
                , send = r.send
                , onComplete = onComplete
                }
                task
    in
    ( TaskRunner
        { pool = nextPool
        , send = r.send
        , receive = r.receive
        , onProgress = r.onProgress
        }
    , Cmd.batch [ cmd, newCmd ]
    )


{-| Subscribe to task progress events. Use in your `subscriptions`.
-}
subscription : TaskRunner msg -> Sub msg
subscription (TaskRunner r) =
    ConcurrentTask.onProgress
        { send = r.send
        , receive = r.receive
        , onProgress = \( newPool, cmd ) -> r.onProgress ( TaskRunner { r | pool = newPool }, cmd )
        }
        r.pool
