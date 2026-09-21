# GLM 5.3 — Meditations result

Model: `glm-5.3`

Dataset: the first five CoNLL-U blocks in `../../inputs/meditations/meditations-gold.conllu`.

## Attempt 1

The workflow made no successful model call. PPQ rejected all three bounded translation-call attempts with HTTP 400:

> Reasoning is mandatory for this endpoint and cannot be disabled.

The current Roc clients unconditionally send `reasoning.enabled = false`. Supporting this model would therefore require changing request construction in maintained Roc code, not merely changing model, prompt, or sampling parameters in the JSON configs. That falls outside this experiment's config-only boundary.

`attempt-1-endpoint-failure/` preserves the exact generation configs and provider error response. No semantic output or gold score exists for this model.
