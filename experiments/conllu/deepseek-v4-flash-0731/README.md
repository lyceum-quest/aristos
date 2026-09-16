# DeepSeek V4 Flash 0731 CoNLL-U experiment

Experiment 2 corrects and converts sentence-aligned shards from the byte-identical pinned GLAUx XML inputs documented in [`../README.md`](../README.md). Reasoning is enabled; structured records are validated and serialized by the Roc runner. Experiment-1 artifacts remain under `outputs/experiment_1/`.

Run `kai run check-conllu-deepseek-v4-flash-0731-experiment` to construct requests without API calls. The paid smoke task is `kai run smoke-conllu-deepseek-v4-flash-0731-experiment`; the paid full task is `kai run conllu-deepseek-v4-flash-0731-experiment`.
