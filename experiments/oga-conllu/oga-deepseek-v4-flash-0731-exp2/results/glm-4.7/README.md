# GLM 4.7 — Meditations results

Model: `z-ai/glm-4.7`

Dataset: the first five CoNLL-U blocks in `../../inputs/meditations/meditations-gold.conllu`.

## Attempts

GLM 4.7 accepted requests with reasoning disabled, but none of three config-only attempts produced a valid first gloss patch:

| Attempt | Prompt | Terminal failure |
|---|---|---|
| 1 | DeepSeek Pro's work-context prompt | Omitted source ID 10 and renumbered punctuation as 9 |
| 2 | Shorter successful Flash prompt | Omitted source ID 10 and renumbered punctuation as 9 |
| 3 | Short prompt plus explicit per-sentence ID allowlists | Duplicated ID 7, assigned punctuation to ID 8, and also returned ID 10 |

Every attempt preserves its exact configs, terminal gloss response, and the one completed translation block. The translations were broadly intelligible, but the workflow correctly rejected each gloss response before a complete five-block result existed. No gold score is reported.

Unlike `glm-5.3`, this model is operationally compatible with reasoning disabled. Its blocker is strict token-ID adherence under the current direct text protocol.
