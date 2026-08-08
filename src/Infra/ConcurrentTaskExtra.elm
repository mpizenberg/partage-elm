module Infra.ConcurrentTaskExtra exposing (TaskRunner, TaskRunnerConfig, initTaskRunner, andRun, andCmd, subscription)

{-| Helpers for working with `ConcurrentTask`.


## Task Runner

A pipeline-friendly wrapper around `ConcurrentTask.Pool` and the send port.
Thread a `( TaskRunner msg, Cmd msg )` tuple through multiple task attempts.

    ( model.runner, otherCmd )
        |> andRun OnTask1Complete task1
        |> andRun OnTask2Complete task2
        |> Tuple.mapFirst (\r -> { model | runner = r })

@docs TaskRunner, TaskRunnerConfig, initTaskRunner, andRun, andCmd, subscription

-}

import ConcurrentTask exposing (ConcurrentTask, Pool, Response)
import Json.Decode as Decode
import Json.Encode as Encode


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


{-| Batch an extra `Cmd msg` into the runner pipeline without scheduling a task.
Useful for fire-and-forget side effects (e.g. `File.Download.string`) that sit
alongside task attempts in the same update branch.
-}
andCmd : Cmd msg -> ( TaskRunner msg, Cmd msg ) -> ( TaskRunner msg, Cmd msg )
andCmd extraCmd ( runner, cmd ) =
    ( runner, Cmd.batch [ cmd, extraCmd ] )


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
