module Update exposing (addCmd, wrap)

{-| Helper TEA update functions.
-}


{-| Wrap an update on a subcomponent.
-}
wrap : (subMsg -> msg) -> (subModel -> model) -> ( subModel, Cmd subMsg ) -> ( model, Cmd msg )
wrap tag f ( subModel, subCmd ) =
    ( f subModel, Cmd.map tag subCmd )


{-| Add another command.
-}
addCmd : Cmd msg -> ( model, Cmd msg ) -> ( model, Cmd msg )
addCmd newCmd ( model, cmd ) =
    ( model, Cmd.batch [ cmd, newCmd ] )
