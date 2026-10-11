module Words exposing
    ( Card
    , Occurrence
    , Review
    , cards
    , due
    , encodeReview
    , isMature
    , ratingName
    , reviewDecoder
    , reviewKey
    )

{-| Spaced review of words, one card per lemma (see `Review` for passages).

A word card is not stored: it is replayed through FSRS from the learner's history, in time order, so attempts made before
word cards existed count and cards can never disagree with the history.

Words and passages are tracked separately. Recall inside a passage is helped by its context (the encoding-specificity
principle), so a word answered right there is weak evidence that the learner knows it alone, while a word missed even
with that help is strong evidence that they do not. So a passage only ever counts against a word: a word marked wrong
or revealed before the checkpoint gets a card if it has none (its first miss introduces it) and an Again review.
Words answered right in passages never get cards; otherwise only word reviews move a word's schedule.

-}

import Dict exposing (Dict)
import Fsrs
import Json.Decode as Decode
import Json.Encode as Encode
import Review
import Study


{-| Where a word was met: the passage, the token's position in it (`Study.wordKey`), the form, its reference gloss, the
passage text, and the learner's answer there.
-}
type alias Occurrence =
    { work : String
    , passage : String
    , position : Int
    , form : String
    , gloss : String
    , text : String
    , guess : String
    }


{-| A word review: the learner recalled the lemma's meaning in one occurrence and rated it.
-}
type alias Review =
    { lemma : String
    , at : Int
    , rating : Fsrs.Rating
    , occurrence : Occurrence
    }


{-| A lemma's schedule and history. `context` is the occurrence to quiz on next: the latest one missed, else the latest
seen. `forms` are the inflected forms met, most recent first. `works` holds the latest occurrence in each work where the
word was missed or reviewed, for studying one work at a time.
-}
type alias Card =
    { lemma : String
    , card : Fsrs.Card
    , introducedAt : Int
    , lastAt : Int
    , seen : Int
    , misses : Int
    , forms : List String
    , context : Occurrence
    , missedContext : Bool
    , works : Dict String Occurrence
    }


type alias Event =
    { lemma : String
    , at : Int
    , rating : Fsrs.Rating
    , occurrence : Occurrence
    }


reviewKey : Review -> String
reviewKey review =
    "wordreview:" ++ review.lemma ++ ":" ++ String.fromInt review.at


{-| Due word cards, most overdue first.
-}
due : Int -> Dict String Card -> List Card
due now all =
    all
        |> Dict.values
        |> List.filter (\word -> word.card.due <= now)
        |> List.sortBy (\word -> word.card.due)


{-| Known for now: in review with at least three weeks' stability, as Anki calls a card mature.
-}
isMature : Card -> Bool
isMature word =
    word.card.state == Fsrs.Review && word.card.stability >= 21


{-| Every lemma's card, from all finished attempts and word reviews.
-}
cards : List Study.Attempt -> List Review -> Dict String Card
cards attempts reviews =
    (List.concatMap attemptEvents attempts ++ List.map reviewEvent reviews)
        |> List.sortBy .at
        |> List.foldl apply Dict.empty


reviewEvent : Review -> Event
reviewEvent review =
    { lemma = review.lemma, at = review.at, rating = review.rating, occurrence = review.occurrence }


{-| One Again per lemma the learner missed or revealed in the attempt; words answered right are not reviews.
-}
attemptEvents : Study.Attempt -> List Event
attemptEvents attempt =
    attempt.items
        |> List.filterMap
            (\item ->
                case ( item.kind, itemRating item, positionOf item.key ) of
                    ( Study.WordItem, Just rating, Just position ) ->
                        if usableLemma item.lemma then
                            Just
                                { lemma = item.lemma
                                , at = attempt.finishedAt
                                , rating = rating
                                , occurrence =
                                    { work = attempt.work
                                    , passage = attempt.passage
                                    , position = position
                                    , form = item.form
                                    , gloss = item.reference
                                    , text = attempt.sentenceText
                                    , guess = item.guess
                                    }
                                }

                        else
                            Nothing

                    _ ->
                        Nothing
            )
        |> List.foldl
            (\event worst ->
                case Dict.get event.lemma worst of
                    Just prior ->
                        if ratingRank event.rating < ratingRank prior.rating then
                            Dict.insert event.lemma event worst

                        else
                            worst

                    Nothing ->
                        Dict.insert event.lemma event worst
            )
            Dict.empty
        |> Dict.values


itemRating : Study.Item -> Maybe Fsrs.Rating
itemRating item =
    if item.mark == Just False || item.revealedEarly then
        Just Fsrs.Again

    else
        Nothing


positionOf : String -> Maybe Int
positionOf key =
    if String.startsWith "w:" key then
        String.toInt (String.dropLeft 2 key)

    else
        Nothing


usableLemma : String -> Bool
usableLemma lemma =
    not (String.isEmpty (String.trim lemma)) && lemma /= "_"


ratingRank : Fsrs.Rating -> Int
ratingRank rating =
    case rating of
        Fsrs.Again ->
            0

        Fsrs.Hard ->
            1

        Fsrs.Good ->
            2

        Fsrs.Easy ->
            3


apply : Event -> Dict String Card -> Dict String Card
apply event all =
    let
        existing =
            Dict.get event.lemma all

        prior =
            existing |> Maybe.map .card |> Maybe.withDefault (Fsrs.newCard event.at)

        scheduled =
            Review.scheduler
                |> Maybe.andThen (\fsrs -> Fsrs.next fsrs event.at event.rating prior |> Result.toMaybe)
                |> Maybe.map .card
                |> Maybe.withDefault prior

        missed =
            event.rating == Fsrs.Again

        updated =
            case existing of
                Just word ->
                    { word
                        | card = scheduled
                        , lastAt = event.at
                        , seen = word.seen + 1
                        , misses =
                            if missed then
                                word.misses + 1

                            else
                                word.misses
                        , forms = event.occurrence.form :: List.filter ((/=) event.occurrence.form) word.forms
                        , context =
                            if missed || not word.missedContext then
                                event.occurrence

                            else
                                word.context
                        , missedContext = missed || word.missedContext
                        , works = Dict.insert event.occurrence.work event.occurrence word.works
                    }

                Nothing ->
                    { lemma = event.lemma
                    , card = scheduled
                    , introducedAt = event.at
                    , lastAt = event.at
                    , seen = 1
                    , misses =
                        if missed then
                            1

                        else
                            0
                    , forms = [ event.occurrence.form ]
                    , context = event.occurrence
                    , missedContext = missed
                    , works = Dict.singleton event.occurrence.work event.occurrence
                    }
    in
    Dict.insert event.lemma updated all


ratingName : Fsrs.Rating -> String
ratingName rating =
    case rating of
        Fsrs.Again ->
            "again"

        Fsrs.Hard ->
            "hard"

        Fsrs.Good ->
            "good"

        Fsrs.Easy ->
            "easy"



-- ENCODING


encodeReview : Review -> Encode.Value
encodeReview review =
    Encode.object
        [ ( "id", Encode.string (reviewKey review) )
        , ( "type", Encode.string "wordreview" )
        , ( "lemma", Encode.string review.lemma )
        , ( "at", Encode.int review.at )
        , ( "rating", Encode.string (ratingName review.rating) )
        , ( "occurrence"
          , Encode.object
                [ ( "work", Encode.string review.occurrence.work )
                , ( "passage", Encode.string review.occurrence.passage )
                , ( "position", Encode.int review.occurrence.position )
                , ( "form", Encode.string review.occurrence.form )
                , ( "gloss", Encode.string review.occurrence.gloss )
                , ( "text", Encode.string review.occurrence.text )
                , ( "guess", Encode.string review.occurrence.guess )
                ]
          )
        ]


{-| Only records written by `encodeReview` decode; other rows in the progress store are ignored.
-}
reviewDecoder : Decode.Decoder Review
reviewDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\kind ->
                if kind /= "wordreview" then
                    Decode.fail "not a word review"

                else
                    Decode.map4 Review
                        (Decode.field "lemma" Decode.string)
                        (Decode.field "at" Decode.int)
                        (Decode.field "rating" Decode.string |> Decode.andThen ratingDecoder)
                        (Decode.field "occurrence" occurrenceDecoder)
            )


occurrenceDecoder : Decode.Decoder Occurrence
occurrenceDecoder =
    Decode.map7 Occurrence
        (Decode.field "work" Decode.string)
        (Decode.field "passage" Decode.string)
        (Decode.field "position" Decode.int)
        (Decode.field "form" Decode.string)
        (Decode.field "gloss" Decode.string)
        (Decode.field "text" Decode.string)
        (Decode.field "guess" Decode.string)


ratingDecoder : String -> Decode.Decoder Fsrs.Rating
ratingDecoder name =
    case name of
        "again" ->
            Decode.succeed Fsrs.Again

        "hard" ->
            Decode.succeed Fsrs.Hard

        "good" ->
            Decode.succeed Fsrs.Good

        "easy" ->
            Decode.succeed Fsrs.Easy

        _ ->
            Decode.fail ("unknown rating " ++ name)
