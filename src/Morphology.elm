module Morphology exposing (abbreviation)

{-| Short learner-facing morphology tags from OGA's AGDT part of speech and features: `aor act ind 3pl`,
`pf m/p ptc gen pl n`, `art gen pl n`, `nom sg m` (nouns carry no part-of-speech label), `prep`.
-}

import Dict exposing (Dict)


{-| Empty for punctuation and tokens without an analysis.
-}
abbreviation : String -> String -> String
abbreviation pos feats =
    let
        features =
            parse feats

        get key table =
            Dict.get key features |> Maybe.andThen (\code -> lookup code table) |> Maybe.withDefault ""

        person =
            get "Person" persons

        nominal =
            [ get "Case" cases
            , number (get "Number" numbers) person
            , if person == "1" || person == "2" then
                ""

              else
                get "Gender" genders
            ]

        personNumber =
            person ++ get "Number" numbers

        verbal =
            [ get "Tense" tenses, get "Voice" voices, get "Mood" moods ]

        parts =
            case pos of
                "v" ->
                    if Dict.get "Mood" features == Just "p" then
                        verbal ++ [ get "Case" cases, get "Number" numbers, get "Gender" genders ]

                    else
                        verbal ++ [ personNumber ]

                "n" ->
                    nominal

                "a" ->
                    "adj" :: nominal ++ [ get "Degree" degrees ]

                "l" ->
                    "art" :: nominal

                "p" ->
                    "pron" :: nominal

                "m" ->
                    "num" :: nominal

                "d" ->
                    [ "adv", get "Degree" degrees ]

                "r" ->
                    [ "prep" ]

                "c" ->
                    [ "conj" ]

                "g" ->
                    [ "ptcl" ]

                "i" ->
                    [ "intj" ]

                _ ->
                    []
    in
    parts |> List.filter (not << String.isEmpty) |> String.join " "


{-| Pronouns of the first and second person carry person with number (`1pl`) and no gender.
-}
number : String -> String -> String
number count person =
    if person == "1" || person == "2" then
        person ++ count

    else
        count


parse : String -> Dict String String
parse feats =
    feats
        |> String.split "|"
        |> List.filterMap
            (\pair ->
                case String.split "=" pair of
                    [ key, value ] ->
                        Just ( key, value )

                    _ ->
                        Nothing
            )
        |> Dict.fromList


lookup : String -> List ( String, String ) -> Maybe String
lookup code table =
    table |> List.filter (\( key, _ ) -> key == code) |> List.head |> Maybe.map Tuple.second


cases : List ( String, String )
cases =
    [ ( "n", "nom" ), ( "g", "gen" ), ( "d", "dat" ), ( "a", "acc" ), ( "v", "voc" ), ( "l", "loc" ) ]


numbers : List ( String, String )
numbers =
    [ ( "s", "sg" ), ( "p", "pl" ), ( "d", "du" ) ]


genders : List ( String, String )
genders =
    [ ( "m", "m" ), ( "f", "f" ), ( "n", "n" ), ( "c", "m/f" ) ]


persons : List ( String, String )
persons =
    [ ( "1", "1" ), ( "2", "2" ), ( "3", "3" ) ]


tenses : List ( String, String )
tenses =
    [ ( "p", "pres" ), ( "i", "impf" ), ( "f", "fut" ), ( "a", "aor" ), ( "r", "pf" ), ( "l", "plpf" ), ( "t", "fut pf" ) ]


voices : List ( String, String )
voices =
    [ ( "a", "act" ), ( "m", "mid" ), ( "p", "pass" ), ( "e", "m/p" ) ]


moods : List ( String, String )
moods =
    [ ( "i", "ind" ), ( "s", "subj" ), ( "o", "opt" ), ( "n", "inf" ), ( "m", "impv" ), ( "p", "ptc" ) ]


degrees : List ( String, String )
degrees =
    [ ( "c", "comp" ), ( "s", "superl" ) ]
