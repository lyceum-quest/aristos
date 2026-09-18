app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

import cli.Cmd
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
	frequency_penalty : Dec,
	include_reasoning : Bool,
	max_tokens : U64,
	presence_penalty : Dec,
	profile : Str,
	provider : { allow_fallbacks : Bool, only : List(Str), require_parameters : Bool },
	reasoning : { enabled : Bool, exclude : Bool },
	seed : U64,
	temperature : Dec,
	top_k : U64,
	top_p : Dec,
}

Config : {
	candidates : {
		generation : Generation,
		model : { id : Str },
		provider : { api_key_env : Str, base_url : Str, name : Str },
		validation : { max_attempts : U64 },
	},
	execution : { candidate_count : U64, tokens_per_shard : U64 },
	experiment_name : Str,
	experiment_version : U64,
	selector : {
		input_cost_per_million_tokens_usd : Dec,
		model : { id : Str },
		provider : { api_key_env : Str, endpoint : Str, name : Str },
		transport : { backoff_initial_ms : U64, backoff_max_ms : U64, max_retries : U64, max_retry_after_ms : U64 },
		validation : { max_attempts : U64 },
	},
}

Token : { form : Str, id : Str, line : U64 }
Candidate : { candidates : List(Str), id : Str }

DeepResponse : {
	choices : List({ finish_reason : Str, message : { content : Str } }),
	id : Str,
	model : Str,
	provider : Str,
	usage : {
		completion_tokens : U64,
		completion_tokens_details : { reasoning_tokens : U64 },
		cost : Dec,
		prompt_tokens : U64,
		total_tokens : U64,
	},
}

JevAnswer : {
	choice : Str,
	confidence : Dec,
	probabilities : Dict(Str, Dec),
	type : Str,
}

JevResponse : {
	answers : Dict(Str, JevAnswer),
	model : Str,
	usage : { input_tokens : U64, output_tokens : U64 },
}

Usage : { input_tokens : U64, output_tokens : U64, reasoning_tokens : U64, total_tokens : U64 }

CallAudit : {
	client_request_id : Str,
	cost_usd : Dec,
	elapsed_ms : U128,
	provider_request_id : Str,
	received_at : Str,
	requested_at : Str,
	requested_model : Str,
	requested_provider : Str,
	resolved_model : Str,
	resolved_provider : Str,
	response_id : Str,
	token_usage : Usage,
}

CandidateCheckpoint : {
	call : CallAudit,
	candidates : List(Candidate),
	experiment_version : U64,
	shard_count : U64,
	shard_index : U64,
	work : Str,
}

TokenAudit : {
	candidates : List(Str),
	confidence : Dec,
	form : Str,
	id : Str,
	line : U64,
	presented : { a : Str, b : Str, c : Str, none : Str },
	probabilities : { a : Dec, b : Dec, c : Dec, none : Dec },
	selected_label : Str,
	selected_value : Str,
	winner_runner_up_margin : Dec,
}

ShardAudit : {
	candidate_call : CallAudit,
	experiment_version : U64,
	jev_call : CallAudit,
	shard_count : U64,
	shard_index : U64,
	tokens : List(TokenAudit),
	work : Str,
}

Presented : {
	candidates : List(Str),
	form : Str,
	id : Str,
	labels : { a : Str, b : Str, c : Str, none : Str },
	line : U64,
	question_key : Str,
}

Manifest : { experiment_version : U64, mode : Str, run_id : Str }
WorkAudit : { experiment_version : U64, run_id : Str, shards : List(ShardAudit), source_path : Str, work : Str }
JevState : { source_passage : Str, target_tokens : List({ form : Str, id : Str }), task : Str }
JevQuestion : { criteria : { a : Str, b : Str, c : Str, none : Str }, instructions : Str, type : Str }

CandidateAttemptRecord : {
	attempt : U64,
	call : CallAudit,
	decoded_response : DeepResponse,
	http_status : U16,
	raw_response_path : Str,
	request_body : Str,
	request_path : Str,
	run_id : Str,
	shard_count : U64,
	shard_index : U64,
	stage : Str,
	validation_error : Str,
	validation_status : Str,
	work : Str,
}

ParsedProbability : { label : Str, value : Dec }
ParsedJevAnswer : { choice : Str, confidence : Dec, probabilities : List(ParsedProbability), question_key : Str, type : Str }

JevAttemptRecord : {
	attempt : U64,
	call : CallAudit,
	headers_path : Str,
	http_status : U16,
	parsed_answer_count : U64,
	parsed_answers : List(ParsedJevAnswer),
	parsed_model : Str,
	parsed_usage : { input_tokens : U64, output_tokens : U64 },
	possible_duplicate_billing : Bool,
	raw_response_path : Str,
	request_body : Str,
	request_path : Str,
	run_id : Str,
	shard_count : U64,
	shard_index : U64,
	stage : Str,
	transport : Str,
	transport_attempt : U64,
	transport_output_path : Str,
	validation_error : Str,
	validation_status : Str,
	work : Str,
}

FailureAttemptRecord : {
	attempt : U64,
	client_request_id : Str,
	elapsed_ms : U128,
	headers_path : Str,
	http_status : U16,
	possible_duplicate_billing : Bool,
	provider_request_id : Str,
	raw_response_path : Str,
	received_at : Str,
	request_path : Str,
	requested_at : Str,
	retry_delay_ms : U64,
	run_id : Str,
	shard_count : U64,
	shard_index : U64,
	stage : Str,
	transport : Str,
	transport_attempt : U64,
	transport_error_category : Str,
	transport_error_message : Str,
	transport_output_path : Str,
	validation_error : Str,
	validation_status : Str,
	work : Str,
}

CurlOutputRecord : { exit_code : Str, http_status : U16, stderr : Str, stdout : Str }

main! = |args| {
	displayed = List.map(args, OsStr.display)
	match List.drop_first(displayed, 1) {
		["--check"] => check_experiment!()
		["--check-resume-smoke"] => check_latest_smoke_resume!()
		["--smoke"] => start_run!(Bool.True)
		["--run"] => start_run!(Bool.False)
		["--resume"] => resume_latest!()
		["--resume-smoke"] => resume_latest_smoke!()
		_ => {
			_ = Stderr.line!("usage: run-jev-gloss-experiment [--check | --check-resume-smoke | --smoke | --run | --resume | --resume-smoke]")?
			Err(Exit(2))
		}
	}
}

experiment_dir = "experiments/gloss/deepseek-v4-flash-0731/experiment_3"

expected_inputs = [
	"clouds-1-20",
	"galen-natural-faculties-1.1",
	"genesis-1.1-10",
	"herodotus-histories-1.11",
	"iliad-1.1-20",
	"xenophon-anabasis-1.8.8-10",
]

check_experiment! = || {
	config = read_config!()?
	_ = validate_config(config)?
	inputs = discover_inputs!()?
	_ = validate_input_set(inputs)?
	_ = check_inputs!(inputs, config)?
	_ = Stdout.line!("checked DeepSeek + Jev gloss experiment 3: 6 inputs; no API keys read and no requests sent")?
	Ok({})
}

check_inputs! = |inputs, config|
	match inputs {
		[] => Ok({})
		[path, .. as rest] => {
			source = Path.read_utf8!(Path.utf8(path))?
			_ = validate_source(source, path)?
			tokens = tokenize_source(source)
			shards = shard_tokens(tokens, config.execution.tokens_per_shard)
			_ = check_shards(shards, source, config)?
			check_inputs!(rest, config)
		}
	}

check_shards = |shards, source, config|
	match shards {
		[] => Ok({})
		[tokens, .. as rest] => {
			_ = candidate_request_body(config, source, tokens, "")?
			fake = fake_candidates(tokens)
			validated = validate_candidates(tokens, fake)?
			presented = present_candidates(tokens, validated)
			_ = jev_request_body(config, source, tokens, presented)?
			check_shards(rest, source, config)
		}
	}

start_run! = |smoke| {
	config = read_config!()?
	_ = validate_config(config)?
	inputs = discover_inputs!()?
	_ = validate_input_set(inputs)?
	keys = read_api_keys!(config)?
	started = Utc.now!()
	prefix = if smoke "smoke" else "run"
	run_id = "${prefix}-${run_id_for(started, config.experiment_version)}"
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = if smoke "${experiment_dir}/outputs/smoke/${run_id}" else "${experiment_dir}/outputs/${run_id}"
	_ = create_run!(run_id, run_dir, output_dir, smoke, config)?
	selected_inputs = if smoke [smoke_input(inputs)?] else inputs
	_ = run_inputs!(selected_inputs, config, keys, run_id, run_dir, output_dir, smoke)?
	_ = write_new_utf8!("complete\n", "${run_dir}/run.complete")?
	_ = Stdout.line!("completed ${run_id}\t${output_dir}")?
	Ok({})
}

resume_latest! = || {
	config = read_config!()?
	_ = validate_config(config)?
	inputs = discover_inputs!()?
	_ = validate_input_set(inputs)?
	run_id = latest_incomplete_run!("run-", "${experiment_dir}/outputs")?
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/${run_id}"
	_ = validate_run_manifest!(run_id, run_dir, output_dir, "full", config)?
	keys = read_api_keys!(config)?
	_ = run_inputs!(inputs, config, keys, run_id, run_dir, output_dir, Bool.False)?
	_ = write_new_utf8!("complete\n", "${run_dir}/run.complete")?
	_ = Stdout.line!("completed resumed run ${run_id}\t${output_dir}")?
	Ok({})
}

check_latest_smoke_resume! = || {
	config = read_config!()?
	_ = validate_config(config)?
	inputs = discover_inputs!()?
	_ = validate_input_set(inputs)?
	run_id = latest_incomplete_run!("smoke-", "${experiment_dir}/outputs/smoke")?
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/smoke/${run_id}"
	_ = validate_run_manifest!(run_id, run_dir, output_dir, "smoke", config)?
	path = smoke_input(inputs)?
	_ = validate_smoke_checkpoint!(path, config, run_id, run_dir)?
	_ = Stdout.line!("checked resumable smoke run ${run_id}: accepted candidates will be reused; no API keys read and no requests sent")?
	Ok({})
}

resume_latest_smoke! = || {
	config = read_config!()?
	_ = validate_config(config)?
	inputs = discover_inputs!()?
	_ = validate_input_set(inputs)?
	run_id = latest_incomplete_run!("smoke-", "${experiment_dir}/outputs/smoke")?
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/smoke/${run_id}"
	_ = validate_run_manifest!(run_id, run_dir, output_dir, "smoke", config)?
	path = smoke_input(inputs)?
	_ = validate_smoke_checkpoint!(path, config, run_id, run_dir)?
	typesafe = read_typesafe_api_key!(config)?
	_ = run_inputs!([path], config, { ppq: "", typesafe }, run_id, run_dir, output_dir, Bool.True)?
	_ = write_new_utf8!("complete\n", "${run_dir}/run.complete")?
	_ = Stdout.line!("completed resumed smoke run ${run_id}\t${output_dir}")?
	Ok({})
}

create_run! = |run_id, run_dir, output_dir, smoke, config| {
	if Path.exists!(Path.utf8(run_dir))? or Path.exists!(Path.utf8(output_dir))? {
		Err(RunAlreadyExists(run_id))
	} else {
		_ = Path.create_all!(Path.utf8(run_dir))?
		_ = Path.create_all!(Path.utf8(output_dir))?
		manifest : Manifest
		manifest = {
			experiment_version: config.experiment_version,
			mode: if smoke "smoke" else "full",
			run_id,
		}
		manifest_json = Json.to_str_try(manifest)?
		_ = write_new_utf8!("${manifest_json}\n", "${run_dir}/run.json")?
		Ok({})
	}
}

validate_run_manifest! = |run_id, run_dir, output_dir, expected_mode, config| {
	if !Path.exists!(Path.utf8(output_dir))? {
		Err(MissingRunOutputDirectory(output_dir))
	} else {
		raw = Path.read_utf8!(Path.utf8("${run_dir}/run.json"))?
		manifest : Manifest
		manifest = Json.parse(raw)?
		if manifest.run_id != run_id or manifest.mode != expected_mode or manifest.experiment_version != config.experiment_version {
			Err(RunManifestMismatch(run_id))
		} else {
			Ok({})
		}
	}
}

validate_smoke_checkpoint! = |path, config, run_id, run_dir| {
	source = Path.read_utf8!(Path.utf8(path))?
	_ = validate_source(source, path)?
	all_shards = shard_tokens(tokenize_source(source), config.execution.tokens_per_shard)
	match all_shards {
		[first, ..] => {
			work = work_name(path)
			shard_count = List.len(all_shards)
			checkpoint_path = "${run_dir}/${work}.shard-1-of-${U64.to_str(shard_count)}.candidates.json"
			checkpoint = read_candidate_checkpoint!(checkpoint_path)?
			_ = validate_candidate_checkpoint(checkpoint, first, work, 1, shard_count, config)?
			_ = validate_checkpoint_request!(checkpoint, source, first, run_dir, config)?
			if Path.exists!(Path.utf8("${run_dir}/${work}.complete"))? {
				Err(RunManifestMismatch(run_id))
			} else {
				Ok({})
			}
		}
		[] => Err(NoTokens(path))
	}
}

latest_incomplete_run! = |required_prefix, output_root| {
	root = "${experiment_dir}/responses"
	entries = Path.list!(Path.utf8(root))?
	find_latest_run!(entries, "", required_prefix, output_root)
}

find_latest_run! = |entries, latest, required_prefix, output_root|
	match entries {
		[] => if latest == "" Err(NoIncompleteRun) else Ok(latest)
		[entry, .. as rest] => {
			path = Path.display(entry)
			prefix = "${experiment_dir}/responses/"
			name = Str.replace_first(path, prefix, "")
			is_dir = match Path.type!(entry)? {
				IsDir => Bool.True
				_ => Bool.False
			}
			eligible = is_dir and Str.starts_with(name, required_prefix) and Str.ends_with(name, "-v3") and Path.exists!(Path.utf8("${path}/run.json"))? and Path.exists!(Path.utf8("${output_root}/${name}"))? and !Path.exists!(Path.utf8("${path}/run.complete"))?
			next = if eligible and (latest == "" or compare_str(latest, name) == Before) name else latest
			find_latest_run!(rest, next, required_prefix, output_root)
		}
	}

smoke_input = |inputs|
	match inputs {
		[] => Err(MissingSmokeInput("iliad-1.1-20"))
		[path, .. as rest] => if work_name(path) == "iliad-1.1-20" Ok(path) else smoke_input(rest)
	}

run_inputs! = |inputs, config, keys, run_id, run_dir, output_dir, smoke|
	match inputs {
		[] => Ok({})
		[path, .. as rest] => {
			work = work_name(path)
			marker = "${run_dir}/${work}.complete"
			if Path.exists!(Path.utf8(marker))? {
				_ = Stdout.line!("skipped completed work ${work}")?
				run_inputs!(rest, config, keys, run_id, run_dir, output_dir, smoke)
			} else {
				_ = run_input!(path, config, keys, run_id, run_dir, output_dir, smoke)?
				if smoke Ok({}) else run_inputs!(rest, config, keys, run_id, run_dir, output_dir, smoke)
			}
		}
	}

run_input! = |path, config, keys, run_id, run_dir, output_dir, smoke| {
	source = Path.read_utf8!(Path.utf8(path))?
	_ = validate_source(source, path)?
	tokens = tokenize_source(source)
	all_shards = shard_tokens(tokens, config.execution.tokens_per_shard)
	shards = if smoke {
		match all_shards {
			[first, ..] => [first]
			[] => []
		}
	} else all_shards
	work = work_name(path)
	shard_count = List.len(all_shards)
	audits = run_shards!(shards, work, source, config, keys, run_id, run_dir, 1, shard_count, [])?
	readable = render_audits(audits)
	work_audit : WorkAudit
	work_audit = {
		experiment_version: config.experiment_version,
		run_id,
		shards: audits,
		source_path: path,
		work,
	}
	audit_json = Json.to_str_try(work_audit)?
	name = if smoke "${work}.shard-1-of-${U64.to_str(shard_count)}" else work
	_ = write_atomic_or_verify!(readable, "${output_dir}/${name}.txt")?
	_ = write_atomic_or_verify!("${audit_json}\n", "${output_dir}/${name}.audit.json")?
	_ = write_new_utf8!("${output_dir}/${name}.txt\n", "${run_dir}/${work}.complete")?
	_ = Stdout.line!("completed work ${work}\t${output_dir}/${name}.txt")?
	Ok({})
}

run_shards! = |shards, work, source, config, keys, run_id, run_dir, shard_index, shard_count, found|
	match shards {
		[] => Ok(found)
		[tokens, .. as rest] => {
			base = "${run_dir}/${work}.shard-${U64.to_str(shard_index)}-of-${U64.to_str(shard_count)}"
			audit_path = "${base}.audit.json"
			audit = if Path.exists!(Path.utf8(audit_path))? {
				loaded = read_shard_audit!(audit_path)?
				_ = validate_shard_audit(loaded, tokens, work, shard_index, shard_count, config)?
				_ = Stdout.line!("reused shard audit ${work} ${U64.to_str(shard_index)}/${U64.to_str(shard_count)}")?
				loaded
			} else {
				candidate_checkpoint = load_or_generate_candidates!(base, work, source, tokens, config, keys.ppq, run_id, run_dir, shard_index, shard_count)?
				presented = present_candidates(tokens, candidate_checkpoint.candidates)
				jev_body = jev_request_body(config, source, tokens, presented)?
				run_jev_attempt!(work, tokens, presented, candidate_checkpoint.call, config, keys.typesafe, run_id, run_dir, shard_index, shard_count, 1, jev_body, Bool.False)?
			}
			run_shards!(rest, work, source, config, keys, run_id, run_dir, shard_index + 1, shard_count, List.append(found, audit))
		}
	}

load_or_generate_candidates! = |base, work, source, tokens, config, api_key, run_id, run_dir, shard_index, shard_count| {
	checkpoint_path = "${base}.candidates.json"
	if Path.exists!(Path.utf8(checkpoint_path))? {
		checkpoint = read_candidate_checkpoint!(checkpoint_path)?
		_ = validate_candidate_checkpoint(checkpoint, tokens, work, shard_index, shard_count, config)?
		_ = Stdout.line!("reused candidate checkpoint ${work} ${U64.to_str(shard_index)}/${U64.to_str(shard_count)}")?
		Ok(checkpoint)
	} else {
		run_candidate_attempt!(work, source, tokens, config, api_key, run_id, run_dir, shard_index, shard_count, 1, "")
	}
}

run_candidate_attempt! = |work, source, tokens, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, feedback| {
	body = candidate_request_body(config, source, tokens, feedback)?
	captured = send_candidate_request!(work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body)?
	outcome = process_candidate_response!(work, tokens, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured)?
	match outcome {
		Accepted(value) => Ok(value)
		Rejected(error_text) => {
			_ = Stdout.line!("rejected DeepSeek candidates ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} attempt ${U64.to_str(attempt)}: ${error_text}")?
			if attempt < config.candidates.validation.max_attempts {
				run_candidate_attempt!(work, source, tokens, config, api_key, run_id, run_dir, shard_index, shard_count, attempt + 1, error_text)
			} else {
				Err(CandidateValidationAttemptsExhausted(work, shard_index, error_text))
			}
		}
	}
}

send_candidate_request! = |work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body| {
	requested_at = Utc.now!()
	requested_text = Utc.to_iso_8601(requested_at)
	nonce = U128.to_str(Utc.to_nanos_since_epoch(requested_at))
	client_request_id = "deepseek-${work}-shard-${U64.to_str(shard_index)}-attempt-${U64.to_str(attempt)}-${nonce}"
	request_path = "${run_dir}/${client_request_id}.request.json"
	raw_path = "${run_dir}/${client_request_id}.raw.json"
	_ = write_new_utf8!(body, request_path)?
	request = Request.from_method(POST)
		.with_uri("${config.candidates.provider.base_url}/chat/completions")
		.with_timeout(TimeoutMilliseconds(300000))
		.add_header("Authorization", "Bearer ${api_key}")
		.add_header("Content-Type", "application/json")
		.with_body(Str.to_utf8(body))
	match Http.send!(request) {
		Err(problem) => {
			received_at = Utc.now!()
			error = http_transport_error(problem, api_key)
			_ = write_new_bytes!([], raw_path)?
			_ = write_native_transport_failure!("deepseek", work, run_id, run_dir, shard_index, shard_count, attempt, client_request_id, request_path, raw_path, requested_text, Utc.to_iso_8601(received_at), Utc.delta_as_millis(received_at, requested_at), error.category, error.message)?
			Err(DeepSeekTransportFailure(work, shard_index))
		}
		Ok(response) => {
			received_at = Utc.now!()
			raw = Response.body(response)
			_ = write_new_bytes!(raw, raw_path)?
			status = Response.status(response)
			if status < 200 or status >= 300 {
				_ = write_native_http_failure!("deepseek", work, run_id, run_dir, shard_index, shard_count, attempt, client_request_id, request_path, raw_path, requested_text, Utc.to_iso_8601(received_at), Utc.delta_as_millis(received_at, requested_at), status, Response.headers(response))?
				Err(DeepSeekHttpFailure(status))
			} else {
				Ok({
					client_request_id,
					elapsed_ms: Utc.delta_as_millis(received_at, requested_at),
					headers: Response.headers(response),
					raw,
					raw_path,
					received_at: Utc.to_iso_8601(received_at),
					requested_at: requested_text,
					request_path,
					status,
				})
			}
		}
	}
}

process_candidate_response! = |work, tokens, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured| {
	parsed : Try(DeepResponse, _)
	parsed = decode_json_bytes(captured.raw)
	match parsed {
		Err(_) => reject_candidate_attempt!(work, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured, empty_deep_response, "captured response was not the required PPQ completion envelope")
		Ok(decoded) =>
			match decoded.choices {
				[] => reject_candidate_attempt!(work, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, "captured response contained no completion choice")
				[choice, ..] => {
					validation = if choice.finish_reason != "stop" {
						Err(IncompleteFinish(choice.finish_reason))
					} else if decoded.model != config.candidates.model.id {
						Err(WrongCandidateModel(config.candidates.model.id, decoded.model))
					} else if decoded.provider != "Sail Research" {
						Err(WrongCandidateProvider("Sail Research", decoded.provider))
					} else {
						validate_candidate_content(choice.message.content, tokens)
					}
					match validation {
						Err(problem) => reject_candidate_attempt!(work, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, candidate_error_text(problem))
						Ok(candidates) => {
							call = deep_call_audit(config, decoded, captured)
							checkpoint : CandidateCheckpoint
							checkpoint = {
								call,
								candidates,
								experiment_version: config.experiment_version,
								shard_count,
								shard_index,
								work,
							}
							checkpoint_json = Json.to_str_try(checkpoint)?
							checkpoint_path = "${run_dir}/${work}.shard-${U64.to_str(shard_index)}-of-${U64.to_str(shard_count)}.candidates.json"
							_ = write_atomic_new!("${checkpoint_json}\n", checkpoint_path)?
							_ = write_candidate_attempt!(work, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, "valid", "", call)?
							Ok(Accepted(checkpoint))
						}
					}
				}
		}
	}
}

reject_candidate_attempt! = |work, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, error_text| {
	call = deep_call_audit(config, decoded, captured)
	_ = write_candidate_attempt!(work, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, "rejected", error_text, call)?
	Ok(Rejected(error_text))
}

deep_call_audit = |config, decoded, captured| {
	call : CallAudit
	call = {
		client_request_id: captured.client_request_id,
		cost_usd: decoded.usage.cost,
		elapsed_ms: captured.elapsed_ms,
		provider_request_id: response_request_id(captured.headers),
		received_at: captured.received_at,
		requested_at: captured.requested_at,
		requested_model: config.candidates.model.id,
		requested_provider: "ppq/sail-research",
		resolved_model: decoded.model,
		resolved_provider: decoded.provider,
		response_id: decoded.id,
		token_usage: {
			input_tokens: decoded.usage.prompt_tokens,
			output_tokens: decoded.usage.completion_tokens,
			reasoning_tokens: decoded.usage.completion_tokens_details.reasoning_tokens,
			total_tokens: decoded.usage.total_tokens,
		},
	}
	call
}

write_candidate_attempt! = |work, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, status, error_text, call| {
	record : CandidateAttemptRecord
	record = {
		attempt,
		call,
		decoded_response: decoded,
		http_status: captured.status,
		raw_response_path: captured.raw_path,
		request_body: body,
		request_path: captured.request_path,
		run_id,
		shard_count,
		shard_index,
		stage: "deepseek-candidates",
		validation_error: error_text,
		validation_status: status,
		work,
	}
	json = Json.to_str_try(record)?
	write_new_utf8!("${json}\n", "${run_dir}/${captured.client_request_id}.attempt.json")
}

run_jev_attempt! = |work, tokens, presented, candidate_call, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body, possible_duplicate_billing| {
	transport_state = jev_transport_state!(run_dir, work, shard_index, attempt)?
	if transport_state.current_count > config.selector.transport.max_retries {
		Err(JevTransportFailure(work, shard_index))?
	} else {}
	retries_remaining = config.selector.transport.max_retries - transport_state.current_count
	duplicate_risk = possible_duplicate_billing or transport_state.prior_request_exists
	captured = send_jev_request!(work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, transport_state.next_attempt, retries_remaining, body, duplicate_risk)?
	outcome = process_jev_response!(work, tokens, presented, candidate_call, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured)?
	match outcome {
		Accepted(value) => Ok(value)
		Rejected(error_text) => {
			_ = Stdout.line!("rejected Jev selection ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} attempt ${U64.to_str(attempt)}: ${error_text}")?
			if attempt < config.selector.validation.max_attempts {
				run_jev_attempt!(work, tokens, presented, candidate_call, config, api_key, run_id, run_dir, shard_index, shard_count, attempt + 1, body, captured.possible_duplicate_billing)
			} else {
				Err(JevValidationAttemptsExhausted(work, shard_index, error_text))
			}
		}
	}
}

jev_transport_state! = |run_dir, work, shard_index, validation_attempt| {
	entries = Path.list!(Path.utf8(run_dir))?
	prefix = "jev-${work}-shard-${U64.to_str(shard_index)}-"
	request_entries = List.keep_if(entries, |entry| {
		name = Path.display(entry)
		Str.contains(name, prefix) and Str.ends_with(name, ".request.json")
	})
	validation_marker = "${prefix}validation-${U64.to_str(validation_attempt)}-transport-"
	current_count = List.len(List.keep_if(request_entries, |entry| {
		name = Path.display(entry)
		new_attempt = Str.contains(name, validation_marker)
		legacy_attempt = validation_attempt == 1 and Str.contains(name, "${prefix}attempt-")
		new_attempt or legacy_attempt
	}))
	Ok({
		current_count,
		next_attempt: List.len(request_entries) + 1,
		prior_request_exists: !List.is_empty(request_entries),
	})
}

# Work around basic-cli's HTTP/1-only Hyper transport failure for this valid TypeSafe POST.
# Upstream: https://github.com/roc-lang/basic-cli/issues/455 and https://github.com/roc-lang/basic-cli/issues/438
# Remove curl after a released compatible basic-cli transport completes this retained request and exposes safe diagnostics.
send_jev_request! = |work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, transport_attempt, retries_remaining, body, possible_duplicate_billing| {
	requested_at = Utc.now!()
	requested_text = Utc.to_iso_8601(requested_at)
	nonce = U128.to_str(Utc.to_nanos_since_epoch(requested_at))
	client_request_id = "jev-${work}-shard-${U64.to_str(shard_index)}-validation-${U64.to_str(attempt)}-transport-${U64.to_str(transport_attempt)}-${nonce}"
	request_path = "${run_dir}/${client_request_id}.request.json"
	raw_path = "${run_dir}/${client_request_id}.raw.json"
	headers_path = "${run_dir}/${client_request_id}.headers"
	transport_output_path = "${run_dir}/${client_request_id}.transport.json"
	_ = write_new_utf8!(body, request_path)?
	curl_result = Cmd.new_str("curl")
		.args_str([
			"--silent",
			"--show-error",
			"--request",
			"POST",
			"--connect-timeout",
			"30",
			"--max-time",
			"300",
			"--proto",
			"=https",
			"--header",
			"Content-Type: application/json",
			"--header",
			"Expect:",
			"--variable",
			"%ARISTOS_TYPESAFE_API_KEY",
			"--expand-header",
			"Authorization: Bearer {{ARISTOS_TYPESAFE_API_KEY}}",
			"--data-binary",
			"@${request_path}",
			"--dump-header",
			headers_path,
			"--output",
			raw_path,
			"--write-out",
			"%{http_code}",
			config.selector.provider.endpoint,
		])
		.env_str("ARISTOS_TYPESAFE_API_KEY", api_key)
		.exec_output!()
	match curl_result {
		Ok(output) => {
			status = curl_http_status(output.stdout_utf8)
			_ = write_curl_output!(transport_output_path, "0", status, output.stdout_utf8, safe_transport_message(output.stderr_utf8_lossy, api_key))?
			_ = ensure_bytes_artifact!(raw_path)?
			_ = ensure_bytes_artifact!(headers_path)?
			received_at = Utc.now!()
			raw = Path.read_bytes!(Path.utf8(raw_path))?
			headers = read_curl_headers!(headers_path)?
			if status < 200 or status >= 300 {
				retryable = is_transient_jev_status(status)
				delay_ms = if retryable and retries_remaining > 0 retry_delay_ms!(headers, config.selector.transport, config.selector.transport.max_retries - retries_remaining + 1)? else 0
				_ = write_http_failure!("jev", work, run_id, run_dir, shard_index, shard_count, attempt, "curl-workaround", transport_attempt, client_request_id, request_path, raw_path, headers_path, transport_output_path, requested_text, Utc.to_iso_8601(received_at), Utc.delta_as_millis(received_at, requested_at), status, headers, delay_ms, possible_duplicate_billing)?
				if retryable and retries_remaining > 0 {
					_ = Stdout.line!("retrying Jev transport ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} after ${U64.to_str(delay_ms)} ms: HTTP ${U16.to_str(status)}")?
					_ = Sleep.millis!(delay_ms)
					send_jev_request!(work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, transport_attempt + 1, retries_remaining - 1, body, possible_duplicate_billing)
				} else {
					Err(JevHttpFailure(status))
				}
			} else {
				Ok({
					client_request_id,
					elapsed_ms: Utc.delta_as_millis(received_at, requested_at),
					headers,
					headers_path,
					possible_duplicate_billing,
					raw,
					raw_path,
					received_at: Utc.to_iso_8601(received_at),
					requested_at: requested_text,
					request_path,
					status,
					transport: "curl-workaround",
					transport_attempt,
					transport_output_path,
				})
			}
		}
		Err(NonZeroExitCode(details)) => {
			status = curl_http_status(details.stdout_utf8_lossy)
			stderr = safe_transport_message(details.stderr_utf8_lossy, api_key)
			error = curl_transport_error(details.exit_code, stderr)
			_ = write_curl_output!(transport_output_path, I32.to_str(details.exit_code), status, details.stdout_utf8_lossy, stderr)?
			_ = ensure_bytes_artifact!(raw_path)?
			_ = ensure_bytes_artifact!(headers_path)?
			received_at = Utc.now!()
			next_duplicate = possible_duplicate_billing or error.ambiguous
			retryable = error.retryable
			delay_ms = if retryable and retries_remaining > 0 retry_backoff_ms(config.selector.transport, config.selector.transport.max_retries - retries_remaining + 1) else 0
			_ = write_transport_failure!("jev", work, run_id, run_dir, shard_index, shard_count, attempt, transport_attempt, client_request_id, request_path, raw_path, headers_path, transport_output_path, requested_text, Utc.to_iso_8601(received_at), Utc.delta_as_millis(received_at, requested_at), status, "curl-workaround", error.category, error.message, delay_ms, next_duplicate)?
			if retryable and retries_remaining > 0 {
				_ = Stdout.line!("retrying Jev transport ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} after ${U64.to_str(delay_ms)} ms: ${error.category}")?
				_ = Sleep.millis!(delay_ms)
				send_jev_request!(work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, transport_attempt + 1, retries_remaining - 1, body, next_duplicate)
			} else {
				Err(JevTransportFailure(work, shard_index))
			}
		}
		Err(_) => {
			_ = write_curl_output!(transport_output_path, "not-started", 0, "", "curl process could not be started")?
			_ = ensure_bytes_artifact!(raw_path)?
			_ = ensure_bytes_artifact!(headers_path)?
			received_at = Utc.now!()
			_ = write_transport_failure!("jev", work, run_id, run_dir, shard_index, shard_count, attempt, transport_attempt, client_request_id, request_path, raw_path, headers_path, transport_output_path, requested_text, Utc.to_iso_8601(received_at), Utc.delta_as_millis(received_at, requested_at), 0, "curl-workaround", "process-start", "curl process could not be started", 0, possible_duplicate_billing)?
			Err(JevTransportFailure(work, shard_index))
		}
	}
}

process_jev_response! = |work, tokens, presented, candidate_call, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured| {
	parsed : Try(JevResponse, _)
	parsed = decode_json_bytes(captured.raw)
	match parsed {
		Err(_) => reject_jev_attempt!(work, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured, empty_jev_response, "captured response was not the direct TypeSafe System One schema")
		Ok(decoded) => {
			validation = if decoded.model != config.selector.model.id {
				Err(WrongJevModel(config.selector.model.id, decoded.model))
			} else {
				validate_jev_answers(tokens, presented, decoded.answers)
			}
			match validation {
				Err(problem) => reject_jev_attempt!(work, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, jev_error_text(problem))
				Ok(token_audits) => {
					call = jev_call_audit(config, decoded, captured)
					audit : ShardAudit
					audit = {
						candidate_call,
						experiment_version: config.experiment_version,
						jev_call: call,
						shard_count,
						shard_index,
						tokens: token_audits,
						work,
					}
					audit_json = Json.to_str_try(audit)?
					audit_path = "${run_dir}/${work}.shard-${U64.to_str(shard_index)}-of-${U64.to_str(shard_count)}.audit.json"
					_ = write_atomic_new!("${audit_json}\n", audit_path)?
					_ = write_jev_attempt!(work, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, "valid", "", call)?
					Ok(Accepted(audit))
				}
			}
		}
	}
}

reject_jev_attempt! = |work, config, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, error_text| {
	call = jev_call_audit(config, decoded, captured)
	_ = write_jev_attempt!(work, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, "rejected", error_text, call)?
	Ok(Rejected(error_text))
}

jev_call_audit = |config, decoded, captured| {
	input_as_dec : Dec
	input_as_dec = U64.to_dec(decoded.usage.input_tokens)
	cost = input_as_dec * config.selector.input_cost_per_million_tokens_usd / 1000000
	call : CallAudit
	call = {
		client_request_id: captured.client_request_id,
		cost_usd: cost,
		elapsed_ms: captured.elapsed_ms,
		provider_request_id: response_request_id(captured.headers),
		received_at: captured.received_at,
		requested_at: captured.requested_at,
		requested_model: config.selector.model.id,
		requested_provider: config.selector.provider.name,
		resolved_model: decoded.model,
		resolved_provider: config.selector.provider.name,
		response_id: response_request_id(captured.headers),
		token_usage: {
			input_tokens: decoded.usage.input_tokens,
			output_tokens: decoded.usage.output_tokens,
			reasoning_tokens: 0,
			total_tokens: decoded.usage.input_tokens + decoded.usage.output_tokens,
		},
	}
	call
}

write_jev_attempt! = |work, run_id, run_dir, shard_index, shard_count, attempt, body, captured, decoded, status, error_text, call| {
	record : JevAttemptRecord
	record = {
		attempt,
		call,
		headers_path: captured.headers_path,
		http_status: captured.status,
		parsed_answer_count: Dict.len(decoded.answers),
		parsed_answers: parsed_jev_answers(decoded.answers),
		parsed_model: decoded.model,
		parsed_usage: decoded.usage,
		possible_duplicate_billing: captured.possible_duplicate_billing,
		raw_response_path: captured.raw_path,
		request_body: body,
		request_path: captured.request_path,
		run_id,
		shard_count,
		shard_index,
		stage: "jev-selection",
		transport: captured.transport,
		transport_attempt: captured.transport_attempt,
		transport_output_path: captured.transport_output_path,
		validation_error: error_text,
		validation_status: status,
		work,
	}
	json = Json.to_str_try(record)?
	write_new_utf8!("${json}\n", "${run_dir}/${captured.client_request_id}.attempt.json")
}

parsed_jev_answers = |answers|
	List.map(Dict.to_list(answers), |pair|
		match pair {
			(question_key, answer) => {
				choice: answer.choice,
				confidence: answer.confidence,
				probabilities: List.map(Dict.to_list(answer.probabilities), |probability_pair|
					match probability_pair {
						(label, value) => { label, value }
					}
				),
				question_key,
				type: answer.type,
			}
		}
	)

write_transport_failure! = |stage, work, run_id, run_dir, shard_index, shard_count, attempt, transport_attempt, client_request_id, request_path, raw_path, headers_path, transport_output_path, requested_at, received_at, elapsed_ms, http_status, transport, category, message, retry_delay_ms, possible_duplicate_billing| {
	record : FailureAttemptRecord
	record = {
		attempt,
		client_request_id,
		elapsed_ms,
		headers_path,
		http_status,
		possible_duplicate_billing,
		provider_request_id: "",
		raw_response_path: raw_path,
		received_at,
		request_path,
		requested_at,
		retry_delay_ms,
		run_id,
		shard_count,
		shard_index,
		stage,
		transport,
		transport_attempt,
		transport_error_category: category,
		transport_error_message: message,
		transport_output_path,
		validation_error: "HTTP transport failed before a complete response was captured",
		validation_status: "transport-failed",
		work,
	}
	json = Json.to_str_try(record)?
	write_new_utf8!("${json}\n", "${run_dir}/${client_request_id}.attempt.json")
}

write_http_failure! = |stage, work, run_id, run_dir, shard_index, shard_count, attempt, transport, transport_attempt, client_request_id, request_path, raw_path, headers_path, transport_output_path, requested_at, received_at, elapsed_ms, http_status, headers, retry_delay_ms, possible_duplicate_billing| {
	record : FailureAttemptRecord
	record = {
		attempt,
		client_request_id,
		elapsed_ms,
		headers_path,
		http_status,
		possible_duplicate_billing,
		provider_request_id: response_request_id(headers),
		raw_response_path: raw_path,
		received_at,
		request_path,
		requested_at,
		retry_delay_ms,
		run_id,
		shard_count,
		shard_index,
		stage,
		transport,
		transport_attempt,
		transport_error_category: "http-status",
		transport_error_message: "provider returned HTTP ${U16.to_str(http_status)}",
		transport_output_path,
		validation_error: "provider returned a non-success HTTP status",
		validation_status: "http-rejected",
		work,
	}
	json = Json.to_str_try(record)?
	write_new_utf8!("${json}\n", "${run_dir}/${client_request_id}.attempt.json")
}

write_native_transport_failure! = |stage, work, run_id, run_dir, shard_index, shard_count, attempt, client_request_id, request_path, raw_path, requested_at, received_at, elapsed_ms, category, message| {
	write_transport_failure!(stage, work, run_id, run_dir, shard_index, shard_count, attempt, 1, client_request_id, request_path, raw_path, "", "", requested_at, received_at, elapsed_ms, 0, "basic-cli", category, message, 0, Bool.False)
}

write_native_http_failure! = |stage, work, run_id, run_dir, shard_index, shard_count, attempt, client_request_id, request_path, raw_path, requested_at, received_at, elapsed_ms, http_status, headers| {
	write_http_failure!(stage, work, run_id, run_dir, shard_index, shard_count, attempt, "basic-cli", 1, client_request_id, request_path, raw_path, "", "", requested_at, received_at, elapsed_ms, http_status, headers, 0, Bool.False)
}

write_curl_output! = |path, exit_code, http_status, stdout, stderr| {
	record : CurlOutputRecord
	record = { exit_code, http_status, stderr, stdout }
	json = Json.to_str_try(record)?
	write_new_utf8!("${json}\n", path)
}

ensure_bytes_artifact! = |path|
	if Path.exists!(Path.utf8(path))? Ok({}) else write_new_bytes!([], path)

curl_http_status = |stdout|
	match U16.from_str(Str.trim(stdout)) {
		Ok(status) => status
		Err(_) => 0
	}

safe_transport_message = |message, api_key| {
	trimmed = Str.trim(message)
	redacted = if api_key == "" trimmed else Str.replace_each(trimmed, api_key, "[REDACTED]")
	if redacted == "" "no transport detail was returned" else redacted
}

curl_transport_error = |exit_code, message| {
	category = if exit_code == 6 {
		"dns"
	} else if exit_code == 7 {
		"connect"
	} else if exit_code == 28 {
		"timeout"
	} else if exit_code == 35 or exit_code == 51 or exit_code == 58 or exit_code == 60 {
		"tls"
	} else if exit_code == 52 {
		"empty-response"
	} else if exit_code == 55 {
		"send"
	} else if exit_code == 56 {
		"receive"
	} else {
		"curl-exit"
	}
	ambiguous = exit_code != 6 and exit_code != 7 and exit_code != 35 and exit_code != 51 and exit_code != 58 and exit_code != 60
	retryable = exit_code == 5 or exit_code == 6 or exit_code == 7 or exit_code == 16 or exit_code == 18 or exit_code == 28 or exit_code == 52 or exit_code == 55 or exit_code == 56 or exit_code == 92
	{ ambiguous, category, message, retryable }
}

http_transport_error = |problem, api_key|
	match problem {
		HttpErr(Timeout) => { category: "timeout", message: "basic-cli HTTP request timed out" }
		HttpErr(NetworkError) => { category: "network", message: "basic-cli reported a network error" }
		HttpErr(BadBody) => { category: "response-body", message: "basic-cli failed while collecting the response body" }
		HttpErr(Other(bytes)) => { category: "other", message: safe_transport_message(Str.from_utf8_lossy(bytes), api_key) }
		InvalidUrl(_) => { category: "invalid-url", message: "basic-cli rejected the request URL" }
	}

read_curl_headers! = |path| {
	bytes = Path.read_bytes!(Path.utf8(path))?
	text = Str.from_utf8(bytes) ? |_| InvalidUtf8Response
	Ok(parse_curl_header_lines(Str.split_on(text, "\n"), []))
}

parse_curl_header_lines = |lines, found|
	match lines {
		[] => found
		[line, .. as rest] => {
			clean = Str.trim(line)
			parts = Str.split_on(clean, ":")
			next = match parts {
				[name, value, .. as remaining] => List.append(found, { name: Str.trim(name), value: Str.trim(Str.join_with(List.prepend(remaining, value), ":")) })
				_ => found
			}
			parse_curl_header_lines(rest, next)
		}
	}

is_transient_jev_status = |status| status == 408 or status == 429 or status >= 500

retry_backoff_ms = |transport, retry_number| {
	uncapped = retry_backoff_uncapped(transport.backoff_initial_ms, retry_number)
	if uncapped > transport.backoff_max_ms transport.backoff_max_ms else uncapped
}

retry_backoff_uncapped : U64, U64 -> U64
retry_backoff_uncapped = |delay, retry_number|
	if retry_number <= 1 delay else retry_backoff_uncapped(delay * 2, retry_number - 1)

retry_delay_ms! = |headers, transport, retry_number| {
	fallback = retry_backoff_ms(transport, retry_number)
	retry_after_millis = response_header_value(headers, "retry-after-ms")
	retry_after = response_header_value(headers, "retry-after")
	if retry_after_millis != "" {
		Ok(retry_header_delay(retry_after_millis, 1, fallback, transport.max_retry_after_ms))
	} else if retry_after == "" {
		Ok(fallback)
	} else {
		match U64.from_str(retry_after) {
			Ok(seconds) => Ok(retry_header_delay(U64.to_str(seconds), 1000, fallback, transport.max_retry_after_ms))
			Err(_) => retry_after_date_ms!(retry_after, fallback, transport.max_retry_after_ms)
		}
	}
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
	parsed = Cmd.new_str("date")
		.args_str(["--date", value, "+%s"])
		.exec_output!()
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

response_header_value = |headers, expected|
	match headers {
		[] => ""
		[header, .. as rest] => {
			{name, value} = header
			if Str.caseless_ascii_equals(name, expected) value else response_header_value(rest, expected)
		}
	}

candidate_request_body = |config, source, tokens, feedback| {
	generation : Generation
	generation = config.candidates.generation
	model_id : Str
	model_id = config.candidates.model.id
	typed_tokens : List(Token)
	typed_tokens = tokens
	source_text : Str
	source_text = source
	system_prompt = \\
		\\Act as an Ancient Greek philologist producing concise contextual English token glosses.
		\\Return only the requested JSON. Do not return commentary, lemmas, morphology, Greek text, or prose translations.
	instructions = \\
		\\Produce exactly three distinct candidate glosses for every target token, in target order.
		\\Each candidate must reflect the inflected token in the complete source context. Good Anabasis-style glosses include of-Darius, of-birds, to-him, are-born, and he-was-thinking.
		\\A candidate must be nonempty and must not contain spaces, tabs, line breaks, or the <=> delimiter. Join every multiword gloss with hyphens.
		\\Copy every token ID exactly. Return no token not listed and omit no listed token.
	retry = if feedback == "" "" else "RETRY: The previous captured response was rejected: ${feedback}\nCorrect that structural error without adding commentary."
	table = Str.join_with(List.map(typed_tokens, |token| "${token.id} | ${U64.to_str(token.line)} | ${token.form}"), "\n")
	user_prompt = Str.join_with([
		instructions,
		retry,
		"",
		"COMPLETE SOURCE PASSAGE:",
		source_text,
		"TARGET TOKENS (immutable ID | source line | exact form):",
		table,
	], "\n")
	token_ids = List.map(typed_tokens, |token| token.id)
	count = List.len(typed_tokens)
	one : U64
	one = 1
	three : U64
	three = 3
	response_format = {
		json_schema: {
			name: "three_contextual_gloss_candidates",
			schema: {
				additionalProperties: Bool.False,
				properties: {
					tokens: {
						items: {
							additionalProperties: Bool.False,
							properties: {
								candidates: { items: { minLength: one, type: "string" }, maxItems: three, minItems: three, type: "array" },
								id: { enum: token_ids, type: "string" },
							},
							required: ["id", "candidates"],
							type: "object",
						},
						maxItems: count,
						minItems: count,
						type: "array",
					},
				},
				required: ["tokens"],
				type: "object",
			},
			strict: Bool.True,
		},
		type: "json_schema",
	}
	body = {
		frequency_penalty: generation.frequency_penalty,
		include_reasoning: generation.include_reasoning,
		max_tokens: generation.max_tokens,
		messages: [
			{ content: system_prompt, role: "system" },
			{ content: user_prompt, role: "user" },
		],
		model: model_id,
		presence_penalty: generation.presence_penalty,
		provider: generation.provider,
		reasoning: generation.reasoning,
		response_format,
		seed: generation.seed,
		temperature: generation.temperature,
		top_k: generation.top_k,
		top_p: generation.top_p,
	}
	Json.to_str_try(body)
}

jev_request_body = |config, source, tokens, presented| {
	model_id : Str
	model_id = config.selector.model.id
	typed_tokens : List(Token)
	typed_tokens = tokens
	typed_presented : List(Presented)
	typed_presented = presented
	state : JevState
	state = {
		source_passage: source,
		target_tokens: List.map(typed_tokens, |token| { form: token.form, id: token.id }),
		task: "Select the best concise contextual English gloss for each identified Ancient Greek token. Choices are generated candidates; choose none only when no candidate fits the token in this passage.",
	}
	model_json = Json.to_str_try(model_id)?
	state_json = Json.to_str_try(state)?
	question_entries = jev_question_entries(typed_presented, [])?
	Ok("{\"model\":${model_json},\"questions\":{${Str.join_with(question_entries, ",")}},\"state\":${state_json}}")
}

jev_question_entries = |presented, found|
	match presented {
		[] => Ok(found)
		[item, .. as rest] => {
			question : JevQuestion
			question = {
				criteria: {
					a: item.labels.a,
					b: item.labels.b,
					c: item.labels.c,
					none: "None of candidates a, b, or c is a valid contextual gloss for this target token.",
				},
				instructions: "For target token ID ${item.id} with exact Greek form ${item.form}, select the best contextual English gloss in the complete source passage. Select none only if a, b, and c are all invalid. Evaluate this identified token, not any other occurrence.",
				type: "choice",
			}
			key_json = Json.to_str_try(item.question_key)?
			question_json = Json.to_str_try(question)?
			jev_question_entries(rest, List.append(found, "${key_json}:${question_json}"))
		}
	}

validate_candidate_content = |content, tokens| {
	parsed : Try({ tokens : List(Candidate) }, _)
	parsed = Json.parse(content)
	match parsed {
		Err(_) => Err(InvalidCandidateJson)
		Ok(payload) => validate_candidates(tokens, payload.tokens)
	}
}

validate_candidates = |tokens, candidates|
	if List.len(tokens) != List.len(candidates) {
		Err(WrongCandidateTokenCount(List.len(tokens), List.len(candidates)))
	} else {
		validate_candidate_rows(tokens, candidates, [])
	}

validate_candidate_rows = |tokens, candidates, found|
	match (tokens, candidates) {
		([], []) => Ok(found)
		([token, .. as rest_tokens], [entry, .. as rest_entries]) => {
			if entry.id != token.id {
				Err(WrongCandidateId(token.id, entry.id))
			} else {
				values = validate_three_candidates(token.id, entry.candidates)?
				validate_candidate_rows(rest_tokens, rest_entries, List.append(found, { candidates: values, id: entry.id }))
			}
		}
		_ => Err(InternalCandidateLengthMismatch)
	}

validate_three_candidates = |token_id, raw|
	match raw {
		[a_raw, b_raw, c_raw] => {
			_ = validate_candidate_value(token_id, a_raw)?
			_ = validate_candidate_value(token_id, b_raw)?
			_ = validate_candidate_value(token_id, c_raw)?
			a = Str.trim(a_raw)
			b = Str.trim(b_raw)
			c = Str.trim(c_raw)
			if Str.caseless_ascii_equals(a, b) or Str.caseless_ascii_equals(a, c) or Str.caseless_ascii_equals(b, c) {
				Err(DuplicateCandidate(token_id))
			} else {
				Ok([a, b, c])
			}
		}
		_ => Err(WrongCandidateCount(token_id, List.len(raw)))
	}

validate_candidate_value = |token_id, value|
	if value == "" {
		Err(EmptyCandidate(token_id))
	} else if Str.contains(value, " ") or Str.contains(value, "\t") or Str.contains(value, "\n") or Str.contains(value, "\r") or Str.contains(value, "<=>") {
		Err(UnsafeCandidate(token_id))
	} else if Str.caseless_ascii_equals(value, "[UNRESOLVED]") {
		Err(ReservedCandidate(token_id))
	} else {
		Ok({})
	}

present_candidates = |tokens, candidates| present_candidates_loop(tokens, candidates, [])

present_candidates_loop = |tokens, candidates, found|
	match (tokens, candidates) {
		([], []) => found
		([token, .. as rest_tokens], [entry, .. as rest_candidates]) => {
			labels = rotate_candidates(entry.candidates, rotation_for_token_id(token.id))
			item : Presented
			item = {
				candidates: entry.candidates,
				form: token.form,
				id: token.id,
				labels,
				line: token.line,
				question_key: "token_${token.id}",
			}
			present_candidates_loop(rest_tokens, rest_candidates, List.append(found, item))
		}
		_ => found
	}

rotation_for_token_id = |id|
	match U64.from_str(id) {
		Ok(number) => if number == 0 0 else remainder_three(number - 1)
		Err(_) => 0
	}

remainder_three = |number|
	if number < 3 number else remainder_three(number - 3)

rotate_candidates = |values, rotation|
	match values {
		[a, b, c] =>
			if rotation == 0 {
				{ a, b, c, none: "[UNRESOLVED]" }
			} else if rotation == 1 {
				{ a: b, b: c, c: a, none: "[UNRESOLVED]" }
			} else {
				{ a: c, b: a, c: b, none: "[UNRESOLVED]" }
			}
		_ => { a: "", b: "", c: "", none: "[UNRESOLVED]" }
	}

validate_jev_answers = |tokens, presented, answers|
	if Dict.len(answers) != List.len(tokens) {
		Err(WrongJevAnswerCount(List.len(tokens), Dict.len(answers)))
	} else {
		validate_jev_rows(tokens, presented, answers, [])
	}

validate_jev_rows = |tokens, presented, answers, found|
	match (tokens, presented) {
		([], []) => Ok(found)
		([token, .. as rest_tokens], [item, .. as rest_presented]) => {
			answer = Dict.get(answers, item.question_key) ? |_| MissingJevAnswer(item.question_key)
			if answer.type != "choice" {
				Err(WrongJevAnswerType(item.question_key, answer.type))
			} else if answer.choice != "a" and answer.choice != "b" and answer.choice != "c" and answer.choice != "none" {
				Err(UnknownJevChoice(item.question_key, answer.choice))
			} else if Dict.len(answer.probabilities) != 4 {
				Err(IncompleteProbabilityDistribution(item.question_key))
			} else {
				pa = Dict.get(answer.probabilities, "a") ? |_| MissingProbability(item.question_key, "a")
				pb = Dict.get(answer.probabilities, "b") ? |_| MissingProbability(item.question_key, "b")
				pc = Dict.get(answer.probabilities, "c") ? |_| MissingProbability(item.question_key, "c")
				pn = Dict.get(answer.probabilities, "none") ? |_| MissingProbability(item.question_key, "none")
				_ = validate_probability(item.question_key, "a", pa)?
				_ = validate_probability(item.question_key, "b", pb)?
				_ = validate_probability(item.question_key, "c", pc)?
				_ = validate_probability(item.question_key, "none", pn)?
				_ = validate_probability(item.question_key, "confidence", answer.confidence)?
				_ = validate_probability_sum(item.question_key, pa + pb + pc + pn)?
				selected_probability = probability_for_label(answer.choice, pa, pb, pc, pn)
				_ = validate_selected_probability(item.question_key, selected_probability, [pa, pb, pc, pn])?
				selected = selected_value(answer.choice, item.labels)
				margin = winner_margin([pa, pb, pc, pn])
				audit : TokenAudit
				audit = {
					candidates: item.candidates,
					confidence: answer.confidence,
					form: token.form,
					id: token.id,
					line: token.line,
					presented: item.labels,
					probabilities: { a: pa, b: pb, c: pc, none: pn },
					selected_label: answer.choice,
					selected_value: selected,
					winner_runner_up_margin: margin,
				}
				validate_jev_rows(rest_tokens, rest_presented, answers, List.append(found, audit))
			}
		}
		_ => Err(InternalJevLengthMismatch)
	}

selected_value = |label, labels|
	if label == "a" labels.a else if label == "b" labels.b else if label == "c" labels.c else labels.none

validate_probability = |question, label, probability|
	if probability < 0 or probability > 1 Err(ProbabilityOutOfRange(question, label)) else Ok({})

validate_probability_sum = |question, total|
	if total < 0.999 or total > 1.001 Err(ProbabilitySumOutOfRange(question)) else Ok({})

probability_for_label = |label, pa, pb, pc, pn|
	if label == "a" pa else if label == "b" pb else if label == "c" pc else pn

validate_selected_probability = |question, selected, probabilities|
	if List.any(probabilities, |probability| probability > selected) Err(SelectedChoiceNotWinner(question)) else Ok({})

winner_margin = |values| {
	ranked = top_two(values, 0, 0)
	ranked.first - ranked.second
}

top_two = |values, first, second|
	match values {
		[] => { first, second }
		[value, .. as rest] =>
			if value >= first {
				top_two(rest, value, first)
			} else if value > second {
				top_two(rest, first, value)
			} else {
				top_two(rest, first, second)
			}
	}

render_audits = |audits| {
	result = render_audit_shards(audits, 0, "")
	"${result.rendered}\n"
}

render_audit_shards = |audits, previous_line, rendered|
	match audits {
		[] => { previous_line, rendered }
		[audit, .. as rest] => {
			next = render_token_audits(audit.tokens, previous_line, rendered)
			render_audit_shards(rest, next.previous_line, next.rendered)
		}
	}

render_token_audits = |tokens, previous_line, rendered|
	match tokens {
		[] => { previous_line, rendered }
		[token, .. as rest] => {
			spacing = line_spacing(previous_line, token.line)
			prefix = if rendered == "" "" else "\n"
			next = "${rendered}${prefix}${spacing}${token.form} <=> ${token.selected_value}"
			render_token_audits(rest, token.line, next)
		}
	}

line_spacing = |previous, current|
	if previous == 0 or current <= previous "" else blank_lines(current - previous, "")

blank_lines = |count, found|
	if count == 0 found else blank_lines(count - 1, "${found}\n")

read_config! = || {
	raw = Path.read_utf8!(Path.utf8("${experiment_dir}/config.json"))?
	config : Config
	config = Json.parse(raw)?
	Ok(config)
}

validate_config = |config| {
	generation = config.candidates.generation
	if config.experiment_name != "deepseek-v4-flash-0731-jev-gloss" {
		Err(InvalidExperimentName)
	} else if config.experiment_version != 3 {
		Err(InvalidExperimentVersion)
	} else if config.execution.candidate_count != 3 or config.execution.tokens_per_shard != 50 {
		Err(InvalidExecutionPins)
	} else if config.candidates.provider.name != "ppq" or config.candidates.provider.base_url != "https://api.ppq.ai/v1" or config.candidates.provider.api_key_env != "PPQ_API_KEY" {
		Err(InvalidCandidateProviderPins)
	} else if config.candidates.model.id != "deepseek/deepseek-v4-flash-0731" {
		Err(InvalidCandidateModelPin)
	} else if generation.profile != "full-sampling" or generation.temperature != 1 or generation.top_p != 1 or generation.top_k != 0 or generation.seed != 1 or generation.max_tokens != 4096 or generation.frequency_penalty != 0 or generation.presence_penalty != 0 {
		Err(InvalidSamplingPins)
	} else if generation.reasoning.enabled or !generation.reasoning.exclude or generation.include_reasoning {
		Err(InvalidReasoningPins)
	} else if generation.provider.only != ["sail-research"] or !generation.provider.require_parameters or generation.provider.allow_fallbacks {
		Err(InvalidSailResearchPins)
	} else if config.candidates.validation.max_attempts != 2 or config.selector.validation.max_attempts != 2 {
		Err(InvalidValidationPins)
	} else if config.selector.provider.name != "typesafe" or config.selector.provider.endpoint != "https://api.typesafe.ai/v1/systemone" or config.selector.provider.api_key_env != "TYPESAFE_API_KEY" {
		Err(InvalidSelectorProviderPins)
	} else if config.selector.transport.max_retries != 2 or config.selector.transport.backoff_initial_ms != 500 or config.selector.transport.backoff_max_ms != 5000 or config.selector.transport.max_retry_after_ms != 60000 {
		Err(InvalidSelectorTransportPins)
	} else if config.selector.model.id != "jev-1.13.0" or config.selector.input_cost_per_million_tokens_usd != 0.042 {
		Err(InvalidSelectorModelPins)
	} else {
		Ok({})
	}
}

discover_inputs! = || {
	root = "${experiment_dir}/inputs"
	entries = Path.list!(Path.utf8(root))?
	paths = List.sort_with(discover_input_files!(entries, [])?, compare_str)
	if List.is_empty(paths) Err(NoInputs) else Ok(paths)
}

discover_input_files! = |entries, found|
	match entries {
		[] => Ok(found)
		[entry, .. as rest] => {
			path = Path.display(entry)
			next = match Path.type!(entry)? {
				IsFile => if Str.ends_with(path, ".txt") List.append(found, path) else found
				_ => found
			}
			discover_input_files!(rest, next)
		}
	}

validate_input_set = |paths| validate_input_names(paths, expected_inputs)

validate_input_names = |paths, names|
	match (paths, names) {
		([], []) => Ok({})
		([path, .. as rest_paths], [name, .. as rest_names]) => {
			if work_name(path) != name Err(UnexpectedInputSet) else validate_input_names(rest_paths, rest_names)
		}
		_ => Err(UnexpectedInputSet)
	}

validate_source = |source, path|
	if Str.trim(source) == "" {
		Err(EmptyInput(path))
	} else if Str.contains(source, "\r") or Str.contains(source, "\t") {
		Err(UnsupportedInputWhitespace(path))
	} else if List.is_empty(tokenize_source(source)) {
		Err(NoTokens(path))
	} else {
		Ok({})
	}

read_api_keys! = |config| {
	env = Path.read_utf8!(Path.utf8(".env"))?
	ppq = env_value(env, config.candidates.provider.api_key_env)?
	typesafe = env_value(env, config.selector.provider.api_key_env)?
	Ok({ ppq, typesafe })
}

read_typesafe_api_key! = |config| {
	env = Path.read_utf8!(Path.utf8(".env"))?
	env_value(env, config.selector.provider.api_key_env)
}

env_value = |env, variable| {
	prefix = "${variable}="
	match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) {
		[line, ..] => {
			value = Str.trim(Str.replace_first(line, prefix, ""))
			if value == "" Err(EmptyApiKey(variable)) else Ok(value)
		}
		[] => Err(MissingApiKey(variable))
	}
}

read_candidate_checkpoint! = |path| {
	raw = Path.read_utf8!(Path.utf8(path))?
	value : CandidateCheckpoint
	value = Json.parse(raw)?
	Ok(value)
}

validate_checkpoint_request! = |checkpoint, source, tokens, run_dir, config| {
	path = "${run_dir}/${checkpoint.call.client_request_id}.request.json"
	raw = Path.read_utf8!(Path.utf8(path))?
	request : { messages : List({ content : Str, role : Str }), model : Str, provider : { allow_fallbacks : Bool, only : List(Str), require_parameters : Bool } }
	request = Json.parse(raw)?
	table = Str.join_with(List.map(tokens, |token| "${token.id} | ${U64.to_str(token.line)} | ${token.form}"), "\n")
	expected = "COMPLETE SOURCE PASSAGE:\n${source}\nTARGET TOKENS (immutable ID | source line | exact form):\n${table}"
	if request.model != config.candidates.model.id or request.provider != config.candidates.generation.provider or !request_messages_contain(request.messages, expected) {
		Err(CandidateCheckpointSourceMismatch(path))
	} else {
		Ok({})
	}
}

request_messages_contain = |messages, expected|
	match messages {
		[] => Bool.False
		[message, .. as rest] => if message.role == "user" and Str.contains(message.content, expected) Bool.True else request_messages_contain(rest, expected)
	}

read_shard_audit! = |path| {
	raw = Path.read_utf8!(Path.utf8(path))?
	value : ShardAudit
	value = Json.parse(raw)?
	Ok(value)
}

validate_candidate_checkpoint = |checkpoint, tokens, work, shard_index, shard_count, config|
	if checkpoint.work != work or checkpoint.shard_index != shard_index or checkpoint.shard_count != shard_count or checkpoint.experiment_version != config.experiment_version {
		Err(CandidateCheckpointMismatch(work, shard_index))
	} else if checkpoint.call.requested_model != config.candidates.model.id or checkpoint.call.resolved_model != config.candidates.model.id or checkpoint.call.requested_provider != "ppq/sail-research" or checkpoint.call.resolved_provider != "Sail Research" {
		Err(CandidateCheckpointCallMismatch(work, shard_index))
	} else {
		_ = validate_candidates(tokens, checkpoint.candidates)?
		Ok({})
	}

validate_shard_audit = |audit, tokens, work, shard_index, shard_count, config|
	if audit.work != work or audit.shard_index != shard_index or audit.shard_count != shard_count or audit.experiment_version != config.experiment_version {
		Err(ShardAuditMismatch(work, shard_index))
	} else if audit.candidate_call.requested_model != config.candidates.model.id or audit.candidate_call.resolved_model != config.candidates.model.id or audit.candidate_call.requested_provider != "ppq/sail-research" or audit.candidate_call.resolved_provider != "Sail Research" {
		Err(ShardCandidateCallMismatch(work, shard_index))
	} else if audit.jev_call.requested_model != config.selector.model.id or audit.jev_call.resolved_model != config.selector.model.id or audit.jev_call.requested_provider != config.selector.provider.name or audit.jev_call.resolved_provider != config.selector.provider.name {
		Err(ShardJevCallMismatch(work, shard_index))
	} else {
		validate_audit_tokens(tokens, audit.tokens)
	}

validate_audit_tokens = |tokens, audits|
	match (tokens, audits) {
		([], []) => Ok({})
		([token, .. as rest_tokens], [audit, .. as rest_audits]) => {
			question = "token_${token.id}"
			if token.id != audit.id or token.form != audit.form or token.line != audit.line {
				Err(AuditTokenMismatch(token.id))
			} else {
				candidates = validate_three_candidates(token.id, audit.candidates)?
				expected_presented = rotate_candidates(candidates, rotation_for_token_id(token.id))
				if audit.presented != expected_presented {
					Err(AuditPresentationMismatch(token.id))
				} else if audit.selected_label != "a" and audit.selected_label != "b" and audit.selected_label != "c" and audit.selected_label != "none" {
					Err(AuditSelectionMismatch(token.id))
				} else {
					pa = audit.probabilities.a
					pb = audit.probabilities.b
					pc = audit.probabilities.c
					pn = audit.probabilities.none
					_ = validate_probability(question, "a", pa)?
					_ = validate_probability(question, "b", pb)?
					_ = validate_probability(question, "c", pc)?
					_ = validate_probability(question, "none", pn)?
					_ = validate_probability(question, "confidence", audit.confidence)?
					_ = validate_probability_sum(question, pa + pb + pc + pn)?
					selected_probability = probability_for_label(audit.selected_label, pa, pb, pc, pn)
					_ = validate_selected_probability(question, selected_probability, [pa, pb, pc, pn])?
					expected_value = selected_value(audit.selected_label, expected_presented)
					expected_margin = winner_margin([pa, pb, pc, pn])
					if audit.selected_value != expected_value or audit.winner_runner_up_margin != expected_margin {
						Err(AuditSelectionMismatch(token.id))
					} else {
						validate_audit_tokens(rest_tokens, rest_audits)
					}
				}
			}
		}
		_ => Err(AuditTokenCountMismatch)
	}

fake_candidates = |tokens|
	List.map(tokens, |token| {
		candidates: ["fake-a-${token.id}", "fake-b-${token.id}", "fake-c-${token.id}"],
		id: token.id,
	})

tokenize_source = |source| tokenize_lines(Str.split_on(source, "\n"), 1, 1, []).tokens

tokenize_lines = |lines, line_number, next_id, found|
	match lines {
		[] => { next_id, tokens: found }
		[line, .. as rest] => {
			words = List.keep_if(Str.split_on(line, " "), |word| word != "")
			line_result = tokenize_words(words, line_number, next_id, found)
			tokenize_lines(rest, line_number + 1, line_result.next_id, line_result.tokens)
		}
	}

tokenize_words = |words, line_number, next_id, found|
	match words {
		[] => { next_id, tokens: found }
		[word, .. as rest] => {
			token : Token
			token = { form: word, id: U64.to_str(next_id), line: line_number }
			tokenize_words(rest, line_number, next_id + 1, List.append(found, token))
		}
	}

shard_tokens = |tokens, limit|
	match tokens {
		[] => []
		_ => {
			shard = take_tokens(tokens, limit, [])
			List.concat([shard.taken], shard_tokens(shard.remaining, limit))
		}
	}

take_tokens = |remaining, count, taken|
	if count == 0 {
		{ remaining, taken }
	} else {
		match remaining {
			[] => { remaining: [], taken }
			[token, .. as rest] => take_tokens(rest, count - 1, List.append(taken, token))
		}
	}

decode_json_bytes = |bytes| {
	text = Str.from_utf8(bytes) ? |_| InvalidUtf8Response
	Json.parse(text)
}

response_request_id = |headers|
	match headers {
		[] => ""
		[header, .. as rest] => {
			{name, value} = header
			if Str.caseless_ascii_equals(name, "x-request-id") or Str.caseless_ascii_equals(name, "request-id") {
				value
			} else {
				response_request_id(rest)
			}
		}
	}

candidate_error_text = |problem|
	match problem {
		DuplicateCandidate(id) => "token ${id} candidates were not distinct after trim and ASCII-case normalization"
		EmptyCandidate(id) => "token ${id} had an empty candidate"
		ReservedCandidate(id) => "token ${id} used the reserved [UNRESOLVED] value"
		IncompleteFinish(reason) => "finish reason was ${reason}, not stop"
		InternalCandidateLengthMismatch => "candidate rows and target tokens diverged"
		InvalidCandidateJson => "assistant content was not the required candidate JSON"
		UnsafeCandidate(id) => "token ${id} candidate contained whitespace, a line break, or the <=> delimiter"
		WrongCandidateCount(id, actual) => "token ${id} had ${U64.to_str(actual)} candidates instead of 3"
		WrongCandidateId(expected, actual) => "expected candidate token ID ${expected} but received ${actual}"
		WrongCandidateModel(expected, actual) => "expected DeepSeek response model ${expected} but received ${actual}"
		WrongCandidateProvider(expected, actual) => "expected DeepSeek response provider ${expected} but received ${actual}"
		WrongCandidateTokenCount(expected, actual) => "expected ${U64.to_str(expected)} candidate rows but received ${U64.to_str(actual)}"
	}

jev_error_text = |problem|
	match problem {
		IncompleteProbabilityDistribution(question) => "${question} did not return exactly a/b/c/none probabilities"
		InternalJevLengthMismatch => "Jev question and token coverage diverged"
		MissingJevAnswer(question) => "missing Jev answer ${question}"
		MissingProbability(question, label) => "${question} omitted probability ${label}"
		ProbabilityOutOfRange(question, label) => "${question} returned ${label} outside [0,1]"
		ProbabilitySumOutOfRange(question) => "${question} probabilities did not sum to 1"
		SelectedChoiceNotWinner(question) => "${question} selected a label that was not a probability winner"
		UnknownJevChoice(question, label) => "${question} selected unsupported label ${label}"
		WrongJevAnswerCount(expected, actual) => "expected ${U64.to_str(expected)} Jev answers but received ${U64.to_str(actual)}"
		WrongJevAnswerType(question, actual) => "${question} returned type ${actual}, not choice"
		WrongJevModel(expected, actual) => "expected response model ${expected} but received ${actual}"
	}

empty_deep_response : DeepResponse
empty_deep_response = {
	choices: [],
	id: "",
	model: "",
	provider: "",
	usage: {
		completion_tokens: 0,
		completion_tokens_details: { reasoning_tokens: 0 },
		cost: 0,
		prompt_tokens: 0,
		total_tokens: 0,
	},
}

empty_jev_response : JevResponse
empty_jev_response = {
	answers: Dict.empty(),
	model: "",
	usage: { input_tokens: 0, output_tokens: 0 },
}

write_new_utf8! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? Err(RefuseOverwrite(path)) else Path.write_utf8!(roc_path, content)
}

write_new_bytes! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? Err(RefuseOverwrite(path)) else Path.write_bytes!(roc_path, content)
}

write_atomic_or_verify! = |content, path| {
	if Path.exists!(Path.utf8(path))? {
		existing = Path.read_utf8!(Path.utf8(path))?
		if existing == content Ok({}) else Err(ExistingAggregateMismatch(path))
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
		_ = write_new_utf8!(content, temporary)?
		Path.rename!(Path.utf8(temporary), Path.utf8(path))
	}
}

run_id_for = |timestamp, version| {
	compact = Str.replace_each(Str.replace_each(Utc.to_iso_8601(timestamp), "-", ""), ":", "")
	"${compact}-${U128.to_str(Utc.to_nanos_since_epoch(timestamp))}-v${U64.to_str(version)}"
}

work_name = |path| {
	prefix = "${experiment_dir}/inputs/"
	relative = Str.replace_first(path, prefix, "")
	Str.replace_last(relative, ".txt", "")
}

compare_str = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if x < y Before else if x > y After else compare_bytes(xs, ys)
	}
