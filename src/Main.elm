module Main exposing (main)

import Http


type alias Flags =
    { serverPort : Int
    , cwd : String
    }


main : Program Flags () ()
main =
    Platform.worker
        { init = init
        , update = \_ _ -> ( (), Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


init : Flags -> ( (), Cmd () )
init flags =
    ( (), send flags.serverPort <| "\nWelcome to Elmie!\n\nStarted from " ++ flags.cwd ++ "\n\n" )


send : Int -> String -> Cmd ()
send serverPort message =
    Http.post
        { url = "http://localhost:" ++ String.fromInt serverPort
        , body = Http.stringBody "text/plain" message
        , expect = Http.expectWhatever (always ())
        }
