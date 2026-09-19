# DeepSeek + Jev adaptive gloss experiment plan

## Goal

Produce one concise contextual English gloss for every fixed token in the supplied *Iliad* 1.1–20 excerpt. DeepSeek generates one best gloss per unresolved token, and Jev independently judges whether that gloss is valid in context. Accepted glosses are frozen immediately. Only rejected tokens continue to another generation-and-validation round, with an absolute maximum of three semantic rounds.

Tokenization, token identity, source location, request assembly, routing, and final output assembly are deterministic and are never delegated to either model.

The experiment should answer three narrow questions:

1. How often is DeepSeek's first gloss acceptable?
2. How many rejected glosses are recovered by targeted regeneration?
3. Does adaptive regeneration cost less than generating three alternatives for every token?

## Frozen input

- Source: `iliad-1.1-20.txt`
- Source SHA-256: `1263ac162eea8365bd04261361668fab579c2f97299ac0a8b4429f7f33133807`
- Token inventory: `tokens.json`
- Token inventory SHA-256: `09497d4c5decffba19b456258396a578d86d880847f1b49c44038d91c10fe32a`
- Lines: 20
- Tokens: 136

`tokens.json` is the authoritative model-facing token inventory. IDs are contiguous integers from 1 through 136. `line` is the one-based source line and `position` is the one-based whitespace-token position on that line.

The tokenization contract is deliberately simple: split each source line on whitespace and preserve every resulting string byte-for-byte. Terminal punctuation therefore remains attached, as required by the examples in `spec.md`; elision marks are part of their words. Joining each line's tokens with one ASCII space and lines with `\n` reconstructs the source exactly.

As an independent construction check, the 136 lexical forms were compared with the corresponding local OGA Iliad sequence. OGA separates punctuation into its own rows, while this experiment preserves the source's attached punctuation. After accounting for that representational difference, all 136 lexical forms matched. OGA is reference evidence only and is not a runtime input or dependency.

## Experiment design

The unit of progress is a token, not a whole model response.

### Round 1

1. DeepSeek generates exactly one gloss for each of the 136 tokens.
2. Jev independently scores each token/gloss pair with a Noul validity question.
3. Tokens meeting the configured acceptance threshold are accepted and removed from further rounds.
4. Rejected tokens proceed to round 2.

### Round 2

1. DeepSeek receives only the rejected token records, the complete passage for context, and each token's previously rejected gloss.
2. It generates one different replacement gloss per rejected token.
3. Jev independently scores each replacement.
4. Accepted tokens are frozen; remaining rejected tokens proceed to round 3.

### Round 3

1. DeepSeek receives only the still-rejected token records, the complete passage, and both prior rejected glosses.
2. It generates one different replacement gloss per token.
3. Jev independently scores each replacement.
4. Accepted tokens are frozen. Any remaining rejected token becomes unresolved.

There is no round 4. Transport retries and malformed-response correction retries do not count as semantic rounds because they do not introduce a new accepted candidate attempt. Every token may receive at most three distinct semantic gloss attempts.

The run stops early when no rejected tokens remain.

## Scope

### Included

- All 136 frozen tokens.
- One DeepSeek gloss per pending token per semantic round.
- One independent Jev Noul validity judgment per generated gloss.
- At most three semantic rounds.
- Deterministic routing based on a configured Jev threshold.
- A final JSON array containing only `word`, `gloss`, and `valid`.
- A separate audit retaining IDs, locations, every attempted gloss, round numbers, Jev scores, pins, usage, costs, and raw artifact paths.
- Exact model/provider pins and rejection of fallback or resolved-provider drift.
- A no-spend structural check before any paid request.

### Excluded

- Model-created token boundaries, token IDs, or source locations.
- Three up-front candidates for every token.
- More than one replacement per token in a round.
- More than three semantic rounds.
- Jev-generated replacement glosses.
- Lemma, morphology, or dependency generation.
- Treating Jev scores or final model outputs as gold-standard linguistic annotations.
- Using OGA or another corpus as runtime evidence in this first experiment.

## Fixed model roles

### DeepSeek

DeepSeek is a gloss generator only. It receives the complete source for context and the authoritative records for tokens still pending in the current round. It must not add, remove, reorder, normalize, or alter tokens.

The initial pin is:

- API: PPQ OpenAI-compatible chat completions
- Model: `deepseek/deepseek-v4-flash-0731`
- Provider: `sail-research`
- Provider fallbacks: disabled
- Required parameter support: enabled
- Reasoning output: disabled

The request must pin all generation parameters in configuration. The exact request body and unmodified response must be retained.

For rounds 2 and 3, DeepSeek receives prior rejected gloss strings so that it can avoid repeating them. It does not receive permission to reconsider accepted tokens.

### Jev

Jev is a validator only. It receives the complete source and one exact token/gloss pair per pending token. It must not generate alternatives, rank tokens against each other, alter token data, or reconsider previously accepted glosses.

The initial pin is:

- API: direct TypeSafe System One endpoint
- Model: `jev-1.13.0`
- Primitive: Noul

Each Noul asks whether one exact gloss is a natural and contextually accurate gloss for one exact token occurrence, including morphology and syntactic contribution where those should appear naturally in concise English.

## Acceptance policy

Jev returns a Noul probability, not an intrinsic boolean. The experiment configuration must therefore contain one explicit `acceptance_threshold` in the inclusive range 0 through 1.

For the initial experiment, use `0.5` as the routing threshold:

- `noul >= 0.5`: accept and freeze the gloss.
- `noul < 0.5`: reject and route the token to the next round.

This is an experimental more-likely-valid-than-invalid routing rule, not a claim that 0.5 is calibrated for production quality. Preserve every raw score so a human-reviewed sample can evaluate false acceptances and false rejections and support later offline threshold replay. Do not change the threshold during a run.

A token accepted in an earlier round remains accepted even if later work uses a different threshold. Threshold experiments must replay the retained audit into a new derived output rather than mutating the original run.

## Data contracts

### DeepSeek result

Each round returns exactly one row per pending token:

```json
{
  "round": 1,
  "tokens": [
    {
      "id": 1,
      "word": "μῆνιν",
      "gloss": "wrath"
    }
  ]
}
```

Requirements:

- `round` must equal the requested semantic round.
- Rows must exactly match the pending token IDs and order for that round.
- `id` and `word` must exactly match `tokens.json`.
- Every gloss must be nonempty after trimming.
- A gloss must not contain the reserved value `[UNRESOLVED]`.
- In rounds 2 and 3, the new gloss must differ from every prior gloss for that token after trimming and ASCII-case folding.
- Glosses should be concise and contextual, using hyphens where English grammar naturally exposes inflection, such as `of-Achilles`, `to-the-Achaeans`, or `they-separated`.

### Jev result

Each generated token/gloss pair gets one deterministic question key:

```text
round_<round>_token_<id>
```

Jev must return exactly one Noul answer per question. The audit records the token, gloss, round, score, threshold, and routing result. Any missing, duplicate, unknown, out-of-range, or malformed answer invalidates the response.

### Final result

The final user-facing file contains exactly:

```json
[
  {
    "word": "μῆνιν",
    "gloss": "wrath",
    "valid": true
  }
]
```

Deterministic assembly rules:

- Use the first gloss for each token whose Jev score met the threshold.
- Set that row's `valid` value to `true`.
- If no gloss meets the threshold after round 3, set `gloss` to `[UNRESOLVED]` and `valid` to `false`.
- Preserve source order and the exact `word` string from `tokens.json`.
- Do not ask either model to construct this final file.

Because repeated Greek forms occur, the audit retains token IDs even though the requested final schema does not.

## Implementation steps

1. **Freeze and verify token data.**
   - Keep `iliad-1.1-20.txt` and `tokens.json` immutable for the experiment version.
   - Verify both recorded SHA-256 values.
   - Parse `tokens.json` and require exactly 136 records.
   - Require contiguous IDs, valid line/position sequences, and nonempty words.
   - Reconstruct the source from the records and require byte equality with `iliad-1.1-20.txt`.

2. **Add one minimal Roc runner and Kai tasks.**
   - Use `basic-cli` for file I/O, environment access, timestamps, and the PPQ HTTP request.
   - Keep linguistic decisions out of Roc; Roc only validates fixed data, constructs requests, routes IDs, records artifacts, and joins responses.
   - Add no-spend `check`, paid smoke, paid full-run, and resume tasks to `Kaifile`.
   - Read `PPQ_API_KEY` and `TYPESAFE_API_KEY` only in paid modes.

3. **Create a pinned experiment configuration.**
   - Record experiment name and version.
   - Record source and token hashes.
   - Set `max_semantic_rounds` to exactly `3` and reject any other value.
   - Set `acceptance_threshold` to `0.5` for the initial run.
   - Record exact endpoints, model IDs, provider ID, generation parameters, fallback policy, and bounded retry policy.
   - Fail if PPQ reports a different model or provider or if TypeSafe reports a different Jev model.

4. **Implement no-spend preflight.**
   - Run every static-data validation from step 1.
   - Simulate all three rounds with synthetic glosses and synthetic Jev scores.
   - Verify that accepted IDs disappear from later pending sets.
   - Verify that no ID receives more than three semantic attempts.
   - Verify early termination, final unresolved handling, question keys, and final output assembly.
   - Construct and JSON-encode both API request shapes without reading API keys or making network requests.

5. **Construct each DeepSeek request.**
   - Include the complete source as context in every semantic round.
   - Include only the authoritative token records pending in that round.
   - For rounds 2 and 3, include all previous rejected glosses beside the relevant token.
   - Explain the gloss style using examples from `spec.md` without supplying answers for the full passage.
   - Require the exact structured result schema.
   - Explicitly prohibit token correction, normalization, omission, insertion, reordering, and repetition of prior rejected glosses.

6. **Call DeepSeek and retain provenance.**
   - Write the exact request before dispatch.
   - Send it through PPQ with the fixed model/provider and no fallback.
   - Save the unmodified HTTP response before decoding.
   - Record semantic round, pending IDs, request ID, response ID, resolved model/provider, timestamps, token usage, cost, and elapsed time.
   - Retry only bounded transport failures; never silently overwrite an attempt.

7. **Validate each DeepSeek response deterministically.**
   - Enforce the per-round result contract above.
   - Reject the whole response if pending-token coverage, identity, order, gloss count, uniqueness from prior attempts, or string safety is wrong.
   - Permit one bounded correction retry for malformed output, using the exact validation error as feedback.
   - A malformed-output retry remains part of the same semantic round.
   - Save valid generated glosses as an immutable round checkpoint before contacting Jev.

8. **Construct each Jev request.**
   - Include the complete passage and only the current round's immutable token/gloss pairs.
   - Create exactly one Noul question per pending token.
   - Point each question directly to one token record and its proposed gloss.
   - Define validity as contextual lexical meaning plus any grammatical contribution naturally expressible in concise English.
   - Do not include accepted tokens or ask Jev to compare candidates.

9. **Call Jev and retain provenance.**
   - Write the exact request before dispatch.
   - Save unmodified response bytes and headers before decoding.
   - Record semantic round, model identity, usage, cost, timing, request IDs, retries, and possible duplicate-billing ambiguity.
   - Reuse the accepted DeepSeek round checkpoint if Jev fails; never regenerate that round's glosses during a Jev retry or resume.

10. **Validate Jev and route tokens deterministically.**
    - Require exactly one answer for every expected round/token key and no extras.
    - Require a Noul probability in the inclusive range 0 through 1.
    - Accept scores greater than or equal to the fixed threshold.
    - Freeze accepted token/gloss pairs permanently for the run.
    - Route rejected IDs to the next round in original source order.
    - Stop immediately if the rejected set is empty.
    - After round 3, mark every remaining ID unresolved without another model call.

11. **Checkpoint every semantic round.**
    - Atomically save pending IDs, generated glosses, Jev scores, accepted IDs, rejected IDs, accumulated cost, and artifact references.
    - Resume only from a fully validated checkpoint.
    - Never repeat a completed paid stage or overwrite accepted results.

12. **Write final and audit outputs atomically.**
    - Produce the three-field final JSON using the deterministic assembly rules.
    - Produce a separate detailed audit JSON containing every attempt across all rounds.
    - Record first-pass acceptance, round-2 recovery, round-3 recovery, and unresolved counts.
    - Never place credentials in artifacts.
    - Refuse to overwrite a completed run.

13. **Run a paid smoke before the full passage.**
    - Use the first 10 authoritative tokens while still supplying the complete passage as context.
    - Allow the smoke to exercise up to all three rounds.
    - Human-review every smoke judgment, especially tokens near the 0.5 threshold.
    - Inspect model/provider pins, routing, repeated-gloss rejection, checkpoint reuse, artifact retention, and cost.
    - Require explicit authorization before the smoke and again before the full run.

14. **Run and review the full experiment.**
    - Begin round 1 with all 136 tokens.
    - Batch only rejected tokens in rounds 2 and 3.
    - Human-review every final gloss and unresolved token against the passage.
    - Report first-pass acceptance rate, each refinement recovery rate, final unresolved rate, human-observed Jev false acceptances/rejections, malformed paid attempts, retries, per-round token usage, and total cost.
    - Compare measured cost with the estimated cost of generating and validating three candidates for all 136 tokens.

## Acceptance criteria

- `tokens.json` reconstructs the frozen source exactly and neither model controls tokenization.
- Every generated, validated, and final row traces to one authoritative token ID.
- DeepSeek generates only one gloss per pending token in each round.
- Accepted tokens never appear in later model requests.
- No token receives more than three semantic gloss attempts.
- Every generated gloss receives exactly one independently validated Jev score.
- The final JSON has exactly 136 ordered rows and only `word`, `gloss`, and `valid` fields.
- Tokens still rejected after round 3 are explicit `[UNRESOLVED]` values rather than least-bad guesses.
- Requested and resolved model/provider identities match the pins.
- Exact requests, raw responses, routing decisions, usage, costs, timing, and deterministic transformations are auditable.
- No paid command runs during implementation or checking without explicit authorization.
