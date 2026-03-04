module Update exposing
    ( addCmd
    , mapModel
    , wrap
    )

{-| Helper TEA update functions.
-}


{-| Wrap an update on a subcomponent.
-}
wrap : (subMsg -> msg) -> (subModel -> model) -> ( subModel, Cmd subMsg ) -> ( model, Cmd msg )
wrap tag f ( subModel, subCmd ) =
    ( f subModel, Cmd.map tag subCmd )


{-| Map a function to the model.
-}
mapModel : (model1 -> model2) -> ( model1, Cmd msg ) -> ( model2, Cmd msg )
mapModel =
    Tuple.mapFirst


{-| Add another command.
-}
addCmd : Cmd msg -> ( model, Cmd msg ) -> ( model, Cmd msg )
addCmd newCmd ( model, cmd ) =
    ( model, Cmd.batch [ cmd, newCmd ] )
