# DeepSeek V4 Flash + Jev gloss experiment 4

Experiment 4 is an independent, versioned redesign of experiment 3. Experiment 3 and its artifacts remain frozen. This experiment targets the same first 50 whitespace tokens of *Iliad* 1.1–20 while retaining the complete passage for context and audit.

**Paid warning:** every command in the paid section sends billable POSTs. No paid command was run while constructing this experiment.

## Why experiment 3 was insufficient

Experiment 3 changed the DeepSeek provider from OpenInference to Sail Research at the same time that it changed the task from direct glossing to candidate generation. Its Jev request then supplied a complete unstructured Greek passage and bare candidate strings, asked one relative Choice in which `none` competed with real glosses, and accepted every winner without calibration or baseline protection. Candidate validation admitted malformed or superficial forms, generated claims were not separated from independent evidence, and costs from rejected/retried/ambiguous attempts were not summarized as one experiment cost.

The result could not distinguish provider quality, candidate recall, or selector quality. Jev sometimes rejected a stronger available candidate (`but`, `for-dogs`, `for-birds`, `lord`, `then`, `he-sent-forth`) while adding substantial cost.

## Hypotheses and controlled variants

1. **Provider hypothesis:** with model, prompt, response schema, sampling, frozen source, OGA evidence, and target IDs held byte-identical, OpenInference and Sail Research may differ in primary quality, candidate oracle recall, validity, latency, and cost. The two constructed PPQ bodies differ only at `provider.only`.
2. **Candidate-structure hypothesis:** one primary baseline plus two explicitly contrastive interpretations, with strict malformed-output rejection, should improve candidate usefulness without increasing the count above three.
3. **Evidence hypothesis:** pinned OGA lemma/morphology/dependency evidence should help both generation and judgment more than asking DeepSeek to invent structural evidence for its own answer.
4. **Selector hypothesis:** three independent absolute Noul validity judgments should rank candidates more usefully than one relative Choice with `none`. Human labels must test this using candidate oracle recall and selector accuracy conditional on recall.
5. **Baseline-preservation hypothesis:** retaining candidate 1 unless a later human-calibrated policy authorizes replacement prevents silent regressions while still recording the raw selector preference.

OpenInference versus Sail isolates the provider only **within experiment 4**. Comparison with the original direct output or experiment 3 remains a system comparison because prompt/schema/task differ. Selector quality is measured separately from provider quality by scoring candidate recall, the primary candidate, and Jev's top candidate for each provider.

## Frozen input and independent evidence

- Input: `inputs/iliad-1.1-20.txt`
- Input SHA-256: `1263ac162eea8365bd04261361668fab579c2f97299ac0a8b4429f7f33133807`
- Targets: exact experiment token IDs 1–50
- OGA source: `../OGA/opera_graeca_adnotata_v0.2.0/workspace/conllu/tlg0012.tlg001.perseus-grc2.tok01_sentence-seg01_annotated_lemma.conllu`
- OGA SHA-256: `59eea57f7017610dd10bf47a1dcbcd3f9cc7035eb8b491893a82c2dd7695c530`

The tool aligns attached-punctuation experiment tokens to OGA lexical rows `t_1`–`t_56`, skipping detached punctuation. OGA contributes `LEMMA`, `XPOS`, `FEATS`, `HEAD`, and `DEPREL`. These are corpus-derived and independent of DeepSeek/Jev, but they are automatic corpus annotations—not human gold. DeepSeek's interpretation and rationale remain explicitly model-generated claims.

## Exact candidate schema

DeepSeek must return exactly 50 ordered rows:

```json
{
  "tokens": [
    {
      "id": "1",
      "candidates": [
        {
          "candidate_index": 1,
          "role": "primary-baseline",
          "gloss": "natural internal English string",
          "contextual_interpretation": "model-generated interpretation",
          "rationale": "model-generated concise rationale",
          "evidence_refs": ["oga:t_1", "source:line:1"]
        },
        {
          "candidate_index": 2,
          "role": "alternative",
          "gloss": "a genuinely contrastive reading",
          "contextual_interpretation": "model-generated interpretation",
          "rationale": "model-generated concise rationale",
          "evidence_refs": ["oga:t_1"]
        },
        {
          "candidate_index": 3,
          "role": "alternative",
          "gloss": "another genuinely contrastive reading",
          "contextual_interpretation": "model-generated interpretation",
          "rationale": "model-generated concise rationale",
          "evidence_refs": ["source:line:1"]
        }
      ]
    }
  ]
}
```

Candidate 1 is always DeepSeek's primary best gloss and the preserved direct baseline. Alternatives must differ in grammatical or contextual interpretation, not merely spelling or synonym choice. Validation rejects wrong order/count/roles, empty or unsafe fields, duplicate/canonically shallow strings, duplicate interpretations, invalid evidence paths, apostrophe possessives, reserved unresolved markers, and dangling punctuation/hyphens. Natural internal spaces are allowed; the Roc tool separately converts them to hyphenated display values.

String validation cannot prove semantic contrast. The blind candidate-validity worksheet measures failures that pass structural validation.

## Exact Jev schema

The request state is:

```json
{
  "notice": "LIVE REQUEST STATE — generated claims remain separate from OGA evidence",
  "task": "Independently judge each exact candidate; do not rank or infer a threshold.",
  "evidence_legend": "deterministic English explanation of OGA FEATS and DEPREL codes",
  "source_passage": "complete frozen Iliad passage",
  "targets": [
    {
      "id": "1",
      "form": "μῆνιν",
      "line": 1,
      "source_line": "complete source line",
      "local_context": "three-token radius around the exact occurrence",
      "evidence": {
        "corpus": "oga-v0.2.0-corpus",
        "source_path": "pinned local CoNLL-U path",
        "source_sha256": "59ee…c530",
        "row_id": "t_1",
        "form": "μῆνιν",
        "lemma": "μῆνις",
        "xpos": "n-s---fa-",
        "feats": "Case=a|Gender=f|Number=s",
        "head": 2,
        "deprel": "OBJ"
      },
      "candidates": [
        {
          "candidate_index": 1,
          "role": "primary-baseline",
          "gloss": "wrath",
          "display_gloss": "wrath",
          "contextual_interpretation": "generated claim",
          "rationale": "generated claim",
          "evidence_refs": ["oga:t_1"],
          "generated_claims_notice": "not OGA evidence"
        }
      ]
    }
  ]
}
```

For each target index `i` and candidate index `j`, the question key is `token_<id>_candidate_<1..3>` and points directly to ``targets[i].candidates[j]`` and ``targets[i]``:

```json
{
  "type": "noul",
  "instructions": "Is this exact candidate a valid contextual gloss for this exact token record?",
  "criteria": {
    "true": "Natural and contextually accurate; morphology and required syntactic function agree; no phrase-level mistranslation.",
    "false": "Morphology, syntax, sense, occurrence, English, context, or phrase contribution is wrong."
  }
}
```

The direct response schema is:

```json
{
  "answers": {
    "token_1_candidate_1": { "type": "noul", "noul": 0.0 }
  },
  "model": "jev-1.13.0",
  "usage": { "input_tokens": 0, "output_tokens": 0 }
}
```

All 150 candidate questions are batched because they share the same passage state and TypeSafe documents independent parallel question evaluation. Each question points only to one structured target and candidate and instructs Jev to use the complete passage only when long-range context is needed. No final Choice stage is used: it would add cost without demonstrated value over the independent absolute scores.

Roc ranks the three Noul probabilities with stable index tie-breaking and records the top candidate, baseline disagreement, top probability, and top/runner-up margin. It does **not** infer `none` or replace candidate 1. Every raw audit remains baseline-preserved and marked `calibration_required`. A later policy file must declare `human_calibrated: true` before offline replay can apply probability/margin/no-valid thresholds.

## TypeSafe findings

Current official guidance consulted for this design:

- [State](https://docs.typesafe.ai/concepts/state): structured state preserves relationships; questions should use explicit paths; questions over one state are independent.
- [Primitives](https://docs.typesafe.ai/primitives), [Choice](https://docs.typesafe.ai/primitives/choice), and [Noul](https://docs.typesafe.ai/primitives/noul): Choice is relative and returns a distribution/confidence; Noul is an absolute P(yes) with no separate confidence.
- [Confidence](https://docs.typesafe.ai/confidence) and [AI primer](https://docs.typesafe.ai/introduction/machine-learning-primer): calibration is population-level, not a guarantee for one item; thresholds require labeled data.
- [Re-ranking](https://docs.typesafe.ai/cookbooks/rerank_typesafe): score each query/candidate pair with the same Noul and sort in code.
- [Jev 1.13 jaggedness](https://docs.typesafe.ai/model-jaggedness/jev-1.13): reduce indirection and irrelevant context; make boundaries explicit; do generation and arithmetic outside Jev.
- [Parallel questions](https://docs.typesafe.ai/cookbooks/parallel_questions): batching questions over one shared state did not change answers beyond run noise in TypeSafe's published test and was cheaper/faster. That result used Jev 1.12, English, and 13 questions, so this experiment must verify behavior for Jev 1.13 and Ancient Greek rather than assume transfer.

See `RESEARCH.md` for the alternatives, caveats, and upstream `basic-cli` findings.

## No-spend commands

These commands read no API keys and send no POSTs:

```text
kai run check-jev-gloss-experiment-4-tool
kai run check-jev-gloss-evaluation-4-tool
kai run check-deepseek-v4-flash-0731-experiment-4
kai run construct-deepseek-v4-flash-0731-experiment-4
kai run worksheet-deepseek-v4-flash-0731-experiment-4
kai run evaluate-example-deepseek-v4-flash-0731-experiment-4
```

`construct-…` writes or verifies two provider-comparable candidate requests and a clearly marked synthetic Jev fixture under `constructed/`. The fixture is **not for submission**.

After both full provider runs exist, these remain offline:

```text
kai run worksheet-runs-deepseek-v4-flash-0731-experiment-4
# A human edits the generated run-qualified scores.human.tsv without opening the machine key.
kai run evaluate-runs-deepseek-v4-flash-0731-experiment-4
```

The evaluator reports denominators and `N/A` for unscored/unavailable metrics. It calculates human-scored accuracy, baseline retention, candidate oracle recall, selector accuracy conditional on recall, unresolved rate, raw selector disagreement, and separate candidate/Jev costs. Historical accounting includes both rejected experiment-3 candidate attempts and one ambiguous possible Jev charge of unknown amount. Experiment-4 accounting scans every retained run/stage—including smoke, incomplete, validation retries, transport retries, and earlier runs—and never folds unknown possible charges into known charged cost.

## Paid commands — do not run without explicit authorization

The smallest provider comparison starts one candidate-generation request per provider (with the pinned bounded retry policy if transport or validation fails) and leaves resumable checkpoints; it does **not** call Jev:

```text
kai run candidates-deepseek-v4-flash-0731-experiment-4-openinference
kai run candidates-deepseek-v4-flash-0731-experiment-4-sail-research
```

After reviewing the candidates and authorizing Jev, resume those checkpoints:

```text
kai run resume-smoke-deepseek-v4-flash-0731-experiment-4-openinference
kai run resume-smoke-deepseek-v4-flash-0731-experiment-4-sail-research
```

One-command paid smoke/full variants are also available:

```text
kai run smoke-deepseek-v4-flash-0731-experiment-4-openinference
kai run smoke-deepseek-v4-flash-0731-experiment-4-sail-research
kai run deepseek-v4-flash-0731-experiment-4-openinference
kai run deepseek-v4-flash-0731-experiment-4-sail-research
kai run resume-deepseek-v4-flash-0731-experiment-4-openinference
kai run resume-deepseek-v4-flash-0731-experiment-4-sail-research
```

Both smoke and full modes intentionally cover the same frozen first 50 tokens; separate namespaces make construction checks and staged paid work explicit.

## Retention, retry, and policy behavior

Every paid attempt writes its exact request before dispatch and retains raw response bytes, response headers, transport output, request/provider IDs, timing, token usage, cost, validation result, retry delay, and duplicate-billing ambiguity. Accepted checkpoints and final audits are atomic and never overwritten. Resume validates manifests, source/provider/model pins, candidate request settings, checkpoint/audit equality, accounting totals, and derived rankings. If request/response artifacts exist without a matching attempt record after a crash, resume refuses another paid call rather than risk an unaccounted duplicate.

The experiment retains experiment 3's curl-only TypeSafe workaround. `basic-cli` issue [#455](https://github.com/roc-lang/basic-cli/issues/455) still tracks HTTP/2 research and [#438](https://github.com/roc-lang/basic-cli/issues/438) still tracks transport error mapping; no released compatible fix was found. API keys remain in `.env`/child environment only and are never written or passed in process arguments.

After a human-calibrated `policy.json` is deliberately installed at the configured path, replay the latest completed full audit offline:

```text
kai run replay-policy-deepseek-v4-flash-0731-experiment-4-openinference
kai run replay-policy-deepseek-v4-flash-0731-experiment-4-sail-research
```

With no policy file, these commands report that no threshold was assumed and write nothing. No production threshold is supplied by this experiment.

## Recommended next paid step

Run the two candidate-only commands above—one initial OpenInference request and one initial Sail Research request over the identical first 50-token payload, subject only to the same bounded retry policy. Blindly score both primary outputs and both three-candidate sets before spending on Jev. This is the smallest comparison that directly removes the provider confound and reveals whether candidate recall, rather than selector behavior, is the bottleneck.
