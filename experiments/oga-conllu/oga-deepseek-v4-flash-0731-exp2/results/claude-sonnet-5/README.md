# Claude Sonnet 5 — Meditations results

Model: `claude-sonnet-5`

Dataset: the first five CoNLL-U blocks in `../../inputs/meditations/meditations-gold.conllu`.

## Attempts

No config-only attempt completed the first sentence:

| Attempt | Prompt change | Terminal failure |
|---|---|---|
| 1 | DeepSeek Pro's best work-context prompts | Returned PROSE and LITERAL on one line instead of two |
| 2 | Required exactly one newline and two tabs | Inserted a blank line between PROSE and LITERAL |
| 3 | Explicitly prohibited the blank line | Translation passed; glossed artificial ID 9 as `[I-learned]` and omitted punctuation ID 10 |

The first-sentence prose translation in attempt 3 was accurate and nearly identical to the gold, but the workflow correctly rejected the gloss patch. No complete five-block output or gold score exists.

Each attempt preserves its exact configs and terminal response. Attempts 1 and 2 also retain the small provider response proving the formatting failure; attempt 3 retains the accepted partial translation block and rejected gloss response.
