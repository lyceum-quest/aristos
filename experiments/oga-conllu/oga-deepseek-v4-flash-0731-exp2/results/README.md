# Saved model results

Each tested generation model receives a directory named by its stable model ID. Commit-ready results retain:

- the final glossed CoNLL-U output for every complete attempt;
- translation-stage CoNLL-U output;
- exact gloss and translation configuration snapshots;
- small terminal responses for failed protocol attempts; and
- a model-level evaluation against `../inputs/meditations/meditations-gold.conllu`.

Large raw API responses, overwrite-prone scratch files, and JEV audit payloads remain under ignored `outputs/` and are not copied here.

## Cost and quality comparison

PPQ catalog rates captured 2026-09-21. Prices are USD per one million tokens; actual run cost depends on the input/output mix and retries.

| Model | Status | Input | Output | Input vs. Flash | Output vs. Flash | Best exact gloss match |
|---|---|---:|---:|---:|---:|---:|
| `deepseek/deepseek-v4-flash-0731` | Tested | $0.2321 | $0.6963 | 1.00× | 1.00× | 50/85 (58.8%) |
| `deepseek/deepseek-v4-pro-0813` | Tested | $1.3926 | $4.1778 | 6.00× | 6.00× | 52/85 (61.2%) |
| `claude-sonnet-5` | Selected pipeline; structured JSON | $2.1100 | $10.5500 | 9.09× | 15.15× | **73/85 (85.9%)** |
| `z-ai/glm-4.7` | Blocked: invalid token IDs | $0.4220 | $1.84625 | 1.82× | 2.65× | No complete output |
| `glm-5.3` | Blocked: mandatory reasoning | $1.4770 | $4.6420 | 6.36× | 6.67× | No output |

Claude Sonnet 5's catalog token rates are 51.5% higher for input and 152.5% higher for output than DeepSeek V4 Pro. Its best saved calibration result exceeds Pro's by 21 exact gloss matches and 24.7 percentage points, but model, protocol, prompt, and sampling/provider settings differ; this is not an isolated model-quality gain. GLM 4.7 costs 69.7% less for input and 55.8% less for output than DeepSeek V4 Pro, but its earlier plain-text attempts all failed strict token-ID validation. `glm-5.3` costs 6.1% more for input and 11.1% more for output than DeepSeek V4 Pro; PPQ rejected it because the current clients explicitly disable reasoning while that endpoint requires it. This table should be extended whenever another model is tested.

## Interpretation and next comparison

- Claude structured attempt 3 agrees on **73/85** real-token glosses, including six punctuation matches; excluding punctuation gives **67/79 (84.8%)**. Artificial rows are excluded and remain unglossed.
- Its prompt explicitly supplies several gold answers and token divisions. This is tuned, answer-bearing calibration on five blocks, not held-out accuracy. Sonnet is now the user-selected pipeline, but this score does not establish unseen-passage quality.
- Several of the 12 disagreements are defensible alternatives; others lose morphology or contextual relations. Prose generally preserves meaning, while literal translations retain substantial structural and idiomatic defects. See the [direct comparison](../../../../conllu/generated/claude-sonnet-5/structured-attempt-3/REVIEW.md).
- The table reports catalog token prices, not observed run spend or cost per accepted field. Unequal prompts, response lengths, failures, and retries prevent deriving those metrics from price ratios and exact matches alone.
- No additional paid attempt was made for this review. Claude's three structured attempts are exhausted; preserve earlier failures as well, rather than resetting the budget again. Future authorized comparisons should use a frozen shared prompt without target answers and untouched passages with separate gold.

## Model directories

- `deepseek-v4-flash-0731/`
- `deepseek-v4-pro-0813/`
- [Claude Sonnet 5 — selected pipeline](../../../../conllu/generated/claude-sonnet-5/): all saved attempts moved intact to the top-level generated corpus directory.
- `glm-4.7/`
- `glm-5.3/`
