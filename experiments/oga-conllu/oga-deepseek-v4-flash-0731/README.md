# OGA semantic-overlay experiment: DeepSeek V4 Flash 0731

This experiment reads the locally installed Opera Graeca Adnotata v0.2.0 CoNLL-U files for the same Anabasis, Clouds, and Meditations excerpts used by the earlier GLAUx experiment. It preserves every OGA row and structural field, then asks DeepSeek V4 Flash only for contextual token glosses and prose/literal sentence translations. The runner appends those fields and the configured Lyceum-style provenance metadata deterministically.

The OGA source files are selected by exact filename and SHA-256 in `config.json`. Artificial `e_` rows remain context but receive no gloss. No OGA linguistic annotation is corrected or regenerated.

`kai run check-oga-conllu-deepseek-v4-flash-0731-experiment` validates and constructs every request without reading the API key or making a model call. `kai run smoke-oga-conllu-deepseek-v4-flash-0731-experiment` is the paid first-shard test. `kai run oga-conllu-deepseek-v4-flash-0731-experiment` is the paid full run.

No model run has been made for this experiment.
