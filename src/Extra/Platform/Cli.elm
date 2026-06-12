module Extra.Platform.Cli exposing
    ( Flags
    , GlobalState
    , IO
    , consoleError
    , consoleRead
    , consoleWrite
    , createDirectoryIfMissing
    , doesDirectoryExist
    , doesFileExist
    , exitFailure
    , exitSuccess
    , getArgs
    , getCurrentDirectory
    , getElmHome
    , getInterpreter
    , getModificationTime
    , httpPrefix
    , makeAbsolute
    , readFile
    , removeFile
    , stdErrIsTty
    , stdOutIsTty
    , toGlobalState
    , writeFile
    )

import Bytes exposing (Bytes)
import Extra.System.IO as IO
import Extra.System.Path as Path exposing (FilePath)
import Extra.Type.Lens exposing (Lens)
import Extra.Type.List exposing (TList)
import Global
import Http
import Time



-- STATE


type alias Flags =
    { args : TList String
    , cwd : String
    , elmHome : String
    , promptSeparator : String
    , serverPort : Int
    , stderrIsTty : Bool
    , stdoutIsTty : Bool
    }


type alias GlobalState b c d e =
    Global.State LocalState b c d e


type alias LocalState =
    { args : TList String
    , cwd : String
    , elmHome : String
    , host : String
    , promptSeparator : String
    , stderrIsTty : Bool
    , stdoutIsTty : Bool
    }


toGlobalState : Flags -> b -> c -> d -> e -> GlobalState b c d e
toGlobalState flags b c d e =
    Global.State (initialLocalState flags) b c d e


initialLocalState : Flags -> LocalState
initialLocalState flags =
    { args = flags.args
    , cwd = flags.cwd
    , elmHome = flags.elmHome
    , host = "http://localhost:" ++ String.fromInt flags.serverPort
    , promptSeparator = flags.promptSeparator
    , stderrIsTty = flags.stderrIsTty
    , stdoutIsTty = flags.stdoutIsTty
    }


lensLocalState : Lens (GlobalState b c d e) LocalState
lensLocalState =
    { getter = \(Global.State x _ _ _ _) -> x
    , setter = \x (Global.State _ b c d e) -> Global.State x b c d e
    }



-- IO


type alias IO b c d e v =
    IO.IO (GlobalState b c d e) v



-- CONSOLE


consoleRead : String -> String -> IO b c d e String
consoleRead prompt initial =
    IO.bind (IO.getLens lensLocalState) <|
        \localState ->
            IO.bind (serverInput (prompt ++ localState.promptSeparator ++ initial)) <|
                \input ->
                    case String.uncons input of
                        Just ( 'o', rest ) ->
                            IO.return rest

                        Just ( 'c', _ ) ->
                            IO.error "CTRL-C"

                        Just ( 'd', _ ) ->
                            IO.error "CTRL-D"

                        _ ->
                            IO.bind
                                (consoleError ("Unexpected read response: " ++ input))
                                (\() -> exitFailure 1)


consoleWrite : String -> IO b c d e ()
consoleWrite str =
    serverOutput str


consoleError : String -> IO b c d e ()
consoleError str =
    serverError str



-- FILE


createDirectoryIfMissing : FilePath -> IO b c d e ()
createDirectoryIfMissing filePath =
    let
        path =
            Path.toString filePath
    in
    IO.bind (serverGetModificationTime path) <|
        \mTime ->
            if mTime == "0" then
                serverCreateDirectory path

            else
                IO.return ()


doesDirectoryExist : FilePath -> IO b c d e Bool
doesDirectoryExist filePath =
    IO.rmap
        (serverGetModificationTime (Path.toString filePath))
        (\mTime -> String.startsWith "-" mTime)


doesFileExist : FilePath -> IO b c d e Bool
doesFileExist filePath =
    IO.rmap
        (serverGetModificationTime (Path.toString filePath))
        (\mTime -> not (String.startsWith "-" mTime) && mTime /= "0")


getCurrentDirectory : IO b c d e FilePath
getCurrentDirectory =
    IO.rmap (IO.getLens lensLocalState) (\locatState -> Path.fromString locatState.cwd)


getElmHome : IO b c d e FilePath
getElmHome =
    IO.rmap (IO.getLens lensLocalState) (\locatState -> Path.fromString locatState.elmHome)


getModificationTime : FilePath -> IO b c d e Time.Posix
getModificationTime filePath =
    IO.rmap
        (serverGetModificationTime (Path.toString filePath))
        (\mTime ->
            mTime
                |> String.toInt
                |> Maybe.withDefault 0
                |> abs
                |> Time.millisToPosix
        )


makeAbsolute : FilePath -> IO b c d e FilePath
makeAbsolute filePath =
    IO.rmap getCurrentDirectory (\cwd -> Path.makeAbsolute cwd filePath)


readFile : FilePath -> IO b c d e (Maybe Bytes)
readFile filePath =
    IO.fmap Just (serverReadFile (Path.toString filePath))
        |> IO.catch (\_ -> IO.return Nothing)


removeFile : FilePath -> IO b c d e ()
removeFile filePath =
    serverDeleteFile (Path.toString filePath)


writeFile : FilePath -> Bytes -> IO b c d e ()
writeFile filePath contents =
    serverWriteFile (Path.toString filePath) contents



-- HTTP


httpPrefix : IO b c d e (Maybe String)
httpPrefix =
    IO.return (Just "")



-- JAVASCRIPT


getInterpreter : Maybe FilePath -> IO b c d e (String -> IO b c d e Bool)
getInterpreter maybeFilePath =
    case maybeFilePath of
        Just _ ->
            IO.bind (consoleError "Interpreter with custom path is not supported yet\n") <|
                \_ ->
                    exitFailure 1

        Nothing ->
            IO.return interpret


interpret : String -> IO b c d e Bool
interpret code =
    IO.bind (serverEval code) <|
        \result ->
            case String.uncons result of
                Just ( 'o', rest ) ->
                    IO.rmap
                        (consoleWrite (rest ++ "\n"))
                        (\() -> True)

                Just ( 'e', rest ) ->
                    IO.rmap
                        (consoleError (rest ++ "\n"))
                        (\() -> False)

                _ ->
                    IO.bind
                        (consoleError ("Unexpected interpreter response: " ++ result))
                        (\() -> exitFailure 1)



-- PROCESS


getArgs : IO b c d e (TList String)
getArgs =
    IO.rmap (IO.getLens lensLocalState) .args


stdOutIsTty : IO b c d e Bool
stdOutIsTty =
    IO.rmap (IO.getLens lensLocalState) .stdoutIsTty


stdErrIsTty : IO b c d e Bool
stdErrIsTty =
    IO.rmap (IO.getLens lensLocalState) .stderrIsTty


exitSuccess : IO b c d e a
exitSuccess =
    IO.bindSequence [ serverExit 0 ] (IO.error "exited")


exitFailure : Int -> IO b c d e a
exitFailure code =
    IO.bindSequence [ serverExit code ] (IO.error "exited")



-- SERVER API


serverInput : String -> IO b c d e String
serverInput message =
    serverPost "/i" string message string


serverOutput : String -> IO b c d e ()
serverOutput message =
    serverPost "/o" string message nothing


serverError : String -> IO b c d e ()
serverError message =
    serverPost "/e" string message nothing


serverGetModificationTime : String -> IO b c d e String
serverGetModificationTime path =
    serverGet ("/m" ++ path) string


serverReadFile : String -> IO b c d e Bytes
serverReadFile path =
    serverGet ("/r" ++ path) bytes


serverWriteFile : String -> Bytes -> IO b c d e ()
serverWriteFile path content =
    serverPost ("/w" ++ path) bytes content nothing


serverDeleteFile : String -> IO b c d e ()
serverDeleteFile path =
    serverGet ("/d" ++ path) nothing


serverCreateDirectory : String -> IO b c d e ()
serverCreateDirectory path =
    serverGet ("/c" ++ path) nothing


serverEval : String -> IO b c d e String
serverEval code =
    serverPost "/j" string code string


serverExit : Int -> IO b c d e ()
serverExit code =
    serverGet ("/x" ++ String.fromInt code) nothing



-- LOW LEVEL


type alias ApiType b c d e input output =
    { toBody : input -> Http.Body
    , expect : Http.Expect (IO b c d e output)
    }


bytes : ApiType b c d e Bytes Bytes
bytes =
    { toBody = Http.bytesBody "application/octet-stream"
    , expect = Http.expectBytesResponse resultToEio responseToResult
    }


string : ApiType b c d e String String
string =
    { toBody = Http.stringBody "text/plain"
    , expect = Http.expectStringResponse resultToEio responseToResult
    }


nothing : ApiType b c d e Never ()
nothing =
    { toBody = never
    , expect = Http.expectBytesResponse ignoreResultValue responseToResult
    }


serverGet : String -> ApiType b c d e ignoreInput output -> IO b c d e output
serverGet url outputType =
    IO.bind (IO.getLens lensLocalState) <|
        \{ host } ->
            Http.get
                { url = host ++ url
                , expect = outputType.expect
                }
                |> IO.liftCmdIO


serverPost : String -> ApiType b c d e input ignoreOutput -> input -> ApiType b c d e ignoreInput output -> IO b c d e output
serverPost url inputType inputData outputType =
    IO.bind (IO.getLens lensLocalState) <|
        \{ host } ->
            Http.post
                { url = host ++ url
                , body = inputType.toBody inputData
                , expect = outputType.expect
                }
                |> IO.liftCmdIO


responseToResult : Http.Response body -> Result String body
responseToResult response =
    case response of
        Http.BadUrl_ url ->
            Err ("BadUrl " ++ url)

        Http.Timeout_ ->
            Err "Timeout"

        Http.NetworkError_ ->
            Err "NetworkError"

        Http.BadStatus_ metadata _ ->
            Err ("BadStatus " ++ String.fromInt metadata.statusCode)

        Http.GoodStatus_ _ body ->
            Ok body


resultToEio : Result String a -> IO b c d e a
resultToEio result =
    case result of
        Ok value ->
            IO.return value

        Err err ->
            IO.error err


ignoreResultValue : Result String a -> IO b c d e ()
ignoreResultValue result =
    resultToEio result
        |> IO.fmap (\_ -> ())
