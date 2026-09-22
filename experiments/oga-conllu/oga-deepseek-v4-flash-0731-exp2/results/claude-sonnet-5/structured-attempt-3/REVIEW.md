# Structured attempt 3 — direct gold comparison

This is a no-spend, AI-assisted review of the saved `output.conllu` against `../../../inputs/meditations/meditations-gold.conllu`. Judgments are provisional, not blinded philological adjudication. Neither file nor the saved prompts has been changed. Only contextual glosses and the two translation layers are evaluated; inherited OGA analysis is not gold.

## Exact agreement

| Block | All real tokens | Excluding punctuation |
|---|---:|---:|
| 1 | 9/9 | 8/8 |
| 2 | 12/14 | 11/13 |
| 3 | 21/22 | 19/20 |
| 4 | 11/13 | 10/12 |
| 5 | 20/27 | 19/26 |
| **Total** | **73/85 (85.9%)** | **67/79 (84.8%)** |

All six punctuation glosses match. The five artificial rows remain unglossed and are excluded. Exact disagreement is not itself semantic rejection; phrase-level problems can affect multiple token scores.

## Remaining gloss disagreements

IDs below are `sentence_id.token ID`, not the global `t_` identifiers. The table includes every exact disagreement.

| ID | Gold | Output | Provisional assessment |
|---|---|---|---|
| 2.8 | `the-one-who` | `the` | Defensible with a nominal rendering of the next token; assess the pair together. |
| 2.9 | `begot-[me]` | `[father]` | Correct referent, but loses participial morphology and marks the entire overt contribution as supplied. |
| 3.9 | `abstinence` | `refraining` | Defensible contextual alternative. |
| 4.2 | `and` | `then` | Possible discourse alternative, but less clearly additive here; also misses the explicit prompt instruction. |
| 4.9 | `far-from` | `far` | Omits the complement relation; no following gloss supplies `from`. |
| 5.6 | `to` | `into` | Directional alternative, but mechanically spatial with `to-attend`. |
| 5.14 | `at` | `with-regard-to` | Wrong contextual sense for κατʼ οἶκον, “at home.” |
| 5.15 | `home` | `house` | Lexically defensible alone, but the two-token output fails the idiom. |
| 5.19 | `to-know` | `to-recognize` | Defensible; gold prose itself uses “recognize.” |
| 5.21 | `on` | `to` | Misses the contextual relation in spending on something. |
| 5.23 | `such-things` | `of-that-kind` | Hides the substantival plural contribution; unlike 3.21, this is not an adjective modifying an overt noun. |
| 5.26 | `to-spend` | `to-be-spending` | Possible aspectual rendering, but unnecessarily progressive for the general lesson. |

## Translation review

Prose generally preserves meaning. Blocks 1–3 and 5 retain the elliptical list rather than the prompt's requested complete first-person sentences; that is not by itself a mistranslation. Block 4 correctly restores the mother. Block 5's perfect infinitives depart from the requested timeless-lesson reading and need review.

Literal translations remain the weaker layer:

- Blocks 1–2 use “the good-charactered,” “the unangered,” and “the modest and the manly” rather than intelligible abstract qualities. Supplied `my` is unbracketed in blocks 1 and 3.
- Block 3's “coming to be of such a thought” distorts the construction that the gold renders “coming to a thought of that kind.”
- Block 4's “the simple [she taught] according to the manner-of-living” obscures the quality and its relation to lifestyle; it is not merely different wording.
- Block 5 has perfect infinitives despite the explicit instruction against them, “attended into,” “according to house,” and spending “into such things.” These are structural and idiomatic defects, not fluency-only differences.

No translation accuracy percentage or semantic acceptance score is inferred from exact wording.

## Limits and next comparison

The saved gloss prompt explicitly supplies multiple gold answers and their token divisions. The translation prompt also supplies passage-specific interpretation and wording. This is answer-bearing calibration, not independent evaluation. The 85.9% result demonstrates agreement after tuning on these five blocks; it does not estimate performance on unseen Greek.

Comparisons with DeepSeek additionally vary protocol, prompt, and sampling/provider settings. Claude uses JSON-object mode, allows provider fallback, and omits temperature; a stored `temperature: 0` does not make this a temperature-zero run. Historical DeepSeek runs used the plain-text protocol. Catalog token prices alone do not establish cost per accepted gloss.

Do not run a fourth Claude prompt attempt. A future authorized comparison should freeze a shared, non-answer-bearing prompt and use untouched passages with separate gold. Preserve the present calibration results unchanged; do not silently relabel them as held-out scores or reset an exhausted model budget for a new protocol.
