# DeepSeek experiment

Requests use the fixed PPQ model ID, OpenInference provider, and generation settings in `config.json`. Provider fallback is disabled.

## Samples

Each work has one Greek-only input file:

- `inputs/iliad.txt`: Homer, *Iliad* 1.1–5.
- `inputs/clouds.txt`: Aristophanes, *Clouds* 1–5.
- `inputs/genesis.txt`: Septuagint Genesis 1:1–3.

The Homer and Aristophanes text was extracted from Perseus `canonical-greekLit` revision `f72016188f04796e955551ee18e061698f644ced`, files `tlg0012.tlg001.perseus-grc2.xml` and `tlg0019.tlg003.perseus-grc2.xml`. The Genesis text was extracted from UD Ancient Greek PTNK revision `818fb315ff1f6cd95b6e7fa90f3707488d2b010d`, file `grc_ptnk-ud-dev.conllu`. Both repositories distribute these sources under CC BY-SA 4.0.

## Running the experiment

Run `kai run deepseek-experiment` only after the user authorizes the paid calls. The Roc runner:

1. loads `PPQ_API_KEY` from the repository-root `.env` without displaying or storing the key;
2. reads the fixed model ID and every generation parameter from `config.json`;
3. discovers the files under `inputs/` in sorted order and makes one PPQ request per file, without automatic retries;
4. uses one fixed prompt asking for contextual English word glosses beside the original Greek, while permitting sentence punctuation to be omitted from the displayed Greek;
5. preserves the request, raw response, and audit metadata according to the response-retention rule below; and
6. extracts `glossed_text` without token, punctuation, alignment, or semantic validation into the corresponding file under `outputs/`.

The outputs are human-review artifacts. The runner deliberately does not decide whether an English gloss is valid. `kai run check-deepseek-experiment` checks configuration and request construction without making API calls.

## Response retention rule

Before dispatch, the runner saves the exact request body to `responses/<run-id>/<request-id>.request.json`. Immediately after receiving a response, it saves the complete, unmodified response bytes to `responses/<run-id>/<request-id>.raw.json` before parsing or transformation. It then writes `responses/<run-id>/<request-id>.json` with the request ID, timestamps, exact request and response bodies, HTTP metadata, resolved model/provider, token usage, and finish reason. Existing response artifacts are never overwritten, and the API key is never stored.

The `responses/` directory is intentionally ignored by Git because responses may be large. Preserve it with experiment artifacts or other backed-up storage for audit and comparison.
