# Claude Sonnet 5 — Meditations results

Model: `claude-sonnet-5`

Dataset: the first five CoNLL-U blocks in `../../inputs/meditations/meditations-gold.conllu`.

## Structured rerun

The semantic clients now send real tokens and omitted structure separately as JSON, request JSON output, parse typed objects, and validate the returned token IDs before merging. PPQ exposed no Claude endpoint for strict `json_schema`, so these runs used provider JSON-object mode plus the same exact local field and ID validation.

| Attempt | Prompt | Result | Exact gloss match |
|---|---|---|---:|
| 1 | General work context and morphology guidance | Complete | 53/85 (62.4%) |
| 2 | Stronger abstract-quality, alignment, prose, and literal style | Complete | 62/85 (72.9%) |
| 3 | Calibration-specific idiom division and educational style | Complete; best | **73/85 (85.9%)** |

Attempt 3 exact gloss matches by sentence:

| Sentence | Exact | Total |
|---|---:|---:|
| 1 | 9 | 9 |
| 2 | 12 | 14 |
| 3 | 21 | 22 |
| 4 | 11 | 13 |
| 5 | 20 | 27 |

No prose or literal translation exactly matched the gold wording, but prose meaning was generally strong. Remaining gloss disagreements are concentrated in the father participle, two-word connective and prepositional relations, and the education sentence. Some are defensible wording alternatives; others still misalign or over-realize morphology. Literal translations remain less reliable than prose.

Each structured attempt preserves the final glossed output, translation-stage output, and exact configs.

## Earlier plain-text attempts

Before the protocol change, no attempt completed the first sentence:

| Attempt | Prompt change | Terminal failure |
|---|---|---|
| 1 | DeepSeek Pro's best work-context prompts | Returned PROSE and LITERAL on one line instead of two |
| 2 | Required exactly one newline and two tabs | Inserted a blank line between PROSE and LITERAL |
| 3 | Explicitly prohibited the blank line | Translation passed; glossed artificial ID 9 and omitted punctuation ID 10 |

Those failure directories preserve their exact configs and terminal responses.
