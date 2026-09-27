module FsrsTest exposing (suite)

{-| Checks the Elm FSRS port against reference outputs from ts-fsrs 5.4.2
(exact equality) and fsrs-rs 6.6.2 (within f32 tolerance). See
tests/fixtures/fsrs/README.md.
-}

import Dict exposing (Dict)
import Expect exposing (Expectation)
import Fsrs exposing (Card, Rating(..), State(..), Step(..))
import Fsrs.Math
import FsrsFixtures
import Json.Decode as D exposing (Decoder)
import Test exposing (Test, describe, test)



-- FIXTURE TYPES


type alias TsFixture =
    { defaultW : List Float
    , configs : Dict String TsConfig
    , cases : List TsCase
    }


type alias TsConfig =
    { config : Fsrs.Config
    , clippedW : List Float
    , intervalModifier : Float
    }


type alias TsCase =
    { name : String
    , config : String
    , start : Int
    , reviews : List TsReview
    , probes : List ( Int, Float )
    }


type alias TsReview =
    { time : Int
    , rating : Rating
    , retrievability : Float
    , outcomes : Outcomes Card
    , log : Fsrs.ReviewLog
    }


type alias Outcomes a =
    { again : a, hard : a, good : a, easy : a }


type alias RsCase =
    { name : String
    , reviews : List RsReview
    }


type alias RsReview =
    { elapsedDays : Int
    , retrievability : Maybe Float
    , outcomes : Outcomes RsState
    }


type alias RsState =
    { stability : Float, difficulty : Float, interval : Float }



-- DECODERS


tsFixtureDecoder : Decoder TsFixture
tsFixtureDecoder =
    D.map3 TsFixture
        (D.field "default_w" (D.list D.float))
        (D.field "configs" (D.dict configDecoder))
        (D.field "cases" (D.list tsCaseDecoder))


configDecoder : Decoder TsConfig
configDecoder =
    D.map3 TsConfig
        (D.map7 Fsrs.Config
            (D.field "request_retention" D.float)
            (D.field "maximum_interval" D.int)
            (D.field "w" (D.list D.float))
            (D.field "enable_fuzz" D.bool)
            (D.field "enable_short_term" D.bool)
            (D.field "learning_steps" (D.list stepDecoder))
            (D.field "relearning_steps" (D.list stepDecoder))
        )
        (D.field "clipped_w" (D.list D.float))
        (D.field "interval_modifier" D.float)


stepDecoder : Decoder Step
stepDecoder =
    D.string
        |> D.andThen
            (\s ->
                let
                    count =
                        String.toInt (String.dropRight 1 s)
                in
                case ( String.right 1 s, count ) of
                    ( "m", Just n ) ->
                        D.succeed (Minutes n)

                    ( "h", Just n ) ->
                        D.succeed (Hours n)

                    ( "d", Just n ) ->
                        D.succeed (Days n)

                    _ ->
                        D.fail ("bad step " ++ s)
            )


tsCaseDecoder : Decoder TsCase
tsCaseDecoder =
    D.map5 TsCase
        (D.field "name" D.string)
        (D.field "config" D.string)
        (D.field "start" D.int)
        (D.field "reviews" (D.list tsReviewDecoder))
        (D.field "probes" (D.list (D.map2 Tuple.pair (D.field "time" D.int) (D.field "retrievability" D.float))))


tsReviewDecoder : Decoder TsReview
tsReviewDecoder =
    D.map5 TsReview
        (D.field "time" D.int)
        (D.field "rating" ratingDecoder)
        (D.field "retrievability" D.float)
        (D.field "outcomes" (outcomesDecoder cardDecoder))
        (D.field "log" logDecoder)


outcomesDecoder : Decoder a -> Decoder (Outcomes a)
outcomesDecoder item =
    D.map4 Outcomes
        (D.field "Again" item)
        (D.field "Hard" item)
        (D.field "Good" item)
        (D.field "Easy" item)


ratingDecoder : Decoder Rating
ratingDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "Again" ->
                        D.succeed Again

                    "Hard" ->
                        D.succeed Hard

                    "Good" ->
                        D.succeed Good

                    "Easy" ->
                        D.succeed Easy

                    _ ->
                        D.fail ("bad rating " ++ s)
            )


stateDecoder : Decoder State
stateDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "New" ->
                        D.succeed New

                    "Learning" ->
                        D.succeed Learning

                    "Review" ->
                        D.succeed Review

                    "Relearning" ->
                        D.succeed Relearning

                    _ ->
                        D.fail ("bad state " ++ s)
            )


{-| `[due, stability, difficulty, elapsed_days, scheduled_days, learning_steps, reps, lapses, state, last_review]`
-}
cardDecoder : Decoder Card
cardDecoder =
    D.map8 (\due s d elapsed scheduled steps reps lapses -> Card due s d elapsed scheduled steps reps lapses)
        (D.index 0 D.int)
        (D.index 1 D.float)
        (D.index 2 D.float)
        (D.index 3 D.int)
        (D.index 4 D.int)
        (D.index 5 D.int)
        (D.index 6 D.int)
        (D.index 7 D.int)
        |> D.andThen
            (\partial ->
                D.map2 partial
                    (D.index 8 stateDecoder)
                    (D.index 9 (D.nullable D.int))
            )


{-| `[rating, state, due, stability, difficulty, elapsed_days, last_elapsed_days, scheduled_days, learning_steps, review]`
-}
logDecoder : Decoder Fsrs.ReviewLog
logDecoder =
    D.map8 (\rating state due s d elapsed lastElapsed scheduled -> Fsrs.ReviewLog rating state due s d elapsed lastElapsed scheduled)
        (D.index 0 ratingDecoder)
        (D.index 1 stateDecoder)
        (D.index 2 D.int)
        (D.index 3 D.float)
        (D.index 4 D.float)
        (D.index 5 D.int)
        (D.index 6 D.int)
        (D.index 7 D.int)
        |> D.andThen
            (\partial ->
                D.map2 partial
                    (D.index 8 D.int)
                    (D.index 9 D.int)
            )


rsCasesDecoder : Decoder (List RsCase)
rsCasesDecoder =
    D.field "cases"
        (D.list
            (D.map2 RsCase
                (D.field "name" D.string)
                (D.field "reviews"
                    (D.list
                        (D.map3 RsReview
                            (D.field "elapsed_days" D.int)
                            (D.field "retrievability" (D.nullable D.float))
                            (D.field "outcomes" (rsOutcomesDecoder rsStateDecoder))
                        )
                    )
                )
            )
        )


rsOutcomesDecoder : Decoder a -> Decoder (Outcomes a)
rsOutcomesDecoder item =
    D.map4 Outcomes (D.index 0 item) (D.index 1 item) (D.index 2 item) (D.index 3 item)


rsStateDecoder : Decoder RsState
rsStateDecoder =
    D.map3 RsState (D.index 0 D.float) (D.index 1 D.float) (D.index 2 D.float)



-- TESTS


suite : Test
suite =
    case ( D.decodeString tsFixtureDecoder FsrsFixtures.tsFsrs, D.decodeString rsCasesDecoder FsrsFixtures.fsrsRs ) of
        ( Ok ts, Ok rs ) ->
            describe "Fsrs"
                [ test "default weights match ts-fsrs default_w" <|
                    \_ -> Expect.equal ts.defaultW Fsrs.defaultWeights
                , describe "configurations (ts-fsrs clipped weights and interval modifier)"
                    (List.map configTest (Dict.toList ts.configs))
                , describe "ts-fsrs 5.4.2 review sequences (exact)"
                    (List.map (tsCaseTest ts.configs) ts.cases)
                , describe "fsrs-rs 6.6.2 memory states (f32 tolerance)"
                    (List.filterMap (rsCaseTest ts) rs)
                , expTest
                ]

        ( Err err, _ ) ->
            test "decode ts-fsrs fixture" <| \_ -> Expect.fail (D.errorToString err)

        ( _, Err err ) ->
            test "decode fsrs-rs fixture" <| \_ -> Expect.fail (D.errorToString err)


configTest : ( String, TsConfig ) -> Test
configTest ( name, cfg ) =
    test name <|
        \_ ->
            case Fsrs.scheduler cfg.config of
                Ok sched ->
                    Expect.all
                        [ \_ -> Expect.equal cfg.clippedW (Fsrs.weights sched)
                        , \_ -> exactFloat cfg.intervalModifier (Fsrs.intervalModifier sched)
                        ]
                        ()

                Err err ->
                    Expect.fail err


{-| `Fsrs.Math.exp` must equal V8's `Math.exp` bit for bit.
-}
expTest : Test
expTest =
    test "Fsrs.Math.exp equals V8 Math.exp" <|
        \_ ->
            case D.decodeString (D.field "cases" (D.list (D.map2 Tuple.pair (D.index 0 D.float) (D.index 1 D.float)))) FsrsFixtures.mathExp of
                Err err ->
                    Expect.fail (D.errorToString err)

                Ok cases ->
                    case List.filter (\( x, expected ) -> Fsrs.Math.exp x /= expected) cases of
                        [] ->
                            Expect.pass

                        wrong ->
                            Expect.fail ("exp differs for " ++ String.join ", " (List.map (Tuple.first >> String.fromFloat) wrong))


{-| Exact float equality (elm-test's `Expect.equal` rejects floats).
-}
exactFloat : Float -> Float -> Expectation
exactFloat expected actual =
    if actual == expected then
        Expect.pass

    else
        Expect.fail (String.fromFloat actual ++ " /= expected " ++ String.fromFloat expected)


withScheduler : Dict String TsConfig -> String -> (Fsrs.Scheduler -> Expectation) -> Expectation
withScheduler configs name f =
    case Dict.get name configs of
        Nothing ->
            Expect.fail ("unknown config " ++ name)

        Just cfg ->
            case Fsrs.scheduler cfg.config of
                Ok sched ->
                    f sched

                Err err ->
                    Expect.fail err


pick : Rating -> Outcomes a -> a
pick rating o =
    case rating of
        Again ->
            o.again

        Hard ->
            o.hard

        Good ->
            o.good

        Easy ->
            o.easy


{-| Replay a ts-fsrs case: at every review the retrievability, all four
candidate cards, and the chosen review log must equal ts-fsrs exactly.
-}
tsCaseTest : Dict String TsConfig -> TsCase -> Test
tsCaseTest configs c =
    test c.name <|
        \_ ->
            withScheduler configs c.config <|
                \sched ->
                    let
                        step ( index, review ) acc =
                            case acc of
                                Err _ ->
                                    acc

                                Ok card ->
                                    let
                                        at =
                                            "review " ++ String.fromInt index ++ ": "

                                        r =
                                            Fsrs.retrievability sched review.time card
                                    in
                                    if r /= review.retrievability then
                                        Err (at ++ "retrievability " ++ String.fromFloat r ++ " /= " ++ String.fromFloat review.retrievability)

                                    else
                                        case Fsrs.preview sched review.time card of
                                            Err err ->
                                                Err (at ++ err)

                                            Ok outcomes ->
                                                let
                                                    cards =
                                                        { again = outcomes.again.card, hard = outcomes.hard.card, good = outcomes.good.card, easy = outcomes.easy.card }

                                                    chosen =
                                                        pick review.rating outcomes
                                                in
                                                if cards /= review.outcomes then
                                                    Err (at ++ "cards\n  elm:     " ++ Debug.toString cards ++ "\n  ts-fsrs: " ++ Debug.toString review.outcomes)

                                                else if chosen.log /= review.log then
                                                    Err (at ++ "log\n  elm:     " ++ Debug.toString chosen.log ++ "\n  ts-fsrs: " ++ Debug.toString review.log)

                                                else
                                                    case Fsrs.next sched review.time review.rating card of
                                                        Ok outcome ->
                                                            if outcome == chosen then
                                                                Ok outcome.card

                                                            else
                                                                Err (at ++ "next differs from preview")

                                                        Err err ->
                                                            Err (at ++ err)

                        probe ( time, expected ) card =
                            let
                                r =
                                    Fsrs.retrievability sched time card
                            in
                            if r == expected then
                                Nothing

                            else
                                Just ("probe at " ++ String.fromInt time ++ ": " ++ String.fromFloat r ++ " /= " ++ String.fromFloat expected)
                    in
                    case List.foldl step (Ok (Fsrs.newCard c.start)) (List.indexedMap Tuple.pair c.reviews) of
                        Err message ->
                            Expect.fail message

                        Ok card ->
                            case List.filterMap (\p -> probe p card) c.probes of
                                [] ->
                                    Expect.pass

                                problems ->
                                    Expect.fail (String.join "\n" problems)



-- FSRS-RS


{-| fsrs-rs computes in f32 without ts-fsrs's 8-decimal rounding. Over the
fixture sequences the largest differences from ts-fsrs are about 5.1e-6
(relative stability and interval), 5.5e-6 (absolute difficulty), and 1.7e-7
(absolute retrievability); these tolerances leave a margin of about 4x.
-}
stabilityTolerance : Float
stabilityTolerance =
    2.0e-5


difficultyTolerance : Float
difficultyTolerance =
    2.0e-5


retrievabilityTolerance : Float
retrievabilityTolerance =
    1.0e-6


{-| Configurations where fsrs-rs is known to diverge from ts-fsrs (documented
in tests/fixtures/fsrs/README.md): its parameter clipping differs for
out-of-range weights and more than one relearning step.
-}
rsDivergentConfigs : List String
rsDivergentConfigs =
    [ "clipped-w" ]


rsCaseTest : TsFixture -> RsCase -> Maybe Test
rsCaseTest ts rsCase =
    case List.filter (\c -> c.name == rsCase.name) ts.cases of
        [ tsCase ] ->
            if List.member tsCase.config rsDivergentConfigs then
                Nothing

            else
                Just (rsCompare ts.configs tsCase rsCase)

        _ ->
            Just (test rsCase.name <| \_ -> Expect.fail "no matching ts-fsrs case")


rsCompare : Dict String TsConfig -> TsCase -> RsCase -> Test
rsCompare configs tsCase rsCase =
    test rsCase.name <|
        \_ ->
            withScheduler configs tsCase.config <|
                \sched ->
                    let
                        relClose tolerance a b =
                            abs (a - b) <= tolerance * abs b

                        absClose tolerance a b =
                            abs (a - b) <= tolerance

                        checkOutcome at label elm rs =
                            if not (relClose stabilityTolerance elm.stability rs.stability) then
                                Just (at ++ label ++ " stability " ++ String.fromFloat elm.stability ++ " vs " ++ String.fromFloat rs.stability)

                            else if not (absClose difficultyTolerance elm.difficulty rs.difficulty) then
                                Just (at ++ label ++ " difficulty " ++ String.fromFloat elm.difficulty ++ " vs " ++ String.fromFloat rs.difficulty)

                            else if not (relClose stabilityTolerance (elm.stability * Fsrs.intervalModifier sched) rs.interval) then
                                Just (at ++ label ++ " interval " ++ String.fromFloat (elm.stability * Fsrs.intervalModifier sched) ++ " vs " ++ String.fromFloat rs.interval)

                            else
                                Nothing

                        step ( index, ( review, rsReview ) ) acc =
                            case acc of
                                Err _ ->
                                    acc

                                Ok card ->
                                    let
                                        at =
                                            "review " ++ String.fromInt index ++ ": "

                                        rProblem =
                                            case rsReview.retrievability of
                                                Just rsR ->
                                                    let
                                                        r =
                                                            Fsrs.forgettingCurve sched (toFloat rsReview.elapsedDays) card.stability
                                                    in
                                                    if absClose retrievabilityTolerance r rsR then
                                                        Nothing

                                                    else
                                                        Just (at ++ "retrievability " ++ String.fromFloat r ++ " vs " ++ String.fromFloat rsR)

                                                Nothing ->
                                                    Nothing
                                    in
                                    case Fsrs.preview sched review.time card of
                                        Err err ->
                                            Err (at ++ err)

                                        Ok o ->
                                            let
                                                problems =
                                                    List.filterMap identity
                                                        [ rProblem
                                                        , if o.again.log.elapsedDays /= rsReview.elapsedDays then
                                                            Just (at ++ "elapsed days differ")

                                                          else
                                                            Nothing
                                                        , checkOutcome at "Again" o.again.card rsReview.outcomes.again
                                                        , checkOutcome at "Hard" o.hard.card rsReview.outcomes.hard
                                                        , checkOutcome at "Good" o.good.card rsReview.outcomes.good
                                                        , checkOutcome at "Easy" o.easy.card rsReview.outcomes.easy
                                                        ]
                                            in
                                            case problems of
                                                [] ->
                                                    Ok (pick review.rating o).card

                                                _ ->
                                                    Err (String.join "\n" problems)
                    in
                    if List.length tsCase.reviews /= List.length rsCase.reviews then
                        Expect.fail "review counts differ"

                    else
                        case List.foldl step (Ok (Fsrs.newCard tsCase.start)) (List.indexedMap Tuple.pair (List.map2 Tuple.pair tsCase.reviews rsCase.reviews)) of
                            Ok _ ->
                                Expect.pass

                            Err message ->
                                Expect.fail message
