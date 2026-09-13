# UD Ancient Greek PTNK Genesis data

`genesis-data.js` is generated from the Genesis portion of
[UD Ancient Greek PTNK](https://github.com/UniversalDependencies/UD_Ancient_Greek-PTNK)
at commit `818fb315ff1f6cd95b6e7fa90f3707488d2b010d`.

The bundle contains all 1,491 Genesis sentence records (chapters 1–50), with
37,106 tokens from the Septuagint according to Codex Alexandrinus. It preserves:

- Greek forms and sentence text;
- lemmas and universal parts of speech;
- morphological feature bundles;
- dependency heads and relations;
- contextual gloss fields; and
- source spacing.

The treebank describes its lemmas, morphology, and relations as annotated data.
Its introduction notes that initial syntactic relations were projected from a
parallel Ancient Hebrew treebank, then systematically and manually corrected.
Aristos therefore presents dependency analyses as attributed references rather
than unquestionable answers.

The source does not include an aligned English translation. Aristos permits
learner-authored literal and prose drafts for these passages, but does not show
or score a translation reference.

## Rebuild

```sh
python scripts/import-ptnk-genesis.py /path/to/UD_Ancient_Greek-PTNK
```

The importer verifies the expected chapter and sentence counts before replacing
the browser bundle.

## License and attribution

The source treebank and this extracted data bundle are licensed under the
Creative Commons Attribution-ShareAlike 4.0 International license. See
`LICENSE.txt` and the upstream README for attribution and citation details.
