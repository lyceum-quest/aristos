# DeepSeek V4 Pro 0813 — Meditations results

Model: `deepseek/deepseek-v4-pro-0813`

Dataset: the first five CoNLL-U blocks in `../../inputs/meditations/meditations-gold.conllu`.

## Attempts

| Attempt | Prompt | Result | Exact gloss match |
|---|---|---|---:|
| 1 | Concise structural prompt used by the best Flash run | Complete | 49/85 (57.6%) |
| 2 | Added *Meditations* Book 1 work context and morphology guidance | Complete; best overall | 52/85 (61.2%) |
| 3 | Added more explicit token-alignment and translation-style constraints | Rejected: punctuation ID 10 was renumbered as 9 | — |

Attempt 2 exact gloss matches by sentence:

| Sentence | Exact | Total |
|---|---:|---:|
| 1 | 7 | 9 |
| 2 | 8 | 14 |
| 3 | 12 | 22 |
| 4 | 7 | 13 |
| 5 | 18 | 27 |

No prose or literal translation exactly matched the gold. Exact matching understates the prose improvement: attempt 2 correctly recovered the elliptical lesson frame in sentences 2, 3, and 5, where the context-free systems often misparsed the clauses. Sentence 4 and the literal layer still need substantial editing. Gloss errors remain concentrated in token alignment, substantivized qualities, implicit possession, and multi-token idioms.

Compared with Flash's best 50/85, Pro gained two exact glosses (+2.4 percentage points) while costing 6× as much at the current PPQ rates. Its larger improvement was qualitative prose accuracy rather than exact gloss agreement.

Each complete attempt preserves `output.conllu`, the translation-stage `translations.conllu`, and exact generation configs. The failed attempt preserves its partial translation and terminal gloss response. Large provider and JEV payloads remain ignored under `outputs/`.
