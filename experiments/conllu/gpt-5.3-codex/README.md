# GPT-5.3 Codex CoNLL-U experiment

Experiment 2 corrects and converts sentence-aligned shards from the byte-identical pinned GLAUx XML inputs documented in [`../README.md`](../README.md). Structured records are validated and serialized by the Roc runner. Experiment-1 artifacts remain under `outputs/experiment_1/`.

Run `kai run check-conllu-gpt53-codex-experiment` to construct requests without API calls. The paid smoke task is `kai run smoke-conllu-gpt53-codex-experiment`; the paid full task is `kai run conllu-gpt53-codex-experiment`.
