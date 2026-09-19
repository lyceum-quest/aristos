We want to use deepseek flash v4 to:

Generate 3 glosses of Ancient Greek per-word (from the sample of the iliad in iliad.txt)
The glosses prefer to add inflection information when possible:

Below is a good example of the syntax of what the words should be because they give inflection/grammar info (not necessarily the definitions being accurate):

```txt
μῆνιν wrath
ἄειδε sing
θεὰ goddess
Πηληϊάδεω son-of-Peleus
Ἀχιλῆος of-Achilles

οὐλομένην, ruinous
ἣ which
μυρίʼ innumerable
Ἀχαιοῖς to-the-Achaeans
ἄλγεʼ griefs
ἔθηκε, she-set

πολλὰς many
δʼ and
ἰφθίμους valiant
ψυχὰς souls
Ἄϊδι to-Hades
προΐαψεν sent-ahead

ἡρώων, of-heroes
αὐτοὺς their-bodies
δὲ and
ἑλώρια as-prey
τεῦχε he-made
κύνεσσιν to-dogs

οἰωνοῖσί to-birds
τε and
πᾶσι, all
Διὸς Zeus's
δʼ and
ἐτελείετο was-being-fulfilled
βουλή, will

ἐξ from
οὗ when
δὴ then
τὰ the
πρῶτα first
διαστήτην they-separated
ἐρίσαντε having-quarreled

Ἀτρεΐδης Atreus'-son
τε and
ἄναξ king
ἀνδρῶν of-men
καὶ and
δῖος godlike
Ἀχιλλεύς. Achilles

τίς who
τʼ and
ἄρ [UNRESOLVED]
σφωε them-two
θεῶν of-the-gods
ἔριδι in-strife

```


These three glosses should then be passed to jev for selecting the best one.

OR, if this is more likely to get us accurate results, we should have deepseek generate one gloss per greek word, jev go through the result and accept/reject any invalid ones, THEN deepseek goes through again to fill the gaps on the rejected, then those are once again gone through by jev, and etc. for X number of iterations defined by the caller of the program.

We should just build a minimal harness in roc with basic-cli to call our ppq to do this with pinned reproducible providers.

The flow right now is kept simple:

1. call deepseek v4 flash to generate output like above, dead simple text file or maybe json is better:
2. call jev to make decisions about correct gloss for each. for single-generation route, just give some indicator of accuracy/close-enough validity.
3. final output file is generated of json which marks each as valid/invalid.

only two fields in the JSON like:

```
[
    {
        "word": "<greek word>",
        "gloss": "<english gloss>",
        "valid": <boolean>
    }
]
```
