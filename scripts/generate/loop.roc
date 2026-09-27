app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
# Translates and glosses the first N sentences of a work's CoNLL-U input into conllu/generated/<work>-<model>/,
# resuming from that folder's checkpoints. Every new sentence makes paid API calls.
# Kai starts this loop with SIGINT ignored and each stage restores it, so Ctrl-C kills only the running stage and
# the loop can print its summary. basic-cli cannot observe SIGINT yet; remove this once it can
# (../roc-issues/improvements/IMPROVEMENT-002-basic-cli-sigint-handling).
LoopConfig : { input : Str, model : Str }
# A work config either carries full prompts (used verbatim) or a context paragraph appended to base.json's shared prompts.
Prompted : { translate : { prompt : Str }, gloss : { prompt : Str } }
WorkConfig : { input : Str, title : Str, model : Str, base_url : Str, api_key_env : Str, allow_fallbacks : Bool, send_temperature : Bool, structured_schema : Bool, temperature : Dec, context : Str, translate : { max_tokens : U64 }, gloss : { max_tokens : U64 } }
# Every resolved-config field that determines generated output.
Pinned : { input : Str, model : Str, base_url : Str, api_key_env : Str, allow_fallbacks : Bool, send_temperature : Bool, structured_schema : Bool, temperature : Dec, translate : { max_tokens : U64, prompt : Str }, gloss : { max_tokens : U64, prompt : Str } }
Passage : { ref : Str, label : Str, tokens : List(Str) }
# The fields the translate stage reads; passage translation swaps in the passage prompt.
StageConfig : { allow_fallbacks : Bool, api_key_env : Str, base_url : Str, model : Str, send_temperature : Bool, structured_schema : Bool, temperature : Dec, translate : { max_tokens : U64, prompt : Str } }
UnitInstruction : { unit_instruction : Str }
BasePrompts : { translate : Str, gloss : Str }
base_prompts = "scripts/generate/base.json"
ByokUsage : { usage : { cost : Dec, is_byok : Bool, cost_details : { upstream_inference_cost : Dec } } }
Usage : { usage : { cost : Dec } }
Costs : { total : Dec, unknown : U64 }
stage_dir = "scripts/generate"
max_attempts = 3
bar_width = 24
main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[work, config_path, count] => run!(work, config_path, count)
	_ => Err(Usage("loop.roc <work> <config.json> <passage-count|all>"))
}
run! = |work, config_path, count_arg| {
	_ = (if valid_work(work) { Ok({}) } else { Err(InvalidWork(work)) })?
	config_text = resolve_config!(Path.read_utf8!(Path.utf8(config_path))?)?
	config : LoopConfig
	config = Json.parse(config_text)?
	source = blocks_from(Str.replace_each(Path.read_utf8!(Path.utf8(config.input))?, "\r\n", "\n"))
	# Passages follow the work's canonical citation (scripts/Passages.roc); the count is in passages.
	passages = passages!(config.input)?
	available = List.len(passages)
	requested = (if count_arg == "all" { Ok(available) } else { U64.from_str(count_arg) })?
	_ = (if requested == 0 or requested > available { Err(InvalidPassageCount(requested, available)) } else { Ok({}) })?
	wanted = take(passages, requested, [])
	sentences = sentences_needed(source, wanted)
	out = "conllu/generated/${work}-${Str.replace_each(config.model, "/", "-")}"
	_ = Path.create_all!(Path.utf8("${out}/.scratch"))?
	costs = read_costs!(out)?
	job = { work, config_path, count_arg, input: config.input, out, requested, available, wanted, sentences, cost_at_start: costs.total }
	outcome = generate!(job, config_text, source)
	_ = Stderr.write!("\r\u(1b)[2K")?
	_ = summary!(job, outcome)?
	match outcome {
		Ok(_) => Ok({})
		Err(Cancelled) => Err(Exit(130))
		Err(_) => Err(Exit(1))
	}
}
generate! = |job, config_text, source| {
	_ = bind_config!(job.out, config_text)?
	translated = read_blocks!("${job.out}/translations.conllu")?
	glossed = read_blocks!("${job.out}/output.conllu")?
	_ = (if List.len(glossed) > List.len(translated) { Err(InconsistentCheckpoint(job.out)) } else { Ok({}) })?
	_ = bind_source!(job, source, List.len(translated))?
	_ = Stdout.line!("${job.work}: ${U64.to_str(job.requested)} passage(s) requested, covering ${U64.to_str(job.sentences)} sentence(s); ${U64.to_str(List.len(glossed))} sentence(s) already glossed; output in ${job.out}")?
	_ = process!(job, take(source, job.sentences, []), translated, List.len(glossed), 1, job.cost_at_start)?
	costs = read_costs!(job.out)?
	process_units!(job, config_text, costs.total)
}
resolve_config! = |text| {
	prompted : Try(Prompted, _)
	prompted = Json.parse(text)
	match prompted {
		Ok(_) => Ok(text)
		Err(_) => {
			work : WorkConfig
			work = Json.parse(text)?
			base : BasePrompts
			base = Json.parse(Path.read_utf8!(Path.utf8(base_prompts))?)?
			Json.to_str_try({
				input: work.input,
				title: work.title,
				model: work.model,
				base_url: work.base_url,
				api_key_env: work.api_key_env,
				allow_fallbacks: work.allow_fallbacks,
				send_temperature: work.send_temperature,
				structured_schema: work.structured_schema,
				temperature: work.temperature,
				context: work.context,
				translate: { max_tokens: work.translate.max_tokens, prompt: "${base.translate} Text context: ${work.context}" },
				gloss: { max_tokens: work.gloss.max_tokens, prompt: "${base.gloss} Text context: ${work.context}" },
			})
		}
	}
}
# The config snapshot pins prompts and model: resuming with an edited config would mix outputs.
# Stages read this resolved snapshot rather than the work config.
# Only Pinned fields must match; other fields (the display title, or the hand-written source block that
# snapshots before deterministic citations carried) are refreshed in the snapshot on resume.
bind_config! = |out, content| {
	path = "${out}/config.json"
	if Path.exists!(Path.utf8(path))? {
		saved = Path.read_utf8!(Path.utf8(path))?
		if saved == content {
			Ok({})
		} else if same_pinned(saved, content) {
			Path.write_utf8!(Path.utf8(path), content)
		} else {
			Err(CheckpointInputChanged(path))
		}
	} else if Path.exists!(Path.utf8("${out}/translations.conllu"))? {
		Err(MissingCheckpointSnapshot(path))
	} else {
		Path.write_utf8!(Path.utf8(path), content)
	}
}
same_pinned = |saved, content| {
	before : Try(Pinned, _)
	before = Json.parse(saved)
	after : Try(Pinned, _)
	after = Json.parse(content)
	match (before, after) {
		(Ok(a), Ok(b)) => a == b
		_ => Bool.False
	}
}
# The source snapshot may grow with larger requests, but its existing prefix must never change.
bind_source! = |job, source, translated_count| {
	path = "${job.out}/source.conllu"
	saved = read_blocks!(path)?
	_ = (if List.len(saved) < translated_count or saved != take(source, List.len(saved), []) { Err(CheckpointInputChanged(path)) } else { Ok({}) })?
	keep = if List.len(saved) > job.sentences List.len(saved) else job.sentences
	Path.write_utf8!(Path.utf8(path), "${Str.join_with(take(source, keep, []), "\n\n")}\n")
}
process! = |job, sources, translated, glossed_count, index, cost| match sources {
	[] => Ok({})
	[source, .. as rest] => if index <= glossed_count {
		process!(job, rest, List.drop_first(translated, 1), glossed_count, index + 1, cost)
	} else {
		step = match translated {
			[saved, ..] => Ok({ conllu: saved, cost })
			[] => translate!(job, source, index, cost)
		}?
		spent = gloss!(job, step.conllu, index, step.cost)?
		process!(job, rest, List.drop_first(translated, 1), glossed_count, index + 1, spent)
	}
}
translate! = |job, source, index, cost| {
	current = "${job.out}/.scratch/current.conllu"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	spent = run_stage!(job, "translate", "${job.out}/config.json", current, sentence_step(job, index, "translate"), cost, 1)?
	result = Path.read_utf8!(Path.utf8("${job.out}/.scratch/translate-output.conllu"))?
	translated = Str.replace_first(result, "# sentence_id = 1", "# sentence_id = ${U64.to_str(index)}")
	_ = append_text!("${job.out}/translations.conllu", block_chunk!("${job.out}/translations.conllu", translated)?)?
	Ok({ conllu: Str.trim(translated), cost: spent })
}
gloss! = |job, source, index, cost| {
	current = "${job.out}/.scratch/current.conllu"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	spent = run_stage!(job, "gloss", "${job.out}/config.json", current, sentence_step(job, index, "gloss"), cost, 1)?
	result = Path.read_utf8!(Path.utf8("${job.out}/.scratch/gloss-output.conllu"))?
	_ = append_text!("${job.out}/output.conllu", block_chunk!("${job.out}/output.conllu", result)?)?
	Ok(spent)
}
run_stage! = |job, stage, config_path, current, step, cost, attempt| {
	_ = progress!(job, step, cost, attempt)?
	scratch = "${job.out}/.scratch"
	# Passage translations run the translate stage with the passage prompt; costs are recorded as `unit`.
	script = if stage == "unit" "translate" else stage
	response = "${scratch}/${script}-api-response.json"
	_ = remove!(response)?
	_ = remove!("${scratch}/${script}-output.conllu")?
	result = Cmd.new_str("env").args_str(["--default-signal=INT", "timeout", "--foreground", "180", "roc", "${stage_dir}/${script}.roc", config_path, current, scratch]).exec_output!()
	spent = cost + record_cost!(job.out, stage, step.index, response)?
	match result {
		Ok(_) => Ok(spent)
		Err(error) => {
			described = Str.inspect(error)
			if Str.contains(described, "killed by signal") {
				Err(Cancelled)
			} else if attempt >= max_attempts or List.any(["InvalidGloss(", "CopiedGreekForm", "MissingGloss", "UnknownGlossIds", "MissingApiKey", "PathErr(NotFound"], |name| Str.contains(described, name)) {
				Err(StageFailed("${step.label} failed after ${U64.to_str(attempt)} attempt(s): ${failure_text(error)}"))
			} else {
				run_stage!(job, stage, config_path, current, step, spent, attempt + 1)
			}
		}
	}
}
failure_text = |error| match error {
	NonZeroExitCode(failure) => {
		lines = List.keep_if(List.map(Str.split_on(failure.stderr_utf8_lossy, "\n"), Str.trim), |line| line != "")
		match List.last(lines) { Ok(line) => line, Err(_) => "exit code ${Str.inspect(failure.exit_code)}" }
	}
	other => Str.inspect(other)
}
# Each attempt's reported cost is appended to costs.tsv, so totals survive cancellation and resume.
record_cost! = |out, stage, index, response| if Path.exists!(Path.utf8(response))? {
	cost = response_cost(Path.read_utf8!(Path.utf8(response))?)
	value = match cost { Ok(amount) => Dec.to_str(amount), Err(_) => "?" }
	_ = append_text!("${out}/costs.tsv", "${stage}\t${U64.to_str(index)}\t${value}\n")?
	Ok(match cost { Ok(amount) => amount, Err(_) => 0 })
} else {
	Ok(0)
}
# PPQ reports router fees in usage.cost; bring-your-own-key calls bill the upstream inference cost separately.
response_cost = |text| {
	byok : Try(ByokUsage, _)
	byok = Json.parse(text)
	match byok {
		Ok(reply) => Ok(if reply.usage.is_byok { reply.usage.cost + reply.usage.cost_details.upstream_inference_cost } else { reply.usage.cost })
		Err(_) => {
			basic : Try(Usage, _)
			basic = Json.parse(text)
			match basic { Ok(reply) => Ok(reply.usage.cost), Err(_) => Err(NoReportedCost) }
		}
	}
}
read_costs! : Str => Try(Costs, _)
read_costs! = |out| {
	path = "${out}/costs.tsv"
	if Path.exists!(Path.utf8(path))? {
		Ok(sum_costs(Str.split_on(Path.read_utf8!(Path.utf8(path))?, "\n"), { total: 0, unknown: 0 }))
	} else {
		Ok({ total: 0, unknown: 0 })
	}
}
sum_costs : List(Str), Costs -> Costs
sum_costs = |lines, found| match lines {
	[] => found
	[line, .. as rest] => match Str.split_on(line, "\t") {
		[_, _, value] => match Dec.from_str(value) {
			Ok(amount) => sum_costs(rest, { total: found.total + amount, unknown: found.unknown })
			Err(_) => sum_costs(rest, { total: found.total, unknown: found.unknown + 1 })
		}
		_ => sum_costs(rest, found)
	}
}
# One in-place status line on stderr; carriage return plus erase-line avoids scrolling output.
progress! = |_job, step, cost, attempt| {
	filled = if step.total == 0 0 else step.done * bar_width // step.total
	percent = if step.total == 0 0 else step.done * 100 // step.total
	retry = if attempt > 1 " · retry ${U64.to_str(attempt)}/${U64.to_str(max_attempts)}" else ""
	Stderr.write!("\r\u(1b)[2K[${repeat("█", filled)}${repeat("░", bar_width - filled)}] ${U64.to_str(step.done)}/${U64.to_str(step.total)} ${U64.to_str(percent)}% · ${step.label}${retry} · ${usd(cost)}")
}
# Glossing sentences comes first; the bar then counts passages.
sentence_step = |job, index, stage| { index, done: index - 1, total: job.sentences, label: "sentence ${U64.to_str(index)}/${U64.to_str(job.sentences)} ${stage}" }
summary! = |job, outcome| {
	units = read_unit_refs!(job.out)?
	costs = read_costs!(job.out)?
	done = List.len(List.keep_if(job.wanted, |passage| List.contains(units, passage.ref)))
	status = match outcome {
		Ok(_) => "Finished."
		Err(Cancelled) => "Cancelled."
		Err(StageFailed(message)) => "Failed: ${message}"
		Err(other) => "Failed: ${Str.inspect(other)}"
	}
	unknown = if costs.unknown > 0 " (${U64.to_str(costs.unknown)} call(s) reported no cost)" else ""
	resume = match outcome {
		Ok(_) => []
		Err(_) => ["  resume:     kai run generate -- ${job.work} ${job.config_path} ${job.count_arg}"]
	}
	lines = List.concat(
		[
			status,
			"  requested:  ${U64.to_str(done * 100 // job.requested)}% complete (${U64.to_str(done)} of ${U64.to_str(job.requested)} requested)",
			"  input:      ${tenths(List.len(units) * 1000 // job.available)}% complete (${U64.to_str(List.len(units))} of ${U64.to_str(job.available)} passages in ${job.input})",
			"  cost:       ${usd(costs.total - job.cost_at_start)} this run · ${usd(costs.total)} total for ${job.out}${unknown}",
			"  output:     ${job.out}/output.conllu (glosses), ${job.out}/units.jsonl (passage translations)",
		],
		resume,
	)
	Stdout.line!(Str.join_with(lines, "\n"))
}
usd = |amount| {
	text = Dec.to_str(amount)
	match Str.split_on(text, ".") {
		[whole, fraction] => "$${whole}.${Str.from_utf8(take(Str.to_utf8(Str.concat(fraction, "0000")), 4, [])) ?? "0000"}"
		_ => "$${text}.0000"
	}
}
tenths = |value| "${U64.to_str(value // 10)}.${U64.to_str(value % 10)}"
repeat = |text, count| if count == 0 "" else Str.concat(text, repeat(text, count - 1))
valid_work = |work| work != "" and !Str.contains(work, "/") and !Str.contains(work, " ") and !Str.starts_with(work, ".")
remove! = |path| if Path.exists!(Path.utf8(path))? { Path.delete!(Path.utf8(path)) } else { Ok({}) }
read_blocks! = |path| if Path.exists!(Path.utf8(path))? { Ok(blocks_from(Path.read_utf8!(Path.utf8(path))?)) } else { Ok([]) }
blocks_from = |text| List.keep_if(List.map(Str.split_on(Str.trim(text), "\n\n"), Str.trim), |block| block != "")
take = |items, count, found| if count == 0 found else match items { [] => found, [item, .. as rest] => take(rest, count - 1, List.append(found, item)) }
block_chunk! = |path, content| if Path.exists!(Path.utf8(path))? { Ok("\n\n${Str.trim(content)}\n") } else { Ok("${Str.trim(content)}\n") }
# basic-cli has no append mode; dd appends without rewriting completed checkpoints.
append_text! = |path, chunk| {
	temp_path = "${path}.append"
	_ = Path.write_utf8!(Path.utf8(temp_path), chunk)?
	_ = Cmd.new_str("dd").args_str(["if=${temp_path}", "of=${path}", "oflag=append", "conv=notrunc", "status=none"]).exec_output!()?
	Path.delete!(Path.utf8(temp_path))
}
# Passages come from scripts/passages.roc, since a Roc app can import modules only from its own folder.
passages! = |input| {
	output = Cmd.new_str("roc").args_str(["scripts/passages.roc", input]).exec_output!()?
	found : List(Passage)
	found = Json.parse(Str.trim(output.stdout_utf8))?
	Ok(found)
}
# The leading sentence blocks that contain every token of the wanted passages.
sentences_needed = |source, wanted| {
	last = match List.last(wanted) {
		Ok(passage) => List.last(passage.tokens) ?? ""
		Err(_) => ""
	}
	count_until(source, last, 1)
}
count_until = |blocks, token, index| match blocks {
	[] => index - 1
	[block, .. as rest] => if List.contains(block_tokens(block), token) index else count_until(rest, token, index + 1)
}
# `t_N` ids of a block's visible rows (OGA placeholder rows `e_…` excluded).
block_tokens = |block| List.keep_oks(Str.split_on(block, "\n"), |line|
	if Str.starts_with(line, "#") {
		Err(Comment)
	} else {
		match Str.split_on(line, "\t") {
			[_, _, _, _, _, _, _, _, _, misc] => {
				token = List.first(Str.split_on(misc, "|")) ?? ""
				if Str.starts_with(token, "t_") Ok(token) else Err(Placeholder)
			}
			_ => Err(NotARow)
		}
	})
# Translates each wanted passage not yet in units.jsonl, from its glossed rows and the sentences it belongs to.
process_units! = |job, config_text, cost| {
	stage : StageConfig
	stage = Json.parse(config_text)?
	base : UnitInstruction
	base = Json.parse(Path.read_utf8!(Path.utf8(base_prompts))?)?
	unit_config = Json.to_str_try({ ..stage, translate: { max_tokens: stage.translate.max_tokens, prompt: "${stage.translate.prompt} ${base.unit_instruction}" } })?
	_ = bind_unit_config!(job.out, unit_config)?
	glossed = read_blocks!("${job.out}/output.conllu")?
	translated = read_blocks!("${job.out}/translations.conllu")?
	contexts = List.map2(glossed, pad(translated, List.len(glossed)), |block, translation| { block, tokens: block_tokens(block), greek: greek_text(block), prose: comment_value(translation, "prose_translation") })
	done = read_unit_refs!(job.out)?
	units!(job, job.wanted, 1, done, contexts, cost)
}
pad = |items, count| if List.len(items) >= count items else pad(List.append(items, ""), count)
units! = |job, passages, index, done, contexts, cost| match passages {
	[] => Ok({})
	[passage, .. as rest] => if List.contains(done, passage.ref) {
		units!(job, rest, index + 1, done, contexts, cost)
	} else {
		owners = List.keep_if(contexts, |context| List.any(passage.tokens, |token| List.contains(context.tokens, token)))
		rows = List.join(List.map(owners, |context| List.keep_if(Str.split_on(context.block, "\n"), |line| !Str.starts_with(line, "#") and List.contains(passage.tokens, row_token(line)))))
		comments = List.concat(["# passage = ${passage.label}"], List.join(List.map(owners, |context| ["# context_sentence_greek = ${context.greek}", "# context_sentence_translation = ${context.prose}"])))
		current = "${job.out}/.scratch/current.conllu"
		_ = Path.write_utf8!(Path.utf8(current), "${Str.join_with(List.concat(comments, rows), "\n")}\n")?
		step = { index, done: index - 1, total: job.requested, label: "passage ${passage.label}" }
		spent = run_stage!(job, "unit", "${job.out}/units.config.json", current, step, cost, 1)?
		result = Path.read_utf8!(Path.utf8("${job.out}/.scratch/translate-output.conllu"))?
		line = Json.to_str_try({ ref: passage.ref, label: passage.label, tokens: passage.tokens, prose: comment_value(result, "prose_translation"), literal: comment_value(result, "literal_translation") })?
		_ = append_text!("${job.out}/units.jsonl", "${line}\n")?
		units!(job, rest, index + 1, List.append(done, passage.ref), contexts, spent)
	}
}
# The passage prompt is pinned like config.json: resuming with a changed prompt would mix translations.
bind_unit_config! = |out, content| {
	path = "${out}/units.config.json"
	if Path.exists!(Path.utf8(path))? {
		if Path.read_utf8!(Path.utf8(path))? == content { Ok({}) } else { Err(CheckpointInputChanged(path)) }
	} else if Path.exists!(Path.utf8("${out}/units.jsonl"))? {
		Err(MissingCheckpointSnapshot(path))
	} else {
		Path.write_utf8!(Path.utf8(path), content)
	}
}
read_unit_refs! = |out| {
	path = "${out}/units.jsonl"
	if Path.exists!(Path.utf8(path))? {
		lines = List.keep_if(Str.split_on(Path.read_utf8!(Path.utf8(path))?, "\n"), |line| Str.trim(line) != "")
		Ok(List.keep_oks(lines, |line| {
			unit : Try({ ref : Str }, _)
			unit = Json.parse(line)
			match unit {
				Ok(record) => Ok(record.ref)
				Err(problem) => Err(problem)
			}
		}))
	} else {
		Ok([])
	}
}
row_token = |line| match Str.split_on(line, "\t") {
	[_, _, _, _, _, _, _, _, _, misc] => List.first(Str.split_on(misc, "|")) ?? ""
	_ => ""
}
greek_text = |block| Str.join_with(List.keep_oks(Str.split_on(block, "\n"), |line| if Str.starts_with(line, "#") Err(Comment) else match Str.split_on(line, "\t") {
	[_, form, _, _, _, _, _, _, _, misc] => if Str.starts_with(misc, "e_") Err(Placeholder) else Ok(form)
	_ => Err(NotARow)
}), " ")
comment_value = |block, key| {
	prefix = "# ${key} = "
	match List.keep_if(Str.split_on(block, "\n"), |line| Str.starts_with(line, prefix)) {
		[line, ..] => Str.replace_first(line, prefix, "")
		[] => ""
	}
}
