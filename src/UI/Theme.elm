module UI.Theme exposing
    ( ColorScale, Scale
    , base, primary, success, warning, danger
    , font, spacing, radius, sizing
    , fontFamily, fontWeight
    , letterSpacing
    , border
    , shadow, shadowXl, shadowAccent, shadowKnob
    , contentMaxWidth
    )

{-| Design tokens for the warm minimal theme.


# Color Palette

6 colors, each with a 15-step scale.

@docs ColorScale, Scale
@docs base, primary, success, warning, danger


# Size Scales

4 scales with 7 levels each: xs, sm, md, lg, xl, xxl, xxxl.

@docs font, spacing, radius, sizing


# Typography

@docs fontFamily, fontWeight
@docs letterSpacing


# Borders

@docs border


# Shadows

@docs shadow, shadowXl, shadowAccent, shadowKnob


# Layout

@docs contentMaxWidth

-}

import Ui
import Ui.Font
import Ui.Shadow



-- COLOR SCALE TYPE


{-| A color scale with 15 steps, covering backgrounds, tints, accents,
solids, text, and shadow.
-}
type alias ColorScale =
    { bg : Ui.Color
    , bgSubtle : Ui.Color
    , tint : Ui.Color
    , tintSubtle : Ui.Color
    , tintStrong : Ui.Color
    , accent : Ui.Color
    , accentSubtle : Ui.Color
    , accentStrong : Ui.Color
    , solid : Ui.Color
    , solidSubtle : Ui.Color
    , solidStrong : Ui.Color
    , solidText : Ui.Color
    , text : Ui.Color
    , textSubtle : Ui.Color
    , shadow : Ui.Color
    }



-- COLOR PALETTE


{-| Base color — warm neutrals for backgrounds, text, and general content.
-}
base : ColorScale
base =
    { bg = Ui.rgb 255 248 240
    , bgSubtle = Ui.rgb 247 240 232
    , tint = Ui.rgba 176 168 159 0.1
    , tintSubtle = Ui.rgba 176 168 159 0.06
    , tintStrong = Ui.rgba 176 168 159 0.16
    , accent = Ui.rgb 237 232 225
    , accentSubtle = Ui.rgb 243 238 231
    , accentStrong = Ui.rgb 224 218 210
    , solid = Ui.rgb 122 117 112
    , solidSubtle = Ui.rgb 107 102 97
    , solidStrong = Ui.rgb 137 132 127
    , solidText = Ui.rgb 255 255 255
    , text = Ui.rgb 45 45 45
    , textSubtle = Ui.rgb 122 117 112
    , shadow = Ui.rgb 45 45 45
    }


{-| Primary color — warm coral for highlights, CTAs, accent elements.
-}
primary : ColorScale
primary =
    { bg = Ui.rgb 255 246 244
    , bgSubtle = Ui.rgb 253 237 233
    , tint = Ui.rgba 232 114 92 0.1
    , tintSubtle = Ui.rgba 232 114 92 0.06
    , tintStrong = Ui.rgba 232 114 92 0.16
    , accent = Ui.rgb 232 114 92
    , accentSubtle = Ui.rgb 240 150 133
    , accentStrong = Ui.rgb 212 98 78
    , solid = Ui.rgb 232 114 92
    , solidSubtle = Ui.rgb 212 98 78
    , solidStrong = Ui.rgb 245 130 110
    , solidText = Ui.rgb 255 255 255
    , text = Ui.rgb 196 80 60
    , textSubtle = Ui.rgb 218 105 85
    , shadow = Ui.rgb 232 114 92
    }


{-| Success color — sage green for positive feedback and confirmations.
-}
success : ColorScale
success =
    { bg = Ui.rgb 244 250 247
    , bgSubtle = Ui.rgb 232 244 238
    , tint = Ui.rgba 107 144 128 0.1
    , tintSubtle = Ui.rgba 107 144 128 0.06
    , tintStrong = Ui.rgba 107 144 128 0.16
    , accent = Ui.rgb 107 144 128
    , accentSubtle = Ui.rgb 140 170 157
    , accentStrong = Ui.rgb 82 122 106
    , solid = Ui.rgb 82 122 106
    , solidSubtle = Ui.rgb 65 105 89
    , solidStrong = Ui.rgb 99 139 123
    , solidText = Ui.rgb 255 255 255
    , text = Ui.rgb 45 90 74
    , textSubtle = Ui.rgb 82 122 106
    , shadow = Ui.rgb 45 90 74
    }


{-| Warning color — warm amber for cautionary content.
-}
warning : ColorScale
warning =
    { bg = Ui.rgb 255 250 240
    , bgSubtle = Ui.rgb 254 243 220
    , tint = Ui.rgba 217 160 6 0.1
    , tintSubtle = Ui.rgba 217 160 6 0.06
    , tintStrong = Ui.rgba 217 160 6 0.16
    , accent = Ui.rgb 217 160 6
    , accentSubtle = Ui.rgb 230 180 50
    , accentStrong = Ui.rgb 196 140 0
    , solid = Ui.rgb 196 140 0
    , solidSubtle = Ui.rgb 176 124 0
    , solidStrong = Ui.rgb 216 156 10
    , solidText = Ui.rgb 255 255 255
    , text = Ui.rgb 140 100 0
    , textSubtle = Ui.rgb 176 124 0
    , shadow = Ui.rgb 140 100 0
    }


{-| Danger color — muted red for errors and destructive actions.
-}
danger : ColorScale
danger =
    { bg = Ui.rgb 254 246 244
    , bgSubtle = Ui.rgb 252 234 230
    , tint = Ui.rgba 196 101 90 0.1
    , tintSubtle = Ui.rgba 196 101 90 0.06
    , tintStrong = Ui.rgba 196 101 90 0.16
    , accent = Ui.rgb 196 101 90
    , accentSubtle = Ui.rgb 216 135 125
    , accentStrong = Ui.rgb 176 85 74
    , solid = Ui.rgb 196 101 90
    , solidSubtle = Ui.rgb 176 85 74
    , solidStrong = Ui.rgb 216 117 106
    , solidText = Ui.rgb 255 255 255
    , text = Ui.rgb 160 60 48
    , textSubtle = Ui.rgb 196 101 90
    , shadow = Ui.rgb 160 60 48
    }



-- SIZE SCALES


type alias Scale =
    { xs : Int, sm : Int, md : Int, lg : Int, xl : Int, xxl : Int, xxxl : Int }


{-| Font size scale. `md` (15px) is the default body text size.
-}
font : Scale
font =
    { xs = 10
    , sm = 12
    , md = 15
    , lg = 17
    , xl = 22
    , xxl = 28
    , xxxl = 32
    }


{-| Spacing scale for padding, gaps, and margins.
-}
spacing : Scale
spacing =
    { xs = 4
    , sm = 8
    , md = 12
    , lg = 16
    , xl = 24
    , xxl = 32
    , xxxl = 48
    }


{-| Border radius scale. Roughly 50% of the corresponding sizing.
-}
radius : Scale
radius =
    { xs = 4
    , sm = 6
    , md = 10
    , lg = 14
    , xl = 20
    , xxl = 28
    , xxxl = 999
    }


{-| Sizing scale for fixed dimensions (buttons, avatars, icons, etc.).
-}
sizing : Scale
sizing =
    { xs = 16
    , sm = 24
    , md = 32
    , lg = 40
    , xl = 48
    , xxl = 56
    , xxxl = 72
    }



-- TYPOGRAPHY


{-| Font family: Inter with system fallbacks.
-}
fontFamily : Ui.Attribute msg
fontFamily =
    Ui.Font.family
        [ Ui.Font.typeface "Inter"
        , Ui.Font.typeface "-apple-system"
        , Ui.Font.typeface "BlinkMacSystemFont"
        , Ui.Font.typeface "Segoe UI"
        , Ui.Font.typeface "system-ui"
        , Ui.Font.sansSerif
        ]


{-| Font weight tokens.
-}
fontWeight : { regular : Int, medium : Int, semibold : Int, bold : Int }
fontWeight =
    { regular = 400
    , medium = 500
    , semibold = 600
    , bold = 700
    }


{-| Letter spacing tokens.
-}
letterSpacing : { tight : Float, normal : Float, wide : Float }
letterSpacing =
    { tight = -0.02
    , normal = 0
    , wide = 0.06
    }



-- BORDERS


{-| Default border width (1px).
-}
border : Int
border =
    1



-- SHADOWS


{-| Standard card shadow.
-}
shadow : Ui.Attribute msg
shadow =
    Ui.Shadow.shadows
        [ { x = 0, y = 2, size = 0, blur = 12, color = Ui.rgba 45 45 45 0.06 }
        , { x = 0, y = 1, size = 0, blur = 3, color = Ui.rgba 45 45 45 0.04 }
        ]


{-| Large shadow for prominent cards.
-}
shadowXl : Ui.Attribute msg
shadowXl =
    Ui.Shadow.shadows
        [ { x = 0, y = 8, size = 0, blur = 32, color = Ui.rgba 45 45 45 0.18 }
        , { x = 0, y = 2, size = 0, blur = 8, color = Ui.rgba 45 45 45 0.18 }
        ]


{-| Colored shadow for accent/primary elements (e.g. FAB).
-}
shadowAccent : Ui.Attribute msg
shadowAccent =
    Ui.Shadow.shadows
        [ { x = 0, y = 4, size = 0, blur = 20, color = Ui.rgba 232 114 92 0.35 }
        , { x = 0, y = 2, size = 0, blur = 8, color = Ui.rgba 232 114 92 0.2 }
        ]


{-| Subtle shadow for interactive knobs (e.g. toggle switch).
-}
shadowKnob : Ui.Attribute msg
shadowKnob =
    Ui.Shadow.shadows
        [ { x = 0, y = 1, size = 0, blur = 3, color = Ui.rgba 0 0 0 0.15 }
        ]



-- LAYOUT


{-| Maximum width for the main content area (mobile-focused).
-}
contentMaxWidth : Int
contentMaxWidth =
    430
