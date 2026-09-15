# DeepSeek V4 Flash 0731 experiment

Requests use the fixed PPQ model ID, OpenInference provider, and generation settings in `config.json`. Provider fallback is disabled. The shared generic runner owns token IDs, the response schema, structural validation, bounded validation retries, and deterministic output rendering.

## Samples

Each work has one Greek-only input file:

- `inputs/iliad-1.1-20.txt`: Homer, *Iliad* 1.1–20.
- `inputs/clouds-1-20.txt`: Aristophanes, *Clouds* 1–20.
- `inputs/genesis-1.1-10.txt`: Septuagint Genesis 1:1–10.
- `inputs/xenophon-anabasis-1.8.8-10.txt`: Xenophon, *Anabasis* 1.8.8–10.
- `inputs/herodotus-histories-1.11.txt`: Herodotus, *Histories* 1.11.
- `inputs/galen-natural-faculties-1.1.txt`: Galen, *On the Natural Faculties* 1.1.

The Homer and Aristophanes text was extracted from Perseus `canonical-greekLit` revision `f72016188f04796e955551ee18e061698f644ced`, files `tlg0012.tlg001.perseus-grc2.xml` and `tlg0019.tlg003.perseus-grc2.xml`. The Genesis text was extracted from UD Ancient Greek PTNK revision `818fb315ff1f6cd95b6e7fa90f3707488d2b010d`, file `grc_ptnk-ud-dev.conllu`. Both repositories distribute these sources under CC BY-SA 4.0.

## Running the experiment

Run `kai run deepseek-v4-flash-0731-experiment` only after the user authorizes the paid calls. The Roc runner:

1. loads `PPQ_API_KEY` from the repository-root `.env` without displaying or storing the key;
2. reads the fixed model ID, generation settings, and maximum validation attempts from `config.json`;
3. discovers the files under `inputs/` in sorted order, assigns immutable IDs to their whitespace-delimited Greek tokens, and preserves source-line boundaries;
4. asks only for an exact-length JSON array of token IDs and contextual English glosses—the model never supplies the Greek output text;
5. preserves every exact request, raw response, and audit record according to the response-retention rule below;
6. rejects responses with a non-stop finish reason, invalid JSON, wrong item ID, missing, duplicated, unknown, or reordered token IDs, empty glosses, or glosses containing line breaks or the output delimiter;
7. retries only captured validation failures, up to `validation.max_attempts`; ambiguous transport failures are never retried; and
8. combines validated glosses with the original Greek deterministically and atomically writes the corresponding file under `outputs/`.

Version 4 outputs are structurally validated human-review artifacts. The runner deliberately does not decide whether an English gloss is semantically valid. `kai run check-deepseek-v4-flash-0731-experiment` checks configuration and request construction without making API calls.

## Response retention rule

Before dispatch, the runner saves the exact request body to `responses/<run-id>/<request-id>.request.json`. Immediately after receiving a response, it saves the complete, unmodified response bytes to `responses/<run-id>/<request-id>.raw.json` before parsing or transformation. It then writes `responses/<run-id>/<request-id>.json` with the attempt number, request ID, timestamps, exact request and response bodies, HTTP metadata, resolved model/provider, token usage, finish reason, and validation result. Existing response artifacts are never overwritten, and the API key is never stored.

The `responses/` directory is intentionally ignored by Git because responses may be large. Preserve it with experiment artifacts or other backed-up storage for audit and comparison.
