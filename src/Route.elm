module Route exposing (Route(..), fromUrl, toPath)

import Url exposing (Url)
import Url.Parser as Parser exposing ((</>), Parser, int, oneOf, s, string, top)


{-| Passage numbers are 1-based sentence positions in the work's CoNLL-U file.
-}
type Route
    = Library
    | Settings
    | WorkLanding String
    | Study String Int
    | Reader String (Maybe Int)
    | History String Int
    | Comparison String Int


fromUrl : Url -> Maybe Route
fromUrl url =
    Parser.parse parser url


parser : Parser (Route -> a) a
parser =
    oneOf
        [ Parser.map Library top
        , Parser.map Settings (s "settings")
        , Parser.map (\work fragment -> Reader work (Maybe.andThen String.toInt fragment)) (string </> s "read" </> Parser.fragment identity)
        , Parser.map History (string </> int </> s "history")
        , Parser.map Comparison (string </> int </> s "compare")
        , Parser.map Study (string </> int)
        , Parser.map WorkLanding string
        ]


toPath : Route -> String
toPath route =
    case route of
        Library ->
            "/"

        Settings ->
            "/settings"

        WorkLanding work ->
            "/" ++ work

        Study work passage ->
            "/" ++ work ++ "/" ++ String.fromInt passage

        Reader work passage ->
            "/" ++ work ++ "/read" ++ (passage |> Maybe.map (\number -> "#" ++ String.fromInt number) |> Maybe.withDefault "")

        History work passage ->
            "/" ++ work ++ "/" ++ String.fromInt passage ++ "/history"

        Comparison work passage ->
            "/" ++ work ++ "/" ++ String.fromInt passage ++ "/compare"
