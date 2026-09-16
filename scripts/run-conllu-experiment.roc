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
	frequency_penalty : Try(Dec, [Missing]),
	include_reasoning : Bool,
	max_tokens : U64,
	presence_penalty : Try(Dec, [Missing]),
	profile : Str,
	provider : { allow_fallbacks : Bool, only : List(Str), require_parameters : Bool },
	reasoning : { enabled : Bool, exclude : Bool },
	reasoning_effort : Try(Str, [Missing]),
	seed : Try(U64, [Missing]),
	temperature : Try(Dec, [Missing]),
	top_k : Try(U64, [Missing]),
	top_p : Try(Dec, [Missing]),
}

OgaWork : {
	citations : List(Str),
	cts_urn : Str,
	name : Str,
	sentence_count : U64,
	source : Str,
	source_file : Str,
	source_sha256 : Str,
}

OgaSettings : {
	contact : Str,
	date_modified : Str,
	editor : Str,
	gloss_type : Str,
	project : Str,
	root : Str,
	source_doi : Str,
	source_version : Str,
	works : List(OgaWork),
}

Config : {
	compact_generation : Try(Generation, [Missing]),
	execution : { max_overt_tokens_per_shard : U64, min_overt_tokens_per_shard : U64, shard_delay_ms : U64 },
	experiment_name : Str,
	experiment_version : U64,
	generation : Generation,
	model : { id : Str },
	oga : Try(OgaSettings, [Missing]),
	provider : { api_key_env : Str, base_url : Str, name : Str },
	validation : { max_attempts : U64 },
}

OgaRow : { artificial : Bool, form : Str, id : U64, misc : Str, prefix : Str }

OgaSentence : {
	citation : Str,
	rows : List(OgaRow),
	source_sentence_id : Str,
}

SourceWord : { form : Str, reference : Str, source_id : Str, speaker : Str }

SourceSentence : {
	document_id : Str,
	overt_words : List(SourceWord),
	source_sentence_id : Str,
	xml : Str,
}

ModelToken : {
	deprel : Str,
	deps : Str,
	feats : Str,
	gloss : Str,
	head : U64,
	id : U64,
	lemma : Str,
	upos : Str,
	xpos : Str,
}

ModelSentence : {
	literal_translation : Str,
	prose_translation : Str,
	source_sentence_id : Str,
	tokens : List(ModelToken),
}

ModelPayload : { sentences : List(ModelSentence) }

CompactModelToken : { gloss : Str, id : U64 }

CompactModelSentence : {
	literal_translation : Str,
	prose_translation : Str,
	source_sentence_id : Str,
	tokens : List(CompactModelToken),
}

CompactModelPayload : { sentences : List(CompactModelSentence) }

DecodedResponse : {
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

main! = |args| {
	displayed = List.map(args, OsStr.display)

	match List.drop_first(displayed, 1) {
		[experiment_name] => run_named_experiment!(experiment_name)
		[experiment_name, "--check"] => check_named_experiment!(experiment_name)
		[experiment_name, "--check-compact"] => check_compact_named_experiment!(experiment_name)
		[experiment_name, "--smoke"] => smoke_named_experiment!(experiment_name)
		[experiment_name, "--smoke-compact"] => smoke_compact_named_experiment!(experiment_name)
		[experiment_name, "--oga-check"] => check_oga_named_experiment!(experiment_name)
		[experiment_name, "--oga-smoke"] => smoke_oga_named_experiment!(experiment_name)
		[experiment_name, "--oga"] => run_oga_named_experiment!(experiment_name)
		[experiment_name, "--resume", run_id] => resume_named_experiment!(experiment_name, run_id)
		_ => {
			_ = Stderr.line!("usage: run-conllu-experiment <experiment-name> [--check | --check-compact | --smoke | --smoke-compact | --oga-check | --oga-smoke | --oga | --resume <run-id>]")?
			Err(Exit(2))
		}
	}
}

check_named_experiment! = |experiment_name| {
	experiment_dir = experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	inputs = discover_inputs!(experiment_dir)?
	_ = build_requests!(inputs, config, experiment_dir)?
	_ = Stdout.line!("checked ${experiment_name} experiment: ${U64.to_str(List.len(inputs))} input(s)")?
	Ok({})
}

check_compact_named_experiment! = |experiment_name| {
	experiment_dir = experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	inputs = discover_inputs!(experiment_dir)?
	input_path = match inputs {
		[path, ..] => Ok(path)
		[] => Err(NoInputs)
	}?
	source = Path.read_utf8!(Path.utf8(input_path))?
	sentences = parse_glaux_xml(source)?
	shards = shard_sentences(sentences, config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard)?
	first_shard = match shards {
		[shard, ..] => Ok(shard)
		[] => Err(NoSourceSentences)
	}?
	_ = compact_request_body(config, first_shard, "")?
	_ = Stdout.line!("checked compact ${experiment_name} smoke request")?
	Ok({})
}

smoke_named_experiment! = |experiment_name| {
	experiment_dir = experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	api_key = read_api_key!(config.provider.api_key_env)?
	inputs = discover_inputs!(experiment_dir)?
	input_path = match inputs {
		[path, ..] => Ok(path)
		[] => Err(NoInputs)
	}?
	source = Path.read_utf8!(Path.utf8(input_path))?
	sentences = parse_glaux_xml(source)?
	shards = shard_sentences(sentences, config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard)?
	first_shard = match shards {
		[shard, ..] => Ok(shard)
		[] => Err(NoSourceSentences)
	}?
	started = Utc.now!()
	run_id = "smoke-${run_id_for(started, config.experiment_version)}"
	run_dir = "${experiment_dir}/responses/${run_id}"
	work = work_name(experiment_dir, input_path)
	shard_count = List.len(shards)
	output_dir = "${experiment_dir}/outputs/experiment_${U64.to_str(config.experiment_version)}/smoke/${run_id}"
	output_path = "${output_dir}/${work}.shard-1-of-${U64.to_str(shard_count)}.conllu"

	if Path.exists!(Path.utf8(run_dir))? {
		Err(RunAlreadyExists(run_dir))
	} else {
		_ = Path.create_all!(Path.utf8(run_dir))?
		_ = Path.create_all!(Path.utf8(output_dir))?
		_ = Path.write_utf8!(Path.utf8("${run_dir}/run-id"), "${run_id}\n")?
		generated = run_attempt!(work, first_shard, config, api_key, run_id, run_dir, 1, shard_count, 1, "")?
		_ = write_output!(generated.conllu, output_path)?
		_ = Stdout.line!("completed smoke run ${run_id}\t${output_path}")?
		Ok({})
	}
}

smoke_compact_named_experiment! = |experiment_name| {
	experiment_dir = experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	api_key = read_api_key!(config.provider.api_key_env)?
	inputs = discover_inputs!(experiment_dir)?
	input_path = match inputs {
		[path, ..] => Ok(path)
		[] => Err(NoInputs)
	}?
	source = Path.read_utf8!(Path.utf8(input_path))?
	sentences = parse_glaux_xml(source)?
	shards = shard_sentences(sentences, config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard)?
	first_shard = match shards {
		[shard, ..] => Ok(shard)
		[] => Err(NoSourceSentences)
	}?
	started = Utc.now!()
	run_id = "smoke-compact-${run_id_for(started, config.experiment_version)}"
	run_dir = "${experiment_dir}/responses/${run_id}"
	work = work_name(experiment_dir, input_path)
	shard_count = List.len(shards)
	output_dir = "${experiment_dir}/outputs/experiment_${U64.to_str(config.experiment_version)}/smoke-compact/${run_id}"
	output_path = "${output_dir}/${work}.shard-1-of-${U64.to_str(shard_count)}.semantics.txt"

	if Path.exists!(Path.utf8(run_dir))? {
		Err(RunAlreadyExists(run_dir))
	} else {
		_ = Path.create_all!(Path.utf8(run_dir))?
		_ = Path.create_all!(Path.utf8(output_dir))?
		_ = Path.write_utf8!(Path.utf8("${run_dir}/run-id"), "${run_id}\n")?
		generated = run_compact_attempt!(work, first_shard, config, api_key, run_id, run_dir, 1, shard_count, 1, "")?
		_ = write_output!(generated.output, output_path)?
		_ = Stdout.line!("completed compact smoke run ${run_id}\t${output_path}")?
		Ok({})
	}
}

run_named_experiment! = |experiment_name| {
	experiment_dir = experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	api_key = read_api_key!(config.provider.api_key_env)?
	inputs = discover_inputs!(experiment_dir)?
	started = Utc.now!()
	run_id = run_id_for(started, config.experiment_version)
	run_dir = "${experiment_dir}/responses/${run_id}"

	if Path.exists!(Path.utf8(run_dir))? {
		Err(RunAlreadyExists(run_dir))
	} else {
		_ = Path.create_all!(Path.utf8(run_dir))?
		_ = Path.create_all!(Path.utf8("${experiment_dir}/outputs"))?
		_ = Path.write_utf8!(Path.utf8("${run_dir}/run-id"), "${run_id}\n")?
		_ = run_inputs!(inputs, config, api_key, run_id, run_dir, experiment_dir, 0, Bool.False)?
		_ = Stdout.line!("completed run ${run_id}")?
		Ok({})
	}
}

resume_named_experiment! = |experiment_name, run_id| {
	experiment_dir = experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	run_dir = "${experiment_dir}/responses/${run_id}"
	expected_suffix = "-v${U64.to_str(config.experiment_version)}"

	if !valid_path_segment(run_id) {
		Err(InvalidRunId(run_id))
	} else if Str.starts_with(run_id, "smoke-") {
		Err(SmokeRunNotResumable(run_id))
	} else if !Path.exists!(Path.utf8(run_dir))? {
		Err(RunNotFound(run_dir))
	} else if !Str.ends_with(run_id, expected_suffix) {
		Err(RunVersionMismatch(run_id, config.experiment_version))
	} else {
		api_key = read_api_key!(config.provider.api_key_env)?
		inputs = discover_inputs!(experiment_dir)?
		_ = run_inputs!(inputs, config, api_key, run_id, run_dir, experiment_dir, 0, Bool.False)?
		_ = Stdout.line!("completed resumed run ${run_id}")?
		Ok({})
	}
}

experiment_dir_for = |experiment_name|
	if !valid_path_segment(experiment_name) {
		Err(InvalidExperimentName(experiment_name))
	} else {
		Ok("experiments/conllu/${experiment_name}")
	}

oga_experiment_dir_for = |experiment_name|
	if !valid_path_segment(experiment_name) {
		Err(InvalidExperimentName(experiment_name))
	} else {
		Ok("experiments/oga-conllu/${experiment_name}")
	}

valid_path_segment = |segment|
	segment != "" and !Str.contains(segment, "/") and !Str.contains(segment, "\\") and !Str.contains(segment, "..")

read_config! = |experiment_dir| {
	raw = Path.read_utf8!(Path.utf8("${experiment_dir}/config.json"))?
	config : Config
	config = Json.parse(raw)?
	Ok(config)
}

validate_config = |config, experiment_name|
	if config.experiment_name != experiment_name {
		Err(ExperimentNameMismatch(experiment_name, config.experiment_name))
	} else if config.validation.max_attempts == 0 {
		Err(ValidationAttemptsMustBePositive)
	} else if config.execution.min_overt_tokens_per_shard == 0 or config.execution.min_overt_tokens_per_shard > config.execution.max_overt_tokens_per_shard or config.execution.max_overt_tokens_per_shard > 50 {
		Err(InvalidShardTokenRange(config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard))
	} else {
		Ok({})
	}

read_api_key! = |variable| {
	env = Path.read_utf8!(Path.utf8(".env"))?
	prefix = "${variable}="

	match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) {
		[line, ..] => {
			key = Str.replace_first(line, prefix, "")
			if key == "" Err(EmptyApiKey) else Ok(key)
		}
		[] => Err(MissingApiKey)
	}
}

discover_inputs! = |experiment_dir| {
	input_dir = "${experiment_dir}/inputs"
	entries = Path.list!(Path.utf8(input_dir))?
	paths = List.sort_with(discover_input_files!(entries, [])?, compare_str)

	if List.is_empty(paths) Err(NoInputs) else Ok(paths)
}

discover_input_files! = |entries, found|
	match entries {
		[] => Ok(found)
		[entry, .. as rest] => {
			path = Path.display(entry)
			next = match Path.type!(entry)? {
				IsFile => if supported_input_path(path) List.append(found, path) else found
				IsDir => found
				IsSymLink => found
				IsOther => found
			}
			discover_input_files!(rest, next)
		}
	}

build_requests! = |inputs, config, experiment_dir|
	match inputs {
		[] => Ok({})
		[path, .. as rest] => {
			source = Path.read_utf8!(Path.utf8(path))?
			work = work_name(experiment_dir, path)
			sentences = parse_glaux_xml(source)?
			shards = shard_sentences(sentences, config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard)?
			_ = build_shard_requests!(shards, config, work)?
			build_requests!(rest, config, experiment_dir)
		}
	}

build_shard_requests! = |shards, config, work|
	match shards {
		[] => Ok({})
		[sentences, .. as rest] => {
			_ = request_body(config, work, sentences, "")?
			build_shard_requests!(rest, config, work)
		}
	}

run_inputs! = |inputs, config, api_key, run_id, run_dir, experiment_dir, failed, paid_before|
	match inputs {
		[] => if failed == 0 Ok({}) else Err(RunInputsFailed(failed))
		[path, .. as rest] => {
			work = work_name(experiment_dir, path)
			match run_input!(path, config, api_key, run_id, run_dir, experiment_dir, paid_before) {
				Ok(_) => run_inputs!(rest, config, api_key, run_id, run_dir, experiment_dir, failed, Bool.True)
				Err(problem) => {
					_ = Stderr.line!("failed ${work}: ${Str.inspect(problem)}")?
					run_inputs!(rest, config, api_key, run_id, run_dir, experiment_dir, failed + 1, Bool.True)
				}
			}
		}
	}

run_input! = |input_path, config, api_key, run_id, run_dir, experiment_dir, paid_before| {
	work = work_name(experiment_dir, input_path)
	source = Path.read_utf8!(Path.utf8(input_path))?
	sentences = parse_glaux_xml(source)?
	shards = shard_sentences(sentences, config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard)?
	shard_count = List.len(shards)
	output_dir = "${experiment_dir}/outputs/experiment_${U64.to_str(config.experiment_version)}"
	output_path = "${output_dir}/${work}.conllu"
	marker_path = "${run_dir}/${work}.complete"
	_ = Path.create_all!(Path.utf8(output_dir))?
	rendered = run_shards!(shards, work, config, api_key, run_id, run_dir, 1, shard_count, paid_before, "")?
	_ = write_output!(rendered, output_path)?
	_ = write_completion_marker!("${output_path}\n", marker_path)?
	_ = Stdout.line!("completed input ${work}\t${output_path}")?
	Ok({})
}

run_shards! = |shards, work, config, api_key, run_id, run_dir, shard_index, shard_count, paid_before, rendered|
	match shards {
		[] => Ok(rendered)
		[sentences, .. as rest] => {
			shard_output_path = "${run_dir}/${work}.shard-${U64.to_str(shard_index)}-of-${U64.to_str(shard_count)}.output.conllu"
			checkpoint_base_request_path = "${shard_output_path}.base-request.json"
			checkpoint_accepted_request_path = "${shard_output_path}.accepted-request.json"
			expected_request = request_body(config, work, sentences, "")?
			output_exists = Path.exists!(Path.utf8(shard_output_path))?
			base_request_exists = Path.exists!(Path.utf8(checkpoint_base_request_path))?
			accepted_request_exists = Path.exists!(Path.utf8(checkpoint_accepted_request_path))?
			checkpointed = (if output_exists and base_request_exists and accepted_request_exists {
				stored_request = Path.read_utf8!(Path.utf8(checkpoint_base_request_path))?
				if stored_request == expected_request Ok(Bool.True) else Err(StaleShardCheckpoint(shard_output_path))
			} else if output_exists or base_request_exists or accepted_request_exists {
				Err(IncompleteShardCheckpoint(shard_output_path))
			} else {
				Ok(Bool.False)
			})?
			shard_output = if checkpointed {
				_ = Stdout.line!("skipped completed shard ${work} ${U64.to_str(shard_index)}/${U64.to_str(shard_count)}")?
				Path.read_utf8!(Path.utf8(shard_output_path))?
			} else {
				_ = if paid_before and config.execution.shard_delay_ms > 0 {
					Sleep.millis!(config.execution.shard_delay_ms)
				} else {}
				generated = run_attempt!(
					work,
					sentences,
					config,
					api_key,
					run_id,
					run_dir,
					shard_index,
					shard_count,
					1,
					"",
				)?
				_ = write_new_utf8!(expected_request, checkpoint_base_request_path)?
				_ = write_new_utf8!(generated.request_body, checkpoint_accepted_request_path)?
				_ = write_checkpoint!(generated.conllu, shard_output_path)?
				generated.conllu
			}
			next_rendered = "${rendered}${shard_output}"
			run_shards!(
				rest,
				work,
				config,
				api_key,
				run_id,
				run_dir,
				shard_index + 1,
				shard_count,
				paid_before or !checkpointed,
				next_rendered,
			)
		}
	}

run_compact_attempt! = |work, sentences, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, feedback| {
	body = compact_request_body(config, sentences, feedback)?
	captured = send_transport_attempt!(
		work,
		config,
		api_key,
		run_id,
		run_dir,
		shard_index,
		shard_count,
		attempt,
		body,
		1,
	)?
	outcome = process_compact_completion!(work, sentences, run_id, shard_index, shard_count, attempt, body, captured)?

	match outcome {
		Accepted(output) => Ok({ output, request_body: body })
		Rejected(error_text) => {
			_ = Stdout.line!("rejected compact ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} attempt ${U64.to_str(attempt)}: ${error_text}")?
			if attempt < config.validation.max_attempts {
				_ = if config.execution.shard_delay_ms > 0 Sleep.millis!(config.execution.shard_delay_ms) else {}
				run_compact_attempt!(
					work,
					sentences,
					config,
					api_key,
					run_id,
					run_dir,
					shard_index,
					shard_count,
					attempt + 1,
					error_text,
				)
			} else {
				Err(ValidationAttemptsExhausted(work, shard_index, attempt, error_text))
			}
		}
	}
}

run_attempt! = |work, sentences, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, feedback| {
	body = request_body(config, work, sentences, feedback)?
	captured = send_transport_attempt!(
		work,
		config,
		api_key,
		run_id,
		run_dir,
		shard_index,
		shard_count,
		attempt,
		body,
		1,
	)?
	outcome = process_completion!(work, sentences, run_id, shard_index, shard_count, attempt, body, captured)?

	match outcome {
		Accepted(conllu) => Ok({ conllu, request_body: body })
		Rejected(error_text) => {
			_ = Stdout.line!("rejected ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} attempt ${U64.to_str(attempt)}: ${error_text}")?
			if attempt < config.validation.max_attempts {
				_ = if config.execution.shard_delay_ms > 0 Sleep.millis!(config.execution.shard_delay_ms) else {}
				run_attempt!(
					work,
					sentences,
					config,
					api_key,
					run_id,
					run_dir,
					shard_index,
					shard_count,
					attempt + 1,
					error_text,
				)
			} else {
				Err(ValidationAttemptsExhausted(work, shard_index, attempt, error_text))
			}
		}
	}
}

send_transport_attempt! = |work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body, transport_attempt| {
	requested_at = Utc.now!()
	timestamp = Utc.to_iso_8601(requested_at)
	nonce = U128.to_str(Utc.to_nanos_since_epoch(requested_at))
	request_id = "${work}-shard-${U64.to_str(shard_index)}-of-${U64.to_str(shard_count)}-v${U64.to_str(config.experiment_version)}-attempt-${U64.to_str(attempt)}-transport-${U64.to_str(transport_attempt)}-${nonce}"
	request_path = "${run_dir}/${request_id}.request.json"
	raw_response_path = "${run_dir}/${request_id}.raw.json"
	response_path = "${run_dir}/${request_id}.json"

	_ = write_new_utf8!(body, request_path)?

	request = Request.from_method(POST)
		.with_uri("${config.provider.base_url}/chat/completions")
		.with_timeout(TimeoutMilliseconds(300000))
		.add_header("Authorization", "Bearer ${api_key}")
		.add_header("Content-Type", "application/json")
		.with_body(Str.to_utf8(body))

	match Http.send!(request) {
		Err(_) => {
			received_at = Utc.now!()
			error_text = "HTTP transport failed before a response was captured"
			response = Response.from_status(0)
			_ = write_new_bytes!([], raw_response_path)?
			_ = write_attempt_record!(
				response_path,
				attempt,
				transport_attempt,
				shard_index,
				shard_count,
				body,
				empty_decoded_response,
				"",
				response,
				[],
				request_id,
				timestamp,
				requested_at,
				received_at,
				run_id,
				work,
				"transport-failed",
				error_text,
			)?
			if transport_attempt < max_transport_attempts {
				delay_ms = max_u64(backoff_ms(transport_base_delay_ms, transport_attempt), config.execution.shard_delay_ms)
				_ = Stdout.line!("retrying transport for ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} after ${U64.to_str(delay_ms)} ms: ${error_text}")?
				Sleep.millis!(delay_ms)
				send_transport_attempt!(work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body, transport_attempt + 1)
			} else {
				Err(TransportAttemptsExhausted(work, shard_index, transport_attempt, error_text))
			}
		}

		Ok(response) => {
			received_at = Utc.now!()
			response_body = Response.body(response)
			status = Response.status(response)
			headers = Response.headers(response)
			_ = write_new_bytes!(response_body, raw_response_path)?

			if status < 200 or status >= 300 {
				error_text = "provider returned HTTP ${U16.to_str(status)}"
				_ = write_attempt_record!(
					response_path,
					attempt,
					transport_attempt,
					shard_index,
					shard_count,
					body,
					empty_decoded_response,
					"",
					response,
					response_body,
					request_id,
					timestamp,
					requested_at,
					received_at,
					run_id,
					work,
					"transport-rejected",
					error_text,
				)?
				if is_transient_status(status) and transport_attempt < max_transport_attempts {
					fallback = max_u64(backoff_ms(transport_base_delay_ms, transport_attempt), config.execution.shard_delay_ms)
					delay_ms = max_u64(retry_after_ms(headers, fallback), config.execution.shard_delay_ms)
					_ = Stdout.line!("retrying transport for ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} after ${U64.to_str(delay_ms)} ms: ${error_text}")?
					Sleep.millis!(delay_ms)
					send_transport_attempt!(work, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body, transport_attempt + 1)
				} else if is_transient_status(status) {
					Err(TransportAttemptsExhausted(work, shard_index, transport_attempt, error_text))
				} else {
					Err(ProviderHttpFailure(status))
				}
			} else {
				Ok({
					received_at,
					request_id,
					requested_at,
					response,
					response_body,
					response_path,
					timestamp,
					transport_attempt,
				})
			}
		}
	}
}

process_compact_completion! = |work, sentences, run_id, shard_index, shard_count, attempt, body, captured| {
	received_at = captured.received_at
	request_id = captured.request_id
	requested_at = captured.requested_at
	response = captured.response
	response_body = captured.response_body
	response_path = captured.response_path
	timestamp = captured.timestamp
	transport_attempt = captured.transport_attempt
	match decode_response(response_body) {
		Ok(decoded) =>
			match decoded.choices {
				[choice, ..] => {
					validation = if choice.finish_reason != "stop" {
						Err(IncompleteFinish(choice.finish_reason))
					} else {
						validate_compact_content(choice.message.content, sentences)
					}

					match validation {
						Ok(output) => {
							_ = write_attempt_record!(response_path, attempt, transport_attempt, shard_index, shard_count, body, decoded, choice.finish_reason, response, response_body, request_id, timestamp, requested_at, received_at, run_id, work, "valid", "")?
							_ = Stdout.line!("${work}\tcompact shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)}\tattempt ${U64.to_str(attempt)}\ttransport ${U64.to_str(transport_attempt)}\t${decoded.model}\t${decoded.provider}\t${U64.to_str(decoded.usage.prompt_tokens)}/${U64.to_str(decoded.usage.completion_tokens)}/${U64.to_str(decoded.usage.total_tokens)}\t${choice.finish_reason}\t${response_path}")?
							Ok(Accepted(output))
						}
						Err(validation_error) => {
							error_text = validation_error_text(validation_error)
							_ = write_attempt_record!(response_path, attempt, transport_attempt, shard_index, shard_count, body, decoded, choice.finish_reason, response, response_body, request_id, timestamp, requested_at, received_at, run_id, work, "rejected", error_text)?
							Ok(Rejected(error_text))
						}
					}
				}
				[] => {
					error_text = validation_error_text(MissingResponseChoice)
					_ = write_attempt_record!(response_path, attempt, transport_attempt, shard_index, shard_count, body, decoded, "", response, response_body, request_id, timestamp, requested_at, received_at, run_id, work, "rejected", error_text)?
					Ok(Rejected(error_text))
				}
			}
		Err(_) => {
			error_text = validation_error_text(InvalidResponseEnvelope)
			_ = write_attempt_record!(response_path, attempt, transport_attempt, shard_index, shard_count, body, empty_decoded_response, "", response, response_body, request_id, timestamp, requested_at, received_at, run_id, work, "rejected", error_text)?
			Ok(Rejected(error_text))
		}
	}
}

process_completion! = |work, sentences, run_id, shard_index, shard_count, attempt, body, captured| {
	received_at = captured.received_at
	request_id = captured.request_id
	requested_at = captured.requested_at
	response = captured.response
	response_body = captured.response_body
	response_path = captured.response_path
	timestamp = captured.timestamp
	transport_attempt = captured.transport_attempt
	match decode_response(response_body) {
		Ok(decoded) =>
			match decoded.choices {
				[choice, ..] => {
					validation = if choice.finish_reason != "stop" {
						Err(IncompleteFinish(choice.finish_reason))
					} else {
						validate_content(choice.message.content, sentences)
					}

					match validation {
						Ok(conllu) => {
							_ = write_attempt_record!(
								response_path,
								attempt,
								transport_attempt,
								shard_index,
								shard_count,
								body,
								decoded,
								choice.finish_reason,
								response,
								response_body,
								request_id,
								timestamp,
								requested_at,
								received_at,
								run_id,
								work,
								"valid",
								"",
							)?
							_ = Stdout.line!(
								"${work}\tshard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)}\tattempt ${U64.to_str(attempt)}\ttransport ${U64.to_str(transport_attempt)}\t${decoded.model}\t${decoded.provider}\t${U64.to_str(decoded.usage.prompt_tokens)}/${U64.to_str(decoded.usage.completion_tokens)}/${U64.to_str(decoded.usage.total_tokens)}\t${choice.finish_reason}\t${response_path}",
							)?
							Ok(Accepted(conllu))
						}

						Err(validation_error) => {
							error_text = validation_error_text(validation_error)
							_ = write_attempt_record!(
								response_path,
								attempt,
								transport_attempt,
								shard_index,
								shard_count,
								body,
								decoded,
								choice.finish_reason,
								response,
								response_body,
								request_id,
								timestamp,
								requested_at,
								received_at,
								run_id,
								work,
								"rejected",
								error_text,
							)?
							Ok(Rejected(error_text))
						}
					}
				}

				[] => {
					error_text = validation_error_text(MissingResponseChoice)
					_ = write_attempt_record!(
						response_path,
						attempt,
						transport_attempt,
						shard_index,
						shard_count,
						body,
						decoded,
						"",
						response,
						response_body,
						request_id,
						timestamp,
						requested_at,
						received_at,
						run_id,
						work,
						"rejected",
						error_text,
					)?
					Ok(Rejected(error_text))
				}
			}

		Err(_) => {
			error_text = validation_error_text(InvalidResponseEnvelope)
			_ = write_attempt_record!(
				response_path,
				attempt,
				transport_attempt,
				shard_index,
				shard_count,
				body,
				empty_decoded_response,
				"",
				response,
				response_body,
				request_id,
				timestamp,
				requested_at,
				received_at,
				run_id,
				work,
				"rejected",
				error_text,
			)?
			Ok(Rejected(error_text))
		}
	}
}

check_oga_named_experiment! = |experiment_name| {
	experiment_dir = oga_experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	oga = required_oga_settings(config.oga)?
	_ = check_oga_works!(oga.works, oga, config)?
	_ = Stdout.line!("checked ${experiment_name} OGA experiment: ${U64.to_str(List.len(oga.works))} work(s)")?
	Ok({})
}

smoke_oga_named_experiment! = |experiment_name| {
	experiment_dir = oga_experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	oga = required_oga_settings(config.oga)?
	work = match oga.works {
		[first, ..] => Ok(first)
		[] => Err(NoOgaWorks)
	}?
	sentences = read_oga_work!(oga, work)?
	shards = oga_shard_sentences(sentences, config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard)?
	first_shard = match shards {
		[shard, ..] => Ok(shard)
		[] => Err(NoSourceSentences)
	}?
	api_key = read_api_key!(config.provider.api_key_env)?
	started = Utc.now!()
	run_id = "oga-smoke-${run_id_for(started, config.experiment_version)}"
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/experiment_${U64.to_str(config.experiment_version)}/smoke/${run_id}"
	output_path = "${output_dir}/${work.name}.shard-1-of-${U64.to_str(List.len(shards))}.conllu"

	if Path.exists!(Path.utf8(run_dir))? {
		Err(RunAlreadyExists(run_dir))
	} else {
		_ = Path.create_all!(Path.utf8(run_dir))?
		_ = Path.create_all!(Path.utf8(output_dir))?
		_ = Path.write_utf8!(Path.utf8("${run_dir}/run-id"), "${run_id}\n")?
		generated = run_oga_attempt!(work, first_shard, config, api_key, run_id, run_dir, 1, List.len(shards), 1, "")?
		output = "${oga_file_header(oga, work, config, run_id, first_shard)}${generated.conllu}"
		_ = write_output!(output, output_path)?
		_ = Stdout.line!("completed OGA smoke run ${run_id}\t${output_path}")?
		Ok({})
	}
}

run_oga_named_experiment! = |experiment_name| {
	experiment_dir = oga_experiment_dir_for(experiment_name)?
	config = read_config!(experiment_dir)?
	_ = validate_config(config, experiment_name)?
	oga = required_oga_settings(config.oga)?
	_ = check_oga_works!(oga.works, oga, config)?
	api_key = read_api_key!(config.provider.api_key_env)?
	started = Utc.now!()
	run_id = "oga-${run_id_for(started, config.experiment_version)}"
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/experiment_${U64.to_str(config.experiment_version)}/${run_id}"

	if Path.exists!(Path.utf8(run_dir))? {
		Err(RunAlreadyExists(run_dir))
	} else {
		_ = Path.create_all!(Path.utf8(run_dir))?
		_ = Path.create_all!(Path.utf8(output_dir))?
		_ = Path.write_utf8!(Path.utf8("${run_dir}/run-id"), "${run_id}\n")?
		_ = run_oga_works!(oga.works, oga, config, api_key, run_id, run_dir, output_dir, Bool.False)?
		_ = Stdout.line!("completed OGA run ${run_id}")?
		Ok({})
	}
}

required_oga_settings = |setting|
	match setting {
		Ok(oga) => if List.is_empty(oga.works) Err(NoOgaWorks) else Ok(oga)
		Err(Missing) => Err(MissingOgaSettings)
	}

check_oga_works! = |works, oga, config|
	match works {
		[] => Ok({})
		[work, .. as rest] => {
			sentences = read_oga_work!(oga, work)?
			shards = oga_shard_sentences(sentences, config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard)?
			_ = build_oga_requests!(shards, config, work)?
			check_oga_works!(rest, oga, config)
		}
	}

build_oga_requests! = |shards, config, work|
	match shards {
		[] => Ok({})
		[shard, .. as rest] => {
			_ = oga_request_body(config, shard, "")?
			build_oga_requests!(rest, config, work)
		}
	}

run_oga_works! = |works, oga, config, api_key, run_id, run_dir, output_dir, paid_before|
	match works {
		[] => Ok({})
		[work, .. as rest] => {
			sentences = read_oga_work!(oga, work)?
			shards = oga_shard_sentences(sentences, config.execution.min_overt_tokens_per_shard, config.execution.max_overt_tokens_per_shard)?
			rendered = run_oga_shards!(shards, work, config, api_key, run_id, run_dir, 1, List.len(shards), paid_before, "")?
			output_path = "${output_dir}/${work.name}.conllu"
			_ = write_output!("${oga_file_header(oga, work, config, run_id, sentences)}${rendered}", output_path)?
			_ = Stdout.line!("completed OGA work ${work.name}\t${output_path}")?
			run_oga_works!(rest, oga, config, api_key, run_id, run_dir, output_dir, Bool.True)
		}
	}

run_oga_shards! = |shards, work, config, api_key, run_id, run_dir, shard_index, shard_count, paid_before, rendered|
	match shards {
		[] => Ok(rendered)
		[sentences, .. as rest] => {
			_ = if paid_before and config.execution.shard_delay_ms > 0 Sleep.millis!(config.execution.shard_delay_ms) else {}
			generated = run_oga_attempt!(work, sentences, config, api_key, run_id, run_dir, shard_index, shard_count, 1, "")?
			run_oga_shards!(
				rest,
				work,
				config,
				api_key,
				run_id,
				run_dir,
				shard_index + 1,
				shard_count,
				Bool.True,
				"${rendered}${generated.conllu}",
			)
		}
	}

run_oga_attempt! = |work, sentences, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, feedback| {
	body = oga_request_body(config, sentences, feedback)?
	captured = send_transport_attempt!(
		work.name,
		config,
		api_key,
		run_id,
		run_dir,
		shard_index,
		shard_count,
		attempt,
		body,
		1,
	)?
	outcome = process_oga_completion!(work, sentences, run_id, shard_index, shard_count, attempt, body, captured)?

	match outcome {
		Accepted(conllu) => Ok({ conllu, request_body: body })
		Rejected(error_text) => {
			_ = Stdout.line!("rejected OGA ${work.name} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} attempt ${U64.to_str(attempt)}: ${error_text}")?
			if attempt < config.validation.max_attempts {
				_ = if config.execution.shard_delay_ms > 0 Sleep.millis!(config.execution.shard_delay_ms) else {}
				run_oga_attempt!(work, sentences, config, api_key, run_id, run_dir, shard_index, shard_count, attempt + 1, error_text)
			} else {
				Err(ValidationAttemptsExhausted(work.name, shard_index, attempt, error_text))
			}
		}
	}
}

process_oga_completion! = |work, sentences, run_id, shard_index, shard_count, attempt, body, captured| {
	received_at = captured.received_at
	request_id = captured.request_id
	requested_at = captured.requested_at
	response = captured.response
	response_body = captured.response_body
	response_path = captured.response_path
	timestamp = captured.timestamp
	transport_attempt = captured.transport_attempt
	match decode_response(response_body) {
		Ok(decoded) =>
			match decoded.choices {
				[choice, ..] => {
					validation = if choice.finish_reason != "stop" {
						Err(IncompleteFinish(choice.finish_reason))
					} else {
						validate_oga_content(choice.message.content, sentences)
					}
					match validation {
						Ok(conllu) => {
							_ = write_attempt_record!(response_path, attempt, transport_attempt, shard_index, shard_count, body, decoded, choice.finish_reason, response, response_body, request_id, timestamp, requested_at, received_at, run_id, work.name, "valid", "")?
							_ = Stdout.line!("${work.name}\tOGA shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)}\tattempt ${U64.to_str(attempt)}\ttransport ${U64.to_str(transport_attempt)}\t${decoded.model}\t${decoded.provider}\t${U64.to_str(decoded.usage.prompt_tokens)}/${U64.to_str(decoded.usage.completion_tokens)}/${U64.to_str(decoded.usage.total_tokens)}\t${choice.finish_reason}\t${response_path}")?
							Ok(Accepted(conllu))
						}
						Err(validation_error) => {
							error_text = validation_error_text(validation_error)
							_ = write_attempt_record!(response_path, attempt, transport_attempt, shard_index, shard_count, body, decoded, choice.finish_reason, response, response_body, request_id, timestamp, requested_at, received_at, run_id, work.name, "rejected", error_text)?
							Ok(Rejected(error_text))
						}
					}
				}
				[] => {
					error_text = validation_error_text(MissingResponseChoice)
					_ = write_attempt_record!(response_path, attempt, transport_attempt, shard_index, shard_count, body, decoded, "", response, response_body, request_id, timestamp, requested_at, received_at, run_id, work.name, "rejected", error_text)?
					Ok(Rejected(error_text))
				}
			}
		Err(_) => {
			error_text = validation_error_text(InvalidResponseEnvelope)
			_ = write_attempt_record!(response_path, attempt, transport_attempt, shard_index, shard_count, body, empty_decoded_response, "", response, response_body, request_id, timestamp, requested_at, received_at, run_id, work.name, "rejected", error_text)?
			Ok(Rejected(error_text))
		}
	}
}

read_oga_work! = |oga, work| {
	if !valid_path_segment(work.name) or !valid_path_segment(work.source_file) {
		Err(InvalidOgaWorkPath(work.name, work.source_file))
	} else if work.sentence_count == 0 {
		Err(OgaSentenceCountMustBePositive(work.name))
	} else if List.len(work.citations) != work.sentence_count {
		Err(OgaCitationCountMismatch(work.name, work.sentence_count, List.len(work.citations)))
	} else if !safe_comment_value(work.source) or !safe_comment_value(work.cts_urn) {
		Err(UnsafeOgaWorkMetadata(work.name))
	} else {
		path = "${oga.root}/${work.source_file}"
		_ = verify_oga_sha256!(path, work.source_sha256)?
		source = Path.read_utf8!(Path.utf8(path))?
		parse_oga_conllu(source, work)
	}
}

verify_oga_sha256! = |path, expected| {
	output = Cmd.new_str("sha256sum")
		.args_str([path])
		.exec_output!()?
	actual = match Str.split_on(Str.trim(output.stdout_utf8), " ") {
		[hash, ..] => Ok(hash)
		[] => Err(InvalidSha256Output(path))
	}?
	if actual == expected Ok({}) else Err(OgaSha256Mismatch(path, expected, actual))
}

parse_oga_conllu = |source, work| {
	if Str.trim(source) == "" {
		Err(EmptyOgaInput(work.name))
	} else {
		lines = Str.split_on(Str.replace_each(source, "\r\n", "\n"), "\n")
		parse_oga_lines(lines, work, [], [])
	}
}

parse_oga_lines = |lines, work, current_rows, sentences| {
	if List.len(sentences) == work.sentence_count {
		Ok(sentences)
	} else {
		match lines {
			[] => {
				finished = finish_oga_sentence(current_rows, sentences, work)?
				if List.len(finished) == work.sentence_count {
					Ok(finished)
				} else {
					Err(OgaSourceTooShort(work.name, work.sentence_count, List.len(finished)))
				}
			}
			[line, .. as rest] => {
				trimmed = Str.trim(line)
				if trimmed == "" {
					next_sentences = finish_oga_sentence(current_rows, sentences, work)?
					parse_oga_lines(rest, work, [], next_sentences)
				} else if Str.starts_with(trimmed, "#") {
					Err(UnexpectedOgaComment(work.name, trimmed))
				} else {
					row = parse_oga_row(line, work.name)?
					parse_oga_lines(rest, work, List.append(current_rows, row), sentences)
				}
			}
		}
	}
}

finish_oga_sentence = |rows, sentences, work|
	if List.is_empty(rows) {
		Ok(sentences)
	} else {
		index = List.len(sentences) + 1
		citation = oga_citation_at(work.citations, index, 1)?
		sentence : OgaSentence
		sentence = {
			citation,
			rows,
			source_sentence_id: U64.to_str(index),
		}
		Ok(List.append(sentences, sentence))
	}

oga_citation_at = |citations, target, current|
	match citations {
		[] => Err(MissingOgaCitation(target))
		[citation, .. as rest] => if target == current Ok(citation) else oga_citation_at(rest, target, current + 1)
	}

parse_oga_row = |line, work|
	match Str.split_on(line, "\t") {
		[id_text, form, lemma, upos, xpos, feats, head, deprel, deps, misc] => {
			id = U64.from_str(id_text) ? |_| InvalidOgaTokenId(work, id_text)
			prefix = Str.join_with([id_text, form, lemma, upos, xpos, feats, head, deprel, deps], "\t")
			row : OgaRow
			row = {
				artificial: Str.starts_with(misc, "e_"),
				form,
				id,
				misc,
				prefix,
			}
			Ok(row)
		}
		_ => Err(InvalidOgaColumnCount(work, line))
	}

oga_sentence_overt_count = |sentence| oga_rows_overt_count(sentence.rows, 0)

oga_rows_overt_count = |rows, count|
	match rows {
		[] => count
		[row, .. as rest] => oga_rows_overt_count(rest, if row.artificial count else count + 1)
	}

oga_shard_sentences = |sentences, minimum, maximum| {
	greedy = oga_shard_loop(sentences, maximum, [], 0, [])?
	Ok(oga_rebalance_tail(greedy, minimum, maximum))
}

oga_shard_loop = |remaining, maximum, current, current_count, shards|
	match remaining {
		[] => if List.is_empty(current) Ok(shards) else Ok(List.append(shards, current))
		[sentence, .. as rest] => {
			count = oga_sentence_overt_count(sentence)
			if count > maximum {
				Err(SentenceExceedsShardLimit(sentence.source_sentence_id, count, maximum))
			} else if !List.is_empty(current) and current_count + count > maximum {
				oga_shard_loop(remaining, maximum, [], 0, List.append(shards, current))
			} else {
				oga_shard_loop(rest, maximum, List.append(current, sentence), current_count + count, shards)
			}
		}
	}

oga_rebalance_tail = |shards, minimum, maximum|
	match split_last(shards, []) {
		Err(_) => shards
		Ok(split_tail) =>
			match split_last(split_tail.before, []) {
				Err(_) => shards
				Ok(split_previous) => {
					initial = {
						current: split_tail.last,
						previous: split_previous.last,
						score: oga_shard_shortfall(split_previous.last, minimum) + oga_shard_shortfall(split_tail.last, minimum),
					}
					balanced = oga_explore_tail_balance(split_previous.last, split_tail.last, minimum, maximum, initial)
					List.concat(split_previous.before, [balanced.previous, balanced.current])
				}
			}
	}

oga_explore_tail_balance = |previous, current, minimum, maximum, best|
	match split_last(previous, []) {
		Err(_) => best
		Ok(split_previous) => {
			next_current = List.concat([split_previous.last], current)
			if oga_shard_word_count(next_current) > maximum {
				best
			} else {
				next_previous = split_previous.before
				next_score = oga_shard_shortfall(next_previous, minimum) + oga_shard_shortfall(next_current, minimum)
				next_best = if next_score < best.score {
					{ current: next_current, previous: next_previous, score: next_score }
				} else {
					best
				}
				oga_explore_tail_balance(next_previous, next_current, minimum, maximum, next_best)
			}
		}
	}

oga_shard_word_count = |sentences| oga_shard_word_count_loop(sentences, 0)

oga_shard_word_count_loop = |sentences, count|
	match sentences {
		[] => count
		[sentence, .. as rest] => oga_shard_word_count_loop(rest, count + oga_sentence_overt_count(sentence))
	}

oga_shard_shortfall = |sentences, minimum| {
	count = oga_shard_word_count(sentences)
	if count >= minimum 0 else minimum - count
}

render_oga_source = |sentences|
	Str.join_with(List.map(sentences, |sentence| render_oga_rows(sentence.rows)), "\n\n")

render_oga_rows = |rows|
	Str.join_with(List.map(rows, |row| "${row.prefix}\t${row.misc}"), "\n")

render_oga_targets = |sentences|
	Str.join_with(List.map(sentences, |sentence| render_oga_sentence_targets(sentence.rows, sentence.source_sentence_id, [])), "\n")

render_oga_sentence_targets = |rows, sentence_id, rendered|
	match rows {
		[] => Str.join_with(rendered, "\n")
		[row, .. as rest] => {
			next = if row.artificial rendered else List.append(rendered, "${sentence_id} | ${U64.to_str(row.id)} | ${row.form}")
			render_oga_sentence_targets(rest, sentence_id, next)
		}
	}

oga_request_body = |config, sentences, feedback| {
	generation : Generation
	generation = required_generation_parameter(config.compact_generation, "compact_generation")?
	system_prompt = \\
		\\Act as an Ancient Greek philologist.
		\\Return only the requested structured JSON. The tool owns the OGA CoNLL-U rows, token IDs, metadata, and serialization.
	instructions = \\
		\\The source is Opera Graeca Adnotata v0.2.0 CoNLL-U with existing automatic tokenization, lemmas, morphology, and dependencies.
		\\Add only the semantic fields OGA lacks: a prose English translation, a close literal English translation, and one concise contextual English gloss for each overt token.
		\\Return exactly one sentence object per source block, in source order, and exactly one token object per overt target, in target order.
		\\Copy source_sentence_id and each listed integer token id exactly. Rows whose MISC identifier begins e_ are artificial ellipsis context and are not output targets.
		\\Do not correct, replace, or return Greek forms, lemmas, morphology, dependencies, token rows, citations, or metadata.
		\\Glosses must reflect each inflected token in context. Use hyphens instead of spaces inside a gloss.
	retry_instruction = if feedback == "" {
		""
	} else {
		"RETRY: The previous captured response was rejected: ${feedback}\nCorrect that bounded schema error."
	}
	user_prompt = Str.join_with(
		[
			instructions,
			retry_instruction,
			"",
			"SOURCE OGA CONLLU BLOCKS:",
			render_oga_source(sentences),
			"",
			"OVERT OUTPUT TARGETS (source_sentence_id | original local ID | immutable FORM):",
			render_oga_targets(sentences),
		],
		"\n",
	)
	sentence_count = List.len(sentences)
	sentence_ids = List.map(sentences, |sentence| sentence.source_sentence_id)
	token_schema = {
		additionalProperties: Bool.False,
		properties: {
			gloss: { minLength: 1, type: "string" },
			id: { minimum: 1, type: "integer" },
		},
		required: ["id", "gloss"],
		type: "object",
	}
	sentence_schema = {
		additionalProperties: Bool.False,
		properties: {
			literal_translation: { minLength: 1, type: "string" },
			prose_translation: { minLength: 1, type: "string" },
			source_sentence_id: { enum: sentence_ids, type: "string" },
			tokens: { items: token_schema, minItems: 1, type: "array" },
		},
		required: ["source_sentence_id", "prose_translation", "literal_translation", "tokens"],
		type: "object",
	}
	response_format = {
		json_schema: {
			name: "oga_semantic_overlay_v1",
			schema: {
				additionalProperties: Bool.False,
				properties: {
					sentences: {
						items: sentence_schema,
						maxItems: sentence_count,
						minItems: sentence_count,
						type: "array",
					},
				},
				required: ["sentences"],
				type: "object",
			},
			strict: Bool.True,
		},
		type: "json_schema",
	}
	messages = [
		{ content: system_prompt, role: "system" },
		{ content: user_prompt, role: "user" },
	]
	model_id : Str
	model_id = config.model.id
	match generation.profile {
		"full-sampling" => {
			frequency_penalty = required_generation_parameter(generation.frequency_penalty, "frequency_penalty")?
			presence_penalty = required_generation_parameter(generation.presence_penalty, "presence_penalty")?
			seed = required_generation_parameter(generation.seed, "seed")?
			temperature = required_generation_parameter(generation.temperature, "temperature")?
			top_k = required_generation_parameter(generation.top_k, "top_k")?
			top_p = required_generation_parameter(generation.top_p, "top_p")?
			body = {
				frequency_penalty,
				include_reasoning: generation.include_reasoning,
				max_tokens: generation.max_tokens,
				messages,
				model: model_id,
				presence_penalty,
				provider: generation.provider,
				reasoning: generation.reasoning,
				response_format,
				seed,
				temperature,
				top_k,
				top_p,
			}
			Json.to_str_try(body)
		}
		other => Err(UnsupportedGenerationProfile(other))
	}
}

validate_oga_content = |content, source_sentences| {
	decoded : Try(CompactModelPayload, _)
	decoded = Json.parse(content)
	match decoded {
		Ok(payload) =>
			if List.len(payload.sentences) != List.len(source_sentences) {
				Err(WrongSentenceCount(List.len(source_sentences), List.len(payload.sentences)))
			} else {
				validate_oga_sentences(source_sentences, payload.sentences, [])
			}
		Err(_) => Err(InvalidContentJson)
	}
}

validate_oga_sentences = |source_sentences, model_sentences, rendered|
	match (source_sentences, model_sentences) {
		([], []) => Ok(Str.join_with(rendered, ""))
		([source, .. as rest_source], [model, .. as rest_model]) => {
			if model.source_sentence_id != source.source_sentence_id {
				Err(WrongSentenceId(source.source_sentence_id, model.source_sentence_id))
			} else if List.len(model.tokens) != oga_sentence_overt_count(source) {
				Err(WrongTokenCount(source.source_sentence_id, oga_sentence_overt_count(source), List.len(model.tokens)))
			} else {
				prose = Str.trim(model.prose_translation)
				literal = Str.trim(model.literal_translation)
				if !safe_comment_value(prose) {
					Err(UnsafeTranslation(source.source_sentence_id, "prose_translation"))
				} else if !safe_comment_value(literal) {
					Err(UnsafeTranslation(source.source_sentence_id, "literal_translation"))
				} else {
					rows = validate_oga_rows(source.source_sentence_id, source.citation, source.rows, model.tokens, [])?
					block = serialize_oga_sentence(source, prose, literal, rows)
					validate_oga_sentences(rest_source, rest_model, List.append(rendered, block))
				}
			}
		}
		_ => Err(InternalSentenceLengthMismatch)
	}

validate_oga_rows = |sentence_id, citation, source_rows, model_tokens, rendered|
	match source_rows {
		[] =>
			match model_tokens {
				[] => Ok(rendered)
				_ => Err(InternalTokenLengthMismatch(sentence_id))
			}
		[row, .. as rest_rows] =>
			if row.artificial {
				validate_oga_rows(sentence_id, citation, rest_rows, model_tokens, List.append(rendered, "${row.prefix}\t${row.misc}"))
			} else {
				match model_tokens {
					[] => Err(InternalTokenLengthMismatch(sentence_id))
					[token, .. as rest_tokens] => {
						gloss = Str.trim(token.gloss)
						if token.id != row.id {
							Err(WrongTokenId(sentence_id, row.id, token.id))
						} else if !safe_misc_value(gloss) {
							Err(UnsafeTokenField(sentence_id, row.id, "gloss"))
						} else {
							misc = if row.misc == "_" "gloss=${gloss}" else "${row.misc}|gloss=${gloss}"
							validate_oga_rows(sentence_id, citation, rest_rows, rest_tokens, List.append(rendered, "${row.prefix}\t${misc}"))
						}
					}
				}
		}
	}

serialize_oga_sentence = |source, prose, literal, rows|
	Str.join_with(
		[
			"# sentence_id = ${source.source_sentence_id}\n",
			"# citation = ${source.citation}\n",
			"# translation_lang = en\n",
			"# prose_translation = ${prose}\n",
			"# literal_translation = ${literal}\n",
			Str.join_with(rows, "\n"),
			"\n\n",
		],
		"",
	)

oga_file_header = |oga, work, config, run_id, sentences|
	Str.join_with(
		[
			"# global.columns = ID FORM LEMMA UPOS XPOS FEATS HEAD DEPREL DEPS MISC",
			"# source = ${work.source}",
			"# source_edition = Opera Graeca Adnotata ${oga.source_version}",
			"# source_url = ${oga.source_doi}",
			"# source_revision = ${oga.source_version}",
			"# source_file = ${work.source_file}",
			"# source_sha256 = ${work.source_sha256}",
			"# cts_urn = ${oga_cts_urn(work.cts_urn, sentences)}",
			"# encoder = ${config.model.id} (Large Language Model)",
			"# generation_run_id = ${run_id}",
			"# editor = ${oga.editor}",
			"# project = ${oga.project}",
			"# conversion_method = LLM semantic overlay on preserved OGA morphosyntax",
			"# gloss_type = ${oga.gloss_type}",
			"# date_modified = ${oga.date_modified}",
			"# license = CC BY-SA 4.0",
			"# contact = ${oga.contact}",
			"",
		],
		"\n",
	)

oga_cts_urn = |work_urn, sentences|
	match sentences {
		[] => work_urn
		[first, ..] =>
			match split_last(sentences, []) {
				Err(_) => work_urn
				Ok(split) => {
					last_endpoint = match split_last(Str.split_on(split.last.citation, "-"), []) {
						Ok(parts) => parts.last
						Err(_) => split.last.citation
					}
					passage = if first.citation == last_endpoint first.citation else "${first.citation}-${last_endpoint}"
					"${work_urn}:${passage}"
				}
			}
	}

max_transport_attempts : U64
max_transport_attempts = 5

transport_base_delay_ms : U64
transport_base_delay_ms = 10000

is_transient_status = |status| status == 408 or status == 429 or status == 499 or status >= 500

backoff_ms = |base_delay_ms, attempt|
	if attempt <= 1 base_delay_ms else backoff_ms(base_delay_ms * 2, attempt - 1)

max_u64 = |a, b| if a > b a else b

retry_after_ms = |headers, fallback|
	match headers {
		[] => fallback
		[header, .. as rest] => {
			header_record = header_to_record(header)
			if header_record.name == "retry-after" or header_record.name == "Retry-After" {
				match U64.from_str(header_record.value) {
					Ok(seconds) => seconds * 1000
					Err(_) => fallback
				}
			} else {
				retry_after_ms(rest, fallback)
			}
		}
	}

header_to_record = |header| {
	{ name, value } = header
	{ name, value }
}

empty_decoded_response = {
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

decode_response = |response_body| {
	body = Str.from_utf8(response_body) ? |_| InvalidResponseEnvelope
	decoded : Try(DecodedResponse, _)
	decoded = Json.parse(Str.trim(body))
	match decoded {
		Ok(response) => Ok(response)
		Err(_) => Err(InvalidResponseEnvelope)
	}
}

write_attempt_record! : Str, U64, U64, U64, U64, Str, DecodedResponse, Str, Response.Response, List(U8), Str, Str, U128, U128, Str, Str, Str, Str => Try({}, _)
write_attempt_record! = |path, attempt, transport_attempt, shard_index, shard_count, body, decoded, finish_reason, response, raw_response_bytes, request_id, timestamp, requested_at, received_at, run_id, work, validation_status, validation_error| {
	elapsed_ms = Utc.delta_as_millis(received_at, requested_at)
	response_headers = List.map(Response.headers(response), header_to_record)
	record = {
		attempt,
		elapsed_ms,
		finish_reason,
		http_status: Response.status(response),
		raw_request_body: body,
		raw_response_bytes,
		request_body: body,
		request_id,
		requested_at: timestamp,
		resolved_model: decoded.model,
		resolved_provider: decoded.provider,
		response_headers,
		response_id: decoded.id,
		run_id,
		shard_count,
		shard_index,
		token_usage: decoded.usage,
		transport_attempt,
		validation_error,
		validation_status,
		work,
	}
	record_json = Json.to_str_try(record)?
	write_new_utf8!("${record_json}\n", path)
}

supported_input_path = |path| Str.ends_with(path, ".xml")

parse_glaux_xml = |source| {
	if Str.trim(source) == "" {
		Err(EmptyXmlInput)
	} else if !Str.contains(source, "<treebank") or !Str.contains(source, "</treebank>") {
		Err(NotGlauxXml)
	} else {
		sentences = parse_glaux_lines(Str.split_on(Str.replace_each(source, "\r\n", "\n"), "\n"), [])?
		if List.is_empty(sentences) Err(NoSourceSentences) else Ok(sentences)
	}
}

parse_glaux_lines = |lines, found|
	match lines {
		[] => Ok(found)
		[line, .. as rest] => {
			trimmed = Str.trim(line)
			if Str.starts_with(trimmed, "<sentence ") {
				source_sentence_id = required_xml_attribute(line, "id")?
				document_id = required_xml_attribute(line, "document_id")?
				parsed = parse_sentence_block(rest, [line], [], source_sentence_id, document_id)?
				parse_glaux_lines(parsed.remaining, List.append(found, parsed.sentence))
			} else if Str.starts_with(trimmed, "<word ") or trimmed == "</sentence>" {
				Err(MalformedSentenceBoundary)
			} else {
				parse_glaux_lines(rest, found)
			}
		}
	}

parse_sentence_block = |lines, xml_lines, overt_words, source_sentence_id, document_id|
	match lines {
		[] => Err(UnclosedSentence(source_sentence_id))
		[line, .. as rest] => {
			trimmed = Str.trim(line)
			if trimmed == "</sentence>" {
				if List.is_empty(overt_words) {
					Err(NoOvertWords(source_sentence_id))
				} else {
					sentence : SourceSentence
					sentence = {
						document_id,
						overt_words,
						source_sentence_id,
						xml: Str.join_with(List.append(xml_lines, line), "\n"),
					}
					Ok({ remaining: rest, sentence })
				}
			} else if Str.starts_with(trimmed, "<sentence ") {
				Err(UnclosedSentence(source_sentence_id))
			} else if Str.starts_with(trimmed, "<word ") {
				next_words = if Str.contains(line, " artificial=\"") {
					overt_words
				} else {
					List.append(overt_words, parse_overt_word(line)?)
				}
				parse_sentence_block(rest, List.append(xml_lines, line), next_words, source_sentence_id, document_id)
			} else {
				parse_sentence_block(rest, List.append(xml_lines, line), overt_words, source_sentence_id, document_id)
			}
		}
	}

parse_overt_word = |line| {
	source_id = required_xml_attribute(line, "id")?
	form = xml_unescape(required_xml_attribute(line, "form")?)
	section = optional_xml_attribute(line, "div_section")
	line_ref = optional_xml_attribute(line, "line")
	chapter = optional_xml_attribute(line, "div_chapter")
	book = optional_xml_attribute(line, "div_book")
	reference = if section != "" section else if line_ref != "" line_ref else if chapter != "" chapter else book
	word : SourceWord
	word = {
		form,
		reference: xml_unescape(reference),
		source_id,
		speaker: xml_unescape(optional_xml_attribute(line, "speaker")),
	}
	Ok(word)
}

required_xml_attribute = |line, name| {
	value = optional_xml_attribute(line, name)
	if value == "" Err(MissingXmlAttribute(name)) else Ok(value)
}

optional_xml_attribute = |line, name|
	match Str.split_on(line, " ${name}=\"") {
		[_, after, ..] =>
			match Str.split_on(after, "\"") {
				[value, ..] => value
				[] => ""
			}
		_ => ""
	}

xml_unescape = |value|
	Str.replace_each(
		Str.replace_each(
			Str.replace_each(
				Str.replace_each(
					Str.replace_each(value, "&quot;", "\""),
					"&apos;",
					"'",
				),
				"&lt;",
				"<",
			),
			"&gt;",
			">",
		),
		"&amp;",
		"&",
	)

shard_sentences = |sentences, minimum, maximum| {
	greedy = shard_sentence_loop(sentences, maximum, [], 0, [])?
	Ok(rebalance_shard_tail(greedy, minimum, maximum))
}

shard_sentence_loop = |remaining, maximum, current, current_count, shards|
	match remaining {
		[] => if List.is_empty(current) Ok(shards) else Ok(List.append(shards, current))
		[sentence, .. as rest] => {
			count = List.len(sentence.overt_words)
			if count > maximum {
				Err(SentenceExceedsShardLimit(sentence.source_sentence_id, count, maximum))
			} else if !List.is_empty(current) and current_count + count > maximum {
				shard_sentence_loop(remaining, maximum, [], 0, List.append(shards, current))
			} else {
				shard_sentence_loop(rest, maximum, List.append(current, sentence), current_count + count, shards)
			}
		}
	}

rebalance_shard_tail = |shards, minimum, maximum|
	match split_last(shards, []) {
		Err(_) => shards
		Ok(split_tail) =>
			match split_last(split_tail.before, []) {
				Err(_) => shards
				Ok(split_previous) => {
					previous = split_previous.last
					current = split_tail.last
					initial = {
						current,
						previous,
						score: shard_shortfall(previous, minimum) + shard_shortfall(current, minimum),
					}
					balanced = explore_tail_balance(previous, current, minimum, maximum, initial)
					List.concat(split_previous.before, [balanced.previous, balanced.current])
				}
		}
	}

explore_tail_balance = |previous, current, minimum, maximum, best|
	match split_last(previous, []) {
		Err(_) => best
		Ok(split_previous) => {
			moved = split_previous.last
			next_current = List.concat([moved], current)
			if shard_word_count(next_current) > maximum {
				best
			} else {
				next_previous = split_previous.before
				next_score = shard_shortfall(next_previous, minimum) + shard_shortfall(next_current, minimum)
				next_best = if next_score < best.score {
					{ current: next_current, previous: next_previous, score: next_score }
				} else {
					best
				}
				explore_tail_balance(next_previous, next_current, minimum, maximum, next_best)
			}
		}
	}

split_last = |items, before|
	match items {
		[] => Err(EmptyList)
		[item] => Ok({ before, last: item })
		[item, .. as rest] => split_last(rest, List.append(before, item))
	}

shard_word_count = |sentences| shard_word_count_loop(sentences, 0)

shard_word_count_loop = |sentences, total|
	match sentences {
		[] => total
		[sentence, .. as rest] => shard_word_count_loop(rest, total + List.len(sentence.overt_words))
	}

shard_shortfall = |sentences, minimum| {
	count = shard_word_count(sentences)
	if count >= minimum count - count else minimum - count
}

render_shard_xml = |sentences|
	Str.join_with(
		[
			"<treebank version=\"2\" xml:lang=\"grc\">\n",
			Str.join_with(List.map(sentences, |sentence| sentence.xml), "\n"),
			"\n</treebank>",
		],
		"",
	)

render_target_table = |sentences|
	Str.join_with(List.map(sentences, render_sentence_targets), "\n")

render_sentence_targets = |sentence|
	render_word_targets(sentence.overt_words, sentence.source_sentence_id, 1, [])

render_word_targets = |words, sentence_id, local_id, rendered|
	match words {
		[] => Str.join_with(rendered, "\n")
		[word, .. as rest] => {
			line = "${sentence_id} | ${U64.to_str(local_id)} | ${word.form}"
			render_word_targets(rest, sentence_id, local_id + 1, List.append(rendered, line))
		}
	}

golden_example = \\
	\\# sentence_id = 1
	\\# translation_lang = en
	\\# prose_translation = Darius and Parysatis had two sons, the elder being Artaxerxes and the younger Cyrus.
	\\# literal_translation = Of-Darius and of-Parysatis are-born sons two, elder indeed Artaxerxes, younger but Cyrus.
	\\1	Δαρείου	Δαρεῖος	PROPN	n-s---mg-	Case=Gen|Gender=Masc|Number=Sing	5	nmod	_	Ref=1.1.1|gloss=of-Darius
	\\2	καὶ	καί	CCONJ	b--------	_	3	cc	_	Ref=1.1.1|gloss=and
	\\3	Παρυσάτιδος	Παρύσατις	PROPN	n-s---fg-	Case=Gen|Gender=Fem|Number=Sing	1	conj	_	Ref=1.1.1|gloss=of-Parysatis
	\\4	γίγνονται	γίγνομαι	VERB	v3ppie---	Mood=Ind|Number=Plur|Person=3|Tense=Pres|VerbForm=Fin|Voice=Mid	0	root	_	Ref=1.1.1|gloss=are-born
	\\5	παῖδες	παῖς	NOUN	n-p---cn-	Case=Nom|Gender=Com|Number=Plur	4	nsubj	_	Ref=1.1.1|gloss=sons
	\\6	δύο	δύο	NUM	a--------	_	5	nummod	_	Ref=1.1.1|gloss=two
	\\7	,	,	PUNCT	u--------	_	8	punct	_	Ref=1.1.1|gloss=,
	\\8	πρεσβύτερος	πρέσβυς	ADJ	a-s---mnc	Case=Nom|Degree=Cmp|Gender=Masc|Number=Sing	5	appos	_	Ref=1.1.1|gloss=elder
	\\9	μὲν	μέν	ADV	d--------	_	8	discourse	_	Ref=1.1.1|gloss=indeed
	\\10	Ἀρταξέρξης	Ἀρταξέρξης	PROPN	n-s---mn-	Case=Nom|Gender=Masc|Number=Sing	8	nsubj	_	Ref=1.1.1|gloss=Artaxerxes
	\\11	,	,	PUNCT	u--------	_	12	punct	_	Ref=1.1.1|gloss=,
	\\12	νεώτερος	νέος	ADJ	a-s---mnc	Case=Nom|Degree=Cmp|Gender=Masc|Number=Sing	8	conj	_	Ref=1.1.1|gloss=younger
	\\13	δὲ	δέ	CCONJ	b--------	_	12	discourse	_	Ref=1.1.1|gloss=but
	\\14	Κῦρος	Κῦρος	PROPN	n-s---mn-	Case=Nom|Gender=Masc|Number=Sing	12	nsubj	_	Ref=1.1.1|gloss=Cyrus
	\\15	·	·	PUNCT	u--------	_	4	punct	_	Ref=1.1.1|gloss=;

compact_request_body = |config, sentences, feedback| {
	generation : Generation
	generation = required_generation_parameter(config.compact_generation, "compact_generation")?
	system_prompt = \\
		\\Act as an Ancient Greek philologist.
		\\Return only the requested structured JSON. The tool owns the Greek forms, token IDs, and serialization.
	instructions = \\
		\\Translate each complete Ancient Greek sentence and provide one concise contextual English gloss for every target token.
		\\Return exactly one sentence object per source sentence, in source order, and exactly one token object per target, in target order.
		\\Copy source_sentence_id and each local integer token id exactly. Do not return Greek forms, morphology, syntax, or CoNLL-U rows.
		\\The prose translation must be natural English. The literal translation must remain close to Greek wording and structure.
		\\Glosses must reflect each inflected token in context. Use hyphens instead of spaces inside a gloss.
	retry_instruction = if feedback == "" {
		""
	} else {
		"RETRY: The previous captured response was rejected: ${feedback}\nCorrect that bounded schema error."
	}
	user_prompt = Str.join_with(
		[
			instructions,
			retry_instruction,
			"",
			"SOURCE SENTENCES (source_sentence_id | local id | immutable FORM):",
			render_target_table(sentences),
		],
		"\n",
	)
	sentence_count = List.len(sentences)
	sentence_ids = List.map(sentences, |sentence| sentence.source_sentence_id)
	token_schema = {
		additionalProperties: Bool.False,
		properties: {
			gloss: { minLength: 1, type: "string" },
			id: { minimum: 1, type: "integer" },
		},
		required: ["id", "gloss"],
		type: "object",
	}
	sentence_schema = {
		additionalProperties: Bool.False,
		properties: {
			literal_translation: { minLength: 1, type: "string" },
			prose_translation: { minLength: 1, type: "string" },
			source_sentence_id: { enum: sentence_ids, type: "string" },
			tokens: { items: token_schema, minItems: 1, type: "array" },
		},
		required: ["source_sentence_id", "prose_translation", "literal_translation", "tokens"],
		type: "object",
	}
	response_format = {
		json_schema: {
			name: "glaux_semantic_overlay_v2",
			schema: {
				additionalProperties: Bool.False,
				properties: {
					sentences: {
						items: sentence_schema,
						maxItems: sentence_count,
						minItems: sentence_count,
						type: "array",
					},
				},
				required: ["sentences"],
				type: "object",
			},
			strict: Bool.True,
		},
		type: "json_schema",
	}
	messages = [
		{ content: system_prompt, role: "system" },
		{ content: user_prompt, role: "user" },
	]
	model_id : Str
	model_id = config.model.id
	match generation.profile {
		"full-sampling" => {
			frequency_penalty = required_generation_parameter(generation.frequency_penalty, "frequency_penalty")?
			presence_penalty = required_generation_parameter(generation.presence_penalty, "presence_penalty")?
			seed = required_generation_parameter(generation.seed, "seed")?
			temperature = required_generation_parameter(generation.temperature, "temperature")?
			top_k = required_generation_parameter(generation.top_k, "top_k")?
			top_p = required_generation_parameter(generation.top_p, "top_p")?
			body = {
				frequency_penalty,
				include_reasoning: generation.include_reasoning,
				max_tokens: generation.max_tokens,
				messages,
				model: model_id,
				presence_penalty,
				provider: generation.provider,
				reasoning: generation.reasoning,
				response_format,
				seed,
				temperature,
				top_k,
				top_p,
			}
			Json.to_str_try(body)
		}
		other => Err(UnsupportedGenerationProfile(other))
	}
}

request_body = |config, _work, sentences, feedback| {
	system_prompt = \\
		\\Act as an Ancient Greek philologist and Universal Dependencies treebank editor.
		\\Return only the requested structured JSON. The tool, not you, owns FORM, source metadata, and CoNLL-U serialization.
	instructions = \\
		\\The input is line-oriented GLAUx XML whose morphology and Ancient Greek Dependency Treebank syntax are automatic proposals.
		\\Return exactly one sentence object per source sentence, in source order, and exactly one token object per listed overt target, in target order.
		\\Copy source_sentence_id and each local integer token id exactly. Artificial elliptic words are context only and are not output targets.
		\\Correct lemma, UPOS, XPOS, FEATS, HEAD, DEPREL, and DEPS and map GLAUx labels to valid UD v2 analyses. Use _ for DEPS unless a justified enhanced dependency is supplied.
		\\Use local consecutive token IDs starting at 1, local HEAD values, no self-head, and exactly one HEAD 0 root per sentence.
		\\Use _ where XPOS, FEATS, or DEPS has no value. Do not use tabs, line breaks, or spaces in token fields; use CoNLL-U-safe values.
		\\Provide a nonempty prose translation, literal translation, and concise contextual English gloss for every token. Use hyphens instead of spaces inside a gloss.
	retry_instruction = if feedback == "" {
		""
	} else {
		"RETRY: The previous captured response was rejected: ${feedback}\nCorrect that bounded schema or structural error."
	}
	source_xml = render_shard_xml(sentences)
	target_table = render_target_table(sentences)
	user_prompt = Str.join_with(
		[
			instructions,
			retry_instruction,
			"",
			"GOLDEN OUTPUT EXAMPLE (conllu/xenophon/anabasis/book-01-first-sentence.tb.conllu):",
			golden_example,
			"",
			"COMPLETE SOURCE SENTENCE BLOCKS:",
			source_xml,
			"",
			"OVERT OUTPUT TARGETS (source_sentence_id | local id | immutable FORM):",
			target_table,
		],
		"\n",
	)

	sentence_count = List.len(sentences)
	sentence_ids = List.map(sentences, |sentence| sentence.source_sentence_id)
	token_schema = {
		additionalProperties: Bool.False,
		properties: {
			deprel: { minLength: 1, type: "string" },
			deps: { minLength: 1, type: "string" },
			feats: { minLength: 1, type: "string" },
			gloss: { minLength: 1, type: "string" },
			head: { minimum: 0, type: "integer" },
			id: { minimum: 1, type: "integer" },
			lemma: { minLength: 1, type: "string" },
			upos: { minLength: 1, type: "string" },
			xpos: { minLength: 1, type: "string" },
		},
		required: ["id", "lemma", "upos", "xpos", "feats", "head", "deprel", "deps", "gloss"],
		type: "object",
	}
	sentence_schema = {
		additionalProperties: Bool.False,
		properties: {
			literal_translation: { minLength: 1, type: "string" },
			prose_translation: { minLength: 1, type: "string" },
			source_sentence_id: { enum: sentence_ids, type: "string" },
			tokens: { items: token_schema, minItems: 1, type: "array" },
		},
		required: ["source_sentence_id", "prose_translation", "literal_translation", "tokens"],
		type: "object",
	}
	response_format = {
		json_schema: {
			name: "glaux_ud_sentences_v2",
			schema: {
				additionalProperties: Bool.False,
				properties: {
					sentences: {
						items: sentence_schema,
						maxItems: sentence_count,
						minItems: sentence_count,
						type: "array",
					},
				},
				required: ["sentences"],
				type: "object",
			},
			strict: Bool.True,
		},
		type: "json_schema",
	}
	messages = [
		{ content: system_prompt, role: "system" },
		{ content: user_prompt, role: "user" },
	]
	generation : Generation
	generation = config.generation
	model_id : Str
	model_id = config.model.id
	match generation.profile {
		"full-sampling" => {
			frequency_penalty = required_generation_parameter(generation.frequency_penalty, "frequency_penalty")?
			presence_penalty = required_generation_parameter(generation.presence_penalty, "presence_penalty")?
			seed = required_generation_parameter(generation.seed, "seed")?
			temperature = required_generation_parameter(generation.temperature, "temperature")?
			top_k = required_generation_parameter(generation.top_k, "top_k")?
			top_p = required_generation_parameter(generation.top_p, "top_p")?
			body = {
				frequency_penalty,
				include_reasoning: generation.include_reasoning,
				max_tokens: generation.max_tokens,
				messages,
				model: model_id,
				presence_penalty,
				provider: generation.provider,
				reasoning: generation.reasoning,
				response_format,
				seed,
				temperature,
				top_k,
				top_p,
			}
			Json.to_str_try(body)
		}
		"anthropic-non-thinking" => {
			temperature = required_generation_parameter(generation.temperature, "temperature")?
			body = {
				include_reasoning: generation.include_reasoning,
				max_tokens: generation.max_tokens,
				messages,
				model: model_id,
				provider: generation.provider,
				reasoning: generation.reasoning,
				response_format,
				temperature,
			}
			Json.to_str_try(body)
		}
		"openai-non-thinking" => {
			seed = required_generation_parameter(generation.seed, "seed")?
			body = {
				include_reasoning: generation.include_reasoning,
				max_tokens: generation.max_tokens,
				messages,
				model: model_id,
				provider: generation.provider,
				reasoning: generation.reasoning,
				response_format,
				seed,
			}
			Json.to_str_try(body)
		}
		"mistral-non-thinking" => {
			reasoning_effort = required_generation_parameter(generation.reasoning_effort, "reasoning_effort")?
			seed = required_generation_parameter(generation.seed, "seed")?
			temperature = required_generation_parameter(generation.temperature, "temperature")?
			body = {
				include_reasoning: generation.include_reasoning,
				max_tokens: generation.max_tokens,
				messages,
				model: model_id,
				provider: generation.provider,
				reasoning: generation.reasoning,
				reasoning_effort,
				response_format,
				seed,
				temperature,
			}
			Json.to_str_try(body)
		}
		other => Err(UnsupportedGenerationProfile(other))
	}
}

required_generation_parameter = |option, name|
	match option {
		Ok(value) => Ok(value)
		Err(Missing) => Err(MissingGenerationParameter(name))
	}

validate_compact_content = |content, source_sentences| {
	decoded : Try(CompactModelPayload, _)
	decoded = Json.parse(content)
	match decoded {
		Ok(payload) =>
			if List.len(payload.sentences) != List.len(source_sentences) {
				Err(WrongSentenceCount(List.len(source_sentences), List.len(payload.sentences)))
			} else {
				validate_compact_sentences(source_sentences, payload.sentences, [])
			}
		Err(_) => Err(InvalidContentJson)
	}
}

validate_compact_sentences = |source_sentences, model_sentences, rendered|
	match (source_sentences, model_sentences) {
		([], []) => Ok(Str.join_with(rendered, ""))
		([source, .. as rest_source], [model, .. as rest_model]) => {
			if model.source_sentence_id != source.source_sentence_id {
				Err(WrongSentenceId(source.source_sentence_id, model.source_sentence_id))
			} else if List.len(model.tokens) != List.len(source.overt_words) {
				Err(WrongTokenCount(source.source_sentence_id, List.len(source.overt_words), List.len(model.tokens)))
			} else {
				prose = Str.trim(model.prose_translation)
				literal = Str.trim(model.literal_translation)
				if !safe_comment_value(prose) {
					Err(UnsafeTranslation(source.source_sentence_id, "prose_translation"))
				} else if !safe_comment_value(literal) {
					Err(UnsafeTranslation(source.source_sentence_id, "literal_translation"))
				} else {
					rows = validate_compact_tokens(source.source_sentence_id, source.overt_words, model.tokens, 1, [])?
					block = serialize_compact_sentence(source, prose, literal, rows)
					validate_compact_sentences(rest_source, rest_model, List.append(rendered, block))
				}
			}
		}
		_ => Err(InternalSentenceLengthMismatch)
	}

validate_compact_tokens = |sentence_id, source_words, model_tokens, expected_id, rows|
	match (source_words, model_tokens) {
		([], []) => Ok(rows)
		([source_word, .. as rest_source], [token, .. as rest_model]) => {
			gloss = Str.trim(token.gloss)
			if token.id != expected_id {
				Err(WrongTokenId(sentence_id, expected_id, token.id))
			} else if !safe_misc_value(gloss) {
				Err(UnsafeTokenField(sentence_id, expected_id, "gloss"))
			} else {
				row = "${U64.to_str(token.id)}\t${source_word.form}\t${gloss}"
				validate_compact_tokens(sentence_id, rest_source, rest_model, expected_id + 1, List.append(rows, row))
			}
		}
		_ => Err(InternalTokenLengthMismatch(sentence_id))
	}

serialize_compact_sentence = |source, prose, literal, rows| {
	first = first_source_word(source.overt_words)
	citation_comment = if first.reference == "" "" else "# citation = ${first.reference}\n"
	speaker_comment = if first.speaker == "" "" else "# speaker = ${first.speaker}\n"
	Str.join_with(
		[
			"# sentence_id = ${source.source_sentence_id}\n",
			"# source_document_id = ${source.document_id}\n",
			citation_comment,
			speaker_comment,
			"# translation_lang = en\n",
			"# prose_translation = ${prose}\n",
			"# literal_translation = ${literal}\n",
			"# columns = ID FORM GLOSS\n",
			Str.join_with(rows, "\n"),
			"\n\n",
		],
		"",
	)
}

validate_content = |content, source_sentences| {
	decoded : Try(ModelPayload, _)
	decoded = Json.parse(content)
	match decoded {
		Ok(payload) =>
			if List.len(payload.sentences) != List.len(source_sentences) {
				Err(WrongSentenceCount(List.len(source_sentences), List.len(payload.sentences)))
			} else {
				validate_sentences(source_sentences, payload.sentences, [])
			}
		Err(_) => Err(InvalidContentJson)
	}
}

validate_sentences = |source_sentences, model_sentences, rendered|
	match (source_sentences, model_sentences) {
		([], []) => Ok(Str.join_with(rendered, ""))
		([source, .. as rest_source], [model, .. as rest_model]) => {
			if model.source_sentence_id != source.source_sentence_id {
				Err(WrongSentenceId(source.source_sentence_id, model.source_sentence_id))
			} else if List.len(model.tokens) != List.len(source.overt_words) {
				Err(WrongTokenCount(source.source_sentence_id, List.len(source.overt_words), List.len(model.tokens)))
			} else {
				prose = Str.trim(model.prose_translation)
				literal = Str.trim(model.literal_translation)
				if !safe_comment_value(prose) {
					Err(UnsafeTranslation(source.source_sentence_id, "prose_translation"))
				} else if !safe_comment_value(literal) {
					Err(UnsafeTranslation(source.source_sentence_id, "literal_translation"))
				} else {
					validated = validate_tokens(source.source_sentence_id, source.overt_words, model.tokens, List.len(source.overt_words), 1, 0, [], [])?
					if validated.root_count != 1 {
						Err(WrongRootCount(source.source_sentence_id, validated.root_count))
					} else {
						_ = validate_head_graph(source.source_sentence_id, validated.heads)?
						block = serialize_sentence(source, prose, literal, validated.rows)
						validate_sentences(rest_source, rest_model, List.append(rendered, block))
					}
				}
			}
		}
		_ => Err(InternalSentenceLengthMismatch)
	}

validate_tokens = |sentence_id, source_words, model_tokens, token_count, expected_id, root_count, rows, heads|
	match (source_words, model_tokens) {
		([], []) => Ok({ heads, root_count, rows })
		([source_word, .. as rest_source], [token, .. as rest_model]) => {
			lemma = Str.trim(token.lemma)
			upos = Str.trim(token.upos)
			xpos = Str.trim(token.xpos)
			feats = Str.trim(token.feats)
			deprel = Str.trim(token.deprel)
			deps = Str.trim(token.deps)
			gloss = Str.trim(token.gloss)
			if token.id != expected_id {
				Err(WrongTokenId(sentence_id, expected_id, token.id))
			} else if !safe_column(lemma) {
				Err(UnsafeTokenField(sentence_id, expected_id, "lemma"))
			} else if !safe_column(upos) {
				Err(UnsafeTokenField(sentence_id, expected_id, "upos"))
			} else if !safe_column(xpos) {
				Err(UnsafeTokenField(sentence_id, expected_id, "xpos"))
			} else if !safe_column(feats) {
				Err(UnsafeTokenField(sentence_id, expected_id, "feats"))
			} else if !safe_column(deprel) {
				Err(UnsafeTokenField(sentence_id, expected_id, "deprel"))
			} else if !safe_column(deps) {
				Err(UnsafeTokenField(sentence_id, expected_id, "deps"))
			} else if !safe_misc_value(gloss) {
				Err(UnsafeTokenField(sentence_id, expected_id, "gloss"))
			} else if token.head > token_count {
				Err(HeadOutOfBounds(sentence_id, expected_id, token.head, token_count))
			} else if token.head == token.id {
				Err(SelfHead(sentence_id, expected_id))
			} else if token.head == 0 and deprel != "root" {
				Err(RootRelationMismatch(sentence_id, expected_id))
			} else if token.head != 0 and deprel == "root" {
				Err(RootRelationMismatch(sentence_id, expected_id))
			} else {
				misc = source_misc(source_word, gloss)?
				row = Str.join_with(
					[
						U64.to_str(token.id),
						source_word.form,
						lemma,
						upos,
						xpos,
						feats,
						U64.to_str(token.head),
						deprel,
						deps,
						misc,
					],
					"\t",
				)
				next_roots = if token.head == 0 root_count + 1 else root_count
				validate_tokens(
					sentence_id,
					rest_source,
					rest_model,
					token_count,
					expected_id + 1,
					next_roots,
					List.append(rows, row),
					List.append(heads, token.head),
				)
			}
		}
		_ => Err(InternalTokenLengthMismatch(sentence_id))
	}

validate_head_graph = |sentence_id, heads| validate_head_paths(sentence_id, heads, heads, 1)

validate_head_paths = |sentence_id, remaining, all_heads, token_id|
	match remaining {
		[] => Ok({})
		[head, .. as rest] => {
			_ = follow_head_path(sentence_id, token_id, head, all_heads, [token_id])?
			validate_head_paths(sentence_id, rest, all_heads, token_id + 1)
		}
	}

follow_head_path = |sentence_id, token_id, head, all_heads, visited|
	if head == 0 {
		Ok({})
	} else if contains_u64(visited, head) {
		Err(DependencyCycle(sentence_id, token_id, head))
	} else {
		next_head = head_at(all_heads, head, 1)?
		follow_head_path(sentence_id, token_id, next_head, all_heads, List.append(visited, head))
	}

head_at = |heads, target, current|
	match heads {
		[] => Err(MissingHeadTarget(target))
		[head, .. as rest] => if current == target Ok(head) else head_at(rest, target, current + 1)
	}

contains_u64 = |values, target|
	match values {
		[] => Bool.False
		[value, .. as rest] => if value == target Bool.True else contains_u64(rest, target)
	}

safe_comment_value = |value|
	value != "" and !Str.contains(value, "\n") and !Str.contains(value, "\r") and !Str.contains(value, "\t")

safe_column = |value|
	safe_comment_value(value) and !Str.contains(value, " ")

safe_misc_value = |value|
	safe_column(value) and !Str.contains(value, "|") and !Str.contains(value, "=")

source_misc = |word, gloss| {
	if !safe_misc_value(word.reference) and word.reference != "" {
		Err(UnsafeSourceMetadata(word.source_id, "reference"))
	} else {
		fields = List.concat(["gloss=${gloss}"], if word.reference == "" [] else ["Ref=${word.reference}"])
		Ok(Str.join_with(fields, "|"))
	}
}

serialize_sentence = |source, prose, literal, rows| {
	first = first_source_word(source.overt_words)
	citation_comment = if first.reference == "" "" else "# citation = ${first.reference}\n"
	speaker_comment = if first.speaker == "" "" else "# speaker = ${first.speaker}\n"
	Str.join_with(
		[
			"# sentence_id = ${source.source_sentence_id}\n",
			"# source_document_id = ${source.document_id}\n",
			citation_comment,
			speaker_comment,
			"# translation_lang = en\n",
			"# prose_translation = ${prose}\n",
			"# literal_translation = ${literal}\n",
			Str.join_with(rows, "\n"),
			"\n\n",
		],
		"",
	)
}

first_source_word = |words|
	match words {
		[word, ..] => word
		[] => { form: "", reference: "", source_id: "", speaker: "" }
	}

validation_error_text = |error|
	match error {
		DependencyCycle(sentence_id, token_id, head) => "sentence ${sentence_id} token ${U64.to_str(token_id)} enters a dependency cycle at token ${U64.to_str(head)}"
		HeadOutOfBounds(sentence_id, token_id, head, count) => "sentence ${sentence_id} token ${U64.to_str(token_id)} has HEAD ${U64.to_str(head)} outside 0..${U64.to_str(count)}"
		IncompleteFinish(finish_reason) => "finish reason was ${finish_reason}, not stop"
		InternalSentenceLengthMismatch => "source and response sentence lengths diverged during validation"
		InternalTokenLengthMismatch(sentence_id) => "source and response token lengths diverged in sentence ${sentence_id}"
		InvalidContentJson => "assistant content was not the required structured JSON object"
		InvalidResponseEnvelope => "captured response was not the required PPQ completion envelope"
		MissingHeadTarget(token_id) => "dependency validation could not resolve token ${U64.to_str(token_id)}"
		MissingResponseChoice => "captured response contained no completion choice"
		RootRelationMismatch(sentence_id, token_id) => "sentence ${sentence_id} token ${U64.to_str(token_id)} has inconsistent HEAD 0 and root relation"
		SelfHead(sentence_id, token_id) => "sentence ${sentence_id} token ${U64.to_str(token_id)} is its own head"
		UnsafeSourceMetadata(token_id, field) => "source token ${token_id} has unsafe ${field} metadata"
		UnsafeTokenField(sentence_id, token_id, field) => "sentence ${sentence_id} token ${U64.to_str(token_id)} has an empty or unsafe ${field} field"
		UnsafeTranslation(sentence_id, field) => "sentence ${sentence_id} has an empty or unsafe ${field}"
		WrongRootCount(sentence_id, count) => "sentence ${sentence_id} has ${U64.to_str(count)} roots; expected exactly one"
		WrongSentenceCount(expected, actual) => "expected ${U64.to_str(expected)} sentences but received ${U64.to_str(actual)}"
		WrongSentenceId(expected, actual) => "expected source sentence ID ${expected} but received ${actual}"
		WrongTokenCount(sentence_id, expected, actual) => "sentence ${sentence_id} expected ${U64.to_str(expected)} tokens but received ${U64.to_str(actual)}"
		WrongTokenId(sentence_id, expected, actual) => "sentence ${sentence_id} expected token ID ${U64.to_str(expected)} but received ${U64.to_str(actual)}"
	}

write_new_utf8! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? {
		Err(RefuseOverwrite(path))
	} else {
		Path.write_utf8!(roc_path, content)
	}
}

write_new_bytes! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? {
		Err(RefuseOverwrite(path))
	} else {
		Path.write_bytes!(roc_path, content)
	}
}

write_completion_marker! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? {
		existing = Path.read_utf8!(roc_path)?
		if existing == content Ok({}) else Err(StaleCompletionMarker(path))
	} else {
		Path.write_utf8!(roc_path, content)
	}
}

write_checkpoint! = |content, path| {
	roc_path = Path.utf8(path)
	if Path.exists!(roc_path)? {
		Err(RefuseOverwrite(path))
	} else {
		temporary = "${path}.tmp"
		_ = Path.write_utf8!(Path.utf8(temporary), content)?
		Path.rename!(Path.utf8(temporary), roc_path)
	}
}

write_output! = |content, path| {
	temporary = "${path}.tmp"
	_ = Path.write_utf8!(Path.utf8(temporary), content)?
	Path.rename!(Path.utf8(temporary), Path.utf8(path))
}

run_id_for = |timestamp, version| {
	compact = Str.replace_each(Str.replace_each(Utc.to_iso_8601(timestamp), "-", ""), ":", "")
	nanos = Utc.to_nanos_since_epoch(timestamp)

	"${compact}-${U128.to_str(nanos)}-v${U64.to_str(version)}"
}

work_name = |experiment_dir, path| {
	prefix = "${experiment_dir}/inputs/"
	relative = Str.replace_first(path, prefix, "")
	without_conllu = Str.replace_last(relative, ".conllu", "")
	Str.replace_last(without_conllu, ".xml", "")
}

compare_str = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if x < y Before else if x > y After else compare_bytes(xs, ys)
	}
