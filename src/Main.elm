module Main exposing (main)

import Builder.Generate
import Extra.Platform
import Extra.System.IO as IO exposing (IO)
import Terminal.Main


main : Program Flags Model Msg
main =
    Platform.worker
        { init = IO.init initialModel initialIO
        , subscriptions = \_ -> Sub.none
        , update = IO.update
        }


type alias Flags =
    Extra.Platform.Flags


type alias Model =
    Builder.Generate.GlobalState ()


initialModel : Flags -> Model
initialModel flags =
    Builder.Generate.toGlobalState flags ()


type alias Msg =
    IO Model ()


initialIO : Flags -> Msg
initialIO _ =
    IO.sequence
        [ Terminal.Main.runMain
        , Extra.Platform.exitSuccess
        ]
