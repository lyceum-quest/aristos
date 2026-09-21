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
| `glm-5.3` | Blocked: mandatory reasoning | $1.4770 | $4.6420 | 6.36× | 6.67× | No output |

`glm-5.3` costs 6.1% more for input and 11.1% more for output than DeepSeek V4 Pro. PPQ rejected the config-only attempt because the current clients explicitly disable reasoning while this endpoint requires it. This table should be extended whenever another model is tested.

## Model directories

- `deepseek-v4-flash-0731/`
- `deepseek-v4-pro-0813/`
- `glm-5.3/`
