module Page.NotFound exposing (view)

import Html exposing (Html, div, h1, p, text)


view : Html msg
view =
    div []
        [ h1 [] [ text "Page Not Found" ]
        , p [] [ text "The page you are looking for does not exist." ]
        ]
