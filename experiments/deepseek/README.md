# DeepSeek experiment

Requests use the PPQ `~deepseek/deepseek-v4-flash-latest` alias and the generation settings in `config.json`. The alias may resolve to different model revisions or inference providers over time.

## Samples

Each work has one Greek-only input file:

- `inputs/iliad.txt`: Homer, *Iliad* 1.1–5.
- `inputs/clouds.txt`: Aristophanes, *Clouds* 1–5.
- `inputs/genesis.txt`: Septuagint Genesis 1:1–3.

The Homer and Aristophanes text was extracted from Perseus `canonical-greekLit` revision `f72016188f04796e955551ee18e061698f644ced`, files `tlg0012.tlg001.perseus-grc2.xml` and `tlg0019.tlg003.perseus-grc2.xml`. The Genesis text was extracted from UD Ancient Greek PTNK revision `818fb315ff1f6cd95b6e7fa90f3707488d2b010d`, file `grc_ptnk-ud-dev.conllu`. Both repositories distribute these sources under CC BY-SA 4.0.

## `run experiment` instruction

When the user says **run experiment**:

1. Load `PPQ_API_KEY` from the repository-root `.env` without displaying or storing the key.
2. Read the provider, model alias, and all generation parameters from `config.json`; do not substitute another model or alter the parameters.
3. Make one PPQ request for each file under `inputs/`.
4. Ask the model for contextual English word glosses only—not lemmas, morphology, commentary, or a prose translation. Require a JSON object with one `glossed_text` string. Within that string, every whitespace-delimited Greek token must occur exactly once and in source order as `Greek <=> English gloss`, one pair per line. The Greek side must copy the source token exactly, including attached punctuation. Preserve source-line boundaries as blank lines.
5. Save and validate each raw response according to the response-retention rule below. Reject output that omits, duplicates, reorders, or changes a Greek token; do not silently repair it.
6. Extract the validated `glossed_text` into exactly one corresponding output file per work: `outputs/iliad.txt`, `outputs/clouds.txt`, and `outputs/genesis.txt`.
7. Report the resolved model/provider metadata, token usage, finish reason, response paths, and output paths.

Do not make paid API calls merely because this README was read. Calls are authorized only by the user's **run experiment** instruction.

## Response retention rule

Every API call must save the complete, unmodified response to `responses/<run-id>/<request-id>.json` before parsing, validation, retry, or transformation. Never overwrite an existing response. The saved record must include the request ID, timestamp, exact request body, returned model/provider metadata, token usage, finish reason, and raw response body. Never store the API key.

The `responses/` directory is intentionally ignored by Git because responses may be large. Preserve it with experiment artifacts or other backed-up storage for audit and comparison.
