module Today exposing
    ( Item(..)
    , Mode(..)
    , Plan
    , Work
    , modeFromString
    , modeToString
    , next
    , plan
    , upcoming
    )

{-| Today's study session across every work: words and passages in one queue, or either alone.

Order: due words (most overdue first), then due passages from every work (most overdue first), then new passages, so
what has been studied before comes before anything new. New passages come from the work studied most recently, then
the others in library order, up to one daily limit shared by all works. A word or passage rated Again or Hard comes due
again within minutes (FSRS learning steps), so it returns later in the same session, after the next item or two.

-}

import Dict exposing (Dict)
import Review
import Words


type Mode
    = Everything
    | WordsOnly
    | PassagesOnly


type Item
    = WordItem String
    | PassageItem String String


{-| A work's id and its passages in text order.
-}
type alias Work =
    { id : String
    , passages : List String
    }


type alias Plan =
    { words : List String
    , due : List ( String, String )
    , new : List ( String, String )
    }


modeToString : Mode -> String
modeToString mode =
    case mode of
        Everything ->
            "all"

        WordsOnly ->
            "words"

        PassagesOnly ->
            "passages"


modeFromString : String -> Mode
modeFromString name =
    case name of
        "words" ->
            WordsOnly

        "passages" ->
            PassagesOnly

        _ ->
            Everything


{-| Everything due or new now, in session order. `lastWork` is the work studied most recently. With a `scope`, only that
work: its passages, and the words missed or reviewed in it.
-}
plan : Int -> Int -> Maybe String -> Maybe String -> List Work -> Dict String Review.Entry -> Dict String Words.Card -> Plan
plan now newPerDay scope lastWork allWorks entries allWords =
    let
        works =
            List.filter (\work -> inScope scope work.id) allWorks

        wordCards =
            Dict.filter (\_ word -> wordInScope scope word) allWords

        cards =
            Dict.values entries

        studied =
            cards |> List.map (\entry -> ( entry.work, entry.passage ))

        -- The daily new limit counts every work, scoped or not.
        introducedToday =
            cards |> List.filter (\entry -> entry.introducedAt >= Review.startOfDay now) |> List.length

        ordered =
            case lastWork of
                Just id ->
                    List.filter (\work -> work.id == id) works ++ List.filter (\work -> work.id /= id) works

                Nothing ->
                    works

        known =
            List.map .id works
    in
    { words = Words.due now wordCards |> List.map .lemma
    , due =
        cards
            |> List.filter (\entry -> entry.card.due <= now && List.member entry.work known)
            |> List.sortBy (\entry -> entry.card.due)
            |> List.map (\entry -> ( entry.work, entry.passage ))
    , new =
        ordered
            |> List.concatMap (\work -> List.map (Tuple.pair work.id) work.passages)
            |> List.filter (\pair -> not (List.member pair studied))
            |> List.take (max 0 (newPerDay - introducedToday))
    }


inScope : Maybe String -> String -> Bool
inScope scope work =
    scope == Nothing || scope == Just work


wordInScope : Maybe String -> Words.Card -> Bool
wordInScope scope word =
    case scope of
        Just work ->
            Dict.member work word.works

        Nothing ->
            True


{-| The next item to study in this mode, if any is due or new.
-}
next : Mode -> Plan -> Maybe Item
next mode today =
    let
        words =
            List.map WordItem today.words

        passages =
            List.map (\( work, passage ) -> PassageItem work passage) (today.due ++ today.new)
    in
    List.head
        (case mode of
            Everything ->
                words ++ passages

            WordsOnly ->
                words

            PassagesOnly ->
                passages
        )


{-| The earliest item that comes due later today in this mode (a learning step), with its due time.
-}
upcoming : Int -> Mode -> Maybe String -> Dict String Review.Entry -> Dict String Words.Card -> Maybe ( Item, Int )
upcoming now mode scope entries wordCards =
    let
        endOfDay =
            Review.startOfDay now + 86400000

        soon due =
            due > now && due < endOfDay

        words =
            wordCards
                |> Dict.values
                |> List.filter (\word -> soon word.card.due && wordInScope scope word)
                |> List.map (\word -> ( WordItem word.lemma, word.card.due ))

        passages =
            entries
                |> Dict.values
                |> List.filter (\entry -> soon entry.card.due && inScope scope entry.work)
                |> List.map (\entry -> ( PassageItem entry.work entry.passage, entry.card.due ))
    in
    (case mode of
        Everything ->
            words ++ passages

        WordsOnly ->
            words

        PassagesOnly ->
            passages
    )
        |> List.sortBy Tuple.second
        |> List.head
