module StaticPageLinkTest exposing (suite)

import Html.Attributes
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector exposing (attribute, tag)
import UI.Components
import Ui


suite : Test
suite =
    describe "static page link attributes"
        [ test "the referrer survives, trimmed to the origin" <|
            \_ ->
                render (UI.Components.staticPageLinkAttrs "/")
                    |> Query.has
                        [ attribute (Html.Attributes.rel "noopener")
                        , attribute (Html.Attributes.attribute "referrerpolicy" "origin")
                        ]
        , test "the new-tab variant keeps the same referrer policy" <|
            \_ ->
                render (UI.Components.staticPageNewTabLinkAttrs "/en/changelog/")
                    |> Query.has
                        [ attribute (Html.Attributes.rel "noopener")
                        , attribute (Html.Attributes.attribute "referrerpolicy" "origin")
                        , attribute (Html.Attributes.target "_blank")
                        ]
        ]


render : List (Ui.Attribute msg) -> Query.Single msg
render attrs =
    Ui.layout Ui.default [] (Ui.el attrs (Ui.text "link"))
        |> Query.fromHtml
        |> Query.find [ tag "a" ]
