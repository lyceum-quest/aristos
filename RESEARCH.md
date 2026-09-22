# Research: agents, Jev, and simpler tooling for an optimal Ancient Greek learning corpus

## Question

How can Aristos use agents, Jev, existing corpora, and simpler deterministic/NLP tools to build a comprehensive, auditable Ancient Greek dataset with highly accurate CoNLL-U, contextual token glosses, literal translations, and prose translations—useful both for scholarship and, primarily, student learning?

Research date: 2026-09-21.

## Executive recommendation

Do **not** make a society of agents the core corpus generator. Make the core a **reuse-first, candidate-lattice corpus compiler**:

1. import the strongest licensed text, morphology, syntax, translation, and lexical evidence available;
2. preserve all candidates and provenance instead of prematurely selecting one truth;
3. use deterministic constraints and specialized parsers for structure;
4. use a cheap generative model only for missing semantic layers;
5. use Jev as a typed decision and routing plane, not as a generator or gold annotator;
6. send disagreements and high-impact uncertainty to blinded human review;
7. turn accepted corrections into translation memory, reusable rules, retrieval examples, and eventually task-specific models; and
8. publish confidence/review tiers so student-facing defaults can be stricter than scholarly exploratory access.

The highest-value near-term experiment is simpler than another agent loop: **select complete lemma+morphology bundles from analyzers that actually expose such candidates, instead of asking Jev to independently invent every feature**. Lemma-only tools remain lemma evidence; occurrence annotations remain occurrence evidence. The second experiment is **translation/gloss memory over reviewed parallel examples**. The third is **active, risk-weighted human correction of parser/model disagreements**.

Agents are most valuable around this compiler as bounded specialists: source/licensing scouts, evidence retrievers, error critics, review-packet builders, and correction-pattern miners. They should propose immutable patches and evidence, never rewrite canonical files directly.

## Repository findings

### Strong foundations already present

- The architecture already separates tool-owned structure from model-owned semantic patches: `docs/plans/conllu-data-pipeline/README.md`.
- The planned canonical profile correctly distinguishes contextual `Gloss`, lexical `LexGloss`, prose `text_en`, and literal `text_en_literal`.
- The project already recognizes separate citation, syntactic, source, and reading segmentations.
- The current OGA loop is resumable by sentence and separates translation, gloss, Jev audit, and bounded improvement: `experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/src/loop.roc`.
- Experiment 4 correctly separates candidate generation, independent Jev Noul judgments, provider identity, cost accounting, and blinded human evaluation: `experiments/gloss/deepseek-v4-flash-0731/experiment_4/README.md`.
- The learning design is unusually strong: capability-derived activities, immutable attempts, delayed unseen transfer, and no false automatic grading of arbitrary translations: `docs/plans/composable-reading-workspace/README.md` and `VALIDATION.md`.

### Current evidence does not yet establish production accuracy

- On the five-sentence *Meditations* gold fixture, the best saved DeepSeek Flash and Pro runs exactly match only 50/85 (58.8%) and 52/85 (61.2%) contextual glosses. Exact match understates synonym quality, but neither result demonstrates student-safe semantic accuracy.
- No saved generated prose or literal translation exactly matches gold; the result notes report substantial semantic and structural corrections.
- The recorded PPQ input and output unit rates for Pro were 6× Flash for only two additional exact gloss matches in the current small test. This is not a measured 6× end-to-end run cost. Pro's larger observed benefit was qualitative prose recovery, not token-gloss accuracy.
- Model-generated token identity remains fragile: later prompts omitted an artificial row and renumbered punctuation. This validates the project rule that models must never own IDs or serialization.
- Experiment 4 has a strong evaluation harness but no scored experiment-4 provider run yet. Its example evaluation correctly reports `N/A` rather than manufacturing results.
- A single Jev threshold of 0.5 remains uncalibrated. Noul probabilities are useful routing signals, not proof of correctness.

Sources: `experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/results/README.md`, model result READMEs, and `experiments/gloss/deepseek-v4-flash-0731/experiment_4/RESEARCH.md`.

### Important design tension

A scholarly dataset should preserve ambiguity, alternate analyses, textual variants, source schemes, and disagreements. A beginner-facing reference often needs one concise default. Do not resolve this tension by flattening both into one CoNLL-U value.

Use:

- canonical CoNLL-U for one selected interoperable analysis;
- a manifest for layer-specific provenance, license, confidence, and review state;
- sidecars for candidate lattices, alternate analyses, word/phrase alignments, textual variants, and reviewer disagreements; and
- a learner overlay for the selected contextual gloss, accepted alternatives, literal/prose references, and concise explanations.

## Three viable approaches

### Option 1: reuse-first candidate lattice with active human correction — recommended

For each token or sentence, collect candidates from extant reviewed treebanks, OGA/GLAUx, a current parser, morphology analyzers, lexica, aligned translations, and model proposals. Select or abstain using deterministic constraints, calibrated Jev decisions, and human review.

**Pros**

- Preserves existing scholarship and source disagreement.
- Minimizes generation, cost, and hallucination risk.
- Makes uncertainty and provenance inspectable.
- Human corrections compound: one corrected recurring form, construction, or formula can improve many occurrences.
- Supports strict student-facing release gates without hiding scholarly alternatives.

**Cons**

- Requires alignment, adapters, license tracking, and conflict policy.
- Coverage and quality vary by work, genre, dialect, and layer.
- A canonical UD choice still requires scholarly decisions when source schemes disagree.

**Best use**: production corpus compiler.

### Option 2: verifier-gated model cascade

A cheap model proposes only missing fields. Deterministic validation and Jev dimensional checks accept, retry, escalate to a stronger model, or route to a human.

```text
reuse/import
  → cheap patch
  → deterministic validation
  → Jev field-specific checks
  → accept | focused repair | strong-model escalation | human review
```

This closely matches TypeSafe's published structured-data-extraction cascade: cheap extraction, per-field Jev verification, expensive escalation only when verifier signals fire.

**Pros**

- Directly extends the current DeepSeek/Jev experiments.
- Can lower expensive-model calls and review volume.
- Failures are localized to fields or dimensions.

**Cons**

- A verifier can share the generator's blind spots.
- Threshold errors can silently auto-accept wrong annotations.
- Repeated generation/audit loops can cost more than one human correction.
- It does not create independent evidence by itself.

**Best use**: filling semantic gaps after Option 1, never replacing gold review.

Source: [TypeSafe SDE cascade](https://docs.typesafe.ai/cookbooks/sde_cascade).

### Option 3: multi-agent committee or debate

Independent morphology, syntax, lexical-sense, literal-translation, and prose-translation agents propose or criticize annotations; a deterministic aggregator or human adjudicates.

**Pros**

- Specialized prompts expose distinct error modes.
- Heterogeneous models may provide genuinely independent evidence.
- Useful for difficult passages and adjudication packets.

**Cons**

- Expensive and operationally complex.
- Same-family agents are correlated, not independent annotators.
- Debate can reward persuasive explanations rather than correct philology.
- Agent-generated explanations can anchor human reviewers. CHI 2024 found wrong LLM labels hurt human accuracy, and explanations did not repair that harm.
- More calls do not solve absent source evidence or bad tokenization.

**Best use**: a small, high-risk review tier—not bulk generation.

Sources: [Wang et al. 2024](https://dl.acm.org/doi/10.1145/3613904.3641960), [MEGAnno+](https://aclanthology.org/2024.eacl-demo.18), and [agent-as-judge survey](https://arxiv.org/abs/2508.02994).

## High-value Jev applications

Jev is not a generative or coding agent. It is a fast typed decision model returning Choice, Score, or Noul outputs. Its best role is to control a larger deterministic or agentic workflow.

| Published Jev pattern | Aristos application | Priority |
|---|---|---:|
| Pre-parsed extraction: code over-finds candidates, Jev selects or `none` | Candidate-producing analyzers supply exact normalized analyses; Jev selects a complete bundle or `none` | Highest |
| SDE cascade | Keep cheap gloss/translation output only when calibrated checks pass; otherwise escalate | Highest |
| Re-ranking | Retrieve reviewed examples or translation-memory candidates, then rerank for this occurrence | Highest |
| Hierarchical classification | Classify an error first as lexical/morphological/syntactic/alignment/discourse, then ask narrower subtype questions | High |
| Confidence-gated routing | Auto-accept, second-model review, expert review, or abstain based on calibrated per-layer policy | High |
| Structure recovery | Decide uncertain sentence/line/TEI break joins before parsing while retaining source milestones | Medium |
| Speculative fan-out | Ask cheap atomic checks in one call; code retains only checks applicable after deterministic POS/class routing | Medium |
| Composite scoring | Rank review priority from semantic risk dimensions, while preserving each dimension separately | Medium |
| Skill suggestion / two-stage retrieval | Retrieve a wide set of similar reviewed constructions, carry a small shortlist into generation or review | Medium |
| Self-consistency testing | Measure Jev's own run-to-run stability near routing thresholds | Required for calibration |

Official sources:

- [TypeSafe primitives](https://docs.typesafe.ai/primitives)
- [Patterns](https://docs.typesafe.ai/patterns)
- [Pre-parsed value extraction](https://docs.typesafe.ai/cookbooks/pre_parsed_value_extraction_cookbook)
- [Re-ranking](https://docs.typesafe.ai/cookbooks/rerank_typesafe)
- [Hierarchical classification](https://docs.typesafe.ai/cookbooks/hierarchical_classification)
- [Structure recovery](https://docs.typesafe.ai/cookbooks/autoformat)
- [Parallel questions](https://docs.typesafe.ai/cookbooks/parallel_questions)
- [Self-consistency for Nouls](https://docs.typesafe.ai/cookbooks/consistency_noul_cookbook)
- [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13)

### 1. Choose analyzer bundles, not independent morphology features

Current plans improve over free generation by splitting POS/classification from applicable feature questions. A stronger and simpler production design is:

1. Candidate-capable morphology analyzers return complete candidate analyses; imported treebanks/OGA contribute exact occurrence analyses only where edition/token alignment is verified; lemma models such as GreTa contribute lemma evidence only.
2. Normalize only complete analyses into the Aristos morphology profile, retaining source capability, revision, license, and derivation lineage.
3. Remove impossible and duplicate bundles deterministically.
4. Ask one Jev Choice over complete bundles plus `none_of_candidates`.
5. Route low-confidence or `none` cases to another analyzer or human.

Before this experiment, build a source-capability matrix: arbitrary-text inference, lemma candidates, complete morphology bundles, UPOS, dependencies, confidence, annotation scheme, license, and supported dialects. Do not infer capabilities from a tool's general description.

This prevents impossible cross-products such as a finite verb with participial case features. It also lets Jev do what its extraction cookbook recommends: select among exact pre-parsed values rather than generate strings. Ask independent feature questions only when no analyzer supplied the correct bundle or when adjudicating one disputed feature.

### 2. Use a global dependency decoder

Do not independently accept each proposed head and then repeatedly repair cycles. Build arc candidates from:

- imported reviewed trees;
- OGA/GLAUx;
- a UD-native parser;
- a second parser or model; and
- rule-based exclusions.

Jev or a specialist model scores only plausible head/relation candidates. A deterministic **root-constrained** maximum-spanning-arborescence decoder—enumerating the root candidate or otherwise enforcing exactly one artificial-root edge—then proposes one acyclic tree, with labeled-arc compatibility checks. This is a hypothesis to compare with whole-tree repair, not a quality guarantee. Candidate recall and held-out LAS still determine quality; the decoder must abstain when candidate coverage is inadequate, and a valid tree is not necessarily the right tree.

### 3. Calibrate by dimension and stratum

Do not use one threshold across morphology, gloss lexical sense, gloss grammar, prose accuracy, literal structure, Homer, Genesis, and technical prose.

For each decision head:

- preserve raw probabilities;
- create calibration curves on human labels;
- measure precision among auto-accepted items, recall/coverage, and review savings;
- stratify by genre, dialect, token class, frequency, and source provenance;
- create an uncertainty band rather than a knife-edge threshold; and
- recheck calibration after a Jev version change.

Choice `confidence` describes distribution concentration, not correctness. Noul has no separate confidence field. Repeated consistency also does not prove correctness.

### 4. Rerank retrieved evidence, not three invented synonyms

For a token occurrence, retrieve reviewed examples by:

```text
lemma + FEATS + UPOS + governor lemma + DEPREL
+ dependents/particles + author/genre/dialect + local phrase
```

Candidate glosses should come from reviewed occurrences, aligned translations, and lexica before a generator invents alternatives. Jev can rerank exact candidates and select `none`. This creates a corpus-specific translation memory whose value increases with every human correction.

### 5. Use Jev to route review, not certify scholarship

Jev can answer atomic questions such as:

- Is this candidate directly supported by the retrieved occurrence?
- Does the gloss absorb meaning belonging to a neighboring token?
- Does the literal translation omit this aligned Greek contribution?
- Is the prose translation fluent but semantically incomplete?
- Does this proposed edge conflict with the selected clause structure?

The result determines the next workflow step. It should not change `reviewStatus` to `human-reviewed`.

## Innovative bounded-agent workflows

### A. Evidence scout → proposal → independent critics → review packet

For difficult items:

1. **Evidence scout agent** retrieves exact CTS passages, parallel translations, dictionary entries, reviewed analogues, and parser alternatives. It may not propose a final value without citations.
2. **Proposal agent** produces a token-ID-keyed patch from that evidence.
3. **Independent critics** inspect one layer each: lexical sense, morphology, syntax/alignment, literal completeness, prose accuracy.
4. **Deterministic code** rejects structural violations and compiles disagreements.
5. **Review-packet agent** summarizes only the unresolved alternatives and cited evidence for a human.
6. The human decision becomes an immutable correction overlay.

Keep critics independent; do not show them the other agents' rhetoric before their first judgment.

### B. Counterexample agent

Instead of asking “is this right?”, ask an agent to find the strongest corpus counterexample:

- same form with a different lemma;
- same construction with another head relation;
- a translation where the proposed gloss fails;
- an omitted particle or argument;
- another reviewed source analysis.

This adversarial retrieval is more useful than free-form debate because it must return inspectable evidence.

### C. Correction-pattern miner

After human corrections accumulate, an agent clusters them and proposes:

- deterministic Grew/validation queries;
- translation-memory rules;
- author/genre-specific gloss conventions;
- missing lexical candidates;
- new benchmark strata; and
- annotation-guide clarifications.

A proposed rule is developed on correction data, regression-tested against existing reviewed data, and evaluated once on an untouched source- and author-stratified holdout before use. It never mass-edits canonical data directly.

### D. Source and license scout

An agent can discover candidate editions, treebanks, translations, and exact revisions. It should emit a manifest draft containing URLs, hashes, CTS identities, declared licenses, and unresolved rights questions. Deterministic tooling must verify every URL/CTS URN, quoted span, source revision/hash, edition alignment, and declared license before the evidence enters a review packet. A human must approve edition identity and redistribution rights. “Ancient author” does not imply the digital edition, translation, or annotation is public domain.

### E. Learner-error-to-corpus feedback agent

Learner disagreement notes can identify likely corpus defects, but learner answers are not corrections. An agent can cluster repeated disagreements by token/construction and create a curator queue. This turns the educational application into a conservative error-discovery channel without silently learning from student mistakes.

## Simpler tools likely to beat agents

### Existing structural data and models

1. **Opera Graeca Adnotata (OGA)** should be the broad automatic base where edition and license fit. Its published model scores—POS 96.41, FEATS 94.77, UAS 82.60, LAS 77.10, lemma 91.41—show both its value and why it is not student-facing gold without correction.
2. **Reviewed treebanks first**: UD Ancient Greek Perseus, PROIEL, PTNK, original AGDT/PROIEL, and Gorman's prose trees. Preserve native annotation and conversion provenance.
3. **Current OGA models**: Trankit was strongest for syntax and GreTa for lemmas in Celano's 2025 comparison. Benchmark their released artifacts against UD-native Stanza/Trankit models on Aristos strata before choosing.
4. **Morpheus** is valuable as a high-recall morphology/lemma candidate generator, not a contextual selector.
5. **GLAUx** supplies broad automatic morphology/lemmas/dependencies and useful independent disagreement signals, but its original parser models were not released and its scheme requires explicit mapping.

A capability audit should verify exact released artifacts rather than relying on names. The expected starting matrix is:

| Source/tool | Expected role | Do not assume |
|---|---|---|
| Morpheus | lemma + morphology candidate analyses for a form | contextual disambiguation or dependencies |
| GreTa | contextual lemma prediction | complete morphology bundles or dependencies |
| OGA corpus | one automatic occurrence analysis for aligned corpus tokens | alternative candidates, UD-native labels, or reviewed gold |
| OGA Trankit parser artifact | arbitrary-text POS/morphology/syntax inference if the released model can be pinned and run | UD output or learner-safe accuracy |
| Reviewed treebank | occurrence analysis for its exact edition/token span | arbitrary-text inference or error-free truth |
| UD-native Stanza/Trankit model | UD candidate analysis | superiority across all Ancient Greek genres |

Sources:

- [OGA repository and published scores](https://github.com/OperaGraecaAdnotata/OGA)
- [Celano 2025 parser/lemmatizer comparison](https://aclanthology.org/2025.lm4dh-1.5)
- [Morpheus](https://github.com/perseids-tools/morpheus)
- [GLAUx](https://github.com/alekkeersmaekers/glaux)
- [UD Ancient Greek overview](https://universaldependencies.org/grc/)
- [UD Perseus](https://github.com/UniversalDependencies/UD_Ancient_Greek-Perseus)
- [UD PROIEL](https://universaldependencies.org/treebanks/grc_proiel/)
- [Gorman prose treebanks](https://openhumanitiesdata.metajnl.com/articles/10.5334/johd.13)

### Translation alignment before generation

Ancient Greek–English/Portuguese/Latin word-alignment gold datasets already exist, with expert guidelines and reported inter-annotator agreement above 80%. Use them to evaluate an aligner and to define Aristos alignment policy.

For licensed parallel translations:

1. align by CTS span;
2. run phrase/word alignment;
3. derive contextual gloss candidates;
4. retain one-to-many and null alignments;
5. send particles, articles, ellipsis, idioms, and alignment disagreements to review; and
6. store alignment stand-off rather than forcing it into one MISC field.

This is a better source of gloss candidates than unconstrained model invention. Translation-derived candidates are still not gold. Ancient Greek WSD work shows that parallel-text alignment can generate substantial training data for frequent words, while retaining significant automation obstacles.

Sources:

- [Palladino et al. 2023 alignment gold standards](https://openhumanitiesdata.metajnl.com/articles/10.5334/johd.131)
- [Automatic alignment for Ancient Greek](http://www.lrec-conf.org/proceedings/lrec2022/pdf/2022.lrec-1.634.pdf)
- [Ancient Greek WSD from translation alignment](https://aclanthology.org/2023.alp-1.18)
- [LLM word-alignment evaluation](https://www.cambridge.org/core/journals/computational-humanities-research/article/evaluating-large-language-models-with-a-wordlevel-translation-alignment-task-between-ancient-greek-and-english/4DABC9D5270B5662552B5BD8D8EC527D)

### Mature review interfaces

Before building every curator feature into Aristos:

- **ArboratorGrew** provides collaborative dependency annotation, graph queries/rewrites, tree comparison, class/teaching modes, and parser bootstrapping.
- **BoAT** supports CoNLL-U editing, UD validation, search, agreement, and offline desktop use, according to the current UD tools catalog.
- **INCEpTION** provides multilayer annotation, active learning, external recommenders, explicit accept/reject, curation, and inter-annotator agreement.
- **Arethusa** remains relevant for AGDT-style Ancient Greek workflows and Morpheus-backed analysis.

A prototype can export/import immutable patches through a Roc/Kai task while using one of these tools externally. Grew rules or non-Roc scripts must remain disposable/external experiments; production validation rules maintained in this repository must be Roc and exposed through `Kaifile`. The Python-first runner/layout in the older `docs/plans/conllu-data-pipeline/README.md` is superseded by the current repository language boundary and must not be implemented as written.

Sources:

- [UD tools, including BoAT](https://universaldependencies.org/tools.html)
- [ArboratorGrew](https://aclanthology.org/2020.lrec-1.651)
- [INCEpTION](https://inception-project.github.io/)
- [INCEpTION integration](https://aclanthology.org/2024.emnlp-demo.12)
- [Arethusa](https://github.com/alpheios-project/arethusa)

### Deterministic corpus QA

Use agents only after:

- official UD validation;
- exact text reconstruction;
- stable CTS/source IDs;
- graph connectivity/root/cycle checks;
- FEATS/UPOS compatibility constraints;
- Roc-implemented forbidden/suspicious graph-pattern checks, optionally compared experimentally with external Grew queries;
- cross-source consistency checks for frequent forms;
- duplicate/omission checks;
- translation terminology/name checks;
- phrase-alignment coverage; and
- deterministic content hashes.

These checks are cheaper and reproducible. They establish structural invariants, not semantic correctness; semantic agent linting is a separately calibrated triage signal.

## Translation strategy

### Contextual gloss

Use this candidate order:

1. exact reviewed same occurrence;
2. reviewed same lemma+construction occurrence;
3. aligned licensed translation span;
4. lexicon senses filtered by morphology/syntax and author/genre;
5. cheap model proposal;
6. stronger model or human.

Evaluate token alignment, contextual sense, form-sensitive grammar, non-double-counting, clarity, and concision separately. Store reviewed alternatives rather than treating every English synonym as wrong.

### Literal translation

Define a versioned literal style guide. The layer should expose Greek lexical contributions, ellipsis, morphology, and material order/structure while remaining intelligible. It is not a concatenated gloss line.

Generate from the selected tree, token/phrase alignments, reviewed glosses, multiword expressions, and explicit supplied-word markers. Use a model for constrained realization, then audit omissions/additions and alignment. Keep a stand-off mapping from literal spans to Greek token IDs so student comparison can explain structure.

### Prose translation

Prefer an aligned licensed human translation when edition/span fit is exact. Otherwise generate from the complete sentence or short discourse unit, not token-by-token. Audit with a compact MQM-derived taxonomy:

- mistranslation;
- omission;
- unsupported addition;
- name/reference/terminology error;
- discourse or clause-relation error;
- untranslated text; and
- fluency/grammar.

Accuracy errors should dominate routing. The MQM-APE study linked below reports that 27% of errors from its LLM evaluator were `style/awkward` and recommends emphasizing mistranslation detection. Automatic metrics and Jev can triage, not certify.

Sources:

- [MQM scoring](https://www.themqm.org/mqm-pillars/the-mqm-scoring-models)
- [MQM-APE](https://aclanthology.org/2025.coling-main.374/)
- [WMT 2025 error-span task](https://www2.statmt.org/wmt25/mteval-subtask2.html)
- [Ancient Greek technical-prose evaluation](https://arxiv.org/abs/2602.24119)

## Human review and active learning

### Review priority

Rank items by expected harm and information gain, not raw model uncertainty alone. Start with explicit priority strata and hard overrides rather than an uncalibrated multiplicative formula:

1. hard override: invalid structure, unresolved license/edition, catastrophic translation risk, or learner-critical root/lemma error;
2. high: multi-source disagreement plus high recurrence, pedagogical impact, or downstream dependency;
3. medium: uncertainty, source unreliability, novelty, or out-of-domain risk without a hard override;
4. routine: otherwise low-risk, while preserving a random audit sample.

Later fit a normalized priority model only from measured error yield and review cost. Always review a random sample of unanimous and low-priority output to estimate correlated systematic errors.

Examples of high-impact items:

- roots and clause heads;
- frequent particles and articles;
- high-frequency ambiguous lemmas;
- glosses reused as learner references;
- long-distance attachments;
- idioms and multiword expressions;
- translation omissions;
- analyses that unlock many generated exercises; and
- patterns affecting many corpus occurrences.

Keep the factors visible instead of hiding them in one score.

### Avoid automation bias

For the gold/calibration subset and high-risk cases:

1. reviewer A annotates without seeing the model proposal;
2. reviewer B independently annotates or verifies a stratified overlap;
3. only then reveal model/source alternatives;
4. adjudicate disagreements without deleting original decisions.

LLM-assisted annotation is task-dependent. In a 27-task human-centered study, median accuracy was 0.85 and median F1 0.707, but nine tasks fell below 0.5 precision or recall. Wrong model labels can reduce human accuracy. “Human reviewed” therefore must mean more than a reviewer saw a prefilled answer.

Sources:

- [Pangakis & Wolken 2025](https://ojs.aaai.org/index.php/ICWSM/article/view/35883)
- [Wang et al. 2024](https://dl.acm.org/doi/10.1145/3613904.3641960)
- [Törnberg 2024 best practices](https://sociologica.unibo.it/article/view/19461)
- [LLMs in active learning for low-resource languages](https://arxiv.org/abs/2404.02261)

## Quality and publication tiers

A comprehensive corpus should not pretend uniform gold quality.

Track evidence origin, conversion status, Aristos-profile validation, and human review as independent fields; the tiers below are publication policies derived from them, not substitutes for provenance.

### Tier A — curated reference

- independently reviewed under the applicable Aristos layer/style guide, or imported human annotation subsequently validated for the exact Aristos capability;
- any scheme conversion is recorded and validated separately;
- adjudicated high-impact disagreements;
- exact provenance and license;
- eligible only for the student capabilities explicitly validated for that field/layer.

### Tier B — calibrated auto-accepted

- imported/generated with independent evidence;
- deterministic validation passed;
- acceptance policy demonstrated a predeclared upper confidence bound on false acceptance in matching strata;
- visibly labeled automatic;
- eligible only for named low-risk aids defined by policy, never authoritative free-response grading.

### Tier C — automatic exploratory

- structurally valid but not semantically reviewed or calibrated;
- useful for search, corpus exploration, and review queues;
- not authoritative learner feedback.

### Tier D — unresolved

- conflicting evidence, missing candidate, invalid alignment, or failed validation;
- Greek text remains usable, affected capabilities are disabled.

A work can be Tier A for text and morphology, Tier B for dependencies, Tier C for prose translation, and Tier D for literal translation. Review state must be layer- and field-specific.

## Recommended next experiments

### 1. Candidate-bundle morphology experiment

**Question:** Does analyzer-candidate selection beat independent Jev feature generation?

- Use source- and passage-disjoint reviewed sets across Homer, Attic prose, LXX/NT, comedy, and technical prose; mask target annotations and document edition/training overlap.
- Compare each source only for capabilities it actually supplies: lemma candidate recall, complete morphology-bundle oracle recall, or occurrence-analysis agreement.
- Then compare deterministic top candidate, Jev Choice+`none`, and current two-stage Jev morphology on an untouched holdout.
- Measure complete-bundle accuracy, per-feature accuracy, abstention, impossible bundles, cost, latency, and review minutes.

Stop if candidate oracle recall is poor; selection cannot recover an absent answer.

### 2. Reviewed-example retrieval experiment

**Question:** Can translation memory outperform fresh generation?

- Index reviewed glosses by lemma, morphology, syntax, phrase, author, genre, and dialect.
- Retrieve candidates without using the target's gold answer.
- Compare retrieval-only, retrieval+Jev reranking, DeepSeek-only, and retrieval-augmented DeepSeek.
- Report unseen-lemma and unseen-author performance separately.

### 3. Jev calibration experiment

**Question:** Where does Jev safely reduce review?

- The 85-token Meditations fixture is insufficient. Derive per-stratum sample sizes from the desired upper confidence bound on false auto-acceptance; this will likely require hundreds overall and enough accepted cases in every production stratum.
- Keep development/calibration data separate from an untouched confirmation set.
- Freeze Jev version and question wording.
- Produce per-dimension calibration curves and uncertainty bands.
- Optimize precision among auto-accepted fields and reviewer minutes saved—not raw agreement alone.
- Repeat calls near thresholds to measure routing instability.

### 4. Parser-ensemble correction experiment

**Question:** Which disagreement signals best locate structural errors?

- Compare reviewed/imported structures, OGA/Trankit, and a UD-native parser.
- Review unanimous, two-way disagreement, and all-disagree samples separately.
- Measure error enrichment, UAS/LAS, and review time.
- Test global tree decoding against whole-file LLM repair.

### 5. Translation omission/alignment experiment

**Question:** Can stand-off alignment plus dimensional auditing improve literal/prose review?

- Create a small dual-reviewed set with word/phrase alignment, literal translation, and prose translation.
- Compare current generation with generation supplied reviewed gloss/tree/alignment evidence.
- Evaluate MQM errors, alignment coverage, supplied-word correctness, and review minutes.
- Test Jev only as a calibrated router after human scoring.

### 6. Review-interface pilot

Before building a full curator UI, export 50–100 difficult sentences to ArboratorGrew/BoAT for syntax or INCEpTION for multilayer review. Measure setup cost, seconds per correction, adjudication quality, and round-trip loss. Build a native Elm review surface only where existing tools fail the required workflow.

## Phased corpus roadmap

### Phase 0: freeze contracts

- Aristos CoNLL-U profile and gloss/literal/prose style guides.
- Manifest and sidecar schemas.
- Field-level provenance/review states.
- License/edition approval policy.
- Gold, calibration, and untouched holdout sets.

### Phase 1: maximize no-generation coverage

- Inventory the local OGA corpus and all reviewed treebank overlap by CTS edition/span.
- Import reviewed structure first, then automatic OGA/GLAUx candidates.
- Join licensed translations conservatively.
- Build morphology and translation candidate lattices.
- Emit exact capability and gap reports.

### Phase 2: build correction memory

- Review high-impact disagreements.
- Store every correction as an overlay, never an edited upstream snapshot.
- Build gloss/translation memory and Grew/profile checks from recurring corrections.
- Measure propagation precision before applying any rule broadly.

### Phase 3: calibrated semantic enrichment

- Run the cheapest passing generator only on unresolved gloss/literal/prose fields.
- Use Jev to route, not certify.
- Escalate selectively.
- Keep Tier B/C output distinct from Tier A.

### Phase 4: active review and task-specific models

- Use disagreement, recurrence, and learner impact to select review work.
- After enough reviewed corrections exist, train or adapt small task-specific selectors/parsers.
- Compare them with generic LLM/Jev systems on untouched strata.

### Phase 5: learner-optimized overlays

- Add accepted gloss alternatives, idioms, clause boundaries, explanation templates, and aligned literal spans.
- Mine learner disagreement only as review signals.
- Validate learning with delayed unseen transfer, as already specified in `docs/plans/composable-reading-workspace/VALIDATION.md`.

## What not to do

- Do not use model-emitted CoNLL-U as the production or publication path; retain complete-file generation only as a diagnostic benchmark.
- Do not regenerate reviewed layers merely for uniformity.
- Do not treat structural validity as semantic correctness.
- Do not let Jev's 0.5 boundary become an unvalidated production threshold.
- Do not use the same model's proposal, critique, and explanation as three independent votes.
- Do not show pre-annotations during creation of the gold/calibration subset.
- Do not collapse literal translation, prose translation, and joined token glosses.
- Do not force one analysis where scholarship is genuinely divided; preserve alternatives.
- Do not scale generation before reviewer minutes and false-auto-accept rates are measured.
- Do not build a custom annotation platform before testing current tools.

## Recommendation

Adopt **Option 1**, augmented by the verifier cascade from **Option 2**. Keep **Option 3** for difficult adjudication and evidence gathering only.

The production unit should be an immutable **evidence-backed field patch**, not an agent conversation or generated file. The candidate lattice plus candidate-level provenance/license is an internal compiler and review artifact; canonical CoNLL-U plus its manifest remains the published source of truth. Report human-accepted fields per dollar, per GPU-hour, and per reviewer-hour separately, then choose from the Pareto frontier under a predeclared upper confidence bound on false auto-acceptance. Report every metric separately by layer and genre.

This yields the shortest route to both goals:

- scholars receive traceable sources, alternatives, uncertainty, and revision history;
- students receive a stricter selected layer with contextual glosses, aligned literal structure, fluent prose, and no unsupported claim of infallibility.

## Sources

### Local

- `docs/plans/conllu-data-pipeline/README.md`
- `docs/plans/conllu-data-pipeline/RESEARCH.md`
- `docs/plans/conllu-data-pipeline/EXPERIMENT.md`
- `docs/plans/composable-reading-workspace/README.md`
- `docs/plans/composable-reading-workspace/MASS-IMPORT.md`
- `docs/plans/composable-reading-workspace/VALIDATION.md`
- `docs/plans/jev/conllu.md`
- `docs/plans/deepseek-jev/planfix.md`
- `docs/plans/pipeline/v2-analysis-plan.md`
- `experiments/gloss/deepseek-v4-flash-0731/experiment_4/README.md`
- `experiments/gloss/deepseek-v4-flash-0731/experiment_4/RESEARCH.md`
- `experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/results/README.md`

### Web

- TypeSafe documentation and cookbooks linked under **High-value Jev applications**.
- [Universal Dependencies format](https://universaldependencies.org/format.html)
- [UD validation](https://universaldependencies.org/contributing/validation.html)
- [UD tools](https://universaldependencies.org/tools.html)
- [OGA](https://github.com/OperaGraecaAdnotata/OGA)
- [Ancient Greek parser/lemmatizer comparison](https://aclanthology.org/2025.lm4dh-1.5)
- [Ancient Greek translation-alignment gold standards](https://openhumanitiesdata.metajnl.com/articles/10.5334/johd.131)
- [Ancient Greek WSD from parallel translations](https://aclanthology.org/2023.alp-1.18)
- [MEGAnno+](https://aclanthology.org/2024.eacl-demo.18)
- [Human-LLM verification study](https://dl.acm.org/doi/10.1145/3613904.3641960)
- [Human-centered automated annotation](https://ojs.aaai.org/index.php/ICWSM/article/view/35883)
- [Best practices for LLM annotation](https://sociologica.unibo.it/article/view/19461)
- [LLMs in low-resource active learning](https://arxiv.org/abs/2404.02261)
- [LLM dependency parsing with in-context rules](https://aclanthology.org/2025.xllm-1.17)
- [ArboratorGrew](https://aclanthology.org/2020.lrec-1.651)
- [INCEpTION integration](https://aclanthology.org/2024.emnlp-demo.12)
- [MQM](https://www.themqm.org/)

## Uncertainties

- Jev's official examples are mostly English and task-general; none establishes Ancient Greek philological accuracy.
- OGA and parser benchmark scores do not directly predict accuracy after conversion to the Aristos UD profile.
- License terms differ by exact treebank release, edition, annotation, and translation. Some project pages and live repositories may describe different terms; verify the exact artifact before redistribution.
- Human gloss and literal-translation policies contain legitimate variation. Gold creation requires a written style guide and preserved alternate judgments.
- Agent committees may help on some hard cases, but no reviewed evidence in this repository yet shows they beat retrieval plus one strong model plus human adjudication.
