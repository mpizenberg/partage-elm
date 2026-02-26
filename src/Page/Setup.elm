module Page.Setup exposing (view)

import Html exposing (Html, div, h1, p, text)


view : Html msg
view =
    div []
        [ h1 [] [ text "Welcome to Partage" ]
        , p [] [ text "Your privacy-first bill splitting app." ]
        , p [] [ text "Identity generation will be available in Phase 3." ]
        ]
