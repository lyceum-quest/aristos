# DeepSeek V4 Flash 0731 — Meditations results

Model: `deepseek/deepseek-v4-flash-0731`

Dataset: the first five CoNLL-U blocks in `../../inputs/meditations/meditations-gold.conllu`.

## Best complete run

`best-complete-run/output.conllu` is the only attempt that completed translation, glossing, and audit for all five blocks. `translations.conllu` preserves the translation-stage output before gloss insertion, and the two JSON files snapshot the exact generation configs.

Exact contextual-gloss match against the hand-authored gold:

| Sentence | Exact | Total |
|---|---:|---:|
| 1 | 8 | 9 |
| 2 | 8 | 14 |
| 3 | 10 | 22 |
| 4 | 7 | 13 |
| 5 | 17 | 27 |
| **Total** | **50 (58.8%)** | **85** |

No prose or literal translation exactly matched the gold. Sentence 1 prose was close. Sentence 2 was structurally misparsed. Sentences 3–5 retained much of the meaning but required correction, and none of the literal translations met the gold standard.

## Protocol failures

The two directories under `protocol-failures/` preserve later context-enriched prompts and their terminal model responses. Both prompts improved the first translation, but the model renumbered the punctuation token after omitting artificial row 9. The pipeline correctly rejected each response because source token 10 had no gloss.

Large provider responses and JEV audit payloads remain ignored under `outputs/`; this directory retains the small semantic artifacts and exact configs needed for review and comparison.
