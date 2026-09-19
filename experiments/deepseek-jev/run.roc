app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.Http
import cli.OsStr
import cli.Path
import cli.Sleep
import cli.Stderr
import cli.Stdout
import cli.Utc
import http.Request
import http.Response

Generation : {
	allow_fallbacks : Bool,
	frequency_penalty : Dec,
	include_reasoning : Bool,
	max_tokens : U64,
	presence_penalty : Dec,
	reasoning : { enabled : Bool, exclude : Bool },
	require_parameters : Bool,
	seed : U64,
	temperature : Dec,
	top_k : U64,
	top_p : Dec,
}
Retry : { backoff_initial_ms : U64, backoff_max_ms : U64, malformed_response_retries : U64, max_retry_after_ms : U64, transport_retries : U64 }
Config : {
	execution : { acceptance_threshold : Dec, max_semantic_rounds : U64, smoke_token_count : U64 },
	experiment_name : Str,
	experiment_version : U64,
	generator : {
		generation : Generation,
		model : Str,
		provider : { api_key_env : Str, base_url : Str, id : Str, name : Str, request_name : Str, response_name : Str },
	},
	input : { line_count : U64, source_path : Str, source_sha256 : Str, token_count : U64, tokens_path : Str, tokens_sha256 : Str },
	retry : Retry,
	validator : {
		input_cost_per_million_tokens_usd : Dec,
		model : Str,
		primitive : Str,
		provider : { api_key_env : Str, endpoint : Str, name : Str },
	},
}
Token : { id : U64, line : U64, position : U64, word : Str }
DeepRow : { gloss : Str, id : U64, word : Str }
DeepPayload : { round : U64, tokens : List(DeepRow) }
DeepResponse : {
	choices : List({ finish_reason : Str, message : { content : Str } }),
	id : Str,
	model : Str,
	provider : Str,
	usage : { completion_tokens : U64, completion_tokens_details : { reasoning_tokens : U64 }, cost : Dec, prompt_tokens : U64, total_tokens : U64 },
}
JevAnswer : { noul : Dec, type : Str }
JevResponse : { answers : Dict(Str, JevAnswer), model : Str, usage : { input_tokens : U64, output_tokens : U64 } }
Usage : { input_tokens : U64, output_tokens : U64, reasoning_tokens : U64, total_tokens : U64 }
Accounting : { ambiguous_attempts : U64, charged_attempts : U64, known_cost_usd : Dec }
CallAudit : {
	client_request_id : Str,
	cost_usd : Dec,
	elapsed_ms : U128,
	headers_path : Str,
	provider_request_id : Str,
	raw_response_path : Str,
	received_at : Str,
	request_path : Str,
	requested_at : Str,
	requested_model : Str,
	requested_provider : Str,
	resolved_model : Str,
	resolved_provider : Str,
	response_id : Str,
	token_usage : Usage,
	transport : Str,
	transport_attempt : U64,
	validation_attempt : U64,
}
GeneratedCheckpoint : {
	call : CallAudit,
	experiment_version : U64,
	generated : List(DeepRow),
	pending_ids : List(U64),
	round : U64,
	run_id : Str,
}
Judgment : { accepted : Bool, gloss : Str, id : U64, key : Str, score : Dec, threshold : Dec, word : Str }
RoundCheckpoint : {
	accepted_ids : List(U64),
	deepseek_call : CallAudit,
	experiment_version : U64,
	generated : List(DeepRow),
	jev_call : CallAudit,
	judgments : List(Judgment),
	pending_ids : List(U64),
	rejected_ids : List(U64),
	round : U64,
	run_id : Str,
}
FinalRow : { gloss : Str, valid : Bool, word : Str }
Metrics : { first_pass_accepted : U64, round_2_recovered : U64, round_3_recovered : U64, unresolved : U64 }
Manifest : { experiment_version : U64, mode : Str, run_id : Str, target_count : U64 }
AttemptRecord : {
	ambiguous_possible_charge : Bool,
	client_request_id : Str,
	cost_usd : Dec,
	elapsed_ms : U128,
	headers_path : Str,
	http_status : U16,
	provider_request_id : Str,
	raw_response_path : Str,
	received_at : Str,
	request_path : Str,
	requested_at : Str,
	retry_delay_ms : U64,
	round : U64,
	run_id : Str,
	stage : Str,
	status : Str,
	transport : Str,
	transport_attempt : U64,
	transport_output_path : Str,
	validation_attempt : U64,
	validation_error : Str,
}
RunAudit : {
	accounting : Accounting,
	attempts : List(AttemptRecord),
	config : Config,
	final_path : Str,
	metrics : Metrics,
	mode : Str,
	rounds : List(RoundCheckpoint),
	run_id : Str,
	source_sha256 : Str,
	tokens_sha256 : Str,
}
HeaderRecord : { name : Str, value : Str }
CurlOutputRecord : { exit_code : Str, http_status : U16, stderr : Str, stdout : Str }
JevQuestion : { criteria : { false : Str, true : Str }, instructions : Str, type : Str }
JevStateRow : { gloss : Str, id : U64, line : U64, position : U64, word : Str }
PromptToken : { id : U64, line : U64, position : U64, previous_rejected_glosses : List(Str), word : Str }

experiment_dir = "experiments/deepseek-jev"
config_path = "experiments/deepseek-jev/config.json"
unresolved = "[UNRESOLVED]"

main! = |args| {
	displayed = List.map(args, OsStr.display)
	match List.drop_first(displayed, 1) {
		["--check"] => check!()
		["--smoke"] => start!("smoke")
		["--run"] => start!("full")
		["--resume-smoke"] => resume!("smoke")
		["--resume"] => resume!("full")
		_ => {
			_ = Stderr.line!("usage: run.roc [--check | --smoke | --run | --resume-smoke | --resume]")?
			Err(Exit(2))
		}
	}
}

check! = || {
	prepared = prepare!()?
	tokens = prepared.tokens
	fake1 = fake_generated(tokens, 1)
	_ = validate_generated(1, tokens, [], fake1)?
	scores1 = synthetic_judgments(prepared.config, 1, fake1, "odd")?
	pending2 = tokens_for_ids(tokens, rejected_ids(scores1), [])?
	fake2 = fake_generated(pending2, 2)
	_ = validate_generated(2, pending2, [fake1.tokens], fake2)?
	scores2 = synthetic_judgments(prepared.config, 2, fake2, "half")?
	pending3 = tokens_for_ids(tokens, rejected_ids(scores2), [])?
	fake3 = fake_generated(pending3, 3)
	_ = validate_generated(3, pending3, [fake1.tokens, fake2.tokens], fake3)?
	scores3 = synthetic_judgments(prepared.config, 3, fake3, "reject")?
	rounds : List(RoundCheckpoint)
	rounds = [fake_round(1, fake1, scores1), fake_round(2, fake2, scores2), fake_round(3, fake3, scores3)]
	final = assemble_final(tokens, rounds)
	_ = validate_final(tokens, final)?
	_ = validate_simulation(tokens, rounds, final)?
	all_accepted = synthetic_judgments(prepared.config, 1, fake1, "accept")?
	early_rounds = [fake_round(1, fake1, all_accepted)]
	early_final = assemble_final(tokens, early_rounds)
	if !List.is_empty(rejected_ids(all_accepted)) {
		Err(EarlyTerminationSimulationFailed)
	} else {
		_ = validate_simulation(tokens, early_rounds, early_final)?
		deep_body = deep_request_body(prepared.config, prepared.source, 1, tokens, [], "")?
		jev_body = jev_request_body(prepared.config, prepared.source, 1, tokens, fake1.tokens)?
		_deep_json : {}
		_deep_json = Json.parse(deep_body)?
		_jev_json : {}
		_jev_json = Json.parse(jev_body)?
		_ = Stdout.line!("checked deepseek-jev: hashes, 136-token reconstruction, pinned requests, three-round routing, early stop, unresolved output, and retry limits; no API keys read and no requests sent")?
		Ok({})
	}
}

prepare! = || {
	raw_config = Path.read_utf8!(Path.utf8(config_path))?
	config : Config
	config = Json.parse(raw_config)?
	_ = validate_config(config)?
	_ = verify_sha256!(config.input.source_path, config.input.source_sha256, |expected, actual| SourceHashMismatch(expected, actual))?
	_ = verify_sha256!(config.input.tokens_path, config.input.tokens_sha256, |expected, actual| TokensHashMismatch(expected, actual))?
	source = Path.read_utf8!(Path.utf8(config.input.source_path))?
	raw_tokens = Path.read_utf8!(Path.utf8(config.input.tokens_path))?
	tokens : List(Token)
	tokens = Json.parse(raw_tokens)?
	_ = validate_fixed_input(source, tokens, config)?
	Ok({ config, source, tokens })
}

validate_config = |config| {
	g = config.generator.generation
	r = config.retry
	if config.experiment_name != "deepseek-jev-adaptive-gloss" or config.experiment_version != 1 {
		Err(InvalidExperimentIdentity)
	} else if config.input.source_path != "experiments/deepseek-jev/iliad-1.1-20.txt" or config.input.source_sha256 != "1263ac162eea8365bd04261361668fab579c2f97299ac0a8b4429f7f33133807" or config.input.tokens_path != "experiments/deepseek-jev/tokens.json" or config.input.tokens_sha256 != "09497d4c5decffba19b456258396a578d86d880847f1b49c44038d91c10fe32a" or config.input.line_count != 20 or config.input.token_count != 136 {
		Err(InvalidInputPins)
	} else if config.generator.provider != { api_key_env: "PPQ_API_KEY", base_url: "https://api.ppq.ai/v1", id: "sail-research", name: "ppq", request_name: "sail-research", response_name: "Sail Research" } or config.generator.model != "deepseek/deepseek-v4-flash-0731" {
		Err(InvalidGeneratorPins)
	} else if g.temperature != 1 or g.top_p != 1 or g.top_k != 0 or g.seed != 1 or g.max_tokens != 4096 or g.frequency_penalty != 0 or g.presence_penalty != 0 or g.reasoning.enabled or !g.reasoning.exclude or g.include_reasoning or !g.require_parameters or g.allow_fallbacks {
		Err(InvalidGenerationPins)
	} else if config.validator.provider != { api_key_env: "TYPESAFE_API_KEY", endpoint: "https://api.typesafe.ai/v1/systemone", name: "typesafe" } or config.validator.model != "jev-1.13.0" or config.validator.primitive != "noul" or config.validator.input_cost_per_million_tokens_usd != 0.042 {
		Err(InvalidValidatorPins)
	} else if config.execution.max_semantic_rounds != 3 or config.execution.acceptance_threshold != 0.5 or config.execution.smoke_token_count != 10 {
		Err(InvalidExecutionPins)
	} else if r.malformed_response_retries != 1 or r.transport_retries != 2 or r.backoff_initial_ms != 500 or r.backoff_max_ms != 5000 or r.max_retry_after_ms != 60000 {
		Err(InvalidRetryPins)
	} else {
		Ok({})
	}
}

validate_fixed_input = |source, tokens, config| {
	if List.len(tokens) != config.input.token_count {
		Err(WrongTokenCount(config.input.token_count, List.len(tokens)))
	} else if Str.contains(source, "\r") or Str.contains(source, "\t") or List.len(Str.split_on(Str.trim_end(source), "\n")) != config.input.line_count {
		Err(InvalidSourceShape)
	} else {
		_ = validate_tokens(tokens, 1, 1, 1)?
		reconstructed = reconstruct_source(tokens, 1, "")
		if reconstructed != source Err(SourceReconstructionMismatch) else Ok({})
	}
}

validate_tokens = |tokens, expected_id, expected_line, expected_position|
	match tokens {
		[] => Ok({})
		[token, .. as rest] => {
			if token.id != expected_id or token.word == "" or token.line == 0 or token.position == 0 {
				Err(InvalidToken(expected_id))
			} else if token.line == expected_line and token.position == expected_position {
				validate_tokens(rest, expected_id + 1, expected_line, expected_position + 1)
			} else if token.line == expected_line + 1 and token.position == 1 {
				validate_tokens(rest, expected_id + 1, expected_line + 1, 2)
			} else {
				Err(InvalidTokenLocation(token.id))
			}
		}
	}

reconstruct_source = |tokens, current_line, found|
	match tokens {
		[] => "${found}\n"
		[token, .. as rest] => {
			separator = if found == "" "" else if token.line == current_line " " else "\n"
			reconstruct_source(rest, token.line, "${found}${separator}${token.word}")
		}
	}

verify_sha256! = |path, expected, mismatch| {
	output = Cmd.new_str("sha256sum").args_str([path]).exec_output!()?
	actual = match Str.split_on(Str.trim(output.stdout_utf8), " ") { [hash, ..] => Ok(hash), [] => Err(InvalidSha256Output) }?
	if actual == expected Ok({}) else Err(mismatch(expected, actual))
}

start! = |mode| {
	prepared = prepare!()?
	_ = authorize_paid!(mode)?
	_ = (if mode == "full" require_completed_smoke!(prepared.config, prepared.tokens) else Ok({}))?
	keys = read_keys!(prepared.config)?
	target_tokens = if mode == "smoke" take_exact(prepared.tokens, prepared.config.execution.smoke_token_count, [])? else prepared.tokens
	now = Utc.now!()
	run_id = "${mode}-${run_id_for(now, prepared.config.experiment_version)}"
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/${mode}/${run_id}"
	_ = create_run!(prepared.config, mode, run_id, run_dir, output_dir, List.len(target_tokens))?
	_ = acquire_run_lock!(run_dir)?
	result = execute!(prepared, target_tokens, keys, mode, run_id, run_dir, output_dir)
	_ = release_run_lock!(run_dir)?
	result
}

resume! = |mode| {
	prepared = prepare!()?
	_ = authorize_paid!(mode)?
	run_id = latest_incomplete_run!(mode)?
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/${mode}/${run_id}"
	target_tokens = if mode == "smoke" take_exact(prepared.tokens, prepared.config.execution.smoke_token_count, [])? else prepared.tokens
	_ = validate_manifest!(prepared.config, mode, run_id, run_dir, output_dir, List.len(target_tokens))?
	_ = acquire_run_lock!(run_dir)?
	result = resume_locked!(prepared, target_tokens, mode, run_id, run_dir, output_dir)
	_ = release_run_lock!(run_dir)?
	result
}

resume_locked! = |prepared, target_tokens, mode, run_id, run_dir, output_dir| {
	_ = preflight_resume_artifacts!(run_dir)?
	keys = read_keys!(prepared.config)?
	execute!(prepared, target_tokens, keys, mode, run_id, run_dir, output_dir)
}

acquire_run_lock! = |run_dir| {
	lock = "${run_dir}/.run-lock"
	result = Cmd.new_str("mkdir").args_str([lock]).exec_output!()
	match result {
		Ok(_) => Ok({})
		Err(_) => Err(RunLocked(run_dir))
	}
}

release_run_lock! = |run_dir| Path.delete_empty!(Path.utf8("${run_dir}/.run-lock"))

authorize_paid! = |mode| {
	wanted = if mode == "smoke" "smoke" else "full"
	actual = Env.var_str!("DEEPSEEK_JEV_AUTHORIZE") ?? ""
	if actual == wanted Ok({}) else Err(PaidAuthorizationRequired(wanted))
}

read_keys! = |config| {
	ppq = read_key!(config.generator.provider.api_key_env)?
	typesafe = read_key!(config.validator.provider.api_key_env)?
	Ok({ ppq, typesafe })
}

read_key! = |name| {
	exported = if name == "PPQ_API_KEY" Env.var_str!("PPQ_API_KEY") ?? "" else if name == "TYPESAFE_API_KEY" Env.var_str!("TYPESAFE_API_KEY") ?? "" else ""
	if Str.trim(exported) != "" {
		Ok(Str.trim(exported))
	} else {
		env = Path.read_utf8!(Path.utf8(".env"))?
		env_value(env, name)
	}
}

env_value = |env, name| {
	prefix = "${name}="
	match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) {
		[line, ..] => {
			value = Str.trim(Str.replace_first(line, prefix, ""))
			if value == "" Err(MissingApiKey(name)) else Ok(value)
		}
		[] => Err(MissingApiKey(name))
	}
}

create_run! = |config, mode, run_id, run_dir, output_dir, target_count| {
	if Path.exists!(Path.utf8(run_dir))? or Path.exists!(Path.utf8(output_dir))? {
		Err(RunAlreadyExists(run_id))
	} else {
		_ = Path.create_all!(Path.utf8(run_dir))?
		_ = Path.create_all!(Path.utf8(output_dir))?
		manifest : Manifest
		manifest = { experiment_version: config.experiment_version, mode, run_id, target_count }
		json = Json.to_str_try(manifest)?
		write_new_utf8!("${json}\n", "${run_dir}/run.json")
	}
}

validate_manifest! = |config, mode, run_id, run_dir, output_dir, target_count| {
	if !Path.exists!(Path.utf8(output_dir))? or Path.exists!(Path.utf8("${run_dir}/run.complete"))? {
		Err(InvalidResumeRun(run_id))
	} else {
		raw = Path.read_utf8!(Path.utf8("${run_dir}/run.json"))?
		manifest : Manifest
		manifest = Json.parse(raw)?
		if manifest == { experiment_version: config.experiment_version, mode, run_id, target_count } Ok({}) else Err(ManifestMismatch(run_id))
	}
}

execute! = |prepared, target_tokens, keys, mode, run_id, run_dir, output_dir| {
	progress = load_progress!(prepared.config, target_tokens, run_id, run_dir, 1, target_tokens, [], [])?
	completed = run_rounds!(prepared, target_tokens, keys, run_id, run_dir, progress.next_round, progress.pending, progress.rounds)?
	final = assemble_final(target_tokens, completed)
	_ = validate_final(target_tokens, final)?
	final_path = "${output_dir}/final.json"
	audit_path = "${output_dir}/audit.json"
	attempts = List.sort_with(read_all_attempts!(run_dir, run_id)?, compare_attempt_records)
	audit : RunAudit
	audit = {
		accounting: accounting_for(attempts),
		attempts,
		config: prepared.config,
		final_path,
		metrics: metrics_for(completed, final),
		mode,
		rounds: completed,
		run_id,
		source_sha256: prepared.config.input.source_sha256,
		tokens_sha256: prepared.config.input.tokens_sha256,
	}
	final_json = Json.to_str_try(final)?
	audit_json = Json.to_str_try(audit)?
	_ = write_atomic_or_verify!("${final_json}\n", final_path)?
	_ = write_atomic_or_verify!("${audit_json}\n", audit_path)?
	_ = write_atomic_or_verify!("complete\n", "${run_dir}/run.complete")?
	_ = Stdout.line!("completed ${run_id}\t${final_path}\t${audit_path}")?
	Ok({})
}

load_progress! = |config, target_tokens, run_id, run_dir, round, pending, rounds, previous_generated| {
	if round > config.execution.max_semantic_rounds or List.is_empty(pending) {
		Ok({ next_round: round, pending, rounds })
	} else {
		path = round_checkpoint_path(run_dir, round)
		if Path.exists!(Path.utf8(path))? {
			raw = Path.read_utf8!(Path.utf8(path))?
			checkpoint : RoundCheckpoint
			checkpoint = Json.parse(raw)?
			_ = validate_round_checkpoint!(config, target_tokens, run_id, round, pending, previous_generated, checkpoint)?
			next_pending = tokens_for_ids(target_tokens, checkpoint.rejected_ids, [])?
			load_progress!(config, target_tokens, run_id, run_dir, round + 1, next_pending, List.append(rounds, checkpoint), List.append(previous_generated, checkpoint.generated))
		} else {
			Ok({ next_round: round, pending, rounds })
		}
	}
}

run_rounds! = |prepared, target_tokens, keys, run_id, run_dir, round, pending, rounds| {
	if round > prepared.config.execution.max_semantic_rounds or List.is_empty(pending) {
		Ok(rounds)
	} else {
		generated_path = generated_checkpoint_path(run_dir, round)
		generated_checkpoint = if Path.exists!(Path.utf8(generated_path))? {
			raw = Path.read_utf8!(Path.utf8(generated_path))?
			loaded : GeneratedCheckpoint
			loaded = Json.parse(raw)?
			_ = validate_generated_checkpoint!(prepared.config, run_id, round, pending, List.map(rounds, |r| r.generated), loaded)?
			loaded
		} else {
			state = next_attempt_state!(run_dir, run_id, "deepseek", round, prepared.config.retry)?
			run_deep_attempt!(prepared, pending, List.map(rounds, |r| r.generated), keys.ppq, run_id, run_dir, round, state.validation_attempt, state.transport_attempt, state.feedback)?
		}
		checkpoint_path = round_checkpoint_path(run_dir, round)
		checkpoint = if Path.exists!(Path.utf8(checkpoint_path))? {
			raw = Path.read_utf8!(Path.utf8(checkpoint_path))?
			loaded : RoundCheckpoint
			loaded = Json.parse(raw)?
			_ = validate_round_checkpoint!(prepared.config, target_tokens, run_id, round, pending, List.map(rounds, |r| r.generated), loaded)?
			loaded
		} else {
			body = jev_request_body(prepared.config, prepared.source, round, pending, generated_checkpoint.generated)?
			state = next_attempt_state!(run_dir, run_id, "jev", round, prepared.config.retry)?
			run_jev_attempt!(prepared.config, target_tokens, generated_checkpoint, keys.typesafe, run_id, run_dir, round, state.validation_attempt, state.transport_attempt, body)?
		}
		next_pending = tokens_for_ids(target_tokens, checkpoint.rejected_ids, [])?
		run_rounds!(prepared, target_tokens, keys, run_id, run_dir, round + 1, next_pending, List.append(rounds, checkpoint))
	}
}

deep_request_body = |config, source, round, pending, previous_rounds, feedback| {
	g : Generation
	g = config.generator.generation
	model_id : Str
	model_id = config.generator.model
	provider_request_name : Str
	provider_request_name = config.generator.provider.request_name
	prior_instruction = if round == 1 "No prior glosses exist." else "For each token, prior_rejected_glosses lists every earlier rejected gloss. Produce a different replacement after trimming and ASCII-case folding."
	correction = if feedback == "" "" else "MALFORMED-RESPONSE CORRECTION: ${feedback} Regenerate the complete response for this same semantic round. This is not a new semantic attempt."
	state : List(PromptToken)
	state = List.map(pending, |token| { id: token.id, line: token.line, position: token.position, previous_rejected_glosses: prior_glosses(token.id, previous_rounds, []), word: token.word })
	state_json = Json.to_str_try(state)?
	system_prompt = \\
		\\Act as an Ancient Greek philologist. Generate exactly one concise contextual English gloss for each supplied token occurrence. Return only the required strict JSON.
	instructions = \\
		\\Copy every id and word exactly and preserve row order. Never correct, normalize, omit, insert, or reorder a token. The complete passage is context only; gloss only the pending records.
		\\Prefer concise English that naturally exposes morphology or syntax when useful, using forms such as of-Achilles, to-the-Achaeans, or they-separated. A gloss may contain spaces or hyphens. It must be nonempty and must not contain [UNRESOLVED], tabs, carriage returns, or line breaks.
	user_prompt = Str.join_with([instructions, prior_instruction, correction, "SEMANTIC ROUND: ${U64.to_str(round)}", "COMPLETE ILIAD PASSAGE:", source, "PENDING AUTHORITATIVE TOKEN RECORDS:", state_json], "\n")
	ids = List.map(pending, |token| token.id)
	count = List.len(pending)
	one : U64
	one = 1
	response_format = {
		json_schema: {
			name: "adaptive_contextual_gloss_round",
			schema: {
				additionalProperties: Bool.False,
				properties: {
					round: { enum: [round], type: "integer" },
					tokens: {
						items: {
							additionalProperties: Bool.False,
							properties: { gloss: { minLength: one, type: "string" }, id: { enum: ids, type: "integer" }, word: { type: "string" } },
							required: ["id", "word", "gloss"],
							type: "object",
						},
						maxItems: count,
						minItems: count,
						type: "array",
					},
				},
				required: ["round", "tokens"],
				type: "object",
			},
			strict: Bool.True,
		},
		type: "json_schema",
	}
	body = {
		frequency_penalty: g.frequency_penalty,
		include_reasoning: g.include_reasoning,
		max_tokens: g.max_tokens,
		messages: [{ content: system_prompt, role: "system" }, { content: user_prompt, role: "user" }],
		model: model_id,
		presence_penalty: g.presence_penalty,
		provider: { allow_fallbacks: g.allow_fallbacks, only: [provider_request_name], require_parameters: g.require_parameters },
		reasoning: g.reasoning,
		response_format,
		seed: g.seed,
		temperature: g.temperature,
		top_k: g.top_k,
		top_p: g.top_p,
	}
	Json.to_str_try(body)
}

prior_glosses = |id, rounds, found|
	match rounds {
		[] => found
		[rows, .. as rest] => prior_glosses(id, rest, append_gloss_for(id, rows, found))
	}

append_gloss_for = |id, rows, found|
	match rows {
		[] => found
		[row, .. as rest] => if row.id == id List.append(found, row.gloss) else append_gloss_for(id, rest, found)
	}

validate_generated = |round, pending, previous_rounds, payload| {
	if payload.round != round or List.len(payload.tokens) != List.len(pending) {
		Err(DeepCoverageMismatch)
	} else {
		validate_generated_rows(pending, payload.tokens, previous_rounds, [])
	}
}

validate_generated_rows = |pending, rows, previous_rounds, found|
	match (pending, rows) {
		([], []) => Ok(found)
		([token, .. as rest_tokens], [row, .. as rest_rows]) => {
			gloss = Str.trim(row.gloss)
			prior = prior_glosses(token.id, previous_rounds, [])
			if row.id != token.id or row.word != token.word {
				Err(DeepIdentityMismatch(token.id))
			} else if gloss == "" or malformed_gloss(gloss) {
				Err(InvalidGloss(token.id))
			} else if List.any(prior, |old| Str.caseless_ascii_equals(Str.trim(old), gloss)) {
				Err(RepeatedGloss(token.id))
			} else {
				validate_generated_rows(rest_tokens, rest_rows, previous_rounds, List.append(found, { gloss, id: row.id, word: row.word }))
			}
		}
		_ => Err(DeepCoverageMismatch)
	}

malformed_gloss = |gloss| Str.contains(gloss, "\n") or Str.contains(gloss, "\r") or Str.contains(gloss, "\t") or caseless_ascii_contains(gloss, unresolved)

caseless_ascii_contains = |value, needle| caseless_bytes_contains(Str.to_utf8(value), Str.to_utf8(needle))
caseless_bytes_contains = |remaining, needle|
	if caseless_bytes_start_with(remaining, needle) Bool.True else match remaining { [] => Bool.False, [_, .. as rest] => caseless_bytes_contains(rest, needle) }
caseless_bytes_start_with = |remaining, needle|
	match needle { [] => Bool.True, [expected, .. as rest_expected] => match remaining { [] => Bool.False, [actual, .. as rest_actual] => ascii_lower(actual) == ascii_lower(expected) and caseless_bytes_start_with(rest_actual, rest_expected) } }
ascii_lower = |byte| if byte >= 65 and byte <= 90 byte + 32 else byte

jev_request_body = |config, source, round, tokens, generated| {
	state_rows : List(JevStateRow)
	state_rows = jev_state_rows(tokens, generated, [])?
	source_text : Str
	source_text = source
	state = { generated_tokens: state_rows, semantic_round: round, source_passage: source_text, task: "Judge each token/gloss pair independently. Do not compare candidates, generate alternatives, alter token data, or consider accepted tokens from other rounds." }
	state_json = Json.to_str_try(state)?
	model_json = Json.to_str_try(config.validator.model)?
	questions = jev_question_entries(round, generated, 0, [])?
	Ok("{\"model\":${model_json},\"questions\":{${Str.join_with(questions, ",")}},\"state\":${state_json}}")
}

jev_state_rows = |tokens, rows, found|
	match (tokens, rows) {
		([], []) => Ok(found)
		([token, .. as rest_tokens], [row, .. as rest_rows]) => {
			if token.id != row.id or token.word != row.word {
				Err(DeepIdentityMismatch(token.id))
			} else {
				state_row : JevStateRow
				state_row = { gloss: row.gloss, id: token.id, line: token.line, position: token.position, word: token.word }
				jev_state_rows(rest_tokens, rest_rows, List.append(found, state_row))
			}
		}
		_ => Err(DeepCoverageMismatch)
	}

jev_question_entries = |round, rows, index, found|
	match rows {
		[] => Ok(found)
		[row, .. as rest] => {
			question : JevQuestion
			question = {
				criteria: {
					true: "True only if the exact proposed gloss is a natural and contextually accurate concise English gloss for this exact token occurrence, including lexical sense, morphology, and syntactic contribution where those naturally appear in English.",
					false: "False if the gloss has the wrong lexical sense, morphology, syntactic contribution, occurrence, or context; is unnatural as a concise English token gloss; or would create a phrase-level mistranslation.",
				},
				instructions: "Is `generated_tokens[${U64.to_str(index)}].gloss` a valid contextual gloss for the exact word and occurrence in `generated_tokens[${U64.to_str(index)}]`? Use the complete source passage for context. Judge only this pair and do not propose a replacement.",
				type: jev_primitive,
			}
			key_json = Json.to_str_try(question_key(round, row.id))?
			question_json = Json.to_str_try(question)?
			jev_question_entries(round, rest, index + 1, List.append(found, "${key_json}:${question_json}"))
		}
	}

jev_primitive = "noul"
question_key = |round, id| "round_${U64.to_str(round)}_token_${U64.to_str(id)}"

run_deep_attempt! = |prepared, pending, previous_rounds, api_key, run_id, run_dir, round, validation_attempt, transport_attempt, feedback| {
	body = deep_request_body(prepared.config, prepared.source, round, pending, previous_rounds, feedback)?
	captured = send_deep_request!(prepared.config, api_key, run_id, run_dir, round, validation_attempt, transport_attempt, body)?
	parsed : Try(DeepResponse, _)
	parsed = decode_json_bytes(captured.raw)
	match parsed {
		Err(_) => retry_deep_validation!(prepared, pending, previous_rounds, api_key, run_id, run_dir, round, validation_attempt, captured, "captured response was not the required PPQ completion envelope", 0, Bool.True)
		Ok(decoded) => {
			known_cost = if decoded.usage.cost >= 0 decoded.usage.cost else 0
			if decoded.model != prepared.config.generator.model or decoded.provider != prepared.config.generator.provider.response_name {
				error_text = "resolved DeepSeek identity ${decoded.model}/${decoded.provider} did not match the configured pin"
				_ = write_attempt!(captured, run_id, "deepseek", round, validation_attempt, "pin-mismatch", error_text, known_cost, decoded.usage.cost <= 0, 0)?
				Err(DeepIdentityPinMismatch(decoded.model, decoded.provider))
			} else {
				validation = validate_deep_response(prepared.config, round, pending, previous_rounds, decoded)
				match validation {
					Err(error_text) => retry_deep_validation!(prepared, pending, previous_rounds, api_key, run_id, run_dir, round, validation_attempt, captured, error_text, known_cost, decoded.usage.cost <= 0)
					Ok(rows) => {
						call = deep_call_audit(prepared.config, decoded, captured, validation_attempt)
						checkpoint : GeneratedCheckpoint
						checkpoint = { call, experiment_version: prepared.config.experiment_version, generated: rows, pending_ids: List.map(pending, |token| token.id), round, run_id }
						json = Json.to_str_try(checkpoint)?
						_ = write_atomic_new!("${json}\n", generated_checkpoint_path(run_dir, round))?
						_ = write_attempt!(captured, run_id, "deepseek", round, validation_attempt, "valid", "", decoded.usage.cost, decoded.usage.cost == 0, 0)?
						Ok(checkpoint)
					}
				}
			}
		}
	}
}

validate_deep_response = |config, round, pending, previous_rounds, decoded| {
	usage = decoded.usage
	if decoded.model != config.generator.model {
		Err("resolved model ${decoded.model} did not match ${config.generator.model}")
	} else if decoded.provider != config.generator.provider.response_name {
		Err("resolved provider ${decoded.provider} did not match ${config.generator.provider.response_name}")
	} else if usage.prompt_tokens == 0 or usage.completion_tokens == 0 or usage.cost < 0 or usage.total_tokens != usage.prompt_tokens + usage.completion_tokens or usage.completion_tokens_details.reasoning_tokens > usage.completion_tokens {
		Err("PPQ response had invalid usage or cost")
	} else match decoded.choices {
		[choice] => if choice.finish_reason != "stop" {
			Err("finish reason was ${choice.finish_reason}, not stop")
		} else {
			payload : DeepPayload
			payload = Json.parse(choice.message.content) ? |_| "assistant content was not the required round JSON"
			match validate_generated(round, pending, previous_rounds, payload) { Ok(rows) => Ok(rows), Err(problem) => Err(deep_error_text(problem)) }
		}
		_ => Err("PPQ response did not contain exactly one completion choice")
	}
}

retry_deep_validation! = |prepared, pending, previous_rounds, api_key, run_id, run_dir, round, attempt, captured, error_text, cost, ambiguous| {
	_ = write_attempt!(captured, run_id, "deepseek", round, attempt, "rejected", error_text, cost, ambiguous, 0)?
	_ = Stdout.line!("rejected DeepSeek round ${U64.to_str(round)} response ${U64.to_str(attempt)}: ${error_text}")?
	if attempt <= prepared.config.retry.malformed_response_retries {
		run_deep_attempt!(prepared, pending, previous_rounds, api_key, run_id, run_dir, round, attempt + 1, 1, error_text)
	} else {
		Err(DeepValidationAttemptsExhausted(error_text))
	}
}

send_deep_request! = |config, api_key, run_id, run_dir, round, validation_attempt, transport_attempt, body| {
	requested_at = Utc.now!()
	client_request_id = attempt_id("deepseek", round, validation_attempt, transport_attempt, requested_at)
	request_path = "${run_dir}/${client_request_id}.request.json"
	raw_path = "${run_dir}/${client_request_id}.raw.json"
	headers_path = "${run_dir}/${client_request_id}.headers.json"
	_ = write_new_utf8!(body, request_path)?
	request = Request.from_method(POST)
		.with_uri("${config.generator.provider.base_url}/chat/completions")
		.with_timeout(TimeoutMilliseconds(300000))
		.add_header("Authorization", "Bearer ${api_key}")
		.add_header("Content-Type", "application/json")
		.with_body(Str.to_utf8(body))
	match Http.send!(request) {
		Err(problem) => {
			received_at = Utc.now!()
			error = http_transport_error(problem, api_key)
			_ = write_new_bytes!([], raw_path)?
			_ = write_new_utf8!("[]\n", headers_path)?
			captured = empty_capture(client_request_id, request_path, raw_path, headers_path, requested_at, received_at, "basic-cli", transport_attempt, 0)
			delay = if error.retryable and transport_attempt <= config.retry.transport_retries retry_backoff_ms(config.retry, transport_attempt) else 0
			_ = write_attempt!(captured, run_id, "deepseek", round, validation_attempt, "transport-failed", error.message, 0, error.ambiguous, delay)?
			if delay > 0 {
				_ = Sleep.millis!(delay)
				send_deep_request!(config, api_key, run_id, run_dir, round, validation_attempt, transport_attempt + 1, body)
			} else {
				Err(DeepTransportFailure(error.category))
			}
		}
		Ok(response) => {
			received_at = Utc.now!()
			raw = Response.body(response)
			headers = Response.headers(response)
			status = Response.status(response)
			_ = write_new_bytes!(raw, raw_path)?
			_ = write_headers!(headers, headers_path)?
			captured = capture(client_request_id, request_path, raw_path, headers_path, requested_at, received_at, headers, raw, "basic-cli", transport_attempt, status, "")
			if status >= 200 and status < 300 {
				Ok(captured)
			} else {
				retryable = is_transient_status(status)
				delay = if retryable and transport_attempt <= config.retry.transport_retries retry_delay_ms!(headers, config.retry, transport_attempt)? else 0
				_ = write_attempt!(captured, run_id, "deepseek", round, validation_attempt, "http-rejected", "PPQ returned HTTP ${U16.to_str(status)}", 0, retryable, delay)?
				if delay > 0 {
					_ = Sleep.millis!(delay)
					send_deep_request!(config, api_key, run_id, run_dir, round, validation_attempt, transport_attempt + 1, body)
				} else {
					Err(DeepHttpFailure(status))
				}
			}
		}
	}
}

deep_call_audit = |config, decoded, captured, validation_attempt| {
	call : CallAudit
	call = {
		client_request_id: captured.client_request_id,
		cost_usd: decoded.usage.cost,
		elapsed_ms: captured.elapsed_ms,
		headers_path: captured.headers_path,
		provider_request_id: response_request_id(captured.headers),
		raw_response_path: captured.raw_path,
		received_at: captured.received_at,
		request_path: captured.request_path,
		requested_at: captured.requested_at,
		requested_model: config.generator.model,
		requested_provider: "ppq/${config.generator.provider.id}",
		resolved_model: decoded.model,
		resolved_provider: decoded.provider,
		response_id: decoded.id,
		token_usage: { input_tokens: decoded.usage.prompt_tokens, output_tokens: decoded.usage.completion_tokens, reasoning_tokens: decoded.usage.completion_tokens_details.reasoning_tokens, total_tokens: decoded.usage.total_tokens },
		transport: captured.transport,
		transport_attempt: captured.transport_attempt,
		validation_attempt,
	}
	call
}

run_jev_attempt! = |config, target_tokens, generated_checkpoint, api_key, run_id, run_dir, round, validation_attempt, transport_attempt, body| {
	captured = send_jev_request!(config, api_key, run_id, run_dir, round, validation_attempt, transport_attempt, body)?
	parsed : Try(JevResponse, _)
	parsed = decode_json_bytes(captured.raw)
	match parsed {
		Err(_) => retry_jev_validation!(config, target_tokens, generated_checkpoint, api_key, run_id, run_dir, round, validation_attempt, body, captured, "captured response was not the direct TypeSafe Noul schema", 0)
		Ok(decoded) => {
			cost = U64.to_dec(decoded.usage.input_tokens) * config.validator.input_cost_per_million_tokens_usd / 1000000
			raw_text = Str.from_utf8(captured.raw) ? |_| InvalidUtf8Response
			if !answer_keys_occur_once(raw_text, round, generated_checkpoint.generated) {
				retry_jev_validation!(config, target_tokens, generated_checkpoint, api_key, run_id, run_dir, round, validation_attempt, body, captured, "Jev response contained a missing or duplicate answer key", cost)
			} else if decoded.model != config.validator.model {
				error_text = "resolved Jev model ${decoded.model} did not match ${config.validator.model}"
				_ = write_attempt!(captured, run_id, "jev", round, validation_attempt, "pin-mismatch", error_text, cost, decoded.usage.input_tokens == 0, 0)?
				Err(JevIdentityPinMismatch(decoded.model))
			} else {
				validation = if decoded.usage.input_tokens == 0 or decoded.usage.output_tokens == 0 {
					Err("Jev response omitted nonzero token usage")
				} else {
					match validate_jev_answers(config, round, generated_checkpoint.generated, decoded.answers) { Ok(rows) => Ok(rows), Err(problem) => Err(jev_error_text(problem)) }
				}
				match validation {
					Err(error_text) => retry_jev_validation!(config, target_tokens, generated_checkpoint, api_key, run_id, run_dir, round, validation_attempt, body, captured, error_text, cost)
					Ok(judgments) => {
					call = jev_call_audit(config, decoded, captured, validation_attempt, cost)
					checkpoint : RoundCheckpoint
					checkpoint = {
						accepted_ids: accepted_ids(judgments),
						deepseek_call: generated_checkpoint.call,
						experiment_version: config.experiment_version,
						generated: generated_checkpoint.generated,
						jev_call: call,
						judgments,
						pending_ids: generated_checkpoint.pending_ids,
						rejected_ids: rejected_ids(judgments),
						round,
						run_id,
					}
					_ = validate_round_checkpoint!(config, target_tokens, run_id, round, tokens_for_ids(target_tokens, generated_checkpoint.pending_ids, [])?, [], checkpoint)?
					json = Json.to_str_try(checkpoint)?
					_ = write_atomic_new!("${json}\n", round_checkpoint_path(run_dir, round))?
						_ = write_attempt!(captured, run_id, "jev", round, validation_attempt, "valid", "", cost, Bool.False, 0)?
						Ok(checkpoint)
					}
				}
			}
		}
	}
}

retry_jev_validation! = |config, target_tokens, generated_checkpoint, api_key, run_id, run_dir, round, attempt, body, captured, error_text, cost| {
	_ = write_attempt!(captured, run_id, "jev", round, attempt, "rejected", error_text, cost, Bool.True, 0)?
	_ = Stdout.line!("rejected Jev round ${U64.to_str(round)} response ${U64.to_str(attempt)}: ${error_text}")?
	if attempt <= config.retry.malformed_response_retries {
		run_jev_attempt!(config, target_tokens, generated_checkpoint, api_key, run_id, run_dir, round, attempt + 1, 1, body)
	} else {
		Err(JevValidationAttemptsExhausted(error_text))
	}
}

# Work around basic-cli's HTTP/1-only Hyper transport failure for this valid TypeSafe POST.
# Upstream: https://github.com/roc-lang/basic-cli/issues/455 and https://github.com/roc-lang/basic-cli/issues/438
# Remove curl after a released compatible basic-cli transport completes this retained request and exposes safe diagnostics; stable basic-cli 0.22.2 does neither.
send_jev_request! = |config, api_key, run_id, run_dir, round, validation_attempt, transport_attempt, body| {
	requested_at = Utc.now!()
	client_request_id = attempt_id("jev", round, validation_attempt, transport_attempt, requested_at)
	request_path = "${run_dir}/${client_request_id}.request.json"
	raw_path = "${run_dir}/${client_request_id}.raw.json"
	headers_path = "${run_dir}/${client_request_id}.headers"
	transport_path = "${run_dir}/${client_request_id}.transport.json"
	_ = write_new_utf8!(body, request_path)?
	result = Cmd.new_str("curl")
		.args_str([
			"--silent", "--show-error", "--request", "POST", "--connect-timeout", "30", "--max-time", "300", "--proto", "=https",
			"--header", "Content-Type: application/json", "--header", "Expect:", "--variable", "%ARISTOS_TYPESAFE_API_KEY",
			"--expand-header", "Authorization: Bearer {{ARISTOS_TYPESAFE_API_KEY}}", "--data-binary", "@${request_path}",
			"--dump-header", headers_path, "--output", raw_path, "--write-out", "%{http_code}", config.validator.provider.endpoint,
		])
		.env_str("ARISTOS_TYPESAFE_API_KEY", api_key)
		.exec_output!()
	match result {
		Ok(output) => {
			status = curl_http_status(output.stdout_utf8)
			_ = write_curl_output!(transport_path, "0", status, output.stdout_utf8, safe_transport_message(output.stderr_utf8_lossy, api_key))?
			_ = ensure_bytes_artifact!(raw_path)?
			_ = ensure_bytes_artifact!(headers_path)?
			received_at = Utc.now!()
			raw = Path.read_bytes!(Path.utf8(raw_path))?
			headers = read_curl_headers!(headers_path)?
			captured = capture(client_request_id, request_path, raw_path, headers_path, requested_at, received_at, headers, raw, "curl-workaround", transport_attempt, status, transport_path)
			if status >= 200 and status < 300 {
				Ok(captured)
			} else {
				retryable = is_transient_status(status)
				delay = if retryable and transport_attempt <= config.retry.transport_retries retry_delay_ms!(headers, config.retry, transport_attempt)? else 0
				_ = write_attempt!(captured, run_id, "jev", round, validation_attempt, "http-rejected", "TypeSafe returned HTTP ${U16.to_str(status)}", 0, retryable, delay)?
				if delay > 0 {
					_ = Sleep.millis!(delay)
					send_jev_request!(config, api_key, run_id, run_dir, round, validation_attempt, transport_attempt + 1, body)
				} else {
					Err(JevHttpFailure(status))
				}
			}
		}
		Err(NonZeroExitCode(details)) => {
			status = curl_http_status(details.stdout_utf8_lossy)
			stderr = safe_transport_message(details.stderr_utf8_lossy, api_key)
			error = curl_transport_error(details.exit_code, stderr)
			_ = write_curl_output!(transport_path, I32.to_str(details.exit_code), status, details.stdout_utf8_lossy, stderr)?
			_ = ensure_bytes_artifact!(raw_path)?
			_ = ensure_bytes_artifact!(headers_path)?
			received_at = Utc.now!()
			captured = empty_capture(client_request_id, request_path, raw_path, headers_path, requested_at, received_at, "curl-workaround", transport_attempt, status)
			captured_with_transport = { ..captured, transport_output_path: transport_path }
			delay = if error.retryable and transport_attempt <= config.retry.transport_retries retry_backoff_ms(config.retry, transport_attempt) else 0
			_ = write_attempt!(captured_with_transport, run_id, "jev", round, validation_attempt, "transport-failed", error.message, 0, error.ambiguous, delay)?
			if delay > 0 {
				_ = Sleep.millis!(delay)
				send_jev_request!(config, api_key, run_id, run_dir, round, validation_attempt, transport_attempt + 1, body)
			} else {
				Err(JevTransportFailure(error.category))
			}
		}
		Err(_) => {
			_ = write_curl_output!(transport_path, "not-started", 0, "", "curl process could not be started")?
			_ = ensure_bytes_artifact!(raw_path)?
			_ = ensure_bytes_artifact!(headers_path)?
			received_at = Utc.now!()
			captured = empty_capture(client_request_id, request_path, raw_path, headers_path, requested_at, received_at, "curl-workaround", transport_attempt, 0)
			captured_with_transport = { ..captured, transport_output_path: transport_path }
			_ = write_attempt!(captured_with_transport, run_id, "jev", round, validation_attempt, "transport-failed", "curl process could not be started", 0, Bool.False, 0)?
			Err(JevTransportFailure("process-start"))
		}
	}
}

answer_keys_occur_once = |raw, round, rows|
	match rows {
		[] => Bool.True
		[row, .. as rest] => {
			quoted = "\"${question_key(round, row.id)}\""
			List.len(Str.split_on(raw, quoted)) == 2 and answer_keys_occur_once(raw, round, rest)
		}
	}

validate_jev_answers = |config, round, rows, answers| {
	if Dict.len(answers) != List.len(rows) {
		Err(WrongJevAnswerCount(List.len(rows), Dict.len(answers)))
	} else {
		validate_jev_rows(config, round, rows, answers, [])
	}
}

validate_jev_rows = |config, round, rows, answers, found|
	match rows {
		[] => Ok(found)
		[row, .. as rest] => {
			key = question_key(round, row.id)
			answer = Dict.get(answers, key) ? |_| MissingJevAnswer(key)
			if answer.type != config.validator.primitive {
				Err(WrongJevAnswerType(key, answer.type))
			} else if answer.noul < 0 or answer.noul > 1 {
				Err(NoulOutOfRange(key))
			} else {
				judgment : Judgment
				judgment = { accepted: answer.noul >= config.execution.acceptance_threshold, gloss: row.gloss, id: row.id, key, score: answer.noul, threshold: config.execution.acceptance_threshold, word: row.word }
				validate_jev_rows(config, round, rest, answers, List.append(found, judgment))
			}
		}
	}

jev_call_audit = |config, decoded, captured, validation_attempt, cost| {
	call : CallAudit
	call = {
		client_request_id: captured.client_request_id,
		cost_usd: cost,
		elapsed_ms: captured.elapsed_ms,
		headers_path: captured.headers_path,
		provider_request_id: response_request_id(captured.headers),
		raw_response_path: captured.raw_path,
		received_at: captured.received_at,
		request_path: captured.request_path,
		requested_at: captured.requested_at,
		requested_model: config.validator.model,
		requested_provider: config.validator.provider.name,
		resolved_model: decoded.model,
		resolved_provider: config.validator.provider.name,
		response_id: response_request_id(captured.headers),
		token_usage: { input_tokens: decoded.usage.input_tokens, output_tokens: decoded.usage.output_tokens, reasoning_tokens: 0, total_tokens: decoded.usage.input_tokens + decoded.usage.output_tokens },
		transport: captured.transport,
		transport_attempt: captured.transport_attempt,
		validation_attempt,
	}
	call
}

validate_generated_checkpoint! = |config, run_id, round, pending, previous, checkpoint| {
	if checkpoint.experiment_version != config.experiment_version or checkpoint.run_id != run_id or checkpoint.round != round or checkpoint.pending_ids != List.map(pending, |t| t.id) {
		Err(GeneratedCheckpointIdentityMismatch(round))
	} else if checkpoint.call.requested_model != config.generator.model or checkpoint.call.resolved_model != config.generator.model or checkpoint.call.requested_provider != "ppq/${config.generator.provider.id}" or checkpoint.call.resolved_provider != config.generator.provider.response_name {
		Err(GeneratedCheckpointPinMismatch(round))
	} else {
		payload : DeepPayload
		payload = { round, tokens: checkpoint.generated }
		_ = validate_generated(round, pending, previous, payload)?
		_ = validate_call_artifacts!(checkpoint.call, run_id, "deepseek", round)?
		validate_deep_checkpoint_response!(config, round, pending, previous, checkpoint.generated, checkpoint.call)
	}
}

validate_round_checkpoint! = |config, target_tokens, run_id, round, pending, previous, checkpoint| {
	if checkpoint.experiment_version != config.experiment_version or checkpoint.run_id != run_id or checkpoint.round != round or checkpoint.pending_ids != List.map(pending, |t| t.id) or checkpoint.deepseek_call.requested_model != config.generator.model or checkpoint.deepseek_call.requested_provider != "ppq/${config.generator.provider.id}" or checkpoint.deepseek_call.resolved_model != config.generator.model or checkpoint.deepseek_call.resolved_provider != config.generator.provider.response_name or checkpoint.jev_call.requested_model != config.validator.model or checkpoint.jev_call.requested_provider != config.validator.provider.name or checkpoint.jev_call.resolved_model != config.validator.model or checkpoint.jev_call.resolved_provider != config.validator.provider.name {
		Err(RoundCheckpointIdentityMismatch(round))
	} else {
		payload : DeepPayload
		payload = { round, tokens: checkpoint.generated }
		validated = validate_generated(round, pending, previous, payload)?
		if List.len(checkpoint.judgments) != List.len(validated) or checkpoint.accepted_ids != accepted_ids(checkpoint.judgments) or checkpoint.rejected_ids != rejected_ids(checkpoint.judgments) {
			Err(RoundCheckpointRoutingMismatch(round))
		} else {
			_ = validate_judgments(config, round, validated, checkpoint.judgments)?
			_ = tokens_for_ids(target_tokens, checkpoint.accepted_ids, [])?
			_ = tokens_for_ids(target_tokens, checkpoint.rejected_ids, [])?
			_ = validate_call_artifacts!(checkpoint.deepseek_call, run_id, "deepseek", round)?
			_ = validate_call_artifacts!(checkpoint.jev_call, run_id, "jev", round)?
			_ = validate_deep_checkpoint_response!(config, round, pending, previous, checkpoint.generated, checkpoint.deepseek_call)?
			validate_jev_checkpoint_response!(config, round, checkpoint.generated, checkpoint.judgments, checkpoint.jev_call)
		}
	}
}

validate_judgments = |config, round, rows, judgments|
	match (rows, judgments) {
		([], []) => Ok({})
		([row, .. as rest_rows], [j, .. as rest]) => if j.id != row.id or j.word != row.word or j.gloss != row.gloss or j.key != question_key(round, row.id) or j.threshold != config.execution.acceptance_threshold or j.score < 0 or j.score > 1 or j.accepted != (j.score >= j.threshold) { Err(InvalidStoredJudgment(row.id)) } else validate_judgments(config, round, rest_rows, rest)
		_ => Err(StoredJudgmentCoverageMismatch)
	}

validate_call_artifacts! = |call, run_id, stage, round| {
	root = "${experiment_dir}/responses/${run_id}/"
	expected_prefix = "${stage}-round-${U64.to_str(round)}-"
	request_name = path_file_name(call.request_path)
	raw_name = path_file_name(call.raw_response_path)
	headers_name = path_file_name(call.headers_path)
	paths_bound = Str.starts_with(call.request_path, root) and Str.starts_with(call.raw_response_path, root) and Str.starts_with(call.headers_path, root) and Str.starts_with(call.client_request_id, expected_prefix) and request_name == "${call.client_request_id}.request.json" and raw_name == "${call.client_request_id}.raw.json" and (headers_name == "${call.client_request_id}.headers.json" or headers_name == "${call.client_request_id}.headers")
	if !paths_bound or !Path.exists!(Path.utf8(call.request_path))? or !Path.exists!(Path.utf8(call.raw_response_path))? or !Path.exists!(Path.utf8(call.headers_path))? {
		Err(MissingCallArtifact(call.client_request_id))
	} else if call.token_usage.total_tokens != call.token_usage.input_tokens + call.token_usage.output_tokens or call.token_usage.reasoning_tokens > call.token_usage.output_tokens or call.cost_usd < 0 {
		Err(InvalidCallUsage(call.client_request_id))
	} else {
		request_text = Path.read_utf8!(Path.utf8(call.request_path))?
		_request_json : {}
		_request_json = Json.parse(request_text)?
		raw = Path.read_bytes!(Path.utf8(call.raw_response_path))?
		_raw_json : {}
		_raw_json = decode_json_bytes(raw)?
		Ok({})
	}
}

validate_deep_checkpoint_response! = |config, round, pending, previous, expected_rows, call| {
	raw = Path.read_bytes!(Path.utf8(call.raw_response_path))?
	decoded : DeepResponse
	decoded = decode_json_bytes(raw)?
	rows = validate_deep_response(config, round, pending, previous, decoded) ? |error_text| StoredDeepResponseMismatch(round, error_text)
	usage = decoded.usage
	expected_usage : Usage
	expected_usage = { input_tokens: usage.prompt_tokens, output_tokens: usage.completion_tokens, reasoning_tokens: usage.completion_tokens_details.reasoning_tokens, total_tokens: usage.total_tokens }
	if rows != expected_rows or decoded.id != call.response_id or decoded.model != call.resolved_model or decoded.provider != call.resolved_provider or expected_usage != call.token_usage or usage.cost != call.cost_usd {
		Err(StoredDeepResponseMismatch(round, "checkpoint fields diverged from raw response"))
	} else {
		Ok({})
	}
}

validate_jev_checkpoint_response! = |config, round, rows, expected_judgments, call| {
	raw = Path.read_bytes!(Path.utf8(call.raw_response_path))?
	raw_text = Str.from_utf8(raw) ? |_| InvalidUtf8Response
	decoded : JevResponse
	decoded = Json.parse(raw_text)?
	if decoded.model != config.validator.model or !answer_keys_occur_once(raw_text, round, rows) {
		Err(StoredJevResponseMismatch(round))
	} else {
		judgments = validate_jev_answers(config, round, rows, decoded.answers)?
		cost = U64.to_dec(decoded.usage.input_tokens) * config.validator.input_cost_per_million_tokens_usd / 1000000
		usage : Usage
		usage = { input_tokens: decoded.usage.input_tokens, output_tokens: decoded.usage.output_tokens, reasoning_tokens: 0, total_tokens: decoded.usage.input_tokens + decoded.usage.output_tokens }
		if judgments != expected_judgments or usage != call.token_usage or cost != call.cost_usd {
			Err(StoredJevResponseMismatch(round))
		} else {
			Ok({})
		}
	}
}

accepted_ids = |judgments| List.map(List.keep_if(judgments, |j| j.accepted), |j| j.id)
rejected_ids = |judgments| List.map(List.keep_if(judgments, |j| !j.accepted), |j| j.id)

assemble_final = |tokens, rounds| List.map(tokens, |token| final_for_token(token, rounds))
final_for_token = |token, rounds|
	match first_accepted(token.id, rounds) {
		Ok(judgment) => { gloss: judgment.gloss, valid: Bool.True, word: token.word }
		Err(_) => { gloss: unresolved, valid: Bool.False, word: token.word }
	}
first_accepted = |id, rounds|
	match rounds {
		[] => Err(NotAccepted)
		[round, .. as rest] => match accepted_judgment(id, round.judgments) { Ok(found) => Ok(found), Err(_) => first_accepted(id, rest) }
	}
accepted_judgment = |id, judgments|
	match judgments { [] => Err(NotAccepted), [j, .. as rest] => if j.id == id and j.accepted Ok(j) else accepted_judgment(id, rest) }

validate_final = |tokens, rows| {
	if List.len(tokens) != List.len(rows) Err(FinalCoverageMismatch) else validate_final_rows(tokens, rows)
}
validate_final_rows = |tokens, rows|
	match (tokens, rows) {
		([], []) => Ok({})
		([token, .. as rest_tokens], [row, .. as rest_rows]) => if row.word != token.word or (row.valid and row.gloss == unresolved) or (!row.valid and row.gloss != unresolved) { Err(InvalidFinalRow(token.id)) } else validate_final_rows(rest_tokens, rest_rows)
		_ => Err(FinalCoverageMismatch)
	}

metrics_for = |rounds, final| {
	first = match rounds { [r, ..] => List.len(r.accepted_ids), [] => 0 }
	second = round_accept_count(rounds, 2)
	third = round_accept_count(rounds, 3)
	{ first_pass_accepted: first, round_2_recovered: second, round_3_recovered: third, unresolved: List.len(List.keep_if(final, |row| !row.valid)) }
}
round_accept_count = |rounds, wanted|
	match rounds { [] => 0, [round, .. as rest] => if round.round == wanted List.len(round.accepted_ids) else round_accept_count(rest, wanted) }

validate_simulation = |tokens, rounds, final| {
	if List.is_empty(rounds) or List.len(rounds) > 3 or List.len(final) != List.len(tokens) {
		Err(SimulationCoverageFailed)
	} else {
		match rounds {
			[] => Err(SimulationCoverageFailed)
			[first, .. as rest] => {
				expected_ids = List.map(tokens, |token| token.id)
				unresolved_count = List.len(List.keep_if(final, |row| !row.valid))
				if first.round != 1 or first.pending_ids != expected_ids {
					Err(SimulationRoutingFailed)
				} else {
					_ = validate_round_chain(rest, first, first.accepted_ids, unresolved_count)?
					if List.any(tokens, |token| attempt_count(token.id, rounds) > 3) Err(SimulationAttemptBoundFailed) else Ok({})
				}
			}
		}
	}
}

validate_round_chain = |remaining, previous, accepted, unresolved_count|
	match remaining {
		[] => if List.len(previous.rejected_ids) != unresolved_count or (previous.round < 3 and !List.is_empty(previous.rejected_ids)) { Err(SimulationRoutingFailed) } else Ok({})
		[next, .. as rest] => {
			if next.round != previous.round + 1 or next.round > 3 or next.pending_ids != previous.rejected_ids or !disjoint(accepted, next.pending_ids) {
				Err(SimulationRoutingFailed)
			} else {
				validate_round_chain(rest, next, List.concat(accepted, next.accepted_ids), unresolved_count)
			}
		}
	}

disjoint = |left, right| !List.any(left, |id| List.contains(right, id))
attempt_count = |id, rounds| List.len(List.keep_if(rounds, |round| List.contains(round.pending_ids, id)))

fake_generated = |tokens, round| { round, tokens: List.map(tokens, |token| { gloss: "synthetic-${U64.to_str(round)}-${U64.to_str(token.id)}", id: token.id, word: token.word }) }
synthetic_judgments = |config, round, payload, pattern| {
	answers = synthetic_answers(round, payload.tokens, pattern, Dict.empty())
	validate_jev_answers(config, round, payload.tokens, answers)
}
synthetic_answers = |round, rows, pattern, found|
	match rows {
		[] => found
		[row, .. as rest] => {
			accept = if pattern == "accept" Bool.True else if pattern == "reject" Bool.False else if pattern == "odd" row.id % 2 == 1 else row.id % 4 == 0
			answer : JevAnswer
			answer = { noul: if accept 0.75 else 0.25, type: "noul" }
			synthetic_answers(round, rest, pattern, Dict.insert(found, question_key(round, row.id), answer))
		}
	}
fake_round = |round, payload, judgments| {
	empty_call : CallAudit
	empty_call = { client_request_id: "synthetic", cost_usd: 0, elapsed_ms: 0, headers_path: "synthetic", provider_request_id: "synthetic", raw_response_path: "synthetic", received_at: "synthetic", request_path: "synthetic", requested_at: "synthetic", requested_model: "synthetic", requested_provider: "synthetic", resolved_model: "synthetic", resolved_provider: "synthetic", response_id: "synthetic", token_usage: { input_tokens: 0, output_tokens: 0, reasoning_tokens: 0, total_tokens: 0 }, transport: "synthetic", transport_attempt: 1, validation_attempt: 1 }
	{ accepted_ids: accepted_ids(judgments), deepseek_call: empty_call, experiment_version: 1, generated: payload.tokens, jev_call: empty_call, judgments, pending_ids: List.map(payload.tokens, |row| row.id), rejected_ids: rejected_ids(judgments), round, run_id: "synthetic" }
}

# Resume uses immutable attempt records. A recorded retry delay means the bounded retry was authorized but interrupted; zero means the bound was exhausted.
next_attempt_state! = |run_dir, run_id, stage, round, retry| {
	entries = Path.list!(Path.utf8(run_dir))?
	_ = reject_orphan_attempt_artifacts!(entries, stage, round)?
	records = read_attempt_entries!(entries, run_id, stage, round, [])?
	match latest_attempt(records) {
		Err(_) => Ok({ feedback: "", transport_attempt: 1, validation_attempt: 1 })
		Ok(record) => {
			if record.status == "rejected" {
				if record.validation_attempt <= retry.malformed_response_retries Ok({ feedback: record.validation_error, transport_attempt: 1, validation_attempt: record.validation_attempt + 1 }) else Err(RecordedValidationAttemptsExhausted(stage, round))
			} else if record.status == "transport-failed" or record.status == "http-rejected" {
				if record.retry_delay_ms > 0 and record.transport_attempt <= retry.transport_retries Ok({ feedback: "", transport_attempt: record.transport_attempt + 1, validation_attempt: record.validation_attempt }) else Err(RecordedTransportAttemptsExhausted(stage, round))
			} else {
				Err(IncompleteAcceptedCheckpoint(stage, round))
			}
		}
	}
}

preflight_resume_artifacts! = |run_dir| {
	entries = Path.list!(Path.utf8(run_dir))?
	_ = reject_orphan_attempt_artifacts!(entries, "deepseek", 0)?
	reject_orphan_attempt_artifacts!(entries, "jev", 0)
}

reject_orphan_attempt_artifacts! = |entries, stage, round|
	match entries {
		[] => Ok({})
		[entry, .. as rest] => {
			path = Path.display(entry)
			stem = attempt_artifact_stem(path)
			name = path_file_name(path)
			prefix = if round == 0 "${stage}-round-" else "${stage}-round-${U64.to_str(round)}-"
			if stem != "" and Str.starts_with(name, prefix) and !Path.exists!(Path.utf8("${stem}.attempt.json"))? {
				Err(OrphanAttemptArtifact(stage, path))
			} else {
				reject_orphan_attempt_artifacts!(rest, stage, round)
			}
		}
	}

attempt_artifact_stem = |path|
	if Str.ends_with(path, ".request.json") {
		Str.replace_last(path, ".request.json", "")
	} else if Str.ends_with(path, ".raw.json") {
		Str.replace_last(path, ".raw.json", "")
	} else if Str.ends_with(path, ".headers.json") {
		Str.replace_last(path, ".headers.json", "")
	} else if Str.ends_with(path, ".headers") {
		Str.replace_last(path, ".headers", "")
	} else if Str.ends_with(path, ".transport.json") {
		Str.replace_last(path, ".transport.json", "")
	} else {
		""
	}

read_all_attempts! = |run_dir, run_id| {
	entries = Path.list!(Path.utf8(run_dir))?
	read_attempt_entries!(entries, run_id, "", 0, [])
}

accounting_for = |records| accounting_loop(records, { ambiguous_attempts: 0, charged_attempts: 0, known_cost_usd: 0 })
accounting_loop = |records, found|
	match records {
		[] => found
		[record, .. as rest] => accounting_loop(rest, {
			ambiguous_attempts: found.ambiguous_attempts + if record.ambiguous_possible_charge 1 else 0,
			charged_attempts: found.charged_attempts + if record.cost_usd > 0 1 else 0,
			known_cost_usd: found.known_cost_usd + record.cost_usd,
		})
	}

read_attempt_entries! = |entries, run_id, stage, round, found|
	match entries {
		[] => Ok(found)
		[entry, .. as rest] => {
			path = Path.display(entry)
			if Str.ends_with(path, ".attempt.json") {
				raw = Path.read_utf8!(entry)?
				record : AttemptRecord
				record = Json.parse(raw)?
				if record.run_id != run_id {
					Err(AttemptRunMismatch(path))
				} else {
					include = (stage == "" or record.stage == stage) and (round == 0 or record.round == round)
					read_attempt_entries!(rest, run_id, stage, round, if include List.append(found, record) else found)
				}
			} else {
				read_attempt_entries!(rest, run_id, stage, round, found)
			}
		}
	}
latest_attempt = |records|
	match records { [] => Err(NoAttempt), [first, .. as rest] => Ok(latest_attempt_loop(rest, first)) }
latest_attempt_loop = |records, latest|
	match records { [] => latest, [first, .. as rest] => latest_attempt_loop(rest, if compare_str(latest.client_request_id, first.client_request_id) == Before first else latest) }

write_attempt! = |captured, run_id, stage, round, validation_attempt, status, error_text, cost, ambiguous, retry_delay_ms| {
	record : AttemptRecord
	record = {
		ambiguous_possible_charge: ambiguous,
		client_request_id: captured.client_request_id,
		cost_usd: cost,
		elapsed_ms: captured.elapsed_ms,
		headers_path: captured.headers_path,
		http_status: captured.status,
		provider_request_id: response_request_id(captured.headers),
		raw_response_path: captured.raw_path,
		received_at: captured.received_at,
		request_path: captured.request_path,
		requested_at: captured.requested_at,
		retry_delay_ms,
		round,
		run_id,
		stage,
		status,
		transport: captured.transport,
		transport_attempt: captured.transport_attempt,
		transport_output_path: captured.transport_output_path,
		validation_attempt,
		validation_error: error_text,
	}
	json = Json.to_str_try(record)?
	write_new_utf8!("${json}\n", Str.replace_last(captured.request_path, ".request.json", ".attempt.json"))
}

capture = |client_request_id, request_path, raw_path, headers_path, requested_at, received_at, headers, raw, transport, transport_attempt, status, transport_output_path| {
	client_request_id,
	elapsed_ms: Utc.delta_as_millis(received_at, requested_at),
	headers,
	headers_path,
	raw,
	raw_path,
	received_at: Utc.to_iso_8601(received_at),
	requested_at: Utc.to_iso_8601(requested_at),
	request_path,
	status,
	transport,
	transport_attempt,
	transport_output_path,
}
empty_capture = |client_request_id, request_path, raw_path, headers_path, requested_at, received_at, transport, transport_attempt, status| capture(client_request_id, request_path, raw_path, headers_path, requested_at, received_at, [], [], transport, transport_attempt, status, "")

round_checkpoint_path = |run_dir, round| "${run_dir}/round-${U64.to_str(round)}.checkpoint.json"
generated_checkpoint_path = |run_dir, round| "${run_dir}/round-${U64.to_str(round)}.generated.json"
attempt_id = |stage, round, validation, transport, timestamp| "${stage}-round-${U64.to_str(round)}-validation-${U64.to_str(validation)}-transport-${U64.to_str(transport)}-${U128.to_str(Utc.to_nanos_since_epoch(timestamp))}"

tokens_for_ids = |tokens, ids, found|
	match ids {
		[] => Ok(found)
		[id, .. as rest] => {
			token = token_by_id(tokens, id)?
			tokens_for_ids(tokens, rest, List.append(found, token))
		}
	}
token_by_id = |tokens, id|
	match tokens { [] => Err(UnknownTokenId(id)), [token, .. as rest] => if token.id == id Ok(token) else token_by_id(rest, id) }
take_exact = |items, count, found|
	if count == 0 Ok(found) else match items { [] => Err(NotEnoughTokens), [first, .. as rest] => take_exact(rest, count - 1, List.append(found, first)) }

require_completed_smoke! = |config, tokens| {
	root = "${experiment_dir}/responses"
	if !Path.exists!(Path.utf8(root))? {
		Err(CompletedSmokeRequired)
	} else {
		entries = Path.list!(Path.utf8(root))?
		completed = has_completed_smoke!(entries, config, tokens)?
		if completed Ok({}) else Err(CompletedSmokeRequired)
	}
}

has_completed_smoke! = |entries, config, tokens|
	match entries {
		[] => Ok(Bool.False)
		[entry, .. as rest] => {
			path = Path.display(entry)
			name = path_file_name(path)
			is_dir = match Path.type!(entry)? { IsDir => Bool.True, _ => Bool.False }
			complete = if is_dir and Str.starts_with(name, "smoke-") Path.exists!(Path.utf8("${path}/run.complete"))? else Bool.False
			if complete {
				validated = validate_completed_smoke!(path, name, config, tokens)
				match validated { Ok(_) => Ok(Bool.True), Err(_) => has_completed_smoke!(rest, config, tokens) }
			} else {
				has_completed_smoke!(rest, config, tokens)
			}
		}
	}

validate_completed_smoke! = |run_dir, run_id, config, tokens| {
	manifest_raw = Path.read_utf8!(Path.utf8("${run_dir}/run.json"))?
	manifest : Manifest
	manifest = Json.parse(manifest_raw)?
	if manifest != { experiment_version: config.experiment_version, mode: "smoke", run_id, target_count: config.execution.smoke_token_count } {
		Err(ManifestMismatch(run_id))
	} else {
		audit_path = "${experiment_dir}/outputs/smoke/${run_id}/audit.json"
		final_path = "${experiment_dir}/outputs/smoke/${run_id}/final.json"
		audit_raw = Path.read_utf8!(Path.utf8(audit_path))?
		audit : RunAudit
		audit = Json.parse(audit_raw)?
		final_raw = Path.read_utf8!(Path.utf8(final_path))?
		final : List(FinalRow)
		final = Json.parse(final_raw)?
		smoke_tokens = take_exact(tokens, config.execution.smoke_token_count, [])?
		_ = validate_final(smoke_tokens, final)?
		_ = validate_simulation(smoke_tokens, audit.rounds, final)?
		if audit.config != config or audit.mode != "smoke" or audit.run_id != run_id or audit.final_path != final_path or audit.source_sha256 != config.input.source_sha256 or audit.tokens_sha256 != config.input.tokens_sha256 or audit.metrics != metrics_for(audit.rounds, final) or audit.accounting != accounting_for(audit.attempts) {
			Err(InvalidCompletedSmoke(run_id))
		} else {
			Ok({})
		}
	}
}

latest_incomplete_run! = |mode| {
	root = "${experiment_dir}/responses"
	if !Path.exists!(Path.utf8(root))? {
		Err(NoIncompleteRun(mode))
	} else {
		entries = Path.list!(Path.utf8(root))?
		find_latest_run!(entries, "${mode}-", "")
	}
}
find_latest_run! = |entries, prefix, latest|
	match entries {
		[] => if latest == "" Err(NoIncompleteRun(prefix)) else Ok(latest)
		[entry, .. as rest] => {
			path = Path.display(entry)
			name = path_file_name(path)
			is_dir = match Path.type!(entry)? { IsDir => Bool.True, _ => Bool.False }
			eligible = is_dir and Str.starts_with(name, prefix) and Path.exists!(Path.utf8("${path}/run.json"))? and !Path.exists!(Path.utf8("${path}/run.complete"))?
			next = if eligible and (latest == "" or compare_str(latest, name) == Before) name else latest
			find_latest_run!(rest, prefix, next)
		}
	}
path_file_name = |path| match List.last(Str.split_on(path, "/")) { Ok(name) => name, Err(_) => path }

write_headers! = |headers, path| {
	records = header_records(headers, [])
	json = Json.to_str_try(records)?
	write_new_utf8!("${json}\n", path)
}
header_records = |headers, found|
	match headers {
		[] => found
		[header, .. as rest] => {
			record : HeaderRecord
			record = { name: header.name, value: header.value }
			header_records(rest, List.append(found, record))
		}
	}

write_curl_output! = |path, exit_code, http_status, stdout, stderr| {
	record : CurlOutputRecord
	record = { exit_code, http_status, stderr, stdout }
	json = Json.to_str_try(record)?
	write_new_utf8!("${json}\n", path)
}
ensure_bytes_artifact! = |path| if Path.exists!(Path.utf8(path))? Ok({}) else write_new_bytes!([], path)
curl_http_status = |stdout| match U16.from_str(Str.trim(stdout)) { Ok(status) => status, Err(_) => 0 }
safe_transport_message = |message, api_key| {
	trimmed = Str.trim(message)
	redacted = if api_key == "" trimmed else Str.replace_each(trimmed, api_key, "[REDACTED]")
	if redacted == "" "no transport detail was returned" else redacted
}
curl_transport_error = |exit_code, message| {
	category = if exit_code == 6 "dns" else if exit_code == 7 "connect" else if exit_code == 28 "timeout" else if exit_code == 35 or exit_code == 51 or exit_code == 58 or exit_code == 60 "tls" else if exit_code == 52 "empty-response" else if exit_code == 55 "send" else if exit_code == 56 "receive" else "curl-exit"
	ambiguous = exit_code != 6 and exit_code != 7 and exit_code != 35 and exit_code != 51 and exit_code != 58 and exit_code != 60
	retryable = exit_code == 5 or exit_code == 6 or exit_code == 7 or exit_code == 16 or exit_code == 18 or exit_code == 28 or exit_code == 52 or exit_code == 55 or exit_code == 56 or exit_code == 92
	{ ambiguous, category, message, retryable }
}
http_transport_error = |problem, api_key|
	match problem {
		HttpErr(Timeout) => { ambiguous: Bool.True, category: "timeout", message: "basic-cli HTTP request timed out", retryable: Bool.True }
		HttpErr(NetworkError) => { ambiguous: Bool.True, category: "network", message: "basic-cli reported a network error", retryable: Bool.True }
		HttpErr(BadBody) => { ambiguous: Bool.True, category: "response-body", message: "basic-cli failed while collecting the response body", retryable: Bool.True }
		HttpErr(Other(bytes)) => { ambiguous: Bool.True, category: "other", message: safe_transport_message(Str.from_utf8_lossy(bytes), api_key), retryable: Bool.True }
		InvalidUrl(_) => { ambiguous: Bool.False, category: "invalid-url", message: "basic-cli rejected the request URL", retryable: Bool.False }
	}
read_curl_headers! = |path| {
	bytes = Path.read_bytes!(Path.utf8(path))?
	text = Str.from_utf8(bytes) ? |_| InvalidUtf8Headers
	Ok(parse_curl_header_lines(Str.split_on(text, "\n"), []))
}
parse_curl_header_lines = |lines, found|
	match lines {
		[] => found
		[line, .. as rest] => {
			clean = Str.trim(line)
			parts = Str.split_on(clean, ":")
			next = match parts { [name, value, .. as remaining] => List.append(found, { name: Str.trim(name), value: Str.trim(Str.join_with(List.prepend(remaining, value), ":")) }), _ => found }
			parse_curl_header_lines(rest, next)
		}
	}

is_transient_status = |status| status == 408 or status == 429 or status >= 500
retry_backoff_ms = |retry, retry_number| {
	uncapped = retry_backoff_uncapped(retry.backoff_initial_ms, retry_number)
	if uncapped > retry.backoff_max_ms retry.backoff_max_ms else uncapped
}
retry_backoff_uncapped : U64, U64 -> U64
retry_backoff_uncapped = |delay, retry_number| if retry_number <= 1 delay else retry_backoff_uncapped(delay * 2, retry_number - 1)
retry_delay_ms! = |headers, retry, retry_number| {
	fallback = retry_backoff_ms(retry, retry_number)
	milliseconds = response_header_value(headers, "retry-after-ms")
	seconds = response_header_value(headers, "retry-after")
	if milliseconds != "" {
		Ok(retry_header_delay(milliseconds, 1, fallback, retry.max_retry_after_ms))
	} else if seconds == "" {
		Ok(fallback)
	} else match U64.from_str(seconds) { Ok(value) => Ok(retry_header_delay(U64.to_str(value), 1000, fallback, retry.max_retry_after_ms)), Err(_) => retry_after_date_ms!(seconds, fallback, retry.max_retry_after_ms) }
}
retry_header_delay = |value, multiplier, fallback, maximum|
	match U64.from_str(value) {
		Ok(number) => {
			delay = number * multiplier
			if delay <= maximum delay else fallback
		}
		Err(_) => fallback
	}
retry_after_date_ms! = |value, fallback, maximum| {
	parsed = Cmd.new_str("date").args_str(["--date", value, "+%s"]).exec_output!()
	match parsed {
		Ok(output) => {
			now_text = U128.to_str(Utc.to_millis_since_epoch(Utc.now!()))
			match (U64.from_str(Str.trim(output.stdout_utf8)), U64.from_str(now_text)) {
				(Ok(target_seconds), Ok(now_millis)) => {
					target_millis = target_seconds * 1000
					delay = if target_millis > now_millis target_millis - now_millis else 0
					Ok(if delay <= maximum delay else fallback)
				}
				_ => Ok(fallback)
			}
		}
		Err(_) => Ok(fallback)
	}
}
response_header_value = |headers, expected| match headers { [] => "", [header, .. as rest] => if Str.caseless_ascii_equals(header.name, expected) header.value else response_header_value(rest, expected) }
response_request_id = |headers| match headers { [] => "", [header, .. as rest] => if Str.caseless_ascii_equals(header.name, "x-request-id") or Str.caseless_ascii_equals(header.name, "request-id") header.value else response_request_id(rest) }

decode_json_bytes = |bytes| {
	text = Str.from_utf8(bytes) ? |_| InvalidUtf8Response
	Json.parse(text)
}
write_new_utf8! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? Err(RefuseOverwrite(path)) else Path.write_utf8!(roc_path, content)
}
write_new_bytes! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? Err(RefuseOverwrite(path)) else Path.write_bytes!(roc_path, content)
}
write_atomic_new! = |content, path| {
	if Path.exists!(Path.utf8(path))? {
		Err(RefuseOverwrite(path))
	} else {
		now = Utc.now!()
		temporary = "${path}.tmp-${U128.to_str(Utc.to_nanos_since_epoch(now))}"
		_ = write_new_utf8!(content, temporary)?
		Path.rename!(Path.utf8(temporary), Path.utf8(path))
	}
}

write_atomic_or_verify! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? {
		existing = Path.read_utf8!(roc_path)?
		if existing == content Ok({}) else Err(ExistingArtifactMismatch(path))
	} else {
		write_atomic_new!(content, path)
	}
}
run_id_for = |timestamp, version| {
	compact = Str.replace_each(Str.replace_each(Utc.to_iso_8601(timestamp), "-", ""), ":", "")
	"${compact}-${U128.to_str(Utc.to_nanos_since_epoch(timestamp))}-v${U64.to_str(version)}"
}
compare_attempt_records = |a, b| compare_str(a.client_request_id, b.client_request_id)
compare_str = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))
compare_bytes = |a, b| match (a, b) { ([], []) => Same, ([], _) => Before, (_, []) => After, ([x, .. as xs], [y, .. as ys]) => if x < y Before else if x > y After else compare_bytes(xs, ys) }

deep_error_text = |problem|
	match problem {
		DeepCoverageMismatch => "round or pending-token coverage did not match"
		DeepIdentityMismatch(id) => "token ${U64.to_str(id)} had the wrong id, word, or order"
		InvalidGloss(id) => "token ${U64.to_str(id)} had an empty or unsafe gloss"
		RepeatedGloss(id) => "token ${U64.to_str(id)} repeated a prior rejected gloss after trim and ASCII-case folding"
	}
jev_error_text = |problem|
	match problem {
		MissingJevAnswer(key) => "missing Jev answer ${key}"
		NoulOutOfRange(key) => "${key} returned noul outside [0,1]"
		WrongJevAnswerCount(expected, actual) => "expected ${U64.to_str(expected)} Jev answers but received ${U64.to_str(actual)}"
		WrongJevAnswerType(key, actual) => "${key} returned type ${actual}, not noul"
	}
