module ReviewCardsTest exposing (suite)

{-| Passage cards replayed from attempts (`Review.cards`), which sync relies on: any device holding the same attempts,
in any order, must reach the same cards.
-}

import Dict
import Expect
import Fsrs exposing (Rating(..))
import Json.Decode as Decode
import Review
import Study exposing (ItemKind(..))
import Test exposing (Test, describe, test)


day : Int
day =
    86400000


start : Int
start =
    1760000000000


item : Maybe Bool -> Study.Item
item mark =
    { key = "w:1", kind = WordItem, form = "λόγος", lemma = "λόγος", guess = "", reference = "word", revealedEarly = False, mark = mark }


attempt : String -> Int -> Maybe Rating -> Study.Attempt
attempt passage at rating =
    { id = "attempt:plato.crito:" ++ passage ++ ":" ++ String.fromInt at
    , work = "plato.crito"
    , passage = passage
    , sentenceId = "s1"
    , sentenceText = "text"
    , startedAt = at - 60000
    , finishedAt = at
    , items = [ item (Just True) ]
    , rating = rating
    }


{-| Grading as the app does it live: one `Review.schedule` per attempt, in order.
-}
gradedLive : List ( Study.Attempt, Rating ) -> Dict.Dict String Review.Entry
gradedLive =
    List.foldl
        (\( a, rating ) entries ->
            Review.schedule a.finishedAt rating a.work a.passage entries
                |> Maybe.map (\entry -> Dict.insert (Review.entryKey a.work a.passage) entry entries)
                |> Maybe.withDefault entries
        )
        Dict.empty


suite : Test
suite =
    describe "Review.cards"
        [ test "rated attempts replay to the cards live grading made" <|
            \_ ->
                let
                    graded =
                        [ ( attempt "1.1" start (Just Good), Good )
                        , ( attempt "1.1" (start + 3 * day) (Just Hard), Hard )
                        , ( attempt "1.2" (start + day) (Just Again), Again )
                        ]
                in
                Review.cards Dict.empty (List.map Tuple.first graded)
                    |> Expect.equal (gradedLive (List.sortBy (Tuple.first >> .finishedAt) graded))
        , test "the order attempts arrive in does not matter" <|
            \_ ->
                let
                    attempts =
                        [ attempt "1.1" (start + 3 * day) (Just Hard), attempt "1.2" (start + day) (Just Again), attempt "1.1" start (Just Good) ]
                in
                Review.cards Dict.empty attempts
                    |> Expect.equal (Review.cards Dict.empty (List.reverse attempts))
        , test "a passage with an unrated (older) attempt keeps its stored card, and later rated attempts apply on top" <|
            \_ ->
                let
                    stored =
                        gradedLive [ ( attempt "1.1" start Nothing, Easy ) ]

                    later =
                        attempt "1.1" (start + 5 * day) (Just Again)
                in
                Review.cards stored [ attempt "1.1" start Nothing, later ]
                    |> Expect.equal (gradedLive [ ( attempt "1.1" start Nothing, Easy ), ( later, Again ) ])
        , test "without a stored card, an unrated attempt replays with the suggested rating" <|
            \_ ->
                let
                    old =
                        attempt "1.1" start Nothing
                in
                Review.cards Dict.empty [ old ]
                    |> Expect.equal (gradedLive [ ( old, Review.suggestRating old.items ) ])
        , test "the rating survives encoding, and older attempts decode without one" <|
            \_ ->
                let
                    roundTrip a =
                        Decode.decodeValue Study.attemptDecoder (Study.encodeAttempt a) |> Result.map .rating
                in
                Expect.equal ( roundTrip (attempt "1.1" start (Just Hard)), roundTrip (attempt "1.1" start Nothing) )
                    ( Ok (Just Hard), Ok Nothing )
        ]
