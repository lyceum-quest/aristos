module Route exposing (Route(..), fromUrl, query, toPath)

import Dict exposing (Dict)
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


{-| Routes live in the URL fragment (`/#/luke/5?word=7`), so the static server only ever serves `/` and every link or reload works without a server-side fallback.
-}
fromUrl : Url -> Maybe Route
fromUrl url =
    Parser.parse parser { url | path = Tuple.first (fragmentParts url), query = Nothing, fragment = Nothing }


{-| Page state (open popup, tab, tool) carried in the fragment's query string.
-}
query : Url -> Dict String String
query url =
    Tuple.second (fragmentParts url)
        |> String.split "&"
        |> List.filterMap
            (\pair ->
                case String.split "=" pair of
                    [ key, value ] ->
                        Maybe.map2 Tuple.pair (Url.percentDecode key) (Url.percentDecode value)

                    _ ->
                        Nothing
            )
        |> Dict.fromList


fragmentParts : Url -> ( String, String )
fragmentParts url =
    case String.split "?" (Maybe.withDefault "/" url.fragment) of
        path :: rest ->
            ( path, String.join "?" rest )

        [] ->
            ( "/", "" )


parser : Parser (Route -> a) a
parser =
    oneOf
        [ Parser.map Library top
        , Parser.map Settings (s "settings")
        , Parser.map (\work passage -> Reader work (Just passage)) (string </> s "read" </> int)
        , Parser.map (\work -> Reader work Nothing) (string </> s "read")
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
           )
