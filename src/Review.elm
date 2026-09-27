module Review exposing
    ( Entry
    , Queue
    , dueLater
    , encodeEntry
    , entryDecoder
    , entryKey
    , intervalLabel
    , newPerDayDefault
    , queue
    , schedule
    , scheduler
    , startOfDay
    , suggestRating
    )

{-| Spaced review of studied passages with FSRS (see `Fsrs`).

Each passage of a work becomes a card when its first attempt is graded. A work's queue for today is its due cards
(most overdue first) followed by passages not yet studied, in text order, up to a daily limit of new passages.

-}

import Dict exposing (Dict)
import Fsrs
import Json.Decode as Decode
import Json.Encode as Encode
import Study


{-| A scheduled passage, keyed by its citation. `introducedAt` is when it was first graded, for the daily new limit.
-}
type alias Entry =
    { work : String
    , passage : String
    , card : Fsrs.Card
    , introducedAt : Int
    }


type alias Queue =
    { due : List String
    , new : List String
    }


newPerDayDefault : Int
newPerDayDefault =
    10


{-| ts-fsrs defaults: 90% target retention, learning steps 1m and 10m, relearning step 10m, fuzz off.
-}
scheduler : Maybe Fsrs.Scheduler
scheduler =
    Fsrs.scheduler Fsrs.defaultConfig |> Result.toMaybe


entryKey : String -> String -> String
entryKey work passage =
    "card:" ++ work ++ ":" ++ passage


{-| Days are UTC days, matching how FSRS counts elapsed days.
-}
startOfDay : Int -> Int
startOfDay now =
    now - modBy 86400000 now


{-| Today's queue for a work whose passages, in text order, are `passages` (citations).
-}
queue : Int -> Int -> String -> List String -> Dict String Entry -> Queue
queue now newPerDay work passages entries =
    let
        cards =
            entries |> Dict.values |> List.filter (\entry -> entry.work == work)

        studied =
            cards |> List.map .passage

        introducedToday =
            cards |> List.filter (\entry -> entry.introducedAt >= startOfDay now) |> List.length

        newSlots =
            max 0 (newPerDay - introducedToday)
    in
    { due =
        cards
            |> List.filter (\entry -> entry.card.due <= now)
            |> List.sortBy (\entry -> entry.card.due)
            |> List.map .passage
    , new =
        passages
            |> List.filter (\passage -> not (List.member passage studied))
            |> List.take newSlots
    }


{-| When the work's next card becomes due after now, if any.
-}
dueLater : Int -> String -> Dict String Entry -> Maybe Int
dueLater now work entries =
    entries
        |> Dict.values
        |> List.filter (\entry -> entry.work == work && entry.card.due > now)
        |> List.map (\entry -> entry.card.due)
        |> List.minimum


{-| Reviews a passage (a new card on its first review) and returns its updated entry.
-}
schedule : Int -> Fsrs.Rating -> String -> String -> Dict String Entry -> Maybe Entry
schedule now rating work passage entries =
    let
        existing =
            Dict.get (entryKey work passage) entries

        card =
            existing |> Maybe.map .card |> Maybe.withDefault (Fsrs.newCard now)
    in
    scheduler
        |> Maybe.andThen (\fsrs -> Fsrs.next fsrs now rating card |> Result.toMaybe)
        |> Maybe.map
            (\outcome ->
                { work = work
                , passage = passage
                , card = outcome.card
                , introducedAt = existing |> Maybe.map .introducedAt |> Maybe.withDefault now
                }
            )


{-| A suggested rating from the learner's own marks. Nothing marked counts as Again; any wrong answer beyond a quarter of
the marked items is Again; fewer wrong answers, or early reveals with none wrong, are Hard; all right unassisted is Good.
Easy is left to the learner.
-}
suggestRating : List Study.Item -> Fsrs.Rating
suggestRating items =
    let
        judged =
            List.filter (\item -> item.mark /= Nothing) items

        wrong =
            List.length (List.filter (\item -> item.mark == Just False) judged)

        revealed =
            List.length (List.filter .revealedEarly items)
    in
    if List.isEmpty judged then
        Fsrs.Again

    else if wrong * 4 > List.length judged then
        Fsrs.Again

    else if wrong > 0 || revealed > 0 then
        Fsrs.Hard

    else
        Fsrs.Good


{-| A short interval such as "1 min", "10 min", "4 h", "3 d", "2 mo", or "1 y".
-}
intervalLabel : Int -> Int -> String
intervalLabel now due =
    let
        minutes =
            max 1 (round (toFloat (due - now) / 60000))

        hours =
            toFloat minutes / 60

        days =
            hours / 24
    in
    if minutes < 60 then
        String.fromInt minutes ++ " min"

    else if hours < 24 then
        String.fromInt (round hours) ++ " h"

    else if days < 31 then
        String.fromInt (round days) ++ " d"

    else if days < 365 then
        String.fromInt (round (days / 30)) ++ " mo"

    else
        String.fromInt (round (days / 365)) ++ " y"



-- ENCODING


encodeEntry : Entry -> Encode.Value
encodeEntry entry =
    let
        card =
            entry.card
    in
    Encode.object
        [ ( "id", Encode.string (entryKey entry.work entry.passage) )
        , ( "type", Encode.string "card" )
        , ( "work", Encode.string entry.work )
        , ( "passage", Encode.string entry.passage )
        , ( "introducedAt", Encode.int entry.introducedAt )
        , ( "fsrs", Encode.string Fsrs.fsrsVersion )
        , ( "card"
          , Encode.object
                [ ( "due", Encode.int card.due )
                , ( "stability", Encode.float card.stability )
                , ( "difficulty", Encode.float card.difficulty )
                , ( "elapsedDays", Encode.int card.elapsedDays )
                , ( "scheduledDays", Encode.int card.scheduledDays )
                , ( "learningSteps", Encode.int card.learningSteps )
                , ( "reps", Encode.int card.reps )
                , ( "lapses", Encode.int card.lapses )
                , ( "state", Encode.string (stateName card.state) )
                , ( "lastReview", card.lastReview |> Maybe.map Encode.int |> Maybe.withDefault Encode.null )
                ]
          )
        ]


{-| Only records written by `encodeEntry` decode; attempts and other rows in the progress store are ignored.
-}
entryDecoder : Decode.Decoder Entry
entryDecoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\kind ->
                if kind /= "card" then
                    Decode.fail "not a card"

                else
                    Decode.map4 Entry
                        (Decode.field "work" Decode.string)
                        (Decode.field "passage" Decode.string)
                        (Decode.field "card" cardDecoder)
                        (Decode.field "introducedAt" Decode.int)
            )


cardDecoder : Decode.Decoder Fsrs.Card
cardDecoder =
    Decode.map8
        (\due stability difficulty elapsedDays scheduledDays learningSteps reps ( lapses, state, lastReview ) ->
            { due = due
            , stability = stability
            , difficulty = difficulty
            , elapsedDays = elapsedDays
            , scheduledDays = scheduledDays
            , learningSteps = learningSteps
            , reps = reps
            , lapses = lapses
            , state = state
            , lastReview = lastReview
            }
        )
        (Decode.field "due" Decode.int)
        (Decode.field "stability" Decode.float)
        (Decode.field "difficulty" Decode.float)
        (Decode.field "elapsedDays" Decode.int)
        (Decode.field "scheduledDays" Decode.int)
        (Decode.field "learningSteps" Decode.int)
        (Decode.field "reps" Decode.int)
        (Decode.map3 (\a b c -> ( a, b, c ))
            (Decode.field "lapses" Decode.int)
            (Decode.field "state" Decode.string |> Decode.andThen stateDecoder)
            (Decode.field "lastReview" (Decode.nullable Decode.int))
        )


stateName : Fsrs.State -> String
stateName state =
    case state of
        Fsrs.New ->
            "new"

        Fsrs.Learning ->
            "learning"

        Fsrs.Review ->
            "review"

        Fsrs.Relearning ->
            "relearning"


stateDecoder : String -> Decode.Decoder Fsrs.State
stateDecoder name =
    case name of
        "new" ->
            Decode.succeed Fsrs.New

        "learning" ->
            Decode.succeed Fsrs.Learning

        "review" ->
            Decode.succeed Fsrs.Review

        "relearning" ->
            Decode.succeed Fsrs.Relearning

        _ ->
            Decode.fail ("unknown card state " ++ name)
