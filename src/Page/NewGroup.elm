module Page.NewGroup exposing (view)

import Html exposing (Html, div, h1, p, text)


view : Html msg
view =
    div []
        [ h1 [] [ text "Create a Group" ]
        , p [] [ text "Group creation form will be available in Phase 5." ]
        ]
