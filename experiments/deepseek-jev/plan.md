# DeepSeek + Jev gloss experiment plan

## Goal

Produce one concise contextual English gloss for every fixed token in the supplied *Iliad* 1.1–20 excerpt. DeepSeek generates alternatives; Jev selects a valid alternative or rejects all of them. Tokenization, token identity, source location, request assembly, validation, and output assembly are deterministic and are never delegated to either model.

The experiment should answer one narrow question: does three-candidate DeepSeek generation followed by Jev selection produce useful per-token glosses, including grammatical information where natural in English?

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

## Scope

### Included

- All 136 frozen tokens.
- Exactly three DeepSeek gloss candidates per token.
- One Jev choice per token among those candidates and `none`.
- A final JSON array containing only `word`, `gloss`, and `valid`.
- A separate audit artifact retaining token IDs, locations, candidates, label mappings, model answers, probabilities, pins, usage, and raw artifact paths.
- Exact model/provider pins and rejection of fallback or resolved-provider drift.
- A no-spend structural check before any paid request.

### Excluded

- Model-created token boundaries, token IDs, or source locations.
- Recursive reject/regenerate iterations.
- Lemma, morphology, or dependency generation.
- Automatic confidence thresholds beyond Jev's explicit `none` choice.
- Treating model output as gold-standard linguistic annotation.
- Using OGA or another corpus as runtime evidence in this first experiment.

The recursive approach is deferred because it adds termination rules, changing prompts, more paid calls, and difficult provenance before the basic two-stage hypothesis has been tested.

## Fixed model roles

### DeepSeek

DeepSeek is a gloss generator only. It receives the complete source for context and the frozen token records. It must not add, remove, reorder, normalize, or alter tokens.

The initial pin is:

- API: PPQ OpenAI-compatible chat completions
- Model: `deepseek/deepseek-v4-flash-0731`
- Provider: `sail-research`
- Provider fallbacks: disabled
- Required parameter support: enabled
- Reasoning output: disabled

The request must pin all generation parameters in configuration. The exact request body and unmodified response must be retained.

### Jev

Jev is a validator and selector only. It receives the complete source, immutable token records, and DeepSeek's three validated candidates. It must not generate replacement glosses or alter token data.

The initial pin is:

- API: direct TypeSafe System One endpoint
- Model: `jev-1.13.0`

For each token, Jev receives a Choice question with anonymous labels `a`, `b`, `c`, and `none`. `none` means that all three candidates are invalid contextual glosses.

## Data contracts

### DeepSeek result

DeepSeek must return exactly this shape for all 136 tokens:

```json
{
  "tokens": [
    {
      "id": 1,
      "word": "μῆνιν",
      "candidates": ["wrath", "rage", "anger"]
    }
  ]
}
```

Requirements:

- Exactly 136 rows in authoritative token order.
- `id` and `word` must exactly match `tokens.json`.
- Exactly three nonempty candidate strings per row.
- Candidates must be distinct after trimming and ASCII-case folding.
- Candidates must not contain the reserved value `[UNRESOLVED]`.
- Candidates should be concise contextual glosses, using hyphens where English grammar naturally exposes inflection, such as `of-Achilles`, `to-the-Achaeans`, or `they-separated`.

### Jev result

Each token gets one deterministic question key, `token_<id>`. Candidate labels are rotated deterministically from the token ID so that the same DeepSeek candidate is not always presented under the same label. The audit records both original candidate order and presented labels.

Jev must return one Choice answer per question, including its complete probability distribution and confidence information supplied by the API. Any missing, duplicate, unknown, or malformed answer invalidates the response.

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

- If Jev chooses `a`, `b`, or `c`, map the label back to its candidate, set `gloss` to that candidate, and set `valid` to `true`.
- If Jev chooses `none`, set `gloss` to `[UNRESOLVED]` and `valid` to `false`.
- Preserve source order and the exact `word` string from `tokens.json`.
- Do not ask either model to construct this final file.

Because repeated Greek forms occur, the audit retains IDs even though the requested final schema does not.

## Implementation steps

1. **Freeze and verify token data.**
   - Keep `iliad-1.1-20.txt` and `tokens.json` immutable for the experiment version.
   - Verify both recorded SHA-256 values.
   - Parse `tokens.json` and require exactly 136 records.
   - Require contiguous IDs, valid line/position sequences, and nonempty words.
   - Reconstruct the source from the records and require byte equality with `iliad-1.1-20.txt`.

2. **Add one minimal Roc runner and Kai tasks.**
   - Use `basic-cli` for file I/O, environment access, timestamps, and the PPQ HTTP request.
   - Keep linguistic decisions out of Roc; Roc only validates fixed data, constructs requests, records artifacts, and joins responses.
   - Add no-spend `check`, paid candidate-generation, paid Jev-validation, and full-run tasks to `Kaifile`.
   - Read `PPQ_API_KEY` and `TYPESAFE_API_KEY` only in paid modes.

3. **Create a pinned experiment configuration.**
   - Record experiment name and version.
   - Record source and token hashes.
   - Record exact endpoints, model IDs, provider ID, generation parameters, fallback policy, and bounded retry policy.
   - Fail if PPQ reports a different model or provider or if TypeSafe reports a different Jev model.

4. **Implement no-spend preflight.**
   - Run every static-data validation from step 1.
   - Construct and JSON-encode both request shapes using synthetic candidates.
   - Confirm expected question keys and deterministic candidate rotations.
   - Do not read API keys or make network requests.

5. **Construct the DeepSeek request.**
   - Include the complete source as context.
   - Include all authoritative token IDs, words, lines, and positions.
   - Explain the gloss style using examples from `spec.md` without supplying answers for the full passage.
   - Require the exact structured result schema.
   - Explicitly prohibit token correction, normalization, omission, insertion, and reordering.

6. **Call DeepSeek and retain provenance.**
   - Write the exact request before dispatch.
   - Send it through PPQ with the fixed model/provider and no fallback.
   - Save the unmodified HTTP response before decoding.
   - Record request ID, response ID, resolved model/provider, timestamps, token usage, cost, and elapsed time.
   - Retry only bounded transport failures; never silently overwrite an attempt.

7. **Validate DeepSeek candidates deterministically.**
   - Enforce the result contract above.
   - Reject the entire attempt if token coverage, identity, order, candidate count, or string safety is wrong.
   - Permit one bounded validation retry with the exact validation error supplied as correction feedback.
   - Save accepted candidates as an immutable checkpoint before contacting Jev.

8. **Construct the Jev request.**
   - Include the complete passage and immutable token records.
   - Attach exactly three candidates to each token.
   - Rotate anonymous labels deterministically and retain the mapping.
   - Create exactly 136 Choice questions plus `none`, each explicitly referring to one token ID and exact form.
   - Define validity as contextual lexical meaning plus any grammatical contribution naturally expressible in a concise English gloss.

9. **Call Jev and retain provenance.**
   - Write the exact request before dispatch.
   - Save unmodified response bytes and headers before decoding.
   - Record model identity, usage, cost, timing, request IDs, retries, and possible duplicate-billing ambiguity.
   - Reuse the accepted DeepSeek checkpoint if Jev fails; never regenerate candidates during a Jev retry or resume.

10. **Validate Jev's response deterministically.**
    - Require exactly one answer for each `token_<id>` key and no extra answers.
    - Require only `a`, `b`, `c`, or `none` choices.
    - Validate all reported probabilities and their distribution.
    - Map labels back to candidates using the recorded rotation, not model text.

11. **Write final and audit outputs atomically.**
    - Produce the three-field final JSON using the deterministic assembly rules.
    - Produce a separate detailed audit JSON.
    - Never place credentials in artifacts.
    - Refuse to overwrite a completed run.

12. **Run a paid smoke before the full passage.**
    - Use the first 10 authoritative tokens while still supplying the complete passage as context.
    - Inspect candidate quality, Jev coverage, resolved provider/model pins, artifact retention, and output assembly.
    - Require explicit authorization before the smoke and again before the full 136-token run.

13. **Run and review the full experiment.**
    - Process all 136 tokens in one candidate stage and one Jev stage unless an API limit discovered during no-spend construction requires deterministic fixed shards.
    - Human-review every final gloss against the passage.
    - Record counts of valid and unresolved tokens, malformed paid attempts, retries, total token usage, and total cost.
    - Decide from human review whether candidate generation, Jev selection, or both merit a second experiment.

## Acceptance criteria

- `tokens.json` reconstructs the frozen source exactly and neither model controls tokenization.
- Every model-facing and final row traces to one authoritative token ID.
- DeepSeek supplies exactly three structurally valid candidates for every target token.
- Jev supplies exactly one validly shaped answer for every target token.
- The final JSON has exactly 136 ordered rows and only `word`, `gloss`, and `valid` fields.
- Any unresolved token is explicit rather than silently assigned the least-bad gloss.
- Requested and resolved model/provider identities match the pins.
- Exact requests, raw responses, usage, costs, timing, and deterministic transformations are auditable.
- No paid command runs during implementation or checking without explicit authorization.
