module Conllu exposing (Corpus, CorpusSource, CorpusToken, Morphology, Sentence, parse)

import Char
import Dict exposing (Dict)


type alias Corpus =
    { source : CorpusSource
    , sentences : List Sentence
    }


type alias CorpusSource =
    { name : String
    , url : String
    , commit : String
    , license : String
    , edition : String
    }


type alias Sentence =
    { id : String
    , chapter : Int
    , verse : String
    , text : String
    , literalTranslation : String
    , proseTranslation : String
    , tokens : List CorpusToken
    , placeholders : List CorpusToken
    }


type alias CorpusToken =
    { id : Int
    , tid : String
    , form : String
    , lemma : String
    , upos : String
    , morphology : Morphology
    , head : Int
    , relation : String
    , gloss : String
    , spaceAfter : Bool
    }


type alias Morphology =
    { summary : String
    , case_ : String
    , number : String
    , gender : String
    }


type alias Row =
    { id : String
    , form : String
    , lemma : String
    , upos : String
    , feats : String
    , head : String
    , relation : String
    , misc : String
    }


type alias ParseState =
    { metadata : Dict String String
    , rows : List Row
    , sentences : List Sentence
    }


parse : CorpusSource -> String -> Result String Corpus
parse source raw =
    raw
        |> String.replace "\u{000D}\n" "\n"
        |> String.replace "\u{000D}" "\n"
        |> String.lines
        |> parseLines { metadata = Dict.empty, rows = [], sentences = [] }
        |> Result.andThen finishSentence
        |> Result.andThen
            (\state ->
                if List.isEmpty state.sentences then
                    Err "Corpus contains no sentences"

                else
                    Ok { source = source, sentences = List.reverse state.sentences }
            )


parseLines : ParseState -> List String -> Result String ParseState
parseLines state lines =
    -- Direct self-calls keep this tail-recursive; recursing inside Result.andThen overflows the stack on large corpora.
    case lines of
        [] ->
            Ok state

        line :: rest ->
            if String.isEmpty line then
                case finishSentence state of
                    Ok next ->
                        parseLines next rest

                    Err problem ->
                        Err problem

            else if String.startsWith "#" line then
                parseLines { state | metadata = insertMetadata line state.metadata } rest

            else
                case parseRow line of
                    Ok row ->
                        parseLines { state | rows = row :: state.rows } rest

                    Err problem ->
                        Err problem


insertMetadata : String -> Dict String String -> Dict String String
insertMetadata line metadata =
    case String.split "=" (String.dropLeft 1 line) of
        key :: values ->
            if List.isEmpty values then
                metadata

            else
                Dict.insert (String.trim key) (String.trim (String.join "=" values)) metadata

        [] ->
            metadata


parseRow : String -> Result String Row
parseRow line =
    case String.split "\t" line of
        [ id, form, lemma, upos, _, feats, head, relation, _, misc ] ->
            Ok
                { id = id
                , form = form
                , lemma = lemma
                , upos = upos
                , feats = feats
                , head = head
                , relation = relation
                , misc = misc
                }

        _ ->
            Err "Invalid CoNLL-U row: expected 10 tab-separated columns"


finishSentence : ParseState -> Result String ParseState
finishSentence state =
    let
        rows =
            state.rows
                |> List.reverse
                |> List.filter (\row -> String.all Char.isDigit row.id && not (String.isEmpty row.id))
    in
    if List.isEmpty rows then
        Ok { state | rows = [] }

    else
        Result.map2 Tuple.pair
            (rows |> List.filter (not << isPlaceholder) |> tokensFromRows)
            (rows |> List.filter isPlaceholder |> tokensFromRows)
            |> Result.map
                (\( tokens, placeholders ) ->
                    let
                        sentenceId =
                            firstMetadata state.metadata [ "sent_id", "sentence_id" ]

                        citation =
                            firstMetadata state.metadata [ "citation", "cts_urn" ]

                        reference =
                            firstReference rows citation sentenceId

                        stableId =
                            if not (String.isEmpty (metadataValue "sent_id" state.metadata)) then
                                metadataValue "sent_id" state.metadata

                            else if not (String.isEmpty citation) && not (String.isEmpty sentenceId) then
                                citation ++ "-s" ++ sentenceId

                            else
                                sentenceId

                        normalizedId =
                            if String.isEmpty stableId then
                                "sentence-" ++ String.fromInt (List.length state.sentences + 1)

                            else
                                stableId

                        reconstructed =
                            tokens
                                |> List.map (\token -> token.form ++ (if token.spaceAfter then " " else ""))
                                |> String.concat
                                |> String.trimRight
                    in
                    { metadata = Dict.empty
                    , rows = []
                    , sentences =
                        { id = normalizedId
                        , chapter =
                            -- A sentence number is not a citation; corpora without references form one division.
                            if reference == sentenceId then
                                1

                            else
                                chapterFromReference reference
                        , verse = if String.isEmpty reference then sentenceId else reference
                        , text = metadataOr "text" reconstructed state.metadata
                        , literalTranslation = firstMetadata state.metadata [ "text_en_literal", "literal_translation" ]
                        , proseTranslation = firstMetadata state.metadata [ "text_en", "prose_translation" ]
                        , tokens = tokens
                        , placeholders = placeholders
                        }
                            :: state.sentences
                    }
                )


{-| OGA adds rows for elided or implied words (forms like `[0]`, MISC starting `e_`). They are kept apart from the
visible tokens so no view shows, glosses, counts, or grades them, and spacing is computed as if they were absent.
-}
isPlaceholder : Row -> Bool
isPlaceholder row =
    String.startsWith "e_" row.misc


tokensFromRows : List Row -> Result String (List CorpusToken)
tokensFromRows rows =
    let
        nextParts =
            List.map Just (List.drop 1 rows) ++ [ Nothing ]
    in
    List.map2 tokenFromRow rows nextParts
        |> combineResults


tokenFromRow : Row -> Maybe Row -> Result String CorpusToken
tokenFromRow row next =
    case ( String.toInt row.id, parseHead row.id row.head ) of
        ( Just tokenId, Ok head ) ->
            let
                features =
                    parseFields row.feats

                misc =
                    parseFields row.misc

                nextIsPunctuation =
                    next |> Maybe.map (\nextRow -> nextRow.upos == "PUNCT") |> Maybe.withDefault False
            in
            Ok
                { id = tokenId
                , tid =
                    -- OGA keys each token by `t_N` in the first MISC field; canonical passages refer to it.
                    String.split "|" row.misc |> List.head |> Maybe.withDefault "" |> (\first -> if String.startsWith "t_" first then first else "")
                , form = normalizedField row.form
                , lemma = normalizedField row.lemma
                , upos = normalizedField row.upos
                , morphology =
                    { summary = normalizedField row.feats
                    , case_ = Dict.get "Case" features |> Maybe.withDefault ""
                    , number = Dict.get "Number" features |> Maybe.withDefault ""
                    , gender = Dict.get "Gender" features |> Maybe.withDefault ""
                    }
                , head = head
                , relation = normalizedField row.relation
                , gloss =
                    if row.upos == "PUNCT" then
                        ""

                    else
                        Dict.get "Gloss" misc
                            |> Maybe.withDefault (Dict.get "gloss" misc |> Maybe.withDefault "")
                , spaceAfter = Dict.get "SpaceAfter" misc /= Just "No" && not nextIsPunctuation
                }

        ( Nothing, _ ) ->
            Err ("Invalid token ID " ++ row.id)

        ( _, Err problem ) ->
            Err problem


parseHead : String -> String -> Result String Int
parseHead tokenId head =
    if head == "_" then
        Ok 0

    else
        String.toInt head
            |> Result.fromMaybe ("Token " ++ tokenId ++ " has an invalid dependency head")


combineResults : List (Result String value) -> Result String (List value)
combineResults results =
    List.foldr (Result.map2 (::)) (Ok []) results


parseFields : String -> Dict String String
parseFields serialized =
    if serialized == "" || serialized == "_" then
        Dict.empty

    else
        serialized
            |> String.split "|"
            |> List.foldl
                (\item fields ->
                    case String.split "=" item of
                        key :: values ->
                            Dict.insert key (String.join "=" values) fields

                        [] ->
                            fields
                )
                Dict.empty


firstReference : List Row -> String -> String -> String
firstReference rows citation sentenceId =
    let
        miscReference =
            rows
                |> List.head
                |> Maybe.map (.misc >> parseFields >> Dict.get "Ref" >> Maybe.withDefault "")
                |> Maybe.withDefault ""

        citationReference =
            citation |> String.split ":" |> List.reverse |> List.head |> Maybe.withDefault ""
    in
    if not (String.isEmpty miscReference) then
        miscReference

    else if not (String.isEmpty citationReference) then
        citationReference

    else
        sentenceId


chapterFromReference : String -> Int
chapterFromReference reference =
    let
        localReference =
            reference |> String.split ":" |> List.reverse |> List.head |> Maybe.withDefault reference

        digits =
            localReference
                |> String.toList
                |> dropUntil Char.isDigit
                |> takeWhile Char.isDigit
                |> String.fromList
    in
    String.toInt digits |> Maybe.withDefault 1


dropUntil : (value -> Bool) -> List value -> List value
dropUntil predicate values =
    case values of
        [] ->
            []

        first :: rest ->
            if predicate first then
                values

            else
                dropUntil predicate rest


takeWhile : (value -> Bool) -> List value -> List value
takeWhile predicate values =
    case values of
        [] ->
            []

        first :: rest ->
            if predicate first then
                first :: takeWhile predicate rest

            else
                []


firstMetadata : Dict String String -> List String -> String
firstMetadata metadata keys =
    keys
        |> List.filterMap (\key -> Dict.get key metadata)
        |> List.filter (not << String.isEmpty)
        |> List.head
        |> Maybe.withDefault ""


metadataValue : String -> Dict String String -> String
metadataValue key metadata =
    Dict.get key metadata |> Maybe.withDefault ""


metadataOr : String -> String -> Dict String String -> String
metadataOr key fallback metadata =
    let
        value =
            metadataValue key metadata
    in
    if String.isEmpty value then
        fallback

    else
        value


normalizedField : String -> String
normalizedField value =
    if value == "_" then
        ""

    else
        value
