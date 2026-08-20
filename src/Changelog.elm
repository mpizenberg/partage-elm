module Changelog exposing (Entry, entries, hasUnseen, latest)

{-| The user-facing history of the app.

One entry per shipped batch of user-visible work: a change nobody would notice
does not belong here, and neither does one entry per commit. The date labels the
entry and identifies it, so no two entries share one.

Entries live in the translation files and therefore ship inside the bundle, so a
client only ever reads about changes the build it is running actually has.

-}

import Translations as T exposing (I18n)


type alias Entry =
    { date : String
    , title : I18n -> String
    , body : I18n -> String
    }


{-| Newest first.
-}
entries : List Entry
entries =
    [ { date = "2026-08-19"
      , title = T.changelogNotificationsTitle
      , body = T.changelogNotificationsBody
      }
    , { date = "2026-07-28"
      , title = T.changelogPaymentMethodsTitle
      , body = T.changelogPaymentMethodsBody
      }
    , { date = "2026-07-22"
      , title = T.changelogArchiveTitle
      , body = T.changelogArchiveBody
      }
    ]


{-| The date of the newest entry.
-}
latest : String
latest =
    List.head entries |> Maybe.map .date |> Maybe.withDefault ""


{-| Whether anything was published after the last entry the reader saw. A marker
that was never written belongs to an install that has never seen the app change,
so nothing counts as new until the first launch records where it started.
-}
hasUnseen : Maybe String -> Bool
hasUnseen marker =
    case marker of
        Nothing ->
            False

        Just seen ->
            seen < latest
