# Research: DeepSeek + Jev gloss experiment 4

## Question

How should experiment 4 separate DeepSeek provider quality from Jev selector quality, while giving Jev enough structured evidence and preserving the direct DeepSeek baseline?

## Findings

### Option 1: keep experiment 3's four-way Choice

- Pros: directly ranks the three glosses and `none`; Choice exposes the full distribution and a derived concentration confidence.
- Cons: relative probabilities must sum to one, so `none` competes with otherwise useful glosses; a winner exists even when all glosses are poor; experiment 3 accepts every winner; this does not test candidates independently.
- Official guidance: Choice is relative, should include `none` when coverage is incomplete, and returns a distribution plus confidence.
- Sources: https://docs.typesafe.ai/primitives/choice, https://docs.typesafe.ai/confidence

### Option 2: independent Noul validity judgments

- Pros: asks the desired absolute question for each candidate; each answer is P(yes); candidates can all score low or all score high; deterministic code can rank scores and represent no-valid-candidate separately.
- Cons: Noul has no separate confidence; its scores are not interchangeable with Choice probabilities; any action threshold or uncertainty band needs human-scored calibration.
- Official reranking guidance evaluates each query/candidate pair with the same Noul and sorts in code. Near 0.5 is uncertainty, not a generic quality grade.
- Sources: https://docs.typesafe.ai/primitives/noul, https://docs.typesafe.ai/cookbooks/rerank_typesafe, https://docs.typesafe.ai/introduction/machine-learning-primer

### Option 3: Noul validity followed by a final Choice

- Pros: can distinguish absolute validity from relative preference among valid candidates.
- Cons: adds cost and another primitive with different probability semantics; no evidence yet shows that Choice adds value beyond independent validity scores; Jev 1.13 guidance warns against assumed probability identities and unnecessary work.
- Sources: https://docs.typesafe.ai/model-jaggedness/jev-1.13, https://docs.typesafe.ai/primitives

### State, context, and batching

- One request has one shared state; questions see it independently. TypeSafe recommends descriptive structured objects and explicit backticked paths to the exact values under judgment.
- Jev 1.13 is documented as jagged under indirection, irrelevant large state, contradictory criteria, arithmetic/composition, and generation. Filter irrelevant context, point directly to state, and do ranking/margins in code.
- TypeSafe's parallel-questions cookbook reports no answer change beyond run noise from batching 13 questions about the same state, with substantial cost/latency savings. This supports batching questions that genuinely share state; it does not prove that 150 questions over Ancient Greek and a large irrelevant state are harmless.
- Experiment 4 should retain the complete passage for audit and long-range context, while each target record contains an exact ID, source line, local window, evidence, and candidates. Each question names one exact `targets[...]` path. Candidate questions can be batched because they share this bounded first-50-token passage, but each question points only to one target and one candidate.
- Sources: https://docs.typesafe.ai/concepts/state, https://docs.typesafe.ai/primitives, https://docs.typesafe.ai/cookbooks/parallel_questions, https://docs.typesafe.ai/model-jaggedness/jev-1.13

### Confidence and calibration

- TypeSafe describes probabilities as calibrated over groups, not guarantees for individual answers.
- Choice confidence is derived from the shape of the full distribution; it is not the winning probability or winner/runner-up margin. Noul returns only P(yes).
- Thresholds shown in documentation are examples. Production thresholds and uncertainty bands must be chosen from labeled data with explicit error/review costs.
- Experiment 4 should retain every Noul probability, rank deterministically, record the selector's top candidate and baseline disagreement, and leave the effective policy unresolved until human calibration.
- Sources: https://docs.typesafe.ai/confidence, https://docs.typesafe.ai/introduction/machine-learning-primer, https://docs.typesafe.ai/patterns/confidence-routing

### Independent linguistic evidence

- Local OGA v0.2.0 contains the matching Perseus Iliad edition at `../OGA/opera_graeca_adnotata_v0.2.0/workspace/conllu/tlg0012.tlg001.perseus-grc2.tok01_sentence-seg01_annotated_lemma.conllu` (SHA-256 `59eea57f7017610dd10bf47a1dcbcd3f9cc7035eb8b491893a82c2dd7695c530`).
- Its `LEMMA`, compact POS/XPOS, `FEATS`, `HEAD`, and `DEPREL` provide independently supplied morphology and syntax. OGA is external to DeepSeek/Jev, but its annotations are not infallible human gold and share the same underlying Perseus edition.
- Experiment whitespace tokens attach punctuation while OGA gives punctuation separate `t_N` rows. The first 50 experiment tokens align deterministically to OGA `t_1` through `t_56`, skipping six punctuation rows; the tool must verify forms and the source hash rather than assume row positions.
- Corpus-derived evidence must be labeled `oga-v0.2.0-corpus` and kept separate from DeepSeek's generated contextual interpretation/rationale.

### Transport compatibility

- `roc-lang/basic-cli` issue #455 still describes HTTP/2 support as research, not a released repair; issue #438 still tracks transport error mapping. No released compatible fix was found.
- Preserve the experiment 3 curl workaround, redaction, retries, atomic writes, and checkpoint validation.
- Sources: https://github.com/roc-lang/basic-cli/issues/455, https://github.com/roc-lang/basic-cli/issues/438

## Recommendation

Use exactly three DeepSeek candidates. Candidate 1 is the direct primary baseline. Candidates 2 and 3 must encode explicitly different grammatical or contextual interpretations, with natural internal gloss strings and separately normalized display strings. Supply pinned OGA evidence as corpus-derived facts; keep DeepSeek interpretation and rationale visibly model-generated.

Construct byte-comparable OpenInference and Sail Research requests that differ only in the pinned provider field. Run neither during construction. For each provider's accepted candidate checkpoint, ask one focused Noul per candidate against the same structured target state. Rank the three probabilities in Roc, but preserve candidate 1 unless a later policy replay—using thresholds and margins learned from human-scored calibration—allows replacement. Do not add a final Choice stage initially.

Blindly evaluate original OpenInference output, experiment 3, and future experiment-4 provider variants on the same first 50 Iliad tokens. Report accuracy, baseline retention, candidate oracle recall, selector accuracy conditional on recall, unresolved rate, and complete attempt-level cost accounting.

## Uncertainties

- Official TypeSafe examples are primarily English and do not establish Ancient Greek accuracy.
- The batching cookbook used 13 questions and Jev 1.12; experiment 4 uses 150 Nouls and Jev 1.13. Measure rather than assume equivalence.
- OGA annotation quality is useful evidence, not gold adjudication.
- Semantic-equivalence rejection cannot be guaranteed by string checks alone; validation can reject malformed/duplicate/shallow forms, while human evaluation must measure whether alternatives are genuinely contrastive.
