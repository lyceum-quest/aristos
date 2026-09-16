# GLAUx-to-CoNLL-U enhancement experiment

This experiment follows Dr. Crane’s correction-first workflow: each model receives existing linguistic annotation, corrects it, converts it to valid UD-style CoNLL-U, and adds sentence translations plus contextual token glosses. The golden output example is [`conllu/xenophon/anabasis/book-01-first-sentence.tb.conllu`](../../conllu/xenophon/anabasis/book-01-first-sentence.tb.conllu).

## Source distinction and pin

The authoritative comprehensive input source is **GLAUx**, not a UD treebank and not CoNLL-U. GLAUx publishes Ancient Greek text with morphology, lemmas, and Ancient Greek Dependency Treebank-style syntactic dependencies in XML. Most annotation is automatic. The model must therefore treat these values as proposals to correct and map into UD v2 rather than as reviewed UD gold.

- Repository: <https://github.com/alekkeersmaekers/glaux>
- Release: `v2.1`
- Revision: `be838c1ac152a0a8380ffbb0844504d7d253c1d6`
- Version DOI: <https://doi.org/10.5281/zenodo.17295426>
- Concept DOI: <https://doi.org/10.5281/zenodo.10948374>
- Metadata file: [`metadata.txt`](https://github.com/alekkeersmaekers/glaux/blob/be838c1ac152a0a8380ffbb0844504d7d253c1d6/metadata.txt)
- GLAUx XML encoding: Unicode NFD

Release `v2.1` fixes XML attribute escaping and is otherwise identical to `v2.0`. The exact commit, rather than the movable tag, is the experiment pin. The pinned GLAUx README describes the corpus as generally CC BY-SA 4.0 while warning that particular texts or manual annotations can be more restrictive; the Zenodo software record declares CC BY 4.0. These release-level statements do not replace the per-text `SOURCE_LICENSE` values below. The selected excerpts have automatic GLAUx annotations and no separately listed manual-treebank layer.

## Per-text provenance

The source, license, and manual-treebank status below are transcribed from `metadata.txt` at the pinned revision. `TREEBANK_ANNOTATIONS=NA`, together with `analysis="auto"` on every selected source sentence, means these excerpts use GLAUx automatic annotation rather than one of its manually annotated treebank imports. `SOURCE_LICENSE` is the per-text license reported by GLAUx; it is distinct from the general corpus/release license.

| Work | GLAUx metadata ID | Source filename | Original text source | Source format | Annotation status | Per-text license | Full source SHA-256 |
|---|---:|---|---|---|---|---|---|
| Xenophon, *Anabasis* | 405 / `0032-006` | `xml/0032-006.xml` | Perseus | XML | Automatic; no manual treebank annotation listed | CC BY-SA 4.0 | `19588704269e06a28c9ef353266a4886266cf14578a8adee1ef1ebfc0fba3244` |
| Aristophanes, *Nubes* (*Clouds*) | 212 / `0019-003` | `xml/0019-003.xml` | Perseus | XML | Automatic; no manual treebank annotation listed | CC BY-SA 4.0 | `8a0f3f00cca66dd410efa8127a62d20baa1d8d20c9916239ef0f7a3e1a975596` |
| Marcus Aurelius Antoninus Imperator, *Τὰ εἰς ἑαυτόν* (*Meditations*) | 1618 / `0562-001` | `xml/0562-001.xml` | Perseus | XML | Automatic; no manual treebank annotation listed | CC BY-SA 4.0 | `029c752c71e4bc08fd9a83ea38f606dae6b63e7dcfeb33bc2be58a1945ad13d2` |

Relevant pinned `metadata.txt` fields are:

```text
GLAUX_TEXT_ID  TLG       AUTHOR_STANDARD                              TITLE_STANDARD       SOURCE   SOURCE_LICENSE   SOURCE_FORMAT   TREEBANK_ANNOTATIONS
212            0019-003  Aristophanes                                 Nubes                Perseus  CC BY-SA 4.0    XML             NA
405            0032-006  Xenophon                                     Anabasis             Perseus  CC BY-SA 4.0    XML             NA
1618           0562-001  Marcus Aurelius Antoninus Imperator          Τὰ εἰς ἑαυτόν       Perseus  CC BY-SA 4.0    XML             NA
```

## Frozen excerpts

Each excerpt contains complete opening GLAUx `<sentence>` elements. Artificial elliptic `E` nodes are counted separately from overt words and remain available to the model as structural evidence.

| Input | Selection | Overt words | Input SHA-256 |
|---|---|---:|---|
| `anabasis.xml` | Source sentences 1–9; sections 1.1.1–1.1.4 | 152 | `aa32be7e3bf41c0cfe0d5f9677cb569e9241bff06a6ba579ea87b5ea6e4d5aef` |
| `clouds.xml` | Source sentences 1–15; lines 1–20 | 142 | `28217450bece7526726a3d15047038987f7d611c64ba9d3c9897e687cc5ed71d` |
| `meditations.xml` | Source sentences 1–11; sections 1.1.1–1.6.1 | 144 | `e140ff962ab1b8706ce8e00380c478514fee2880b80fdd14076f8f85e8b54fc6` |

These sizes approximate the existing gloss experiments: the Xenophon gloss passage has 143 whitespace-delimited words, while the *Clouds* gloss passage covers the same opening lines 1–20. Every model directory contains byte-identical copies of all three frozen inputs.

## Experiment versions

### `experiment_1`

The first run sent each complete excerpt in one request and asked for a complete CoNLL-U file inside one JSON string. Its retained outputs are under each model’s `outputs/experiment_1/` directory. Claude Sonnet 4.6 and GPT-5.3 Codex returned multiline files. DeepSeek V4 Flash returned malformed or truncated one-line files. Qwen3.5 397B returned one malformed file and repeatedly failed at its pinned DeepInfra provider, so that arm is deprecated and excluded from future Kai tasks.

### `experiment_2`

The next run changes the harness while preserving the frozen excerpts and golden example:

- complete GLAUx sentences are greedily grouped and tail-rebalanced toward 30–50 overt words; the frozen excerpts produce Anabasis `[38,46,31,37]`, Clouds `[37,40,32,33]`, and Meditations `[45,40,29,30]`, where the indivisible sentence boundaries make the single 29-word shard unavoidable;
- shard boundaries and target order are deterministic and identical across systems;
- artificial elliptic nodes remain prompt context but are not overt output tokens;
- each response is structured as ordered sentence and token records rather than a JSON-escaped CoNLL-U string;
- `FORM`, source sentence identity, references, speakers, row ordering, and final serialization are tool-owned;
- bounded response validation checks sentence/token identity and coverage, local IDs, safe fields, head bounds, self-heads, cycles/connectivity, and one root before accepting a shard;
- completed shards are checkpointed independently with both the deterministic base request and the actual accepted retry request; resume revalidates every work and refuses stale or incomplete checkpoints;
- paid shard requests are paced by five seconds in addition to transport backoff; and
- accepted shards are deterministically assembled under `outputs/experiment_2/<work>.conllu`.

This bounded response validation is not a general CoNLL-U or UD linter. No corpus linting was added.

## Models and execution

Active experiment-2 systems are:

| Experiment directory | Fixed model ID | Provider pin | Reasoning |
|---|---|---|---|
| `deepseek-v4-flash-0731` | `deepseek/deepseek-v4-flash-0731` | OpenInference | enabled, excluded from returned content |
| `deepseek-v4-pro-0813` | `deepseek/deepseek-v4-pro-0813` | Fireworks | enabled, excluded from returned content |
| `glm-5.3` | `glm-5.3` | Fireworks | enabled, excluded from returned content |
| `claude-sonnet-4.6` | `anthropic/claude-sonnet-4.6` | Anthropic | disabled |
| `gpt-5.3-codex` | `gpt-5.3-codex` | OpenAI | disabled |

`qwen3.5-397b-a17b` is retained as deprecated experiment-1 provenance only. No other models were added.

The Roc runner retains the complete request body, raw response bytes containing the structured payload, selected decoded envelope fields, provider-resolved model and provider, token usage, cost, timestamps, elapsed time, finish reason, validation result, and every transport or bounded-response retry. Dry-run checks construct every shard request but do not read the API key or contact the provider.

```sh
kai run check-conllu-deepseek-v4-flash-0731-experiment
kai run check-conllu-deepseek-v4-pro-0813-experiment
kai run check-conllu-glm53-experiment
kai run check-conllu-claude-sonnet-46-experiment
kai run check-conllu-gpt53-codex-experiment
```

The corresponding full-run tasks without `check-` make paid model calls and require explicit authorization. Each active system also has a `smoke-conllu-…-experiment` task. A smoke task sends only the first deterministic Anabasis shard (38 overt words), retains normal request/response/cost/timing records, and writes its result under `outputs/experiment_2/smoke/<run-id>/` without occupying or overwriting the full-run output. Smoke run IDs cannot be resumed as full runs. The experiment-2 smoke test has not been run.
