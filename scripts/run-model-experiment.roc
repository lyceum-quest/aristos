app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
}

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

Config : {
	experiment_name : Str,
	experiment_version : U64,
	generation : Generation,
	model : { id : Str },
	provider : { api_key_env : Str, base_url : Str, name : Str },
	validation : { max_attempts : U64 },
}

Token : { form : Str, id : Str, line : U64 }

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
		[experiment_name, "--resume", run_id] => resume_named_experiment!(experiment_name, run_id)
		_ => {
			_ = Stderr.line!("usage: run-model-experiment <experiment-name> [--check | --resume <run-id>]")?
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
		_ = run_inputs!(inputs, config, api_key, run_id, run_dir, experiment_dir, 0)?
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
	} else if !Path.exists!(Path.utf8(run_dir))? {
		Err(RunNotFound(run_dir))
	} else if !Str.ends_with(run_id, expected_suffix) {
		Err(RunVersionMismatch(run_id, config.experiment_version))
	} else {
		api_key = read_api_key!(config.provider.api_key_env)?
		inputs = discover_inputs!(experiment_dir)?
		_ = run_inputs!(inputs, config, api_key, run_id, run_dir, experiment_dir, 0)?
		_ = Stdout.line!("completed resumed run ${run_id}")?
		Ok({})
	}
}

experiment_dir_for = |experiment_name|
	if !valid_path_segment(experiment_name) {
		Err(InvalidExperimentName(experiment_name))
	} else {
		Ok("experiments/${experiment_name}")
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
				IsFile => if Str.ends_with(path, ".txt") List.append(found, path) else found
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
			tokens = tokenize_source(source)
			work = work_name(experiment_dir, path)
			if List.is_empty(tokens) {
				Err(NoTokens(path))
			} else {
				shards = shard_tokens(tokens, max_target_tokens)
				_ = build_shard_requests!(shards, config, work, source)?
				build_requests!(rest, config, experiment_dir)
			}
		}
	}

build_shard_requests! = |shards, config, work, source|
	match shards {
		[] => Ok({})
		[tokens, .. as rest] => {
			_ = request_body(config, work, source, tokens, "")?
			build_shard_requests!(rest, config, work, source)
		}
	}

run_inputs! = |inputs, config, api_key, run_id, run_dir, experiment_dir, failed|
	match inputs {
		[] => if failed == 0 Ok({}) else Err(RunInputsFailed(failed))
		[path, .. as rest] => {
			work = work_name(experiment_dir, path)
			marker_path = "${run_dir}/${work}.complete"
			if Path.exists!(Path.utf8(marker_path))? {
				_ = Stdout.line!("skipped completed input ${work}")?
				run_inputs!(rest, config, api_key, run_id, run_dir, experiment_dir, failed)
			} else {
				match run_input!(path, config, api_key, run_id, run_dir, experiment_dir) {
					Ok(_) => run_inputs!(rest, config, api_key, run_id, run_dir, experiment_dir, failed)
					Err(problem) => {
						_ = Stderr.line!("failed ${work}: ${Str.inspect(problem)}")?
						run_inputs!(rest, config, api_key, run_id, run_dir, experiment_dir, failed + 1)
					}
				}
			}
		}
	}

run_input! = |input_path, config, api_key, run_id, run_dir, experiment_dir| {
	work = work_name(experiment_dir, input_path)
	source = Path.read_utf8!(Path.utf8(input_path))?
	tokens = tokenize_source(source)

	if List.is_empty(tokens) {
		Err(NoTokens(input_path))
	} else {
		shards = shard_tokens(tokens, max_target_tokens)
		shard_count = List.len(shards)
		rendered = run_shards!(shards, work, source, config, api_key, run_id, run_dir, 1, shard_count, 0, "")?
		output_path = "${experiment_dir}/outputs/${work}.txt"
		marker_path = "${run_dir}/${work}.complete"
		_ = write_output!(rendered, output_path)?
		_ = write_new_utf8!("${output_path}\n", marker_path)?
		_ = Stdout.line!("completed input ${work}\t${output_path}")?
		Ok({})
	}
}

run_shards! = |shards, work, source, config, api_key, run_id, run_dir, shard_index, shard_count, previous_line, rendered|
	match shards {
		[] => Ok(rendered)
		[tokens, .. as rest] => {
			shard_output_path = "${run_dir}/${work}.shard-${U64.to_str(shard_index)}-of-${U64.to_str(shard_count)}.output.txt"
			shard_output = if Path.exists!(Path.utf8(shard_output_path))? {
				_ = Stdout.line!("skipped completed shard ${work} ${U64.to_str(shard_index)}/${U64.to_str(shard_count)}")?
				Path.read_utf8!(Path.utf8(shard_output_path))?
			} else {
				generated = run_attempt!(
					work,
					source,
					tokens,
					config,
					api_key,
					run_id,
					run_dir,
					shard_index,
					shard_count,
					1,
					"",
				)?
				_ = write_new_utf8!(generated, shard_output_path)?
				generated
			}
			first_line = first_token_line(tokens)
			separator = if rendered == "" or first_line == previous_line "" else "\n"
			next_rendered = "${rendered}${separator}${shard_output}"
			run_shards!(
				rest,
				work,
				source,
				config,
				api_key,
				run_id,
				run_dir,
				shard_index + 1,
				shard_count,
				last_token_line(tokens, first_line),
				next_rendered,
			)
		}
	}

run_attempt! = |work, source, tokens, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, feedback| {
	body = request_body(config, work, source, tokens, feedback)?
	captured = send_transport_attempt!(
		work,
		tokens,
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
	outcome = process_completion!(work, tokens, run_id, shard_index, shard_count, attempt, body, captured)?

	match outcome {
		Accepted(glosses) => Ok(glosses)
		Rejected(error_text) => {
			_ = Stdout.line!("rejected ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} attempt ${U64.to_str(attempt)}: ${error_text}")?
			if attempt < config.validation.max_attempts {
				run_attempt!(
					work,
					source,
					tokens,
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

send_transport_attempt! = |work, tokens, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body, transport_attempt| {
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
				delay_ms = backoff_ms(transport_base_delay_ms, transport_attempt)
				_ = Stdout.line!("retrying transport for ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} after ${U64.to_str(delay_ms)} ms: ${error_text}")?
				Sleep.millis!(delay_ms)
				send_transport_attempt!(work, tokens, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body, transport_attempt + 1)
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
					fallback = backoff_ms(transport_base_delay_ms, transport_attempt)
					delay_ms = retry_after_ms(headers, fallback)
					_ = Stdout.line!("retrying transport for ${work} shard ${U64.to_str(shard_index)}/${U64.to_str(shard_count)} after ${U64.to_str(delay_ms)} ms: ${error_text}")?
					Sleep.millis!(delay_ms)
					send_transport_attempt!(work, tokens, config, api_key, run_id, run_dir, shard_index, shard_count, attempt, body, transport_attempt + 1)
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

process_completion! = |work, tokens, run_id, shard_index, shard_count, attempt, body, captured| {
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
						validate_content(choice.message.content, tokens)
					}

					match validation {
						Ok(glosses) => {
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
							Ok(Accepted(glosses))
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

max_target_tokens : U64
max_target_tokens = 64

max_transport_attempts : U64
max_transport_attempts = 5

transport_base_delay_ms : U64
transport_base_delay_ms = 10000

is_transient_status = |status| status == 408 or status == 429 or status == 499 or status >= 500

backoff_ms = |base_delay_ms, attempt|
	if attempt <= 1 base_delay_ms else backoff_ms(base_delay_ms * 2, attempt - 1)

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
	decoded = Json.parse(body)
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

request_body = |config, _work, source, tokens, feedback| {
	system_prompt = "Produce concise contextual English word glosses for Ancient Greek tokens. Return only the requested compact JSON without indentation or insignificant whitespace. Do not return Greek text, lemmas, morphology, commentary, or a prose translation."
	token_table = Str.join_with(List.map(tokens, |token| "${token.id} | ${U64.to_str(token.line)} | ${token.form}"), "\n")
	retry_instruction = if feedback == "" {
		""
	} else {
		"RETRY: The previous captured response was rejected: ${feedback}\nCorrect that structural error."
	}
	user_prompt = Str.join_with(
		[
			"Return a JSON object with glosses.",
			"Return exactly one glosses array item for every target token, in the listed order.",
			"Each item must contain exactly id and gloss. Copy each listed ID exactly; supply only its concise contextual English gloss.",
			"Glosses may contain spaces but must be nonempty and must not contain line breaks or the <=> delimiter.",
			"Serialize the entire JSON object on one line with no indentation or insignificant whitespace.",
			retry_instruction,
			"",
			"SOURCE CONTEXT:",
			source,
			"TARGET TOKENS (id | source line | immutable Greek form):",
			token_table,
		],
		"\n",
	)

	generation : Generation
	generation = config.generation
	model_id : Str
	model_id = config.model.id
	token_count = List.len(tokens)
	token_ids = List.map(tokens, |token| token.id)
	response_format = {
		json_schema: {
			name: "contextual_glosses",
			schema: {
				additionalProperties: Bool.False,
				properties: {
					glosses: {
						items: {
							additionalProperties: Bool.False,
							properties: {
								gloss: { type: "string" },
								id: { enum: token_ids, type: "string" },
							},
							required: ["id", "gloss"],
							type: "object",
						},
						maxItems: token_count,
						minItems: token_count,
						type: "array",
					},
				},
				required: ["glosses"],
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

validate_content = |content, tokens| {
	decoded : Try({ glosses : List({ gloss : Str, id : Str }) }, _)
	decoded = Json.parse(content)
	match decoded {
		Ok(payload) =>
			if List.len(payload.glosses) != List.len(tokens) {
				Err(WrongGlossCount(List.len(tokens), List.len(payload.glosses)))
			} else {
				validate_glosses(tokens, payload.glosses, 0, [])
			}
		Err(_) => Err(InvalidContentJson)
	}
}

validate_glosses = |tokens, glosses, previous_line, rendered_lines|
	match (tokens, glosses) {
		([], []) => Ok("${Str.join_with(rendered_lines, "\n")}\n")
		([token, .. as rest_tokens], [entry, .. as rest_glosses]) => {
			gloss = Str.trim(entry.gloss)
			if entry.id != token.id {
				Err(WrongGlossId(token.id, entry.id))
			} else if gloss == "" {
				Err(EmptyGloss(token.id))
			} else if Str.contains(gloss, "\n") or Str.contains(gloss, "\r") or Str.contains(gloss, "<=>") {
				Err(UnsafeGloss(token.id))
			} else {
				line = "${token.form} <=> ${gloss}"
				next_lines = if previous_line == 0 or previous_line == token.line {
					List.append(rendered_lines, line)
				} else {
					List.append(List.append(rendered_lines, ""), line)
				}
				validate_glosses(rest_tokens, rest_glosses, token.line, next_lines)
			}
		}
		_ => Err(InternalGlossLengthMismatch)
	}

validation_error_text = |error|
	match error {
		EmptyGloss(token_id) => "empty gloss for token ${token_id}"
		IncompleteFinish(finish_reason) => "finish reason was ${finish_reason}, not stop"
		InternalGlossLengthMismatch => "token and gloss lengths diverged during validation"
		InvalidContentJson => "assistant content was not the required JSON object"
		InvalidResponseEnvelope => "captured response was not the required PPQ completion envelope"
		MissingResponseChoice => "captured response contained no completion choice"
		UnsafeGloss(token_id) => "gloss for token ${token_id} contained a line break or <=> delimiter"
		WrongGlossCount(expected, actual) => "expected ${U64.to_str(expected)} glosses but received ${U64.to_str(actual)}"
		WrongGlossId(expected, actual) => "expected token ID ${expected} but received ${actual}"
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

first_token_line = |tokens|
	match tokens {
		[token, ..] => token.line
		[] => 0
	}

last_token_line = |tokens, found|
	match tokens {
		[] => found
		[token, .. as rest] => last_token_line(rest, token.line)
	}

tokenize_source = |source| {
	normalized = Str.replace_each(Str.replace_each(source, "\r\n", "\n"), "\t", " ")
	tokenize_lines(Str.split_on(normalized, "\n"), 1, 1, []).tokens
}

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
