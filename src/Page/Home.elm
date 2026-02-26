module Page.Home exposing (view)

import Html exposing (Html, div, h1, p, text)


view : Html msg
view =
    div []
        [ h1 [] [ text "Your Groups" ]
        , p [] [ text "No groups yet. Create one to get started!" ]
        ]
