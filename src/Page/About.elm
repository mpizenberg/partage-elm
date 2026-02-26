module Page.About exposing (view)

import Html exposing (Html, div, h1, p, text)


view : Html msg
view =
    div []
        [ h1 [] [ text "About Partage" ]
        , p [] [ text "A fully encrypted, local-first bill-splitting application." ]
        ]
