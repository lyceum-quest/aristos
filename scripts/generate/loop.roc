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
Source : { corpus : Str, work : Str, edition : Str, license : Str }
WorkConfig : { input : Str, source : Source, model : Str, base_url : Str, api_key_env : Str, allow_fallbacks : Bool, send_temperature : Bool, structured_schema : Bool, temperature : Dec, context : Str, translate : { max_tokens : U64 }, gloss : { max_tokens : U64 } }
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
	_ => Err(Usage("loop.roc <work> <config.json> <sentence-count|all>"))
}
run! = |work, config_path, count_arg| {
	_ = (if valid_work(work) { Ok({}) } else { Err(InvalidWork(work)) })?
	config_text = resolve_config!(Path.read_utf8!(Path.utf8(config_path))?)?
	config : LoopConfig
	config = Json.parse(config_text)?
	source = blocks_from(Str.replace_each(Path.read_utf8!(Path.utf8(config.input))?, "\r\n", "\n"))
	available = List.len(source)
	requested = (if count_arg == "all" { Ok(available) } else { U64.from_str(count_arg) })?
	_ = (if requested == 0 or requested > available { Err(InvalidSentenceCount(requested, available)) } else { Ok({}) })?
	out = "conllu/generated/${work}-${Str.replace_each(config.model, "/", "-")}"
	_ = Path.create_all!(Path.utf8("${out}/.scratch"))?
	costs = read_costs!(out)?
	job = { work, config_path, count_arg, input: config.input, out, requested, available, cost_at_start: costs.total }
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
	_ = Stdout.line!("${job.work}: ${U64.to_str(List.len(glossed))} sentence(s) already done; generating up to ${U64.to_str(job.requested)} into ${job.out}")?
	process!(job, take(source, job.requested, []), translated, List.len(glossed), 1, job.cost_at_start)
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
				source: work.source,
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
bind_config! = |out, content| {
	path = "${out}/config.json"
	if Path.exists!(Path.utf8(path))? {
		if Path.read_utf8!(Path.utf8(path))? == content { Ok({}) } else { Err(CheckpointInputChanged(path)) }
	} else if Path.exists!(Path.utf8("${out}/translations.conllu"))? {
		Err(MissingCheckpointSnapshot(path))
	} else {
		Path.write_utf8!(Path.utf8(path), content)
	}
}
# The source snapshot may grow with larger requests, but its existing prefix must never change.
bind_source! = |job, source, translated_count| {
	path = "${job.out}/source.conllu"
	saved = read_blocks!(path)?
	_ = (if List.len(saved) < translated_count or saved != take(source, List.len(saved), []) { Err(CheckpointInputChanged(path)) } else { Ok({}) })?
	keep = if List.len(saved) > job.requested List.len(saved) else job.requested
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
	spent = run_stage!(job, "translate", current, index, cost, 1)?
	result = Path.read_utf8!(Path.utf8("${job.out}/.scratch/translate-output.conllu"))?
	translated = Str.replace_first(result, "# sentence_id = 1", "# sentence_id = ${U64.to_str(index)}")
	_ = append_text!("${job.out}/translations.conllu", block_chunk!("${job.out}/translations.conllu", translated)?)?
	Ok({ conllu: Str.trim(translated), cost: spent })
}
gloss! = |job, source, index, cost| {
	current = "${job.out}/.scratch/current.conllu"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	spent = run_stage!(job, "gloss", current, index, cost, 1)?
	result = Path.read_utf8!(Path.utf8("${job.out}/.scratch/gloss-output.conllu"))?
	_ = append_text!("${job.out}/output.conllu", block_chunk!("${job.out}/output.conllu", result)?)?
	Ok(spent)
}
run_stage! = |job, stage, current, index, cost, attempt| {
	_ = progress!(job, index, stage, cost, attempt)?
	scratch = "${job.out}/.scratch"
	response = "${scratch}/${stage}-api-response.json"
	_ = remove!(response)?
	_ = remove!("${scratch}/${stage}-output.conllu")?
	result = Cmd.new_str("env").args_str(["--default-signal=INT", "timeout", "--foreground", "180", "roc", "${stage_dir}/${stage}.roc", "${job.out}/config.json", current, scratch]).exec_output!()
	spent = cost + record_cost!(job.out, stage, index, response)?
	match result {
		Ok(_) => Ok(spent)
		Err(error) => {
			described = Str.inspect(error)
			if Str.contains(described, "killed by signal") {
				Err(Cancelled)
			} else if attempt >= max_attempts or List.any(["InvalidGloss(", "CopiedGreekForm", "MissingGloss", "UnknownGlossIds", "MissingApiKey", "PathErr(NotFound"], |name| Str.contains(described, name)) {
				Err(StageFailed("${stage} failed on sentence ${U64.to_str(index)} after ${U64.to_str(attempt)} attempt(s): ${failure_text(error)}"))
			} else {
				run_stage!(job, stage, current, index, spent, attempt + 1)
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
progress! = |job, index, stage, cost, attempt| {
	done = index - 1
	filled = done * bar_width // job.requested
	retry = if attempt > 1 " · retry ${U64.to_str(attempt)}/${U64.to_str(max_attempts)}" else ""
	Stderr.write!("\r\u(1b)[2K[${repeat("█", filled)}${repeat("░", bar_width - filled)}] ${U64.to_str(done)}/${U64.to_str(job.requested)} ${U64.to_str(done * 100 // job.requested)}% · sentence ${U64.to_str(index)} ${stage}${retry} · ${usd(cost)}")
}
summary! = |job, outcome| {
	glossed = List.len(read_blocks!("${job.out}/output.conllu")?)
	costs = read_costs!(job.out)?
	done = if glossed > job.requested job.requested else glossed
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
			"  input:      ${tenths(glossed * 1000 // job.available)}% complete (${U64.to_str(glossed)} of ${U64.to_str(job.available)} sentences in ${job.input})",
			"  cost:       ${usd(costs.total - job.cost_at_start)} this run · ${usd(costs.total)} total for ${job.out}${unknown}",
			"  output:     ${job.out}/output.conllu",
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
