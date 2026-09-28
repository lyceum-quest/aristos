module Passage exposing (Unit, fromUnits, isSplit, levelNames, levels, parts, unitsDecoder)

{-| Canonical passages: a work's text regrouped by its canonical citation (verses, sections, …) rather than by
syntactic sentence. The preload ships each work's passages (`corpora/<id>.units.json`, written by the Roc pipeline
from OGA's citation layer): a citation, a display label, the OGA token ids it spans, and its translations.

A passage becomes a `Conllu.Sentence` whose id is the citation (`1.2`) and whose verse is the label (`1:2`), so the
rest of the app treats passages exactly as it treated sentences. Its tokens are renumbered 1…n because a passage can
join tokens from two OGA sentences, whose own numbering restarts.

-}

import Conllu
import Dict
import Json.Decode as Decode


type alias Unit =
    { ref : String
    , label : String
    , tokens : List String
    , prose : String
    , literal : String
    }


unitsDecoder : Decode.Decoder (List Unit)
unitsDecoder =
    Decode.list
        (Decode.map5 Unit
            (Decode.field "ref" Decode.string)
            (Decode.field "label" Decode.string)
            (Decode.field "tokens" (Decode.list Decode.string))
            (Decode.field "prose" Decode.string)
            (Decode.field "literal" Decode.string)
        )


{-| Rebuilds a parsed corpus as its passages. Passages whose tokens are not all present are dropped.
-}
fromUnits : List Unit -> Conllu.Corpus -> Conllu.Corpus
fromUnits units corpus =
    let
        byTid =
            corpus.sentences
                |> List.concatMap .tokens
                |> List.map (\token -> ( token.tid, token ))
                |> Dict.fromList

        passage unit =
            let
                found =
                    List.filterMap (\tid -> Dict.get tid byTid) unit.tokens
            in
            if List.length found /= List.length unit.tokens || List.isEmpty found then
                Nothing

            else
                let
                    tokens =
                        List.indexedMap (\index token -> { token | id = index + 1 }) found
                in
                Just
                    { id = unit.ref
                    , chapter = parts unit.ref |> List.head |> Maybe.andThen String.toInt |> Maybe.withDefault 1
                    , verse = unit.label
                    , text = tokens |> List.map (\token -> token.form ++ (if token.spaceAfter then " " else "")) |> String.concat |> String.trimRight
                    , literalTranslation = unit.literal
                    , proseTranslation = unit.prose
                    , tokens = tokens
                    , placeholders = []
                    }
    in
    { corpus | sentences = List.filterMap passage units }


{-| Citation levels of a ref: `1.2` -> ["1", "2"]. A unit split at its sentences adds its part number as a level:
`43~2` (Stephanus page 43, §2) -> ["43", "2"].
-}
parts : String -> List String
parts ref =
    ref |> String.replace "~" "." |> String.split "."


{-| Whether the work's canonical units are split into numbered parts (every ref has a `~n`).
-}
isSplit : List Conllu.Sentence -> Bool
isSplit passages =
    not (List.isEmpty passages) && List.all (.id >> String.contains "~") passages


levels : List Conllu.Sentence -> Int
levels passages =
    passages |> List.head |> Maybe.map (.id >> parts >> List.length) |> Maybe.withDefault 1


{-| Names for the picker's selects, by citation depth; split works end with a `§` level.
-}
levelNames : Bool -> Bool -> Int -> List String
levelNames bible split depth =
    if split then
        (if depth == 2 then
            [ "Page" ]

         else
            levelNames bible False (depth - 1)
        )
            ++ [ "§" ]

    else
        unsplitNames bible depth


unsplitNames : Bool -> Int -> List String
unsplitNames bible depth =
    case ( bible, depth ) of
        ( True, 2 ) ->
            [ "Chapter", "Verse" ]

        ( _, 2 ) ->
            [ "Book", "Line" ]

        ( _, 3 ) ->
            [ "Book", "Chapter", "Section" ]

        _ ->
            List.repeat depth "Part"
