# FSRS reference fixtures

Expected outputs for the Elm FSRS port (`src/Fsrs.elm`), produced by the
reference implementations. `devtools/generate-fsrs-fixtures.roc` embeds these
files in `tests/FsrsFixtures.elm` (generated, not committed), and
`tests/FsrsTest.elm` checks the port against them. Run
`kai workflow test-fsrs`, which runs the `generate-fsrs-fixtures` and
`test-elm` tasks.

The generator programs were throwaway programs run outside this repository and
are not kept here; this file describes how the data was made.

## Reference versions

| File | Library | Version | Source | Runtime |
|---|---|---|---|---|
| `ts-fsrs.json` | [ts-fsrs](https://github.com/open-spaced-repetition/ts-fsrs) (MIT) | 5.4.2 | npm `ts-fsrs@5.4.2` (integrity `sha512-z4qop4pzTcyTzuJ566d9EaX/4bZZzhYfeaPImfVr+xcYT65c5oBgFDijUhCE/D+C78eaolHIhKRZ04/RwF+v2g==`); git tag `v5.4.2` = `bb71e35a2f5af5a5ac6cce9ef7c41ad24855721d` | Node.js v24.20.0 (nixpkgs) |
| `fsrs-rs.json` | [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs) (BSD-3-Clause) | 6.6.2 | crates.io `fsrs = "=6.6.2"` (checksum `89836c0a26b347b585b23824034600b69bfc7f0b0112d0cd656791799eb3a717`); git tag `v6.6.2` = `6088949b99d44f46f5328fd7289d209b9a842b68` | rustc 1.98.1, release build |
| `math-exp.json` | V8 `Math.exp` | Node.js v24.20.0 | 1526 arguments | Node.js v24.20.0 |

Both libraries implement FSRS-6 with the same 21 default weights:
`0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666,
0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658,
0.1542`.

## How the data was produced

**ts-fsrs.** A Node script created a scheduler with `fsrs(params)` for each of
18 named configurations (below), started from `createEmptyCard(start)`, and
replayed fixed review sequences. Before each review it recorded
`get_retrievability(card, now, false)`; it then recorded the four candidate
cards from `repeat(card, now)`, reviewed with `next(card, now, rating)`
(asserting that it equals the matching `repeat` entry), and recorded the review
log. After the last review it recorded retrievability at six later times
(0, 0.5, 1, 7, 30, and 400 days plus 17 minutes). It also recorded, for each
configuration, the weights after ts-fsrs's clipping and the interval modifier.

Sequences:

- 13 hand-written sequences, each run under all 18 configurations: a new card
  with each rating (4); 14 Good, 10 Easy, and 12 Hard reviews on the due date;
  4 Again then 8 Good; lapses and relearning; early reviews (10–90% of the
  interval); late reviews (1–10 intervals late, one year and 1000 days later);
  repeated reviews at the same instant; and a 20-review mixed sequence starting
  at 23:50 UTC so that reviews cross UTC midnight.
- 120 pseudo-random sequences (mulberry32 seed 20260927), 5–24 reviews each,
  cycling through the configurations: ratings Again 15%, Hard 15%, Good 55%,
  Easy 15%; review times early, on the due date with a random time of day,
  late (up to 10 intervals), or at the same instant.

Review times are absolute milliseconds since the Unix epoch; start dates are in
2026–2027.

**fsrs-rs.** A Rust program read `ts-fsrs.json` and replayed every case whose
configuration has short-term scheduling enabled (fsrs-rs always applies the
short-term formula on same-day reviews). It created `FSRS::new(&w)` from the
configuration's unclipped weights, and at each review called
`next_states(state, request_retention, elapsed_days)`, where `elapsed_days` is
the value ts-fsrs used (from its review log) and `state` is `None` for a new
card, and then continued from fsrs-rs's own memory state for the chosen rating.
It recorded all four candidate `(stability, difficulty, interval)` triples and
`current_retrievability(state, elapsed_days, w[20])` before the review. The f32
values were widened to f64 before serialization.

**math-exp.** `Math.exp(x)` for special values (thresholds of the fdlibm
algorithm, ±1, ±745, …) and 1500 pseudo-random arguments in [-1, 1],
[-10, 10], and [-700, 700].

## Configurations

Unless stated, each configuration uses ts-fsrs's defaults: retention 0.9,
maximum interval 36500 days, default weights, fuzz off, short-term on, learning
steps `1m, 10m`, relearning steps `10m`.

| Name | Changes |
|---|---|
| `default` | none |
| `retention-0.80`, `retention-0.95` | retention 0.8 / 0.95 |
| `retention-0.70-max-365` | retention 0.7, maximum interval 365 |
| `max-30`, `max-7` | maximum interval 30 / 7 |
| `long-term` | short-term off (ts-fsrs `LongTermScheduler`) |
| `long-term-0.85-max-180` | short-term off, retention 0.85, maximum interval 180 |
| `no-steps` | no learning or relearning steps |
| `steps-5m` | learning and relearning steps `5m` |
| `steps-long` | learning `1m, 10m, 1h, 1d`; relearning `10m, 1h` |
| `steps-hours` | learning `2h`; relearning `30m, 2d` |
| `fuzz` | fuzz on (ts-fsrs default seed strategy) |
| `fuzz-long-term-max-100` | fuzz on, short-term off, maximum interval 100 |
| `fuzz-0.85` | fuzz on, retention 0.85 |
| `custom-w` | weights `0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234, 1.616, 0.1544, 1.0824, 1.9813, 0.0953, 0.2975, 2.2042, 0.2407, 2.9466, 0.5034, 0.6567, 0.1, 0.35` |
| `custom-w-long-term` | the same weights, short-term off, retention 0.92 |
| `clipped-w` | out-of-range weights (w0 0.05, w3 150, w7 0.9, w17 and w18 2.5, w20 0.05) and relearning steps `10m, 20m, 30m`, to exercise clipping |

## Coverage

- `ts-fsrs.json`: 354 cases (234 hand-written, 120 random), 3815 reviews, and
  15260 candidate cards (1840 Learning, 10999 Review, 2421 Relearning), 369 of
  them lapses from the Review state, plus 2124 retrievability probes.
- `fsrs-rs.json`: the 276 short-term cases (2960 reviews); the tests compare
  257 of them (2764 reviews) and skip the 19 `clipped-w` cases (see below).

## Formats

`ts-fsrs.json` stores cards as arrays to keep the file small:
`[due, stability, difficulty, elapsed_days, scheduled_days, learning_steps,
reps, lapses, state, last_review]`, and review logs as `[rating, state, due,
stability, difficulty, elapsed_days, last_elapsed_days, scheduled_days,
learning_steps, review]`. Times are milliseconds since the Unix epoch.
`fsrs-rs.json` stores each review's four outcomes (Again, Hard, Good, Easy) as
`[stability, difficulty, interval]`, with the interval in unrounded days.

## Differences between ts-fsrs and fsrs-rs

The Elm port follows ts-fsrs exactly; the tests require exact equality with
`ts-fsrs.json`. fsrs-rs is the memory model Anki uses, but it computes only
memory states and unrounded intervals; learning steps, interval rounding and
ordering, maximum intervals, and fuzz live in Anki itself.

- **Precision and rounding.** fsrs-rs computes in f32 and does not round;
  ts-fsrs computes in f64 and rounds difficulty, stability, retrievability,
  the decay factor, and the interval modifier to 8 decimals. Over the compared
  cases the largest differences are 5.1e-6 relative in stability and interval,
  5.5e-6 absolute in difficulty, and 1.7e-7 absolute in retrievability. The
  tests allow 2e-5, 2e-5, and 1e-6. Rounding each interval the ts-fsrs way
  (`round`, at least 1, at most the maximum) gives the same days for all 1720
  fuzz-free chosen Review outcomes outside `clipped-w`.
- **Parameter clipping.** fsrs-rs `FSRS::new` always clips as if there were one
  relearning step and short-term scheduling were off, so it never lowers the
  w17/w18 ceiling for several relearning steps and allows w19 down to 0; its
  ceiling formula also floors at 0.1 where ts-fsrs floors at 0.01. ts-fsrs uses
  the configured relearning steps and short-term setting. With `clipped-w`
  (three relearning steps, w17 = w18 = 2.5) ts-fsrs clips w17 and w18 to about
  0.49 while fsrs-rs keeps 2.0, so same-day stabilities differ greatly (78 of
  its 105 fuzz-free chosen Review intervals differ). These cases are excluded from the fsrs-rs
  comparison.
- **Initial stability floor.** ts-fsrs uses `max(w[rating - 1], 0.1)`; fsrs-rs
  uses `w[rating - 1]` clamped to [0.001, 36500]. They differ only when an
  initial-stability weight is below 0.1 (as in `clipped-w`, w0 = 0.05).
- **Short-term scheduling off.** fsrs-rs has no such mode; ts-fsrs then skips
  the same-day formula and uses w17 = w18 = 0 in the post-lapse stability
  bound. Those configurations are not compared.
- **Elapsed days.** ts-fsrs counts UTC calendar days between reviews for
  scheduling and whole 24-hour periods for `get_retrievability`; fsrs-rs takes
  elapsed days from the caller (Anki counts days relative to its day rollover
  hour). The fsrs-rs replay uses ts-fsrs's scheduling value.
- **Invalid input.** ts-fsrs throws for a negative elapsed time or an invalid
  memory state; fsrs-rs clamps the previous state into range.
