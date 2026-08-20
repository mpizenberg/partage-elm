module Changelog exposing (Entry, entries)

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
