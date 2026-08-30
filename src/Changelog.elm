module Changelog exposing (hasUnseen)

{-| Whether the app has news the reader hasn't seen.

The entries themselves live in `changelog.json` and render on the public
static pages; the app only carries the newest entry's date (the generated
`Changelog.Latest`) to decide whether to raise the banner.

-}

import Changelog.Latest


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
            seen < Changelog.Latest.date
