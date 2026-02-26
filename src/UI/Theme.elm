module UI.Theme exposing
    ( balanceColor
    , borderWidth
    , contentMaxWidth
    , danger
    , dangerLight
    , fontSize
    , neutral200
    , neutral300
    , neutral500
    , neutral700
    , neutral900
    , primary
    , primaryLight
    , rounding
    , spacing
    , success
    , successLight
    , white
    )

{-| Design tokens: colors, spacing, and layout constants.
-}

import Domain.Balance as Balance
import Ui


{-| Maximum width for the main content area.
-}
contentMaxWidth : Int
contentMaxWidth =
    768


{-| Standard spacing scale.
-}
spacing : { xs : Int, sm : Int, md : Int, lg : Int, xl : Int }
spacing =
    { xs = 4
    , sm = 8
    , md = 16
    , lg = 24
    , xl = 32
    }


{-| Border radius scale.
-}
rounding : { sm : Int, md : Int }
rounding =
    { sm = 6, md = 8 }


{-| Border width scale.
-}
borderWidth : { sm : Int, md : Int }
borderWidth =
    { sm = 1, md = 2 }


{-| Font size scale.
-}
fontSize : { sm : Int, md : Int, lg : Int, xl : Int, hero : Int }
fontSize =
    { sm = 14
    , md = 16
    , lg = 18
    , xl = 22
    , hero = 28
    }



-- COLORS


primary : Ui.Color
primary =
    Ui.rgb 37 99 235


primaryLight : Ui.Color
primaryLight =
    Ui.rgb 219 234 254


success : Ui.Color
success =
    Ui.rgb 22 163 74


successLight : Ui.Color
successLight =
    Ui.rgb 220 252 231


danger : Ui.Color
danger =
    Ui.rgb 220 38 38


dangerLight : Ui.Color
dangerLight =
    Ui.rgb 254 226 226


white : Ui.Color
white =
    Ui.rgb 255 255 255


neutral200 : Ui.Color
neutral200 =
    Ui.rgb 229 231 235


neutral300 : Ui.Color
neutral300 =
    Ui.rgb 209 213 219


neutral500 : Ui.Color
neutral500 =
    Ui.rgb 107 114 128


neutral700 : Ui.Color
neutral700 =
    Ui.rgb 55 65 81


neutral900 : Ui.Color
neutral900 =
    Ui.rgb 17 24 39


{-| Map a balance status to its display color.
-}
balanceColor : Balance.Status -> Ui.Color
balanceColor status =
    case status of
        Balance.Creditor ->
            success

        Balance.Debtor ->
            danger

        Balance.Settled ->
            neutral500
