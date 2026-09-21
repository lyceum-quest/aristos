# Meditations experiment input and gold

This directory contains:

- `tlg0562.tlg001.perseus-grc2.tok01_sentence-seg01_annotated_lemma.conllu`: the complete Marcus Aurelius *Meditations* input copied from Opera Graeca Adnotata v0.2.0. Its source tokenization and annotations are not edited here.
- `meditations-gold.conllu`: hand-authored gold output for the first five CoNLL-U sentence blocks only.

The gold file has the same shape produced by `kai workflow meditations`:

- `sentence_id`, `translation_lang`, `prose_translation`, and `literal_translation` comments precede each block;
- each source-token row has one `gloss` field (with the workflow's lowercase key) in `MISC`; proper-name values retain capitalization;
- artificial rows whose original `MISC` value begins with `e_` remain unglossed; and
- punctuation receives its punctuation character as its gloss.

## Gold scope

Only fields touched by the current workflow are gold: prose translations, literal translations, and contextual glosses. The gold file deliberately preserves every other source field verbatim and makes no judgment about OGA lemmas, morphology, dependencies, artificial rows, or segmentation.

Glosses give one concise contextual contribution rather than a dictionary sense list. They express material morphology or syntax when English needs it, such as `begot-[me]`, `of-that-kind`, `far-from`, `to-attend`, `one-must`, and `to-spend`. Hyphens replace spaces within a gloss. Brackets mark words supplied to expose Greek ellipsis in a literal rendering.

The prose translation prioritizes accurate, idiomatic English. The literal translation remains intelligible while preserving Greek ellipsis, structure, lexical contributions, and materially relevant morphology. Because OGA splits *Meditations* 1.3 into two blocks, sentence 4's prose translation restores its immediately preceding subject (“my mother”), while its literal translation marks supplied wording in brackets.

The source file is the experiment input. Do not modify the separately installed OGA corpus under `../OGA/opera_graeca_adnotata_v0.2.0`.
