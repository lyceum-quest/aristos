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


{-| Routes live in the URL fragment (`/#/luke/5`), so the static server only ever serves `/` and every link or reload works without a server-side fallback.
-}
fromUrl : Url -> Maybe Route
fromUrl url =
    Parser.parse parser { url | path = Maybe.withDefault "/" url.fragment, query = Nothing, fragment = Nothing }


parser : Parser (Route -> a) a
parser =
    oneOf
        [ Parser.map Library top
        , Parser.map Settings (s "settings")
        , Parser.map (\work passage -> Reader work (Just passage)) (string </> s "read" </> int)
        , Parser.map (\work -> Reader work Nothing) (string </> s "read")
        , Parser.map History (string </> int </> s "history")
        , Parser.map Comparison (string </> int </> s "compare")
        , Parser.map Study (string </> int)
        , Parser.map WorkLanding string
        ]


toPath : Route -> String
toPath route =
    "#"
        ++ (case route of
                Library ->
                    "/"

                Settings ->
                    "/settings"

                WorkLanding work ->
                    "/" ++ work

                Study work passage ->
                    "/" ++ work ++ "/" ++ String.fromInt passage

                Reader work passage ->
                    "/" ++ work ++ "/read" ++ (passage |> Maybe.map (\number -> "/" ++ String.fromInt number) |> Maybe.withDefault "")

                History work passage ->
                    "/" ++ work ++ "/" ++ String.fromInt passage ++ "/history"

                Comparison work passage ->
                    "/" ++ work ++ "/" ++ String.fromInt passage ++ "/compare"
           )
