app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst",
}

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import cli.Utc

Target : { form : Str, id : Str, line : U64, local_context : Str, source_line : Str }
GlossRow : { form : Str, gloss : Str }
SystemValue : { output : Str, system : Str }
LabelKey : { label : Str, system : Str }
SetKey : { label : Str, provider_id : Str }
KeyRow : { candidate_sets : List(SetKey), id : Str, labels : List(LabelKey) }
Candidate : { candidate_index : U64, gloss : Str }
Accounting : {
	ambiguous_possible_charge_attempts : U64,
	ambiguous_possible_cost_usd : Dec,
	known_charged_attempts : U64,
	known_charged_cost_usd : Dec,
	transport_attempts : U64,
	validation_attempts : U64,
}
FutureToken : {
	baseline_candidate_index : U64,
	baseline_display_gloss : Str,
	candidates : List(Candidate),
	effective_display_gloss : Str,
	effective_policy_status : Str,
	flags : List(Str),
	form : Str,
	id : Str,
	line : U64,
	no_valid_candidate_status : Str,
	probabilities : { candidate_1 : Dec, candidate_2 : Dec, candidate_3 : Dec },
	runner_up_candidate_index : U64,
	selector_baseline_probability_difference : Dec,
	selector_differs_from_baseline : Bool,
	selector_top_candidate_index : U64,
	selector_top_display_gloss : Str,
	top_probability : Dec,
	top_runner_up_margin : Dec,
}
FutureProvider : {
	accounting_candidates : Accounting,
	accounting_selector : Accounting,
	audit_path : Str,
	available : Bool,
	provider_id : Str,
	run_id : Str,
	tokens : List(FutureToken),
}
MachineKey : {
	costs : List(CostRow),
	future_providers : List(FutureProvider),
	rows : List(KeyRow),
	schema_version : U64,
	warning : Str,
	worksheet_sha256 : Str,
}
RunAudit : {
	accounting : { candidates : Accounting, selector : Accounting, total : Accounting },
	experiment_version : U64,
	provider_id : Str,
	run_id : Str,
	source_path : Str,
	token_audits : List(FutureToken),
	work : Str,
}
Exp3Token : { form : Str, id : Str, selected_value : Str }
Exp3Audit : { experiment_version : U64, shards : List({ tokens : List(Exp3Token) }), work : Str }
ScoreRow : {
	candidate_x_1 : Str, candidate_x_2 : Str, candidate_x_3 : Str,
	candidate_y_1 : Str, candidate_y_2 : Str, candidate_y_3 : Str,
	correct_a : Str, correct_b : Str, correct_c : Str, correct_d : Str,
	error_a : Str, error_b : Str, error_c : Str, error_d : Str,
	form : Str, id : Str, line : Str, local_context : Str, notes : Str,
	output_a : Str, output_b : Str, output_c : Str, output_d : Str,
	preferred : Str, source_line : Str,
	valid_x_1 : Str, valid_x_2 : Str, valid_x_3 : Str,
	valid_y_1 : Str, valid_y_2 : Str, valid_y_3 : Str,
}
Metric : { denominator : U64, numerator : U64, rate : Str }
SystemCount : { available : U64, no : U64, unresolved : U64, yes : U64 }
CandidateCount : { complete : U64, oracle : U64, selector_correct : U64, selector_disagrees : U64 }
CostRow : {
	ambiguous_possible_charge_attempts : U64,
	ambiguous_possible_cost_usd_known : Dec,
	ambiguous_possible_cost_usd_unknown : Bool,
	known_charged_attempts : U64,
	known_charged_cost_usd : Dec,
	stage : Str,
	status : Str,
}
AttemptAccountingRecord : {
	accounting_after_attempt : Accounting,
	client_request_id : Str,
	provider_id : Str,
	requested_at : Str,
	run_id : Str,
	stage : Str,
}
StageSnapshot : { accounting : Accounting, client_request_id : Str, provider_id : Str, requested_at : Str, run_id : Str, stage : Str }
OrphanCount : { candidates : U64, provider_id : Str, selector : U64 }

experiment_dir = "experiments/gloss/deepseek-v4-flash-0731/experiment_4"
evaluation_dir = "experiments/gloss/deepseek-v4-flash-0731/experiment_4/evaluation/v1"
source_path = "experiments/gloss/deepseek-v4-flash-0731/experiment_4/inputs/iliad-1.1-20.txt"
original_path = "experiments/gloss/deepseek-v4-flash-0731/outputs/iliad-1.1-20.txt"
exp3_audit_path = "experiments/gloss/deepseek-v4-flash-0731/experiment_3/outputs/smoke/smoke-20260918T143502Z-1789742102743302853-v3/iliad-1.1-20.shard-1-of-3.audit.json"
worksheet_path = "experiments/gloss/deepseek-v4-flash-0731/experiment_4/evaluation/v1/worksheet.v1.tsv"
example_path = "experiments/gloss/deepseek-v4-flash-0731/experiment_4/evaluation/v1/scores.example.v1.tsv"
key_path = "experiments/gloss/deepseek-v4-flash-0731/experiment_4/evaluation/v1/MACHINE_KEY_NOT_FOR_REVIEWER.v1.json"
ledger_path = "experiments/gloss/deepseek-v4-flash-0731/experiment_4/evaluation/v1/cost-ledger.v1.json"
guide_path = "experiments/gloss/deepseek-v4-flash-0731/experiment_4/evaluation/v1/REVIEWER_INSTRUCTIONS.v1.txt"
work_name = "iliad-1.1-20"

header = "id\tform\tline\tsource_line\tlocal_context\toutput_a\tcorrect_a\terror_a\toutput_b\tcorrect_b\terror_b\toutput_c\tcorrect_c\terror_c\toutput_d\tcorrect_d\terror_d\tpreferred\tcandidate_x_1\tvalid_x_1\tcandidate_x_2\tvalid_x_2\tcandidate_x_3\tvalid_x_3\tcandidate_y_1\tvalid_y_1\tcandidate_y_2\tvalid_y_2\tcandidate_y_3\tvalid_y_3\tnotes"

main! = |args| {
	displayed = List.map(args, OsStr.display)
	match List.drop_first(displayed, 1) {
		["--worksheet"] => build_worksheet!()
		["--worksheet-runs"] => build_run_worksheet!()
		["--worksheet-runs", open_run_id, sail_run_id] => build_explicit_run_worksheet!(open_run_id, sail_run_id)
		["--evaluate", scores_path] => evaluate_scores!(scores_path)
		["--evaluate-runs"] => evaluate_latest_run_scores!()
		["--evaluate-run", scores_path, explicit_worksheet_path, explicit_key_path] => evaluate_scores_with!(scores_path, explicit_worksheet_path, explicit_key_path)
		_ => {
			_ = Stderr.line!("usage: evaluate-jev-gloss-experiment-4 [--worksheet | --worksheet-runs [<openinference-run-id> <sail-research-run-id>] | --evaluate <scores.tsv> | --evaluate-runs | --evaluate-run <scores.tsv> <worksheet.tsv> <machine-key.json>]")?
			Err(Exit(2))
		}
	}
}

build_worksheet! = || {
	discovered = prepare!()?
	pending_costs = List.concat(historical_cost_rows, experiment_4_cost_rows([], []))
	prepared = { ..discovered, costs: pending_costs, open: empty_future("openinference"), sail: empty_future("sail-research") }
	_ = Path.create_all!(Path.utf8(evaluation_dir))?
	worksheet = render_worksheet(prepared.target_rows, prepared.original, prepared.exp3, prepared.open, prepared.sail)?
	_ = write_atomic_or_verify!(worksheet, worksheet_path)?
	worksheet_sha256 = sha256_file!(worksheet_path)?
	key = machine_key(prepared.target_rows, prepared.open, prepared.sail, prepared.costs, worksheet_sha256)
	key_json = Json.to_str_try(key)?
	ledger_json = Json.to_str_try(cost_ledger(prepared.costs))?
	_ = write_atomic_or_verify!(worksheet, example_path)?
	_ = write_atomic_or_verify!(reviewer_instructions, guide_path)?
	_ = write_atomic_or_verify!("${key_json}\n", key_path)?
	_ = write_atomic_or_verify!("${ledger_json}\n", ledger_path)?
	_ = Stdout.line!("worksheet\t${worksheet_path}")?
	_ = Stdout.line!("reviewer instructions\t${guide_path}")?
	_ = Stdout.line!("empty example scores\t${example_path}")?
	_ = Stdout.line!("MACHINE KEY — NOT FOR REVIEWER USE\t${key_path}")?
	Stdout.line!("cost ledger\t${ledger_path}")
}

build_run_worksheet! = || {
	prepared = prepare!()?
	write_run_worksheet!(prepared)
}

build_explicit_run_worksheet! = |open_run_id, sail_run_id| {
	prepared = prepare_runs!(open_run_id, sail_run_id)?
	write_run_worksheet!(prepared)
}

write_run_worksheet! = |prepared| {
	if !prepared.open.available or !prepared.sail.available {
		_ = Stderr.line!("run-qualified comparison requires completed full audits for both OpenInference and Sail Research; no comparison artifacts were written")?
		Err(CompletedFullAuditsRequired(prepared.open.available, prepared.sail.available))
	} else if !valid_path_segment(prepared.open.run_id) or !valid_path_segment(prepared.sail.run_id) {
		Err(UnsafeComparisonRunId)
	} else {
		comparison_id = "${prepared.open.run_id}--${prepared.sail.run_id}"
		root = "${evaluation_dir}/runs"
		final_dir = "${root}/${comparison_id}"
		if Path.exists!(Path.utf8(final_dir))? {
			Err(ComparisonDirectoryAlreadyExists(final_dir))
		} else {
			worksheet = render_worksheet(prepared.target_rows, prepared.original, prepared.exp3, prepared.open, prepared.sail)?
			ledger_json = Json.to_str_try(cost_ledger(prepared.costs))?
			now = Utc.now!()
			temporary_dir = "${root}/.${comparison_id}.tmp-${U128.to_str(Utc.to_nanos_since_epoch(now))}"
			_ = Path.create_all!(Path.utf8(temporary_dir))?
			_ = Path.write_utf8!(Path.utf8("${temporary_dir}/worksheet.tsv"), worksheet)?
			worksheet_sha256 = sha256_file!("${temporary_dir}/worksheet.tsv")?
			key_json = Json.to_str_try(machine_key(prepared.target_rows, prepared.open, prepared.sail, prepared.costs, worksheet_sha256))?
			_ = Path.write_utf8!(Path.utf8("${temporary_dir}/scores.example.tsv"), worksheet)?
			_ = Path.write_utf8!(Path.utf8("${temporary_dir}/scores.human.tsv"), worksheet)?
			_ = Path.write_utf8!(Path.utf8("${temporary_dir}/REVIEWER_INSTRUCTIONS.txt"), reviewer_instructions)?
			_ = Path.write_utf8!(Path.utf8("${temporary_dir}/MACHINE_KEY_NOT_FOR_REVIEWER.json"), "${key_json}\n")?
			_ = Path.write_utf8!(Path.utf8("${temporary_dir}/cost-ledger.json"), "${ledger_json}\n")?
			_ = rename_comparison_directory!(temporary_dir, final_dir)?
			_ = Stdout.line!("run-qualified worksheet\t${final_dir}/worksheet.tsv")?
			_ = Stdout.line!("human score file\t${final_dir}/scores.human.tsv")?
			_ = Stdout.line!("run-qualified machine key\t${final_dir}/MACHINE_KEY_NOT_FOR_REVIEWER.json")?
			Stdout.line!("evaluate latest paired runs with --evaluate-runs")
		}
	}
}

rename_comparison_directory! = |temporary_dir, final_dir|
	if Path.exists!(Path.utf8(final_dir))? {
		Err(ComparisonDirectoryAlreadyExists(final_dir))
	} else {
		Path.rename!(Path.utf8(temporary_dir), Path.utf8(final_dir))
	}

prepare! = || prepare_selected_runs!(Missing, Missing)

prepare_runs! = |open_run_id, sail_run_id| prepare_selected_runs!(Present(open_run_id), Present(sail_run_id))

prepare_selected_runs! = |open_selection, sail_selection| {
	source = Path.read_utf8!(Path.utf8(source_path))?
	target_rows = targets_from_source(source)?
	original_raw = Path.read_utf8!(Path.utf8(original_path))?
	original = parse_gloss_output(original_raw, target_rows, [])?
	exp3_raw = Path.read_utf8!(Path.utf8(exp3_audit_path))?
	exp3_audit : Exp3Audit
	exp3_audit = Json.parse(exp3_raw)?
	exp3 = validate_exp3(exp3_audit, target_rows)?
	open = discover_selected_future!("openinference", open_selection, target_rows)?
	sail = discover_selected_future!("sail-research", sail_selection, target_rows)?
	costs = discover_all_costs!()?
	Ok({ costs, exp3, open, original, sail, target_rows })
}

targets_from_source = |source| {
	if Str.contains(source, "\t") or Str.contains(source, "\r") {
		Err(InvalidSource)
	} else {
		all = tokenize_lines(Str.split_on(source, "\n"), 1, 1, [])
		first = take_exact(all, 50, [])?
		Ok(add_context(first, all, source, 0, []))
	}
}

tokenize_lines = |lines, line_number, next_id, found|
	match lines {
		[] => found
		[line, .. as rest] => {
			words = List.keep_if(Str.split_on(line, " "), |word| word != "")
			result = tokenize_words(words, line_number, next_id, found)
			tokenize_lines(rest, line_number + 1, result.next_id, result.tokens)
		}
	}

tokenize_words = |words, line_number, next_id, found|
	match words {
		[] => { next_id, tokens: found }
		[word, .. as rest] => tokenize_words(rest, line_number, next_id + 1, List.append(found, { form: word, id: U64.to_str(next_id), line: line_number }))
	}

take_exact = |items, count, found|
	if count == 0 {
		Ok(found)
	} else {
		match items {
			[] => Err(NotFiftyTargets)
			[first, .. as rest] => take_exact(rest, count - 1, List.append(found, first))
		}
	}

add_context = |target_rows, all, source, index, found|
	match target_rows {
		[] => found
		[token, .. as rest] => {
			target : Target
			target = { form: token.form, id: token.id, line: token.line, local_context: context_window(all, index, 3), source_line: source_line_at(source, token.line) }
			add_context(rest, all, source, index + 1, List.append(found, target))
		}
	}

context_window = |tokens, wanted, radius| Str.join_with(context_forms(tokens, wanted, radius, 0, []), " ")

context_forms = |tokens, wanted, radius, index, found|
	match tokens {
		[] => found
		[token, .. as rest] => {
			inside = (index <= wanted and wanted - index <= radius) or (index > wanted and index - wanted <= radius)
			next = if inside List.append(found, token.form) else found
			context_forms(rest, wanted, radius, index + 1, next)
		}
	}

source_line_at = |source, wanted| source_line_loop(Str.split_on(source, "\n"), wanted, 1)
source_line_loop = |lines, wanted, current|
	match lines {
		[] => ""
		[line, .. as rest] => if wanted == current line else source_line_loop(rest, wanted, current + 1)
	}

parse_gloss_output = |raw, target_rows, found|
	match target_rows {
		[] => Ok(found)
		[target, .. as rest_targets] => parse_next_gloss_line(Str.split_on(raw, "\n"), target, rest_targets, found)
	}

parse_next_gloss_line = |lines, target, rest_targets, found|
	match lines {
		[] => Err(MissingOriginalOutput(target.id))
		[line, .. as rest] => {
			if Str.trim(line) == "" {
				parse_next_gloss_line(rest, target, rest_targets, found)
			} else {
				parts = Str.split_on(line, " <=> ")
				match parts {
					[form, gloss, .. as more] => {
						full_gloss = Str.join_with(List.prepend(more, gloss), " <=> ")
						if form != target.form or Str.trim(full_gloss) == "" {
							Err(OriginalOutputMismatch(target.id, form))
						} else {
							parse_gloss_lines(rest, rest_targets, List.append(found, { form, gloss: full_gloss }))
						}
					}
					_ => Err(InvalidOriginalOutputLine(line))
				}
			}
		}
	}

parse_gloss_lines = |lines, target_rows, found|
	match target_rows {
		[] => Ok(found)
		[target, .. as rest_targets] => parse_next_gloss_line(lines, target, rest_targets, found)
	}

validate_exp3 = |audit, target_rows| {
	if audit.experiment_version != 3 or audit.work != work_name {
		Err(InvalidExperiment3Audit)
	} else {
		tokens = flatten_exp3_shards(audit.shards, [])
		validate_exp3_tokens(tokens, target_rows, [])
	}
}

flatten_exp3_shards = |shards, found|
	match shards {
		[] => found
		[shard, .. as rest] => flatten_exp3_shards(rest, List.concat(found, shard.tokens))
	}

validate_exp3_tokens = |tokens, target_rows, found|
	match target_rows {
		[] => Ok(found)
		[target, .. as rest_targets] =>
			match tokens {
				[] => Err(MissingExperiment3Token(target.id))
				[token, .. as rest] => {
					if token.id != target.id or token.form != target.form {
						Err(Experiment3TokenMismatch(target.id))
					} else {
						validate_exp3_tokens(rest, rest_targets, List.append(found, { form: token.form, gloss: token.selected_value }))
					}
				}
			}
	}

discover_selected_future! = |provider_id, selection, target_rows|
	match selection {
		Missing => discover_future!(provider_id, target_rows)
		Present(run_id) => discover_future_run!(provider_id, run_id, target_rows)
	}

discover_future_run! = |provider_id, run_id, target_rows| {
	if !valid_path_segment(run_id) or !Str.starts_with(run_id, "full-${provider_id}-") {
		Err(InvalidRequestedRunId(provider_id, run_id))
	} else {
		path = "${experiment_dir}/outputs/full/${provider_id}/${run_id}/${work_name}.audit.json"
		complete_path = "${experiment_dir}/responses/${run_id}/run.complete"
		if !Path.exists!(Path.utf8(path))? or !Path.exists!(Path.utf8(complete_path))? {
			Err(RequestedCompletedAuditMissing(provider_id, run_id))
		} else {
			raw = Path.read_utf8!(Path.utf8(path))?
			audit : RunAudit
			audit = Json.parse(raw)?
			_ = validate_future_audit(audit, provider_id, run_id, target_rows)?
			Ok({
				accounting_candidates: audit.accounting.candidates,
				accounting_selector: audit.accounting.selector,
				audit_path: path,
				available: Bool.True,
				provider_id,
				run_id,
				tokens: audit.token_audits,
			})
		}
	}
}

discover_future! = |provider_id, target_rows| {
	root = "${experiment_dir}/outputs/full/${provider_id}"
	if !Path.exists!(Path.utf8(root))? {
		Ok(empty_future(provider_id))
	} else {
		entries = Path.list!(Path.utf8(root))?
		path = latest_completed_audit!(entries, provider_id, "")?
		if path == "" {
			Ok(empty_future(provider_id))
		} else {
			raw = Path.read_utf8!(Path.utf8(path))?
			audit : RunAudit
			audit = Json.parse(raw)?
			discovered_run_id = run_id_from_audit_path(path, provider_id)
			_ = validate_future_audit(audit, provider_id, discovered_run_id, target_rows)?
			Ok({
				accounting_candidates: audit.accounting.candidates,
				accounting_selector: audit.accounting.selector,
				audit_path: path,
				available: Bool.True,
				provider_id,
				run_id: audit.run_id,
				tokens: audit.token_audits,
			})
		}
	}
}

latest_completed_audit! = |entries, provider_id, latest|
	match entries {
		[] => Ok(latest)
		[entry, .. as rest] => {
			display = Path.display(entry)
			prefix = "${experiment_dir}/outputs/full/${provider_id}/"
			run_id = Str.replace_first(display, prefix, "")
			audit_path = "${display}/${work_name}.audit.json"
			complete_path = "${experiment_dir}/responses/${run_id}/run.complete"
			eligible = Path.exists!(Path.utf8(audit_path))? and Path.exists!(Path.utf8(complete_path))?
			next = if eligible and (latest == "" or compare_str(latest, audit_path) == Before) audit_path else latest
			latest_completed_audit!(rest, provider_id, next)
		}
	}

run_id_from_audit_path = |path, provider_id| {
	prefix = "${experiment_dir}/outputs/full/${provider_id}/"
	without_prefix = Str.replace_first(path, prefix, "")
	Str.replace_last(without_prefix, "/${work_name}.audit.json", "")
}

validate_future_audit = |audit, provider_id, discovered_run_id, target_rows| {
	if audit.experiment_version != 4 or audit.provider_id != provider_id or audit.run_id != discovered_run_id or audit.source_path != source_path or audit.work != work_name {
		Err(FutureAuditIdentityMismatch(provider_id))
	} else if audit.accounting.total != add_accounting(audit.accounting.candidates, audit.accounting.selector) {
		Err(FutureAuditAccountingMismatch(provider_id))
	} else {
		validate_future_tokens(audit.token_audits, target_rows)
	}
}

validate_future_tokens = |tokens, target_rows|
	match (tokens, target_rows) {
		([], []) => Ok({})
		([token, .. as rest_tokens], [target, .. as rest_targets]) => {
			p1 = token.probabilities.candidate_1
			p2 = token.probabilities.candidate_2
			p3 = token.probabilities.candidate_3
			ranking = rank_three(p1, p2, p3)
			if token.id != target.id or token.form != target.form or token.line != target.line or token.baseline_candidate_index != 1 or !valid_probability(p1) or !valid_probability(p2) or !valid_probability(p3) {
				Err(FutureAuditTokenMismatch(target.id))
			} else {
				match token.candidates {
					[a, b, c] => {
						top_display = if ranking.top_index == 1 display_gloss(a.gloss) else if ranking.top_index == 2 display_gloss(b.gloss) else display_gloss(c.gloss)
						derived_valid = token.selector_top_candidate_index == ranking.top_index and token.runner_up_candidate_index == ranking.runner_index and token.top_probability == ranking.top_probability and token.top_runner_up_margin == ranking.top_probability - ranking.runner_probability and token.selector_baseline_probability_difference == ranking.top_probability - p1 and token.selector_differs_from_baseline == (ranking.top_index != 1)
						if a.candidate_index != 1 or b.candidate_index != 2 or c.candidate_index != 3 or token.baseline_display_gloss != display_gloss(a.gloss) or token.selector_top_display_gloss != top_display or !derived_valid {
							Err(FutureAuditCandidateMismatch(target.id))
						} else {
							_ = validate_future_policy_fields(token)?
							validate_future_tokens(rest_tokens, rest_targets)
						}
					}
					_ => Err(FutureAuditCandidateMismatch(target.id))
				}
			}
		}
		_ => Err(FutureAuditCoverageMismatch)
	}

validate_future_policy_fields = |token| {
	if token.effective_policy_status == "baseline-pending-human-calibrated-policy" and token.effective_display_gloss == token.baseline_display_gloss and token.no_valid_candidate_status == "not-assessed-without-human-calibrated-policy" and token.flags == ["calibration_required"] {
		Ok({})
	} else {
		Err(FutureAuditPolicyMismatch(token.id))
	}
}

valid_probability = |value| value >= 0 and value <= 1

rank_three = |one, two, three| {
	first = if two > one { top_index: 2, top_probability: two } else { top_index: 1, top_probability: one }
	top = if three > first.top_probability { top_index: 3, top_probability: three } else first
	runner = runner_for(top.top_index, one, two, three)
	{ runner_index: runner.index, runner_probability: runner.probability, top_index: top.top_index, top_probability: top.top_probability }
}

runner_for = |top_index, one, two, three|
	if top_index == 1 {
		if three > two { index: 3, probability: three } else { index: 2, probability: two }
	} else if top_index == 2 {
		if three > one { index: 3, probability: three } else { index: 1, probability: one }
	} else {
		if two > one { index: 2, probability: two } else { index: 1, probability: one }
	}

display_gloss = |value| collapse_display_parts(List.keep_if(Str.split_on(Str.trim(value), " "), |part| part != ""), "")

collapse_display_parts = |parts, found|
	match parts {
		[] => found
		[part, .. as rest] => collapse_display_parts(rest, if found == "" part else "${found}-${part}")
	}

empty_accounting : Accounting
empty_accounting = { ambiguous_possible_charge_attempts: 0, ambiguous_possible_cost_usd: 0, known_charged_attempts: 0, known_charged_cost_usd: 0, transport_attempts: 0, validation_attempts: 0 }

empty_future = |provider_id| {
	accounting_candidates: empty_accounting,
	accounting_selector: empty_accounting,
	audit_path: "",
	available: Bool.False,
	provider_id,
	run_id: "",
	tokens: [],
}

render_worksheet = |target_rows, original, exp3, open, sail| {
	rows = render_rows(target_rows, original, exp3, open.tokens, sail.tokens, 0, [])?
	Ok("${header}\n${Str.join_with(rows, "\n")}\n")
}

render_rows = |target_rows, original, exp3, open_tokens, sail_tokens, index, found|
	match (target_rows, original, exp3) {
		([], [], []) => Ok(found)
		([target, .. as rest_targets], [original_row, .. as rest_original], [exp3_row, .. as rest_exp3]) => {
			open_token = future_at(open_tokens, target.id)
			sail_token = future_at(sail_tokens, target.id)
			open_output = future_output(open_token)
			sail_output = future_output(sail_token)
			systems = rotate_systems(index, [
				{ output: original_row.gloss, system: "original-openinference-direct" },
				{ output: exp3_row.gloss, system: "experiment-3-selected" },
				{ output: open_output, system: "experiment-4-openinference-baseline-preserved" },
				{ output: sail_output, system: "experiment-4-sail-research-baseline-preserved" },
			])?
			sets = candidate_sets(index, open_token, sail_token)
			row = score_row(target, systems, sets.x, sets.y)?
			_ = validate_tsv_safe(row)?
			render_rows(rest_targets, rest_original, rest_exp3, open_tokens, sail_tokens, index + 1, List.append(found, render_score_row(row)))
		}
		_ => Err(WorksheetCoverageMismatch)
	}

rotate_systems = |index, systems|
	match systems {
		[a, b, c, d] => {
			turn = index % 4
			if turn == 0 Ok([a, b, c, d]) else if turn == 1 Ok([b, c, d, a]) else if turn == 2 Ok([c, d, a, b]) else Ok([d, a, b, c])
		}
		_ => Err(InvalidSystemCount)
	}

candidate_sets = |index, open_token, sail_token| {
	open = candidate_values(open_token)
	sail = candidate_values(sail_token)
	if index % 2 == 0 { x: open, y: sail } else { x: sail, y: open }
}

future_at = |tokens, wanted|
	match tokens {
		[] => Missing
		[first, .. as rest] => if first.id == wanted Present(first) else future_at(rest, wanted)
	}

future_output = |token|
	match token {
		Missing => ""
		Present(value) => value.effective_display_gloss
	}

candidate_values = |token|
	match token {
		Missing => ["", "", ""]
		Present(value) =>
			match value.candidates {
				[a, b, c] => [a.gloss, b.gloss, c.gloss]
				_ => ["", "", ""]
			}
	}

score_row = |target, systems, x, y|
	match (systems, x, y) {
		([a, b, c, d], [x1, x2, x3], [y1, y2, y3]) => Ok({
			candidate_x_1: x1, candidate_x_2: x2, candidate_x_3: x3,
			candidate_y_1: y1, candidate_y_2: y2, candidate_y_3: y3,
			correct_a: "unscored", correct_b: "unscored", correct_c: "unscored", correct_d: "unscored",
			error_a: "unscored", error_b: "unscored", error_c: "unscored", error_d: "unscored",
			form: target.form, id: target.id, line: U64.to_str(target.line), local_context: target.local_context, notes: "",
			output_a: a.output, output_b: b.output, output_c: c.output, output_d: d.output,
			preferred: "unscored", source_line: target.source_line,
			valid_x_1: "unscored", valid_x_2: "unscored", valid_x_3: "unscored",
			valid_y_1: "unscored", valid_y_2: "unscored", valid_y_3: "unscored",
		})
		_ => Err(InvalidWorksheetShape)
	}

render_score_row = |r| Str.join_with([
	r.id, r.form, r.line, r.source_line, r.local_context,
	r.output_a, r.correct_a, r.error_a, r.output_b, r.correct_b, r.error_b,
	r.output_c, r.correct_c, r.error_c, r.output_d, r.correct_d, r.error_d, r.preferred,
	r.candidate_x_1, r.valid_x_1, r.candidate_x_2, r.valid_x_2, r.candidate_x_3, r.valid_x_3,
	r.candidate_y_1, r.valid_y_1, r.candidate_y_2, r.valid_y_2, r.candidate_y_3, r.valid_y_3, r.notes,
], "\t")

validate_tsv_safe = |row| {
	values = [row.id, row.form, row.line, row.source_line, row.local_context, row.output_a, row.output_b, row.output_c, row.output_d, row.candidate_x_1, row.candidate_x_2, row.candidate_x_3, row.candidate_y_1, row.candidate_y_2, row.candidate_y_3]
	if List.any(values, |value| Str.contains(value, "\t") or Str.contains(value, "\n") or Str.contains(value, "\r")) Err(UnsafeTsvValue(row.id)) else Ok({})
}

machine_key = |target_rows, open, sail, costs, worksheet_sha256| {
	rows = key_rows(target_rows, 0, [])
	key : MachineKey
	key = {
		costs,
		future_providers: [open, sail],
		rows,
		schema_version: 1,
		warning: "MACHINE MAPPING KEY — NOT FOR REVIEWER USE. Reveals system and provider identities.",
		worksheet_sha256,
	}
	key
}

key_rows = |target_rows, index, found|
	match target_rows {
		[] => found
		[target, .. as rest] => {
			base = [
				{ output: "", system: "original-openinference-direct" },
				{ output: "", system: "experiment-3-selected" },
				{ output: "", system: "experiment-4-openinference-baseline-preserved" },
				{ output: "", system: "experiment-4-sail-research-baseline-preserved" },
			]
			rotated = rotate_systems(index, base)
			labels = match rotated {
				Ok([a, b, c, d]) => [{ label: "a", system: a.system }, { label: "b", system: b.system }, { label: "c", system: c.system }, { label: "d", system: d.system }]
				_ => []
			}
			sets = if index % 2 == 0 [{ label: "x", provider_id: "openinference" }, { label: "y", provider_id: "sail-research" }] else [{ label: "x", provider_id: "sail-research" }, { label: "y", provider_id: "openinference" }]
			key_rows(rest, index + 1, List.append(found, { candidate_sets: sets, id: target.id, labels }))
		}
	}

discover_all_costs! = || {
	root = "${experiment_dir}/responses"
	if !Path.exists!(Path.utf8(root))? {
		Ok(List.concat(historical_cost_rows, experiment_4_cost_rows([], [])))
	} else {
		runs = Path.list!(Path.utf8(root))?
		discovered = scan_run_directories!(runs, [], [])?
		Ok(List.concat(historical_cost_rows, experiment_4_cost_rows(discovered.snapshots, discovered.orphans)))
	}
}

scan_run_directories! = |runs, snapshots, orphans|
	match runs {
		[] => Ok({ orphans, snapshots })
		[run_entry, .. as rest] => {
			is_dir = match Path.type!(run_entry)? { IsDir => Bool.True, _ => Bool.False }
			if !is_dir {
				scan_run_directories!(rest, snapshots, orphans)
			} else {
				run_path = Path.display(run_entry)
				run_id = file_name(run_path)
				entries = Path.list!(run_entry)?
				next = scan_run_artifacts!(entries, run_id, snapshots, orphans)?
				scan_run_directories!(rest, next.snapshots, next.orphans)
			}
		}
	}

scan_run_artifacts! = |entries, run_id, snapshots, orphans|
	match entries {
		[] => Ok({ orphans, snapshots })
		[entry, .. as rest] => {
			path = Path.display(entry)
			name = file_name(path)
			if Str.ends_with(name, ".attempt.json") {
				raw = Path.read_utf8!(entry)?
				record : AttemptAccountingRecord
				record = Json.parse(raw)?
				if record.run_id != run_id or !valid_attempt_provider(record.provider_id) or !valid_attempt_stage(record.stage) {
					Err(InvalidAttemptAccountingArtifact(path))
				} else {
					snapshot : StageSnapshot
					snapshot = { accounting: record.accounting_after_attempt, client_request_id: record.client_request_id, provider_id: record.provider_id, requested_at: record.requested_at, run_id: record.run_id, stage: record.stage }
					scan_run_artifacts!(rest, run_id, upsert_stage_snapshot(snapshots, snapshot, []), orphans)
				}
			} else if Str.ends_with(name, ".request.json") and !Path.exists!(Path.utf8(Str.replace_last(path, ".request.json", ".attempt.json")))? {
				match request_stage(name) {
					NoAttemptStage => scan_run_artifacts!(rest, run_id, snapshots, orphans)
					AttemptStage(key) => scan_run_artifacts!(rest, run_id, snapshots, List.append(orphans, key))
				}
			} else {
				scan_run_artifacts!(rest, run_id, snapshots, orphans)
			}
		}
	}

upsert_stage_snapshot = |snapshots, wanted, found|
	match snapshots {
		[] => List.append(found, wanted)
		[first, .. as rest] => {
			same = first.run_id == wanted.run_id and first.provider_id == wanted.provider_id and first.stage == wanted.stage
			if same {
				latest = if compare_str(first.requested_at, wanted.requested_at) == Before or (first.requested_at == wanted.requested_at and compare_str(first.client_request_id, wanted.client_request_id) == Before) wanted else first
				List.concat(found, List.prepend(rest, latest))
			} else {
				upsert_stage_snapshot(rest, wanted, List.append(found, first))
			}
		}
	}

valid_attempt_provider = |provider_id| provider_id == "openinference" or provider_id == "sail-research"
valid_attempt_stage = |stage| stage == "deepseek-candidates" or stage == "jev-noul-selection"

request_stage = |name|
	if Str.starts_with(name, "deepseek-openinference-") {
		AttemptStage({ provider_id: "openinference", stage: "deepseek-candidates" })
	} else if Str.starts_with(name, "deepseek-sail-research-") {
		AttemptStage({ provider_id: "sail-research", stage: "deepseek-candidates" })
	} else if Str.starts_with(name, "jev-openinference-") {
		AttemptStage({ provider_id: "openinference", stage: "jev-noul-selection" })
	} else if Str.starts_with(name, "jev-sail-research-") {
		AttemptStage({ provider_id: "sail-research", stage: "jev-noul-selection" })
	} else {
		NoAttemptStage
	}

experiment_4_cost_rows = |snapshots, orphans| [
	all_run_cost_row("openinference", "deepseek-candidates", snapshots, orphans),
	all_run_cost_row("openinference", "jev-noul-selection", snapshots, orphans),
	all_run_cost_row("sail-research", "deepseek-candidates", snapshots, orphans),
	all_run_cost_row("sail-research", "jev-noul-selection", snapshots, orphans),
]

all_run_cost_row = |provider_id, stage, snapshots, orphans| {
	matching = List.keep_if(snapshots, |snapshot| snapshot.provider_id == provider_id and snapshot.stage == stage)
	accounting = sum_stage_accounting(matching, empty_accounting)
	orphan_count = List.len(List.keep_if(orphans, |orphan| orphan.provider_id == provider_id and orphan.stage == stage))
	stage_name = if stage == "deepseek-candidates" "candidates" else "selector"
	status = if List.is_empty(matching) and orphan_count == 0 "N/A: no attempt artifacts" else "available"
	row : CostRow
	row = {
		ambiguous_possible_charge_attempts: accounting.ambiguous_possible_charge_attempts + orphan_count,
		ambiguous_possible_cost_usd_known: accounting.ambiguous_possible_cost_usd,
		ambiguous_possible_cost_usd_unknown: accounting.ambiguous_possible_charge_attempts > 0 or orphan_count > 0,
		known_charged_attempts: accounting.known_charged_attempts,
		known_charged_cost_usd: accounting.known_charged_cost_usd,
		stage: "experiment-4-${provider_id}-${stage_name}-all-runs",
		status,
	}
	row
}

sum_stage_accounting = |snapshots, total|
	match snapshots {
		[] => total
		[first, .. as rest] => sum_stage_accounting(rest, add_accounting(total, first.accounting))
	}

add_accounting = |a, b| {
	ambiguous_possible_charge_attempts: a.ambiguous_possible_charge_attempts + b.ambiguous_possible_charge_attempts,
	ambiguous_possible_cost_usd: a.ambiguous_possible_cost_usd + b.ambiguous_possible_cost_usd,
	known_charged_attempts: a.known_charged_attempts + b.known_charged_attempts,
	known_charged_cost_usd: a.known_charged_cost_usd + b.known_charged_cost_usd,
	transport_attempts: a.transport_attempts + b.transport_attempts,
	validation_attempts: a.validation_attempts + b.validation_attempts,
}

file_name = |path| file_name_parts(Str.split_on(path, "/"), path)
file_name_parts = |parts, fallback|
	match parts {
		[] => fallback
		[first] => first
		[_, .. as rest] => file_name_parts(rest, fallback)
	}

valid_path_segment = |segment| segment != "" and !Str.contains(segment, "/") and !Str.contains(segment, "\\") and !Str.contains(segment, "..")

historical_cost_rows : List(CostRow)
historical_cost_rows = [
	{ ambiguous_possible_charge_attempts: 0, ambiguous_possible_cost_usd_known: 0, ambiguous_possible_cost_usd_unknown: Bool.False, known_charged_attempts: 1, known_charged_cost_usd: 0.00009557, stage: "original-openinference-candidate", status: "available" },
	{ ambiguous_possible_charge_attempts: 0, ambiguous_possible_cost_usd_known: 0, ambiguous_possible_cost_usd_unknown: Bool.False, known_charged_attempts: 2, known_charged_cost_usd: 0.0009916119, stage: "experiment-3-candidates-all-attempts", status: "available" },
	{ ambiguous_possible_charge_attempts: 1, ambiguous_possible_cost_usd_known: 0, ambiguous_possible_cost_usd_unknown: Bool.True, known_charged_attempts: 1, known_charged_cost_usd: 0.000394044, stage: "experiment-3-jev", status: "available" },
]

cost_ledger = |all_costs| {
	schema_version : U64
	schema_version = 1
	{ entries: all_costs, note: "Includes historical costs plus every experiment-4 run/stage found in retained attempt artifacts. Unknown possible charges are not treated as zero and are not folded into known charged cost.", schema_version }
}

reviewer_instructions = \\
	\\Blind review worksheet. Do not open the accompanying MACHINE_KEY_NOT_FOR_REVIEWER file until scoring is complete.
	\\Experiment-4 output columns are baseline-preserved raw-audit outputs pending any human-calibrated policy replay. Candidate-set validity questions are separate; selector tops are not presented as effective production output.
	\\
	\\For each nonblank output a-d, set correctness to yes, no, or unscored. Set its error category to none for yes; morphology, syntax, sense, context, english, phrase, or other for no; and unscored when correctness is unscored. Leave blank outputs unscored.
	\\
	\\Set preferred to a, b, c, d, tie, none, or unscored. For each nonblank candidate in sets x and y, set validity to yes, no, or unscored. Leave blank candidates unscored. Notes are free text but must not contain tabs or line breaks.
	\\
	\\All supplied outputs and candidates are anonymous. The worksheet contains no AI-generated correctness or validity labels.


evaluate_scores! = |scores_path| evaluate_scores_with!(scores_path, worksheet_path, key_path)

evaluate_latest_run_scores! = || {
	prepared = prepare!()?
	if !prepared.open.available or !prepared.sail.available {
		Err(CompletedFullAuditsRequired(prepared.open.available, prepared.sail.available))
	} else {
		comparison_id = "${prepared.open.run_id}--${prepared.sail.run_id}"
		root = "${evaluation_dir}/runs/${comparison_id}"
		evaluate_scores_with!("${root}/scores.human.tsv", "${root}/worksheet.tsv", "${root}/MACHINE_KEY_NOT_FOR_REVIEWER.json")
	}
}

evaluate_scores_with! = |scores_path, canonical_worksheet_path, machine_key_path| {
	canonical_raw = Path.read_utf8!(Path.utf8(canonical_worksheet_path))?
	canonical = parse_scores(canonical_raw)?
	scores_raw = Path.read_utf8!(Path.utf8(scores_path))?
	scores = parse_scores(scores_raw)?
	_ = validate_scores(scores, canonical)?
	key_raw = Path.read_utf8!(Path.utf8(machine_key_path))?
	key : MachineKey
	key = Json.parse(key_raw)?
	worksheet_sha256 = sha256_file!(canonical_worksheet_path)?
	_ = validate_key(key, scores, worksheet_sha256)?
	result = calculate(scores, key)?
	json = Json.to_str_try(result.json)?
	report = render_report(result)
	json_path = "${scores_path}.evaluation.json"
	report_path = "${scores_path}.report.txt"
	_ = write_atomic_or_verify!("${json}\n", json_path)?
	_ = write_atomic_or_verify!(report, report_path)?
	_ = Stdout.line!("evaluation JSON\t${json_path}")?
	Stdout.line!("evaluation report\t${report_path}")
}

parse_scores = |raw| {
	lines = Str.split_on(Str.replace_each(raw, "\r\n", "\n"), "\n")
	match lines {
		[first, .. as rest] => if first != header Err(InvalidScoreHeader) else parse_score_lines(rest, [], 1)
		[] => Err(InvalidScoreHeader)
	}
}

parse_score_lines = |lines, found, row_number|
	match lines {
		[] => if List.len(found) == 50 Ok(found) else Err(WrongScoreRowCount(List.len(found)))
		[line, .. as rest] => {
			if line == "" {
				parse_score_lines(rest, found, row_number)
			} else {
				row = parse_score_row(line, row_number)?
				parse_score_lines(rest, List.append(found, row), row_number + 1)
			}
		}
	}

parse_score_row = |line, row_number|
	match Str.split_on(line, "\t") {
		[id, form, source_line_number, source_line, local_context,
		 output_a, correct_a, error_a, output_b, correct_b, error_b,
		 output_c, correct_c, error_c, output_d, correct_d, error_d, preferred,
		 candidate_x_1, valid_x_1, candidate_x_2, valid_x_2, candidate_x_3, valid_x_3,
		 candidate_y_1, valid_y_1, candidate_y_2, valid_y_2, candidate_y_3, valid_y_3, notes] => Ok({
			candidate_x_1, candidate_x_2, candidate_x_3, candidate_y_1, candidate_y_2, candidate_y_3,
			correct_a, correct_b, correct_c, correct_d, error_a, error_b, error_c, error_d,
			form, id, line: source_line_number, local_context, notes,
			output_a, output_b, output_c, output_d, preferred, source_line,
			valid_x_1, valid_x_2, valid_x_3, valid_y_1, valid_y_2, valid_y_3,
		})
		_ => Err(InvalidScoreColumnCount(row_number))
	}

validate_scores = |scores, canonical| validate_score_rows(scores, canonical, 1)

validate_score_rows = |scores, canonical, row_number|
	match (scores, canonical) {
		([], []) => Ok({})
		([score, .. as rest_scores], [expected, .. as rest_expected]) => {
			if immutable_score_fields(score) != immutable_score_fields(expected) {
				Err(ImmutableScoreFieldMismatch(row_number, expected.id))
			} else {
				_ = validate_output_score(score.output_a, score.correct_a, score.error_a, "a", score.id)?
				_ = validate_output_score(score.output_b, score.correct_b, score.error_b, "b", score.id)?
				_ = validate_output_score(score.output_c, score.correct_c, score.error_c, "c", score.id)?
				_ = validate_output_score(score.output_d, score.correct_d, score.error_d, "d", score.id)?
				_ = validate_preferred(score)?
				_ = validate_candidate_score(score.candidate_x_1, score.valid_x_1, "x1", score.id)?
				_ = validate_candidate_score(score.candidate_x_2, score.valid_x_2, "x2", score.id)?
				_ = validate_candidate_score(score.candidate_x_3, score.valid_x_3, "x3", score.id)?
				_ = validate_candidate_score(score.candidate_y_1, score.valid_y_1, "y1", score.id)?
				_ = validate_candidate_score(score.candidate_y_2, score.valid_y_2, "y2", score.id)?
				_ = validate_candidate_score(score.candidate_y_3, score.valid_y_3, "y3", score.id)?
				_ = if Str.contains(score.notes, "\r") Err(InvalidNotes(score.id)) else Ok({})
				validate_score_rows(rest_scores, rest_expected, row_number + 1)
			}
		}
		_ => Err(ScoreCoverageMismatch)
	}

immutable_score_fields = |r| [r.id, r.form, r.line, r.source_line, r.local_context, r.output_a, r.output_b, r.output_c, r.output_d, r.candidate_x_1, r.candidate_x_2, r.candidate_x_3, r.candidate_y_1, r.candidate_y_2, r.candidate_y_3]

validate_output_score = |output, correct, category, label, id| {
	if !List.contains(["yes", "no", "unscored"], correct) {
		Err(InvalidCorrectness(id, label, correct))
	} else if !List.contains(["none", "morphology", "syntax", "sense", "context", "english", "phrase", "other", "unscored"], category) {
		Err(InvalidErrorCategory(id, label, category))
	} else if output == "" and (correct != "unscored" or category != "unscored") {
		Err(ScoredMissingOutput(id, label))
	} else if correct == "yes" and category != "none" {
		Err(CorrectOutputMustUseNone(id, label))
	} else if correct == "no" and (category == "none" or category == "unscored") {
		Err(IncorrectOutputNeedsCategory(id, label))
	} else if correct == "unscored" and category != "unscored" {
		Err(UnscoredOutputNeedsUnscoredCategory(id, label))
	} else {
		Ok({})
	}
}

validate_preferred = |row| {
	if !List.contains(["a", "b", "c", "d", "tie", "none", "unscored"], row.preferred) {
		Err(InvalidPreferred(row.id, row.preferred))
	} else if (row.preferred == "a" and row.output_a == "") or (row.preferred == "b" and row.output_b == "") or (row.preferred == "c" and row.output_c == "") or (row.preferred == "d" and row.output_d == "") {
		Err(PreferredMissingOutput(row.id, row.preferred))
	} else {
		Ok({})
	}
}

validate_candidate_score = |candidate, valid, label, id| {
	if !List.contains(["yes", "no", "unscored"], valid) {
		Err(InvalidCandidateValidity(id, label, valid))
	} else if candidate == "" and valid != "unscored" {
		Err(ScoredMissingCandidate(id, label))
	} else {
		Ok({})
	}
}

validate_key = |key, scores, worksheet_sha256| {
	if key.schema_version != 1 or !Str.starts_with(key.warning, "MACHINE MAPPING KEY") or key.worksheet_sha256 != worksheet_sha256 or List.len(key.costs) < List.len(historical_cost_rows) {
		Err(InvalidMachineKey)
	} else {
		_ = validate_future_providers(key.future_providers)?
		validate_key_rows(key.rows, scores, key.future_providers, 0)
	}
}

validate_future_providers = |providers|
	match providers {
		[open, sail] => {
			if open.provider_id != "openinference" or sail.provider_id != "sail-research" {
				Err(InvalidFutureProviders)
			} else if (!open.available and (open.audit_path != "" or open.run_id != "" or !List.is_empty(open.tokens))) or (!sail.available and (sail.audit_path != "" or sail.run_id != "" or !List.is_empty(sail.tokens))) {
				Err(InvalidUnavailableProvider)
			} else if (open.available and (open.audit_path == "" or !valid_path_segment(open.run_id) or List.len(open.tokens) != 50)) or (sail.available and (sail.audit_path == "" or !valid_path_segment(sail.run_id) or List.len(sail.tokens) != 50)) {
				Err(InvalidAvailableProvider)
			} else {
				Ok({})
			}
		}
		_ => Err(InvalidFutureProviders)
	}

validate_key_rows = |rows, scores, providers, index|
	match (rows, scores) {
		([], []) => Ok({})
		([row, .. as rest_rows], [score, .. as rest_scores]) => {
			expected_labels = expected_label_keys(index)
			expected_sets = if index % 2 == 0 [{ label: "x", provider_id: "openinference" }, { label: "y", provider_id: "sail-research" }] else [{ label: "x", provider_id: "sail-research" }, { label: "y", provider_id: "openinference" }]
			if row.id != score.id or row.labels != expected_labels or row.candidate_sets != expected_sets {
				Err(MachineKeyRowMismatch(score.id))
			} else {
				_ = validate_key_outputs(row.labels, score, providers)?
				_ = validate_key_candidate_sets(row.candidate_sets, score, providers)?
				validate_key_rows(rest_rows, rest_scores, providers, index + 1)
			}
		}
		_ => Err(MachineKeyCoverageMismatch)
	}

validate_key_outputs = |labels, score, providers|
	match labels {
		[] => Ok({})
		[first, .. as rest] => {
			expected = if first.system == "experiment-4-openinference-baseline-preserved" {
				provider_output_for(providers, "openinference", score.id)?
			} else if first.system == "experiment-4-sail-research-baseline-preserved" {
				provider_output_for(providers, "sail-research", score.id)?
			} else {
				score_output_for_label(score, first.label)?
			}
			actual = score_output_for_label(score, first.label)?
			if actual != expected Err(MachineKeyWorksheetOutputMismatch(score.id, first.label)) else validate_key_outputs(rest, score, providers)
		}
	}

provider_output_for = |providers, provider_id, token_id| {
	provider = provider_by_id(providers, provider_id)?
	if provider.available {
		token = future_token_by_id(provider.tokens, token_id)?
		Ok(token.effective_display_gloss)
	} else {
		Ok("")
	}
}

score_output_for_label = |score, label|
	if label == "a" Ok(score.output_a) else if label == "b" Ok(score.output_b) else if label == "c" Ok(score.output_c) else if label == "d" Ok(score.output_d) else Err(MissingLabelMapping(label))

validate_key_candidate_sets = |sets, score, providers|
	match sets {
		[x, y] => {
			expected_x = provider_candidates_for(providers, x.provider_id, score.id)?
			expected_y = provider_candidates_for(providers, y.provider_id, score.id)?
			actual_x = [score.candidate_x_1, score.candidate_x_2, score.candidate_x_3]
			actual_y = [score.candidate_y_1, score.candidate_y_2, score.candidate_y_3]
			if x.label != "x" or y.label != "y" or actual_x != expected_x or actual_y != expected_y Err(MachineKeyWorksheetCandidateMismatch(score.id)) else Ok({})
		}
		_ => Err(MachineKeyWorksheetCandidateMismatch(score.id))
	}

provider_candidates_for = |providers, provider_id, token_id| {
	provider = provider_by_id(providers, provider_id)?
	if !provider.available {
		Ok(["", "", ""])
	} else {
		token = future_token_by_id(provider.tokens, token_id)?
		match token.candidates {
			[a, b, c] => Ok([a.gloss, b.gloss, c.gloss])
			_ => Err(FutureAuditCandidateMismatch(token_id))
		}
	}
}

expected_label_keys = |index| {
	base = [
		{ output: "", system: "original-openinference-direct" },
		{ output: "", system: "experiment-3-selected" },
		{ output: "", system: "experiment-4-openinference-baseline-preserved" },
		{ output: "", system: "experiment-4-sail-research-baseline-preserved" },
	]
	match rotate_systems(index, base) {
		Ok([a, b, c, d]) => [{ label: "a", system: a.system }, { label: "b", system: b.system }, { label: "c", system: c.system }, { label: "d", system: d.system }]
		_ => []
	}
}

calculate = |scores, key| {
	initial_systems = { exp3: empty_system_count, open: empty_system_count, original: empty_system_count, sail: empty_system_count }
	initial_candidates = { open: empty_candidate_count, sail: empty_candidate_count }
	counts = calculate_rows(scores, key.rows, key.future_providers, initial_systems, initial_candidates, 0, 0)?
	original_accuracy = accuracy_metric(counts.systems.original)
	exp3_accuracy = accuracy_metric(counts.systems.exp3)
	open_accuracy = accuracy_metric(counts.systems.open)
	sail_accuracy = accuracy_metric(counts.systems.sail)
	open_provider = provider_by_id(key.future_providers, "openinference")?
	sail_provider = provider_by_id(key.future_providers, "sail-research")?
	open_retention = baseline_retention(open_provider)
	sail_retention = baseline_retention(sail_provider)
	open_oracle = metric(counts.candidates.open.oracle, counts.candidates.open.complete)
	sail_oracle = metric(counts.candidates.sail.oracle, counts.candidates.sail.complete)
	open_selector = metric(counts.candidates.open.selector_correct, counts.candidates.open.oracle)
	sail_selector = metric(counts.candidates.sail.selector_correct, counts.candidates.sail.oracle)
	open_disagreement = selector_disagreement(open_provider)
	sail_disagreement = selector_disagreement(sail_provider)
	preferred_none = metric(counts.preferred_none, counts.preferred_scored)
	costs = key.costs
	cost_summary = sum_costs(costs, { ambiguous_attempts: 0, known_attempts: 0, known_cost: 0, known_possible_cost: 0, unknown_possible_cost: Bool.False })
	schema_version : U64
	schema_version = 1
	json = {
		schema_version,
		score_path_note: "Metrics use only human labels in the supplied TSV; raw selector decisions are not human labels.",
		accuracy: { experiment_3_selected: exp3_accuracy, experiment_4_openinference_baseline_preserved: open_accuracy, experiment_4_sail_research_baseline_preserved: sail_accuracy, original_openinference_direct: original_accuracy },
		baseline_retention: { experiment_4_openinference: open_retention, experiment_4_sail_research: sail_retention },
		candidate_oracle_recall: { experiment_4_openinference: open_oracle, experiment_4_sail_research: sail_oracle },
		selector_accuracy_conditional_on_candidate_recall: { experiment_4_openinference: open_selector, experiment_4_sail_research: sail_selector },
		raw_selector_disagreement_with_baseline: { experiment_4_openinference: open_disagreement, experiment_4_sail_research: sail_disagreement },
		unresolved: {
			experiment_3_selected_output: metric(counts.systems.exp3.unresolved, counts.systems.exp3.available),
			experiment_4_openinference_baseline_preserved_output: metric(counts.systems.open.unresolved, counts.systems.open.available),
			experiment_4_sail_research_baseline_preserved_output: metric(counts.systems.sail.unresolved, counts.systems.sail.available),
			original_openinference_direct_output: metric(counts.systems.original.unresolved, counts.systems.original.available),
			human_preferred_none: preferred_none,
		},
		cost_summary,
		costs,
	}
	Ok({
		candidate_metrics: { open_oracle, open_selector, sail_oracle, sail_selector },
		cost_summary,
		costs,
		json,
		preferred_none,
		retention: { open: open_retention, sail: sail_retention },
		selector_disagreement: { open: open_disagreement, sail: sail_disagreement },
		system_metrics: { exp3: exp3_accuracy, open: open_accuracy, original: original_accuracy, sail: sail_accuracy },
		unresolved: { exp3: metric(counts.systems.exp3.unresolved, counts.systems.exp3.available), open: metric(counts.systems.open.unresolved, counts.systems.open.available), original: metric(counts.systems.original.unresolved, counts.systems.original.available), sail: metric(counts.systems.sail.unresolved, counts.systems.sail.available) },
	})
}

empty_system_count : SystemCount
empty_system_count = { available: 0, no: 0, unresolved: 0, yes: 0 }
empty_candidate_count : CandidateCount
empty_candidate_count = { complete: 0, oracle: 0, selector_correct: 0, selector_disagrees: 0 }

calculate_rows = |scores, key_rows_list, providers, systems, candidates, preferred_scored, preferred_none|
	match (scores, key_rows_list) {
		([], []) => Ok({ candidates, preferred_none, preferred_scored, systems })
		([score, .. as rest_scores], [key_row, .. as rest_keys]) => {
			with_outputs = add_output_labels(score, key_row.labels, systems)?
			with_sets = add_candidate_sets(score, key_row, providers, candidates)?
			next_preferred_scored = preferred_scored + if score.preferred == "unscored" 0 else 1
			next_preferred_none = preferred_none + if score.preferred == "none" 1 else 0
			calculate_rows(rest_scores, rest_keys, providers, with_outputs, with_sets, next_preferred_scored, next_preferred_none)
		}
		_ => Err(CalculationCoverageMismatch)
	}

add_output_labels = |score, labels, systems| {
	a = label_system(labels, "a")?
	b = label_system(labels, "b")?
	c = label_system(labels, "c")?
	d = label_system(labels, "d")?
	after_a = add_system_result(systems, a, score.output_a, score.correct_a)?
	after_b = add_system_result(after_a, b, score.output_b, score.correct_b)?
	after_c = add_system_result(after_b, c, score.output_c, score.correct_c)?
	add_system_result(after_c, d, score.output_d, score.correct_d)
}

label_system = |labels, wanted|
	match labels {
		[] => Err(MissingLabelMapping(wanted))
		[first, .. as rest] => if first.label == wanted Ok(first.system) else label_system(rest, wanted)
	}

add_system_result = |systems, system, output, score| {
	if system == "original-openinference-direct" {
		Ok({ ..systems, original: add_system_count(systems.original, output, score) })
	} else if system == "experiment-3-selected" {
		Ok({ ..systems, exp3: add_system_count(systems.exp3, output, score) })
	} else if system == "experiment-4-openinference-baseline-preserved" {
		Ok({ ..systems, open: add_system_count(systems.open, output, score) })
	} else if system == "experiment-4-sail-research-baseline-preserved" {
		Ok({ ..systems, sail: add_system_count(systems.sail, output, score) })
	} else {
		Err(UnknownSystem(system))
	}
}

add_system_count = |count, output, score| {
	available: count.available + if output == "" 0 else 1,
	no: count.no + if score == "no" 1 else 0,
	unresolved: count.unresolved + if output == "[UNRESOLVED]" 1 else 0,
	yes: count.yes + if score == "yes" 1 else 0,
}

add_candidate_sets = |score, key_row, providers, candidates| {
	x_provider = set_provider(key_row.candidate_sets, "x")?
	y_provider = set_provider(key_row.candidate_sets, "y")?
	x_values = [score.valid_x_1, score.valid_x_2, score.valid_x_3]
	y_values = [score.valid_y_1, score.valid_y_2, score.valid_y_3]
	x_top = provider_top_index(providers, x_provider, score.id)?
	y_top = provider_top_index(providers, y_provider, score.id)?
	after_x = add_candidate_result(candidates, x_provider, x_values, x_top)?
	add_candidate_result(after_x, y_provider, y_values, y_top)
}

set_provider = |sets, wanted|
	match sets {
		[] => Err(MissingSetMapping(wanted))
		[first, .. as rest] => if first.label == wanted Ok(first.provider_id) else set_provider(rest, wanted)
	}

provider_top_index = |providers, provider_id, token_id| {
	provider = provider_by_id(providers, provider_id)?
	if !provider.available {
		Ok(0)
	} else {
		token = future_token_by_id(provider.tokens, token_id)?
		Ok(token.selector_top_candidate_index)
	}
}

provider_by_id = |providers, wanted|
	match providers {
		[] => Err(MissingFutureProvider(wanted))
		[first, .. as rest] => if first.provider_id == wanted Ok(first) else provider_by_id(rest, wanted)
	}

future_token_by_id = |tokens, wanted|
	match tokens {
		[] => Err(MissingFutureToken(wanted))
		[first, .. as rest] => if first.id == wanted Ok(first) else future_token_by_id(rest, wanted)
	}

add_candidate_result = |candidates, provider_id, values, top_index| {
	if provider_id == "openinference" {
		Ok({ ..candidates, open: add_candidate_count(candidates.open, values, top_index) })
	} else if provider_id == "sail-research" {
		Ok({ ..candidates, sail: add_candidate_count(candidates.sail, values, top_index) })
	} else {
		Err(UnknownCandidateProvider(provider_id))
	}
}

add_candidate_count = |count, values, top_index| {
	complete = List.all(values, |value| value != "unscored")
	oracle = complete and List.contains(values, "yes")
	top_valid = if top_index == 1 first_of_three(values) == "yes" else if top_index == 2 second_of_three(values) == "yes" else if top_index == 3 third_of_three(values) == "yes" else Bool.False
	{
		..count,
		complete: count.complete + if complete 1 else 0,
		oracle: count.oracle + if oracle 1 else 0,
		selector_correct: count.selector_correct + if oracle and top_valid 1 else 0,
	}
}

first_of_three = |values| match values { [a, _, _] => a, _ => "" }
second_of_three = |values| match values { [_, b, _] => b, _ => "" }
third_of_three = |values| match values { [_, _, c] => c, _ => "" }

accuracy_metric = |count| metric(count.yes, count.yes + count.no)

metric = |numerator, denominator| {
	rate = if denominator == 0 "N/A" else Dec.to_str(U64.to_dec(numerator) / U64.to_dec(denominator))
	{ denominator, numerator, rate }
}

baseline_retention = |provider| {
	if !provider.available {
		metric(0, 0)
	} else {
		retained = List.len(List.keep_if(provider.tokens, |token| token.effective_policy_status == "baseline-pending-human-calibrated-policy" or token.effective_policy_status == "human-calibrated-baseline-retained"))
		metric(retained, List.len(provider.tokens))
	}
}

selector_disagreement = |provider| {
	if !provider.available {
		metric(0, 0)
	} else {
		disagrees = List.len(List.keep_if(provider.tokens, |token| token.selector_top_candidate_index != 1))
		metric(disagrees, List.len(provider.tokens))
	}
}

historical_costs = || historical_cost_rows

provider_costs = |provider| {
	if !provider.available {
		[unavailable_cost("experiment-4-${provider.provider_id}-candidates"), unavailable_cost("experiment-4-${provider.provider_id}-selector")]
	} else {
		[cost_from_accounting("experiment-4-${provider.provider_id}-candidates", provider.accounting_candidates), cost_from_accounting("experiment-4-${provider.provider_id}-selector", provider.accounting_selector)]
	}
}

unavailable_cost = |stage| {
	row : CostRow
	row = { ambiguous_possible_charge_attempts: 0, ambiguous_possible_cost_usd_known: 0, ambiguous_possible_cost_usd_unknown: Bool.False, known_charged_attempts: 0, known_charged_cost_usd: 0, stage, status: "N/A: no completed audit" }
	row
}

sum_costs = |costs, found|
	match costs {
		[] => found
		[first, .. as rest] => {
			next = if first.status == "available" {
				ambiguous_attempts: found.ambiguous_attempts + first.ambiguous_possible_charge_attempts,
				known_attempts: found.known_attempts + first.known_charged_attempts,
				known_cost: found.known_cost + first.known_charged_cost_usd,
				known_possible_cost: found.known_possible_cost + first.ambiguous_possible_cost_usd_known,
				unknown_possible_cost: found.unknown_possible_cost or first.ambiguous_possible_cost_usd_unknown,
			} else found
			sum_costs(rest, next)
		}
	}

cost_from_accounting = |stage, accounting| {
	row : CostRow
	row = {
		ambiguous_possible_charge_attempts: accounting.ambiguous_possible_charge_attempts,
		ambiguous_possible_cost_usd_known: accounting.ambiguous_possible_cost_usd,
		ambiguous_possible_cost_usd_unknown: accounting.ambiguous_possible_charge_attempts > 0,
		known_charged_attempts: accounting.known_charged_attempts,
		known_charged_cost_usd: accounting.known_charged_cost_usd,
		stage,
		status: "available",
	}
	row
}

render_report = |result| {
	cost_lines = Str.join_with(List.map(result.costs, render_cost), "\n")
	\\Evaluation report: experiment 4 blind gloss comparison
	\\
	\\Accuracy (human-scored outputs only)
	\\- original OpenInference direct: ${render_metric(result.system_metrics.original)}
	\\- experiment 3 selected: ${render_metric(result.system_metrics.exp3)}
	\\- experiment 4 OpenInference baseline-preserved raw audit: ${render_metric(result.system_metrics.open)}
	\\- experiment 4 Sail Research baseline-preserved raw audit: ${render_metric(result.system_metrics.sail)}
	\\
	\\Experiment 4 stored raw-audit output (candidate-1 baseline preserved pending any human-calibrated policy replay)
	\\- OpenInference baseline retention: ${render_metric(result.retention.open)}
	\\- Sail Research baseline retention: ${render_metric(result.retention.sail)}
	\\
	\\Candidate evaluation (only sets with all three human validity marks)
	\\- OpenInference candidate oracle recall: ${render_metric(result.candidate_metrics.open_oracle)}
	\\- Sail Research candidate oracle recall: ${render_metric(result.candidate_metrics.sail_oracle)}
	\\- OpenInference selector accuracy conditional on candidate recall: ${render_metric(result.candidate_metrics.open_selector)}
	\\- Sail Research selector accuracy conditional on candidate recall: ${render_metric(result.candidate_metrics.sail_selector)}
	\\
	\\Raw selector decisions (separate from baseline-preserved output; not production output unless a later policy replay applies them)
	\\- OpenInference top selector differs from baseline: ${render_metric(result.selector_disagreement.open)}
	\\- Sail Research top selector differs from baseline: ${render_metric(result.selector_disagreement.sail)}
	\\
	\\Unresolved rates
	\\- original OpenInference direct output: ${render_metric(result.unresolved.original)}
	\\- experiment 3 selected output: ${render_metric(result.unresolved.exp3)}
	\\- experiment 4 OpenInference baseline-preserved output: ${render_metric(result.unresolved.open)}
	\\- experiment 4 Sail Research baseline-preserved output: ${render_metric(result.unresolved.sail)}
	\\- human preferred none: ${render_metric(result.preferred_none)}
	\\
	\\Cost ledger
	\\${cost_lines}
	\\- total known charged cost: USD ${Dec.to_str(result.cost_summary.known_cost)} over ${U64.to_str(result.cost_summary.known_attempts)} charged attempt(s)
	\\- total ambiguous possible charges: ${U64.to_str(result.cost_summary.ambiguous_attempts)} attempt(s), recorded possible USD ${Dec.to_str(result.cost_summary.known_possible_cost)}, unknown amount possible=${bool_text(result.cost_summary.unknown_possible_cost)}
	\\
	\\N/A means denominator 0. Unknown possible charges are not treated as zero or folded into known charged cost.
}

bool_text = |value| if value "true" else "false"

render_metric = |value| "${U64.to_str(value.numerator)}/${U64.to_str(value.denominator)} (${value.rate})"

render_cost = |cost| {
	if cost.status != "available" {
		"- ${cost.stage}: ${cost.status}"
	} else {
		possible = if cost.ambiguous_possible_cost_usd_unknown "unknown additional amount possible" else "no unknown amount"
		"- ${cost.stage}: known USD ${Dec.to_str(cost.known_charged_cost_usd)} over ${U64.to_str(cost.known_charged_attempts)} charged attempt(s); ambiguous possible attempts ${U64.to_str(cost.ambiguous_possible_charge_attempts)}, known possible USD ${Dec.to_str(cost.ambiguous_possible_cost_usd_known)}, ${possible}"
	}
}

sha256_file! = |path| {
	output = Cmd.new_str("sha256sum").args_str([path]).exec_output!()?
	match Str.split_on(Str.trim(output.stdout_utf8), " ") {
		[hash, ..] => Ok(hash)
		[] => Err(InvalidSha256Output(path))
	}
}

write_atomic_or_verify! = |content, path| {
	if Path.exists!(Path.utf8(path))? {
		existing = Path.read_utf8!(Path.utf8(path))?
		if existing == content Ok({}) else Err(ExistingContentMismatch(path))
	} else {
		write_atomic_new!(content, path)
	}
}

write_atomic_new! = |content, path| {
	if Path.exists!(Path.utf8(path))? {
		Err(RefuseOverwrite(path))
	} else {
		now = Utc.now!()
		temporary = "${path}.tmp-${U128.to_str(Utc.to_nanos_since_epoch(now))}"
		_ = Path.write_utf8!(Path.utf8(temporary), content)?
		Path.rename!(Path.utf8(temporary), Path.utf8(path))
	}
}

compare_str = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))
compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if x < y Before else if x > y After else compare_bytes(xs, ys)
	}
