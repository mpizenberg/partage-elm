module UI.Categories exposing (label, labelWithEmoji)

import Domain.Entry exposing (Category(..))
import Translations as T exposing (I18n)


type alias Presentation =
    { emoji : String
    , label : I18n -> String
    }


label : I18n -> Category -> String
label i18n category =
    (presentation category).label i18n


labelWithEmoji : I18n -> Category -> String
labelWithEmoji i18n category =
    let
        shown : Presentation
        shown =
            presentation category
    in
    shown.emoji ++ " " ++ shown.label i18n


presentation : Category -> Presentation
presentation category =
    case category of
        Food ->
            { emoji = "🍽️", label = T.categoryFood }

        Transport ->
            { emoji = "🚗", label = T.categoryTransport }

        Accommodation ->
            { emoji = "🏠", label = T.categoryAccommodation }

        Entertainment ->
            { emoji = "🎭", label = T.categoryEntertainment }

        Shopping ->
            { emoji = "🛍️", label = T.categoryShopping }

        Groceries ->
            { emoji = "🛒", label = T.categoryGroceries }

        Utilities ->
            { emoji = "⚡", label = T.categoryUtilities }

        Healthcare ->
            { emoji = "💊", label = T.categoryHealthcare }

        Other ->
            { emoji = "📦", label = T.categoryOther }
