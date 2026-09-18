# DeepSeek V4 Flash + Jev gloss experiment 3

This frozen, gloss-only experiment uses one DeepSeek V4 Flash request per 50-token shard to generate exactly three contextual gloss candidates per immutable token ID, then one direct TypeSafe Jev request to choose `a`, `b`, `c`, or `none` independently for each token. `none` renders as `[UNRESOLVED]`; no confidence threshold is applied. The complete Jev probability distribution, confidence, and winner/runner-up margin remain available for later calibration.

`config.json` pins `deepseek/deepseek-v4-flash-0731` to PPQ's Sail Research provider with the sampling settings from the completed DeepSeek experiment and disables provider fallback. It separately pins `jev-1.13.0` at `https://api.typesafe.ai/v1/systemone`. The runner reads `PPQ_API_KEY` and `TYPESAFE_API_KEY` from the repository-root `.env` only for paid modes. Jev transport retries match the TypeSafe SDK's default bound of two retries after the initial attempt, with 500 ms exponential backoff capped at 5 seconds and `Retry-After`/`retry-after-ms` honored up to 60 seconds.

The six files under `inputs/` are byte-for-byte frozen copies of the completed experiment's inputs. DeepSeek receives the complete work as context and must return concise, hyphenated contextual candidates in the style of the Anabasis corpus, including grammatical information when natural in English (`of-Darius`, `of-birds`, `to-him`, `are-born`, `he-was-thinking`). Jev receives the same complete work, token IDs and forms, and deterministically rotated anonymous candidates.

## Commands

Safe setup checks, with no API keys read and no network calls:

```text
kai run check-jev-gloss-experiment-tool
kai run check-deepseek-v4-flash-0731-experiment-3
kai run check-resume-smoke-deepseek-v4-flash-0731-experiment-3
```

The following commands make paid DeepSeek and Jev calls. Run them only after explicit authorization:

```text
kai run smoke-deepseek-v4-flash-0731-experiment-3
kai run resume-smoke-deepseek-v4-flash-0731-experiment-3
kai run deepseek-v4-flash-0731-experiment-3
kai run resume-deepseek-v4-flash-0731-experiment-3
```

The smoke task processes only the first 50-token shard of `iliad-1.1-20.txt`. The smoke-resume task deterministically chooses the lexicographically latest incomplete smoke run and validates its manifest, smoke mode, experiment version, output directory, model/provider pins, source token IDs, first-shard identity, and accepted candidate checkpoint before reading API keys. It then resumes at Jev; it cannot regenerate that shard's candidates. The full resume task similarly chooses the lexicographically latest incomplete non-smoke run. Validated candidate checkpoints are written before Jev is contacted, so Jev validation retries and resumed runs never regenerate accepted candidates.

## TypeSafe transport workaround

`basic-cli` 0.22.2 uses a Hyper transport that enables HTTP/1 only. Its native transport failed the retained, valid TypeSafe POST before a response was captured, while the same body succeeds through curl over HTTP/1.1 and HTTP/2. The historical runner discarded the `Err` payload, so recovering that attempt's exact Hyper category would require another paid POST; native HTTP failures now retain a redacted category/message instead. The newer 0.23.0-rc1 has the same HTTP implementation, and `roc-lang/http` is only the shared request/response data package, so neither available upgrade repairs this path. See upstream [HTTP/2 transport issue #455](https://github.com/roc-lang/basic-cli/issues/455) and [transport error mapping issue #438](https://github.com/roc-lang/basic-cli/issues/438).

Until a compatible released `basic-cli` transport completes the retained TypeSafe request and exposes safe transport diagnostics, the maintained Roc runner invokes the Kai-declared curl dependency for Jev only. The API key is passed in a child-process environment variable and expanded by curl, never placed in arguments or artifacts. Roc still owns request construction, retry policy, checkpointing, validation, and audit generation. Remove this workaround only after that native transport test passes.

## Outputs and retention

Each run has a unique directory under ignored `responses/`. Before every request, the exact body is saved; immediately after a TypeSafe response, its unmodified bytes and exact response headers are saved before decoding. Every Jev transport attempt gets distinct request, raw response, header, transport-output, and parsed attempt artifacts. Parsed records retain HTTP status, safe transport error category/message, request IDs, timing, usage, cost, validation failures, retry delay/count, and whether an ambiguous failure creates possible duplicate billing. Transient connection failures and HTTP 408, 429, and 5xx responses (including 529) are retried. Accepted candidate and Jev shard checkpoints are never overwritten.

Each completed work produces two atomic files under `outputs/<run-id>/`:

- `<work>.txt`: readable `Greek <=> gloss` lines, with `[UNRESOLVED]` for `none`;
- `<work>.audit.json`: candidates, presented rotation, selection, probabilities, confidence, margin, model/provider identities, usage, cost, request IDs, timestamps, and elapsed timing.

Preserve the ignored response directory with experiment artifacts or backed-up storage; review generated outputs before deciding whether to version them.
