# DeepSeek V4 Flash + Jev gloss experiment 3

This frozen, gloss-only experiment uses one DeepSeek V4 Flash request per 50-token shard to generate exactly three contextual gloss candidates per immutable token ID, then one direct TypeSafe Jev request to choose `a`, `b`, `c`, or `none` independently for each token. `none` renders as `[UNRESOLVED]`; no confidence threshold is applied. The complete Jev probability distribution, confidence, and winner/runner-up margin remain available for later calibration.

`config.json` pins `deepseek/deepseek-v4-flash-0731` to PPQ's OpenInference provider with the sampling settings from the completed DeepSeek experiment. It separately pins `jev-1.13.0` at `https://api.typesafe.ai/v1/systemone`. The runner reads `PPQ_API_KEY` and `TYPESAFE_API_KEY` from the repository-root `.env` only for paid modes.

The six files under `inputs/` are byte-for-byte frozen copies of the completed experiment's inputs. DeepSeek receives the complete work as context and must return concise, hyphenated contextual candidates in the style of the Anabasis corpus, including grammatical information when natural in English (`of-Darius`, `of-birds`, `to-him`, `are-born`, `he-was-thinking`). Jev receives the same complete work, token IDs and forms, and deterministically rotated anonymous candidates.

## Commands

Safe setup checks, with no API keys read and no network calls:

```text
kai run check-jev-gloss-experiment-tool
kai run check-deepseek-v4-flash-0731-experiment-3
```

The following commands make paid DeepSeek and Jev calls. Run them only after explicit authorization:

```text
kai run smoke-deepseek-v4-flash-0731-experiment-3
kai run deepseek-v4-flash-0731-experiment-3
kai run resume-deepseek-v4-flash-0731-experiment-3
```

The smoke task processes only the first 50-token shard of `iliad-1.1-20.txt`. The resume task chooses the lexicographically latest incomplete non-smoke run. Validated candidate checkpoints are written before Jev is contacted, so Jev validation retries and resumed runs never regenerate accepted candidates.

## Outputs and retention

Each run has a unique directory under ignored `responses/`. Before every request, the exact body is saved; immediately after a response, its unmodified bytes are saved before decoding. Parsed records retain HTTP metadata, request IDs, timing, usage, cost, validation failures, and retries. Accepted candidate and Jev shard checkpoints are never overwritten.

Each completed work produces two atomic files under `outputs/<run-id>/`:

- `<work>.txt`: readable `Greek <=> gloss` lines, with `[UNRESOLVED]` for `none`;
- `<work>.audit.json`: candidates, presented rotation, selection, probabilities, confidence, margin, model/provider identities, usage, cost, request IDs, timestamps, and elapsed timing.

Preserve the ignored response directory with experiment artifacts or backed-up storage; review generated outputs before deciding whether to version them.
