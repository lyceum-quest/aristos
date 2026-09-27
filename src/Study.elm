module Study exposing
    ( Attempt
    , Draft
    , Item
    , ItemKind(..)
    , Stats
    , WordStat
    , attemptDecoder
    , draftDecoder
    , emptyDraft
    , encodeAttempt
    , encodeDraft
    , isWordToken
    , literalKey
    , missedLastTime
    , proseKey
    , stats
    , wordKey
    )

{-| Study attempts: drafts in progress, self-graded attempts, and statistics over them.

A passage has one item per word (keyed `w:<token id>`) plus the literal and prose translations. Items revealed before
the checkpoint are recorded as such and excluded from unassisted statistics.

-}

import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode
import Set exposing (Set)


{-| An unfinished attempt at one passage, saved as the learner works so a refresh restores it.
-}
type alias Draft =
    { glosses : Dict Int String
    , literal : String
    , prose : String
    , revealed : Set String
    , submitted : Bool
    , marks : Dict String Bool
    , startedAt : Int
    }


type ItemKind
    = WordItem
    | LiteralItem
    | ProseItem


{-| One graded item of a finished attempt. `mark` is the learner's own judgement.
-}
type alias Item =
    { key : String
    , kind : ItemKind
    , form : String
    , lemma : String
    , guess : String
    , reference : String
    , revealedEarly : Bool
    , mark : Maybe Bool
    }


type alias Attempt =
    { id : String
    , work : String
    , passage : Int
    , sentenceId : String
    , sentenceText : String
    , startedAt : Int
    , finishedAt : Int
    , items : List Item
    }


type alias WordStat =
    { lemma : String
    , wrong : Int
    , judged : Int
    }


type alias Stats =
    { attempts : Int
    , judged : Int
    , right : Int
    , unassistedJudged : Int
    , unassistedRight : Int
    , struggles : List WordStat
    }


emptyDraft : Draft
emptyDraft =
    { glosses = Dict.empty
    , literal = ""
    , prose = ""
    , revealed = Set.empty
    , submitted = False
    , marks = Dict.empty
    , startedAt = 0
    }


wordKey : Int -> String
wordKey tokenId =
    "w:" ++ String.fromInt tokenId


literalKey : String
literalKey =
    "literal"


proseKey : String
proseKey =
    "prose"


{-| Punctuation is attached to the preceding word, never a word to gloss.
-}
isWordToken : { a | form : String, upos : String } -> Bool
isWordToken token =
    not (List.member token.upos [ "u", "PUNCT" ])
        && not (String.isEmpty token.form)
        && not (String.all (\char -> String.contains (String.fromChar char) ".,;:!?·\u{0387}\u{037E}()[]«»“”‘’—–'\"") token.form)


{-| Keys the learner marked wrong in their most recent finished attempt at this passage.
-}
missedLastTime : String -> Int -> List Attempt -> Dict String String
missedLastTime work passage attempts =
    attempts
        |> List.filter (\attempt -> attempt.work == work && attempt.passage == passage)
        |> List.sortBy .finishedAt
        |> List.reverse
        |> List.head
        |> Maybe.map
            (\attempt ->
                attempt.items
                    |> List.filter (\item -> item.mark == Just False)
                    |> List.map (\item -> ( item.key, item.guess ))
                    |> Dict.fromList
            )
        |> Maybe.withDefault Dict.empty


stats : List Attempt -> Stats
stats attempts =
    let
        items =
            List.concatMap .items attempts

        judged =
            List.filter (\item -> item.mark /= Nothing) items

        unassisted =
            List.filter (\item -> not item.revealedEarly) judged

        wordTotals =
            judged
                |> List.filter (\item -> item.kind == WordItem)
                |> List.foldl
                    (\item totals ->
                        Dict.update item.lemma
                            (\current ->
                                let
                                    ( wrong, count ) =
                                        Maybe.withDefault ( 0, 0 ) current
                                in
                                Just
                                    ( if item.mark == Just False then
                                        wrong + 1

                                      else
                                        wrong
                                    , count + 1
                                    )
                            )
                            totals
                    )
                    Dict.empty
    in
    { attempts = List.length attempts
    , judged = List.length judged
    , right = List.length (List.filter (\item -> item.mark == Just True) judged)
    , unassistedJudged = List.length unassisted
    , unassistedRight = List.length (List.filter (\item -> item.mark == Just True) unassisted)
    , struggles =
        wordTotals
            |> Dict.toList
            |> List.map (\( lemma, ( wrong, count ) ) -> { lemma = lemma, wrong = wrong, judged = count })
            |> List.filter (\stat -> stat.wrong > 0)
            |> List.sortBy (\stat -> ( negate stat.wrong, stat.lemma ))
            |> List.take 12
    }



-- ENCODING


encodeDraft : Draft -> Encode.Value
encodeDraft draft =
    Encode.object
        [ ( "glosses", Encode.list (\( id, gloss ) -> Encode.list identity [ Encode.int id, Encode.string gloss ]) (Dict.toList draft.glosses) )
        , ( "literal", Encode.string draft.literal )
        , ( "prose", Encode.string draft.prose )
        , ( "revealed", Encode.list Encode.string (Set.toList draft.revealed) )
        , ( "submitted", Encode.bool draft.submitted )
        , ( "marks", Encode.dict identity Encode.bool draft.marks )
        , ( "startedAt", Encode.int draft.startedAt )
        ]


draftDecoder : Decode.Decoder Draft
draftDecoder =
    Decode.map7 Draft
        (Decode.field "glosses" (Decode.list (Decode.map2 Tuple.pair (Decode.index 0 Decode.int) (Decode.index 1 Decode.string)) |> Decode.map Dict.fromList))
        (Decode.field "literal" Decode.string)
        (Decode.field "prose" Decode.string)
        (Decode.field "revealed" (Decode.list Decode.string |> Decode.map Set.fromList))
        (Decode.field "submitted" Decode.bool)
        (Decode.field "marks" (Decode.dict Decode.bool))
        (Decode.field "startedAt" Decode.int)


encodeAttempt : Attempt -> Encode.Value
encodeAttempt attempt =
    Encode.object
        [ ( "id", Encode.string attempt.id )
        , ( "type", Encode.string "attempt" )
        , ( "work", Encode.string attempt.work )
        , ( "passage", Encode.int attempt.passage )
        , ( "sentenceId", Encode.string attempt.sentenceId )
        , ( "sentenceText", Encode.string attempt.sentenceText )
        , ( "startedAt", Encode.int attempt.startedAt )
        , ( "finishedAt", Encode.int attempt.finishedAt )
        , ( "items", Encode.list encodeItem attempt.items )
        ]


encodeItem : Item -> Encode.Value
encodeItem item =
    Encode.object
        [ ( "key", Encode.string item.key )
        , ( "kind"
          , Encode.string
                (case item.kind of
                    WordItem ->
                        "word"

                    LiteralItem ->
                        "literal"

                    ProseItem ->
                        "prose"
                )
          )
        , ( "form", Encode.string item.form )
        , ( "lemma", Encode.string item.lemma )
        , ( "guess", Encode.string item.guess )
        , ( "reference", Encode.string item.reference )
        , ( "revealedEarly", Encode.bool item.revealedEarly )
        , ( "mark", item.mark |> Maybe.map Encode.bool |> Maybe.withDefault Encode.null )
        ]


{-| Only records written by `encodeAttempt` decode; other rows in the progress store are ignored.
-}
attemptDecoder : Decode.Decoder Attempt
attemptDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\kind ->
                if kind /= "attempt" then
                    Decode.fail "not an attempt"

                else
                    Decode.map8 Attempt
                        (Decode.field "id" Decode.string)
                        (Decode.field "work" Decode.string)
                        (Decode.field "passage" Decode.int)
                        (Decode.field "sentenceId" Decode.string)
                        (Decode.field "sentenceText" Decode.string)
                        (Decode.field "startedAt" Decode.int)
                        (Decode.field "finishedAt" Decode.int)
                        (Decode.field "items" (Decode.list itemDecoder |> Decode.map (List.filter (not << isPlaceholderItem))))
            )


{-| Attempts saved before OGA placeholder rows were hidden may hold a graded `[0]`; it is dropped so it is never shown
or counted.
-}
isPlaceholderItem : Item -> Bool
isPlaceholderItem item =
    item.kind
        == WordItem
        && String.startsWith "[" item.form
        && String.endsWith "]" item.form
        && String.all Char.isDigit (String.slice 1 -1 item.form)


itemDecoder : Decode.Decoder Item
itemDecoder =
    Decode.map8 Item
        (Decode.field "key" Decode.string)
        (Decode.field "kind" Decode.string
            |> Decode.map
                (\kind ->
                    case kind of
                        "literal" ->
                            LiteralItem

                        "prose" ->
                            ProseItem

                        _ ->
                            WordItem
                )
        )
        (Decode.field "form" Decode.string)
        (Decode.field "lemma" Decode.string)
        (Decode.field "guess" Decode.string)
        (Decode.field "reference" Decode.string)
        (Decode.field "revealedEarly" Decode.bool)
        (Decode.field "mark" (Decode.nullable Decode.bool))
