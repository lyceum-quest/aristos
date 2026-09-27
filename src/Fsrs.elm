module Fsrs exposing
    ( Rating(..), State(..), Step(..)
    , Config, defaultConfig, defaultWeights, fsrsVersion
    , Scheduler, scheduler, weights, intervalModifier
    , Card, newCard, ReviewLog, Outcome
    , next, preview
    , retrievability, forgettingCurve
    )

{-| FSRS (Free Spaced Repetition Scheduler) card scheduling, ported from
[ts-fsrs](https://github.com/open-spaced-repetition/ts-fsrs) **v5.4.2**
(tag `v5.4.2`, commit `bb71e35a2f5af5a5ac6cce9ef7c41ad24855721d`, npm
`ts-fsrs@5.4.2`), which implements FSRS-6. Only the scheduler is ported; the
parameter optimizer, `rollback`, `forget`, `reschedule`, and the FSRS-4/5
parameter migration (17 or 19 weights) are not.

The port follows ts-fsrs operation by operation, including its rounding: the
decay factor, interval modifier, retrievability, difficulty, and stability are
rounded to 8 decimal places with `Math.round(x * 1e8) / 1e8`, and intervals
with `Math.round`, as ts-fsrs does. Elm's `round`, `floor`, `^`, and
`logBase e` compile to `Math.round`, `Math.floor`, `Math.pow`, and `Math.log`,
so they match ts-fsrs exactly. Elm has no `Math.exp` (`e ^ x` differs from it
in the last bit), so `Fsrs.Math.exp` ports the fdlibm `exp` that V8 uses. Given
the same inputs, the results therefore equal ts-fsrs's exactly when run on V8
(the fixture tests in `tests/` assert exact equality).

Time is an `Int` of milliseconds since the Unix epoch (UTC), like
`Date.getTime()`. As in ts-fsrs, the elapsed days used by `next` count UTC
calendar days between the last review and now, while `retrievability` counts
whole 24-hour periods.

Fuzz is off by default, as in ts-fsrs. When enabled it is deterministic: like
ts-fsrs's default seed strategy, the seed is
`"<review time>_<reps after this review>_<difficulty * stability>"`, fed to
the Alea generator (Johannes Baagøe, MIT), which is ported here exactly.

Differences from ts-fsrs's API: `scheduler` returns an `Err` where ts-fsrs's
constructor throws (weights must have exactly 21 finite values; retention must
be in (0, 1]); `next` and `preview` return an `Err` where ts-fsrs throws (a
review time on an earlier UTC day than the last review, or an invalid memory
state). A non-new card without a last review time is treated as reviewed now
(ts-fsrs throws "Invalid date" from `get_retrievability` in that case).

ts-fsrs license:

    MIT License

    Copyright (c) 2026 Open Spaced Repetition

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

Alea (ported via ts-fsrs `src/alea.ts`) license: Copyright (C) 2010 by
Johannes Baagøe, under the same MIT terms as above.


# Types

@docs Rating, State, Step


# Configuration

@docs Config, defaultConfig, defaultWeights, fsrsVersion
@docs Scheduler, scheduler, weights, intervalModifier


# Cards

@docs Card, newCard, ReviewLog, Outcome


# Scheduling

@docs next, preview
@docs retrievability, forgettingCurve

-}

import Array exposing (Array)
import Fsrs.Math exposing (exp)



-- TYPES


{-| A review grade (ts-fsrs `Rating.Again` .. `Rating.Easy`).
-}
type Rating
    = Again
    | Hard
    | Good
    | Easy


{-| A card's learning state.
-}
type State
    = New
    | Learning
    | Review
    | Relearning


{-| A (re)learning step (ts-fsrs step strings such as `"10m"`, `"1h"`, `"1d"`).
-}
type Step
    = Minutes Int
    | Hours Int
    | Days Int


{-| Scheduler settings, as in ts-fsrs `FSRSParameters`.
-}
type alias Config =
    { requestRetention : Float
    , maximumInterval : Int
    , weights : List Float
    , enableFuzz : Bool
    , enableShortTerm : Bool
    , learningSteps : List Step
    , relearningSteps : List Step
    }


{-| The FSRS-6 default weights of ts-fsrs v5.4.2 (`default_w`).
-}
defaultWeights : List Float
defaultWeights =
    [ 0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542 ]


{-| ts-fsrs defaults: retention 0.9, maximum interval 36500 days, fuzz off,
short-term scheduling on, learning steps 1m and 10m, relearning step 10m.
-}
defaultConfig : Config
defaultConfig =
    { requestRetention = 0.9
    , maximumInterval = 36500
    , weights = defaultWeights
    , enableFuzz = False
    , enableShortTerm = True
    , learningSteps = [ Minutes 1, Minutes 10 ]
    , relearningSteps = [ Minutes 10 ]
    }


{-| The ts-fsrs `FSRSVersion` string of the ported release.
-}
fsrsVersion : String
fsrsVersion =
    "v5.4.2 using FSRS-6.0"


{-| A validated configuration with its derived constants.
-}
type Scheduler
    = Scheduler
        { config : Config
        , w : Array Float
        , decay : Float
        , factor : Float
        , intervalModifier : Float
        }


{-| Validate a configuration, clip its weights (ts-fsrs `clipParameters`), and
precompute the decay factor and interval modifier. As in ts-fsrs, a retention
or maximum interval of 0 means the default.
-}
scheduler : Config -> Result String Scheduler
scheduler raw =
    let
        config =
            { raw
                | requestRetention =
                    if raw.requestRetention == 0 then
                        defaultConfig.requestRetention

                    else
                        raw.requestRetention
                , maximumInterval =
                    if raw.maximumInterval == 0 then
                        defaultConfig.maximumInterval

                    else
                        raw.maximumInterval
            }
    in
    if List.length config.weights /= 21 then
        Err ("Invalid parameter length: " ++ String.fromInt (List.length config.weights) ++ ". Must be 21 (FSRS-6).")

    else if List.any (\x -> isNaN x || isInfinite x) config.weights then
        Err "Non-finite or NaN value in parameters"

    else if config.requestRetention <= 0 || config.requestRetention > 1 then
        Err "Requested retention rate should be in the range (0,1]"

    else
        let
            w =
                Array.fromList (clipParameters config.weights (List.length config.relearningSteps) config.enableShortTerm)

            { decay, factor } =
                computeDecayFactor (weight w 20)
        in
        Ok
            (Scheduler
                { config = { config | weights = Array.toList w }
                , w = w
                , decay = decay
                , factor = factor
                , intervalModifier = roundTo8 (((config.requestRetention ^ (1 / decay)) - 1) / factor)
                }
            )


{-| The clipped weights in use.
-}
weights : Scheduler -> List Float
weights (Scheduler s) =
    Array.toList s.w


{-| ts-fsrs `interval_modifier`: interval = stability × modifier (before rounding).
-}
intervalModifier : Scheduler -> Float
intervalModifier (Scheduler s) =
    s.intervalModifier


{-| A card, as in ts-fsrs `Card`. `elapsedDays` is deprecated in ts-fsrs but
still maintained there, so it is kept here.
-}
type alias Card =
    { due : Int
    , stability : Float
    , difficulty : Float
    , elapsedDays : Int
    , scheduledDays : Int
    , learningSteps : Int
    , reps : Int
    , lapses : Int
    , state : State
    , lastReview : Maybe Int
    }


{-| A review log entry, as in ts-fsrs `ReviewLog`; it records the card as it
was before the review.
-}
type alias ReviewLog =
    { rating : Rating
    , state : State
    , due : Int
    , stability : Float
    , difficulty : Float
    , elapsedDays : Int
    , lastElapsedDays : Int
    , scheduledDays : Int
    , learningSteps : Int
    , review : Int
    }


{-| The card after a review and the log of that review.
-}
type alias Outcome =
    { card : Card, log : ReviewLog }


{-| ts-fsrs `createEmptyCard(now)`.
-}
newCard : Int -> Card
newCard now =
    { due = now
    , stability = 0
    , difficulty = 0
    , elapsedDays = 0
    , scheduledDays = 0
    , learningSteps = 0
    , reps = 0
    , lapses = 0
    , state = New
    , lastReview = Nothing
    }



-- CONSTANTS AND PARAMETERS


sMin : Float
sMin =
    0.001


sMax : Float
sMax =
    36500


initSMax : Float
initSMax =
    100


w17w18Ceiling : Float
w17w18Ceiling =
    2


minuteMs : Int
minuteMs =
    60 * 1000


dayMs : Int
dayMs =
    24 * 60 * 60 * 1000


clampRanges : Float -> Bool -> List ( Float, Float )
clampRanges ceiling enableShortTerm =
    [ ( sMin, initSMax )
    , ( sMin, initSMax )
    , ( sMin, initSMax )
    , ( sMin, initSMax )
    , ( 1.0, 10.0 )
    , ( 0.001, 4.0 )
    , ( 0.001, 4.0 )
    , ( 0.001, 0.75 )
    , ( 0.0, 4.5 )
    , ( 0.0, 0.8 )
    , ( 0.001, 3.5 )
    , ( 0.001, 5.0 )
    , ( 0.001, 0.25 )
    , ( 0.001, 0.9 )
    , ( 0.0, 4.0 )
    , ( 0.0, 1.0 )
    , ( 1.0, 6.0 )
    , ( 0.0, ceiling )
    , ( 0.0, ceiling )
    , ( if enableShortTerm then
            0.01

        else
            0.0
      , 0.8
      )
    , ( 0.1, 0.8 )
    ]


{-| ts-fsrs `clipParameters`.
-}
clipParameters : List Float -> Int -> Bool -> List Float
clipParameters parameters numRelearningSteps enableShortTerm =
    let
        base =
            Array.fromList (clampRanges w17w18Ceiling enableShortTerm)

        p =
            Array.fromList parameters

        clipAt i =
            case Array.get i base of
                Just ( lo, hi ) ->
                    jsClamp (weight p i) lo hi

                Nothing ->
                    weight p i

        ceiling =
            if max 0 numRelearningSteps > 1 then
                let
                    value =
                        negate (ln (clipAt 11) + ln ((2.0 ^ clipAt 13) - 1.0) + clipAt 14 * 0.3)
                            / toFloat numRelearningSteps
                in
                jsClamp (roundTo8 (sqrt (max value 0))) 0.01 w17w18Ceiling

            else
                w17w18Ceiling
    in
    List.map2 (\( lo, hi ) x -> jsClamp x lo hi) (clampRanges ceiling enableShortTerm) parameters


weight : Array Float -> Int -> Float
weight w i =
    Maybe.withDefault 0 (Array.get i w)


computeDecayFactor : Float -> { decay : Float, factor : Float }
computeDecayFactor w20 =
    let
        decay =
            negate w20
    in
    { decay = decay, factor = roundTo8 (exp ((decay ^ -1) * ln 0.9) - 1.0) }



-- MEMORY MODEL (ts-fsrs FSRSAlgorithm)


{-| ts-fsrs `forgetting_curve`: retrievability after `elapsedDays` at `stability`.
-}
forgettingCurve : Scheduler -> Float -> Float -> Float
forgettingCurve (Scheduler s) elapsedDays stability =
    roundTo8 ((1 + (s.factor * elapsedDays) / stability) ^ s.decay)


initStability : Array Float -> Int -> Float
initStability w g =
    max (weight w (g - 1)) 0.1


initDifficulty : Array Float -> Int -> Float
initDifficulty w g =
    roundTo8 (weight w 4 - exp (toFloat (g - 1) * weight w 5) + 1)


linearDamping : Float -> Float -> Float
linearDamping deltaD oldD =
    roundTo8 ((deltaD * (10 - oldD)) / 9)


meanReversion : Array Float -> Float -> Float -> Float
meanReversion w init current =
    roundTo8 (weight w 7 * init + (1 - weight w 7) * current)


nextDifficulty : Array Float -> Float -> Int -> Float
nextDifficulty w d g =
    let
        deltaD =
            negate (weight w 6) * toFloat (g - 3)

        nextD =
            d + linearDamping deltaD d
    in
    jsClamp (meanReversion w (initDifficulty w 4) nextD) 1 10


nextRecallStability : Array Float -> Float -> Float -> Float -> Int -> Float
nextRecallStability w d s r g =
    let
        hardPenalty =
            if g == 2 then
                weight w 15

            else
                1

        easyBound =
            if g == 4 then
                weight w 16

            else
                1
    in
    roundTo8
        (jsClamp
            (s
                * (1
                    + exp (weight w 8)
                    * (11 - d)
                    * (s ^ negate (weight w 9))
                    * (exp ((1 - r) * weight w 10) - 1)
                    * hardPenalty
                    * easyBound
                  )
            )
            sMin
            sMax
        )


nextForgetStability : Array Float -> Float -> Float -> Float -> Float
nextForgetStability w d s r =
    roundTo8
        (jsClamp
            (weight w 11
                * (d ^ negate (weight w 12))
                * (((s + 1) ^ weight w 13) - 1)
                * exp ((1 - r) * weight w 14)
            )
            sMin
            sMax
        )


nextShortTermStability : Array Float -> Float -> Int -> Float
nextShortTermStability w s g =
    let
        sinc =
            (s ^ negate (weight w 19)) * exp (weight w 17 * (toFloat (g - 3) + weight w 18))

        maskedSinc =
            if g >= 2 then
                max sinc 1.0

            else
                sinc
    in
    roundTo8 (jsClamp (s * maskedSinc) sMin 36500.0)


type alias Memory =
    { difficulty : Float, stability : Float }


{-| ts-fsrs `next_state` for grades 1-4.
-}
nextMemory : Scheduler -> Memory -> Float -> Int -> Maybe Float -> Result String Memory
nextMemory ((Scheduler sch) as schedulerValue) { difficulty, stability } t g givenR =
    let
        w =
            sch.w

        d =
            difficulty

        s =
            stability
    in
    if t < 0 then
        Err ("Invalid delta_t \"" ++ String.fromFloat t ++ "\"")

    else if d == 0 && s == 0 then
        Ok { difficulty = jsClamp (initDifficulty w g) 1 10, stability = initStability w g }

    else if d < 1 || s < sMin then
        Err ("Invalid memory state { difficulty: " ++ String.fromFloat d ++ ", stability: " ++ String.fromFloat s ++ " }")

    else
        let
            r =
                case givenR of
                    Just value ->
                        value

                    Nothing ->
                        forgettingCurve schedulerValue t s

            newS =
                if t == 0 && sch.config.enableShortTerm then
                    nextShortTermStability w s g

                else if g == 1 then
                    let
                        sAfterFail =
                            nextForgetStability w d s r

                        ( w17, w18 ) =
                            if sch.config.enableShortTerm then
                                ( weight w 17, weight w 18 )

                            else
                                ( 0, 0 )

                        nextSMin =
                            s / exp (w17 * w18)
                    in
                    jsClamp (roundTo8 nextSMin) sMin sAfterFail

                else
                    nextRecallStability w d s r g
        in
        Ok { difficulty = nextDifficulty w d g, stability = newS }


{-| ts-fsrs `next_interval` (with `apply_fuzz`), in days.
-}
nextInterval : Scheduler -> String -> Float -> Int -> Int
nextInterval (Scheduler sch) seed s elapsedDays =
    let
        newInterval =
            min (max 1 (round (s * sch.intervalModifier))) sch.config.maximumInterval
    in
    if not sch.config.enableFuzz || toFloat newInterval < 2.5 then
        newInterval

    else
        let
            fuzzFactor =
                aleaFirst seed

            range =
                fuzzRange (toFloat newInterval) elapsedDays sch.config.maximumInterval
        in
        floor (fuzzFactor * toFloat (range.maxIvl - range.minIvl + 1) + toFloat range.minIvl)


{-| ts-fsrs `get_fuzz_range`.
-}
fuzzRange : Float -> Int -> Int -> { minIvl : Int, maxIvl : Int }
fuzzRange interval0 elapsedDays maximumInterval =
    let
        addRange ( start, end, factor ) acc =
            acc + factor * max (min interval0 end - start) 0.0

        delta =
            List.foldl addRange 1.0 [ ( 2.5, 7.0, 0.15 ), ( 7.0, 20.0, 0.1 ), ( 20.0, 1 / 0, 0.05 ) ]

        interval =
            min interval0 (toFloat maximumInterval)

        minIvl0 =
            max 2 (round (interval - delta))

        maxIvl =
            min (round (interval + delta)) maximumInterval

        minIvl1 =
            if interval > toFloat elapsedDays then
                max minIvl0 (elapsedDays + 1)

            else
                minIvl0
    in
    { minIvl = min minIvl1 maxIvl, maxIvl = maxIvl }



-- SCHEDULING (ts-fsrs AbstractScheduler, BasicScheduler, LongTermScheduler)


type alias Context =
    { scheduler : Scheduler
    , now : Int
    , last : Card
    , current : Card
    , elapsedDays : Int
    , seed : String
    }


initContext : Scheduler -> Int -> Card -> Context
initContext schedulerValue now card =
    let
        interval =
            case ( card.state, card.lastReview ) of
                ( New, _ ) ->
                    0

                ( _, Just lastReview ) ->
                    utcDay now - utcDay lastReview

                ( _, Nothing ) ->
                    0

        current =
            { card | lastReview = Just now, elapsedDays = interval, reps = card.reps + 1 }
    in
    { scheduler = schedulerValue
    , now = now
    , last = card
    , current = current
    , elapsedDays = interval
    , seed =
        String.fromInt now
            ++ "_"
            ++ String.fromInt current.reps
            ++ "_"
            ++ String.fromFloat (current.difficulty * current.stability)
    }


{-| Review `card` at time `now` (ms) with `rating`: ts-fsrs `next`.
-}
next : Scheduler -> Int -> Rating -> Card -> Result String Outcome
next schedulerValue now rating card =
    preview schedulerValue now card
        |> Result.map
            (\outcomes ->
                case rating of
                    Again ->
                        outcomes.again

                    Hard ->
                        outcomes.hard

                    Good ->
                        outcomes.good

                    Easy ->
                        outcomes.easy
            )


{-| The outcome of each rating for a review at `now`: ts-fsrs `repeat`.
-}
preview : Scheduler -> Int -> Card -> Result String { again : Outcome, hard : Outcome, good : Outcome, easy : Outcome }
preview ((Scheduler sch) as schedulerValue) now card =
    let
        ctx =
            initContext schedulerValue now card
    in
    if sch.config.enableShortTerm then
        case card.state of
            New ->
                eachRating (basicLearning ctx Learning)

            Learning ->
                eachRating (basicLearning ctx Learning)

            Relearning ->
                eachRating (basicLearning ctx Relearning)

            Review ->
                basicReview ctx

    else
        case card.state of
            New ->
                longTermNew ctx

            _ ->
                longTermReview ctx


eachRating : (Int -> Result String Outcome) -> Result String { again : Outcome, hard : Outcome, good : Outcome, easy : Outcome }
eachRating f =
    Result.map4 (\a h g e -> { again = a, hard = h, good = g, easy = e }) (f 1) (f 2) (f 3) (f 4)


ratingFromInt : Int -> Rating
ratingFromInt g =
    case g of
        1 ->
            Again

        2 ->
            Hard

        3 ->
            Good

        _ ->
            Easy


buildLog : Context -> Int -> ReviewLog
buildLog ctx g =
    { rating = ratingFromInt g
    , state = ctx.current.state
    , due = Maybe.withDefault ctx.last.due ctx.last.lastReview
    , stability = ctx.current.stability
    , difficulty = ctx.current.difficulty
    , elapsedDays = ctx.elapsedDays
    , lastElapsedDays = ctx.last.elapsedDays
    , scheduledDays = ctx.current.scheduledDays
    , learningSteps = ctx.current.learningSteps
    , review = ctx.now
    }


nextDs : Context -> Int -> Int -> Maybe Float -> Result String Card
nextDs ctx t g r =
    nextMemory ctx.scheduler
        { difficulty = ctx.current.difficulty, stability = ctx.current.stability }
        (toFloat t)
        g
        r
        |> Result.map
            (\m ->
                let
                    current =
                        ctx.current
                in
                { current | difficulty = m.difficulty, stability = m.stability }
            )


{-| BasicScheduler `newState` / `learningState`.
-}
basicLearning : Context -> State -> Int -> Result String Outcome
basicLearning ctx toState g =
    nextDs ctx ctx.elapsedDays g Nothing
        |> Result.map (\card -> { card = applyLearningSteps ctx card g toState, log = buildLog ctx g })


{-| BasicScheduler `reviewState`.
-}
basicReview : Context -> Result String { again : Outcome, hard : Outcome, good : Outcome, easy : Outcome }
basicReview ctx =
    let
        interval =
            ctx.elapsedDays

        r =
            forgettingCurve ctx.scheduler (toFloat interval) ctx.current.stability

        ds g =
            nextDs ctx interval g (Just r)
    in
    Result.map4
        (\nextAgain nextHard nextGood nextEasy ->
            let
                ivl s =
                    nextInterval ctx.scheduler ctx.seed s interval

                hardInterval =
                    min (ivl nextHard.stability) (ivl nextGood.stability)

                goodInterval =
                    max (ivl nextGood.stability) (hardInterval + 1)

                easyInterval =
                    max (ivl nextEasy.stability) (goodInterval + 1)

                toReview c days =
                    { c | scheduledDays = days, due = ctx.now + days * dayMs, state = Review, learningSteps = 0 }

                again =
                    applyLearningSteps ctx nextAgain 1 Relearning
            in
            { again = { card = { again | lapses = again.lapses + 1 }, log = buildLog ctx 1 }
            , hard = { card = toReview nextHard hardInterval, log = buildLog ctx 2 }
            , good = { card = toReview nextGood goodInterval, log = buildLog ctx 3 }
            , easy = { card = toReview nextEasy easyInterval, log = buildLog ctx 4 }
            }
        )
        (ds 1)
        (ds 2)
        (ds 3)
        (ds 4)


{-| BasicScheduler `applyLearningSteps`.
-}
applyLearningSteps : Context -> Card -> Int -> State -> Card
applyLearningSteps ctx nextCard g toState =
    let
        (Scheduler sch) =
            ctx.scheduler

        entry =
            learningStepsStrategy sch.config ctx.current.state ctx.current.learningSteps g

        scheduledMinutes =
            max 0 (Maybe.withDefault 0 (Maybe.map .scheduledMinutes entry))

        nextSteps =
            max 0 (Maybe.withDefault 0 (Maybe.map .nextStep entry))
    in
    if scheduledMinutes > 0 && scheduledMinutes < 1440 then
        { nextCard
            | learningSteps = nextSteps
            , scheduledDays = 0
            , state = toState
            , due = ctx.now + scheduledMinutes * minuteMs
        }

    else if scheduledMinutes >= 1440 then
        { nextCard
            | state = Review
            , learningSteps = nextSteps
            , due = ctx.now + scheduledMinutes * minuteMs
            , scheduledDays = floor (toFloat scheduledMinutes / 1440)
        }

    else
        let
            interval =
                nextInterval ctx.scheduler ctx.seed nextCard.stability ctx.elapsedDays
        in
        { nextCard
            | state = Review
            , learningSteps = 0
            , scheduledDays = interval
            , due = ctx.now + interval * dayMs
        }


stepMinutes : Step -> Int
stepMinutes step =
    case step of
        Minutes n ->
            n

        Hours n ->
            n * 60

        Days n ->
            n * 1440


{-| ts-fsrs `BasicLearningStepsStrategy`, for one grade.
-}
learningStepsStrategy : Config -> State -> Int -> Int -> Maybe { scheduledMinutes : Int, nextStep : Int }
learningStepsStrategy config state curStep g =
    let
        steps =
            Array.fromList
                (if state == Relearning || state == Review then
                    config.relearningSteps

                 else
                    config.learningSteps
                )

        len =
            Array.length steps

        minutesAt i =
            Maybe.map stepMinutes (Array.get i steps)

        firstMinutes =
            Maybe.withDefault 0 (minutesAt 0)
    in
    if len == 0 || curStep >= len then
        Nothing

    else if state == Review then
        if g == 1 then
            Maybe.map (\m -> { scheduledMinutes = m, nextStep = 0 }) (minutesAt (max 0 curStep))

        else
            Nothing

    else
        case g of
            1 ->
                Just { scheduledMinutes = firstMinutes, nextStep = 0 }

            2 ->
                let
                    hardMinutes =
                        if len == 1 then
                            round (toFloat firstMinutes * 1.5)

                        else
                            round (toFloat (firstMinutes + Maybe.withDefault 0 (minutesAt 1)) / 2)
                in
                Just { scheduledMinutes = hardMinutes, nextStep = curStep }

            3 ->
                case minutesAt (curStep + 1) of
                    Just m ->
                        if m /= 0 then
                            Just { scheduledMinutes = m, nextStep = curStep + 1 }

                        else
                            Nothing

                    Nothing ->
                        Nothing

            _ ->
                Nothing


{-| LongTermScheduler `newState`.
-}
longTermNew : Context -> Result String { again : Outcome, hard : Outcome, good : Outcome, easy : Outcome }
longTermNew ctx0 =
    let
        current0 =
            ctx0.current

        ctx =
            { ctx0 | current = { current0 | scheduledDays = 0, elapsedDays = 0 } }
    in
    longTermAll ctx 0 Nothing False


{-| LongTermScheduler `reviewState` (also used for learning states).
-}
longTermReview : Context -> Result String { again : Outcome, hard : Outcome, good : Outcome, easy : Outcome }
longTermReview ctx =
    let
        interval =
            ctx.elapsedDays
    in
    longTermAll ctx interval (Just (forgettingCurve ctx.scheduler (toFloat interval) ctx.current.stability)) True


longTermAll : Context -> Int -> Maybe Float -> Bool -> Result String { again : Outcome, hard : Outcome, good : Outcome, easy : Outcome }
longTermAll ctx interval r countLapse =
    let
        ds g =
            nextDs ctx interval g r
    in
    Result.map4
        (\nextAgain nextHard nextGood nextEasy ->
            let
                ivl s =
                    nextInterval ctx.scheduler ctx.seed s interval

                againInterval =
                    min (ivl nextAgain.stability) (ivl nextHard.stability)

                hardInterval =
                    max (ivl nextHard.stability) (againInterval + 1)

                goodInterval =
                    max (ivl nextGood.stability) (hardInterval + 1)

                easyInterval =
                    max (ivl nextEasy.stability) (goodInterval + 1)

                toReview c days =
                    { c | scheduledDays = days, due = ctx.now + days * dayMs, state = Review, learningSteps = 0 }

                again =
                    toReview nextAgain againInterval
            in
            { again =
                { card =
                    if countLapse then
                        { again | lapses = again.lapses + 1 }

                    else
                        again
                , log = buildLog ctx 1
                }
            , hard = { card = toReview nextHard hardInterval, log = buildLog ctx 2 }
            , good = { card = toReview nextGood goodInterval, log = buildLog ctx 3 }
            , easy = { card = toReview nextEasy easyInterval, log = buildLog ctx 4 }
            }
        )
        (ds 1)
        (ds 2)
        (ds 3)
        (ds 4)


{-| ts-fsrs `get_retrievability(card, now, false)`: predicted recall
probability at `now`, 0 for a new card. Elapsed time counts whole 24-hour
periods since the last review.
-}
retrievability : Scheduler -> Int -> Card -> Float
retrievability schedulerValue now card =
    if card.state == New then
        0

    else
        let
            t =
                case card.lastReview of
                    Just lastReview ->
                        max (floor (toFloat (now - lastReview) / toFloat dayMs)) 0

                    Nothing ->
                        0
        in
        -- ts-fsrs uses +stability.toFixed(8), which equals roundTo8 for
        -- every stability this module produces (they are already rounded).
        forgettingCurve schedulerValue (toFloat t) (roundTo8 card.stability)



-- NUMERICS


{-| ts-fsrs `roundTo(x, 8)`: `Math.round(x * 1e8) / 1e8`.
-}
roundTo8 : Float -> Float
roundTo8 x =
    toFloat (round (x * 100000000)) / 100000000


{-| `Math.min(Math.max(value, lo), hi)`.
-}
jsClamp : Float -> Float -> Float -> Float
jsClamp value lo hi =
    min (max value lo) hi


{-| Days since the epoch of the UTC calendar day containing `ms`.
-}
utcDay : Int -> Int
utcDay ms =
    floor (toFloat ms / toFloat dayMs)


ln : Float -> Float
ln x =
    -- Elm compiles this to Math.log(x) / Math.log(Math.E), and Math.log(Math.E) is exactly 1.
    logBase e x


{-| The first output of ts-fsrs `alea(seed)()`.
-}
aleaFirst : String -> Float
aleaFirst seed =
    let
        -- Alea's constructor hashes " " three times (s0, s1, s2), then the
        -- seed; the first output depends only on s0 and the first seed hash.
        ( n1, s0Initial ) =
            mash (toFloat 0xEFC8249D) " "

        ( n2, _ ) =
            mash n1 " "

        ( n3, _ ) =
            mash n2 " "

        ( _, seeded ) =
            mash n3 seed

        s0 =
            wrapUnit (s0Initial - seeded)

        t =
            2091639 * s0 + 1 * 2.3283064365386963e-10
    in
    t - toFloat (truncate t)


wrapUnit : Float -> Float
wrapUnit x =
    if x < 0 then
        x + 1

    else
        x


{-| Baagøe's Mash hash: returns the updated state and the hash value.
-}
mash : Float -> String -> ( Float, Float )
mash n0 data =
    let
        step code state =
            let
                na =
                    state + toFloat code

                h0 =
                    0.02519603282416938 * na

                nb =
                    toUint32 h0

                h1 =
                    (h0 - nb) * nb

                nc =
                    toUint32 h1

                h2 =
                    h1 - nc
            in
            nc + h2 * 4294967296

        n =
            List.foldl step n0 (List.map Char.toCode (String.toList data))
    in
    ( n, toUint32 n * 2.3283064365386963e-10 )


{-| JavaScript `x >>> 0` for non-negative finite `x`.
-}
toUint32 : Float -> Float
toUint32 x =
    let
        t =
            toFloat (floor x)
    in
    t - 4294967296 * toFloat (floor (t / 4294967296))
