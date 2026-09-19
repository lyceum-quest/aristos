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
	allow_fallbacks : Bool,
	frequency_penalty : Dec,
	include_reasoning : Bool,
	max_tokens : U64,
	presence_penalty : Dec,
	profile : Str,
	reasoning : { enabled : Bool, exclude : Bool },
	require_parameters : Bool,
	seed : U64,
	temperature : Dec,
	top_k : U64,
	top_p : Dec,
}

Transport : { backoff_initial_ms : U64, backoff_max_ms : U64, max_retries : U64, max_retry_after_ms : U64 }
ProviderVariant : { id : Str, request_name : Str, response_name : Str }

Config : {
	candidates : {
		generation : Generation,
		model : { id : Str },
		provider : { api_key_env : Str, base_url : Str, name : Str },
		providers : List(ProviderVariant),
		transport : Transport,
		validation : { max_attempts : U64 },
	},
	execution : { candidate_count : U64, target_token_count : U64 },
	experiment_name : Str,
	experiment_version : U64,
	input : { source_path : Str, source_sha256 : Str },
	oga : { corpus : Str, local_context_radius : U64, source_path : Str, source_sha256 : Str },
	policy : { default_path : Str },
	selector : {
		input_cost_per_million_tokens_usd : Dec,
		model : { id : Str },
		provider : { api_key_env : Str, endpoint : Str, name : Str },
		transport : Transport,
		validation : { max_attempts : U64 },
	},
}

Token : { form : Str, id : Str, line : U64 }
Evidence : {
	corpus : Str,
	deprel : Str,
	feats : Str,
	form : Str,
	head : U64,
	lemma : Str,
	row_id : Str,
	source_path : Str,
	source_sha256 : Str,
	xpos : Str,
}
Target : { evidence : Evidence, form : Str, id : Str, line : U64, local_context : Str, source_line : Str }
OgaRow : { deprel : Str, feats : Str, form : Str, head : U64, misc : Str, xpos : Str, lemma : Str }

Candidate : {
	candidate_index : U64,
	contextual_interpretation : Str,
	evidence_refs : List(Str),
	gloss : Str,
	rationale : Str,
	role : Str,
}
CandidateRow : { candidates : List(Candidate), id : Str }
CandidatePayload : { tokens : List(CandidateRow) }

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
JevAnswer : { noul : Dec, type : Str }
JevResponse : { answers : Dict(Str, JevAnswer), model : Str, usage : { input_tokens : U64, output_tokens : U64 } }

Usage : { input_tokens : U64, output_tokens : U64, reasoning_tokens : U64, total_tokens : U64 }

Accounting : {
	ambiguous_possible_charge_attempts : U64,
	ambiguous_possible_cost_usd : Dec,
	known_charged_attempts : U64,
	known_charged_cost_usd : Dec,
	transport_attempts : U64,
	validation_attempts : U64,
}

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
	accounting : Accounting,
	call : CallAudit,
	candidates : List(CandidateRow),
	experiment_version : U64,
	provider_id : Str,
	run_id : Str,
	source_path : Str,
	target_count : U64,
	work : Str,
}

TargetState : {
	candidates : List({ candidate_index : U64, contextual_interpretation : Str, display_gloss : Str, evidence_refs : List(Str), generated_claims_notice : Str, gloss : Str, rationale : Str, role : Str }),
	evidence : Evidence,
	form : Str,
	id : Str,
	line : U64,
	local_context : Str,
	source_line : Str,
}
JevQuestion : { criteria : { false : Str, true : Str }, instructions : Str, type : Str }

TokenAudit : {
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

RunAudit : {
	accounting : { candidates : Accounting, selector : Accounting, total : Accounting },
	candidate_call : CallAudit,
	experiment_version : U64,
	provider_id : Str,
	run_id : Str,
	selector_call : CallAudit,
	source_path : Str,
	token_audits : List(TokenAudit),
	work : Str,
}

Manifest : { experiment_version : U64, mode : Str, provider_id : Str, run_id : Str }
Policy : { human_calibrated : Bool, minimum_margin : Dec, minimum_probability : Dec, no_valid_candidate_below_probability : Dec, policy_id : Str }
ReplayAudit : { experiment_version : U64, provider_id : Str, token_audits : List(TokenAudit) }

AttemptRecord : {
	accounting_after_attempt : Accounting,
	ambiguous_possible_charge : Bool,
	client_request_id : Str,
	cost_usd : Dec,
	elapsed_ms : U128,
	headers_path : Str,
	http_status : U16,
	provider_id : Str,
	provider_request_id : Str,
	raw_response_path : Str,
	received_at : Str,
	request_path : Str,
	requested_at : Str,
	retry_delay_ms : U64,
	run_id : Str,
	stage : Str,
	status : Str,
	transport : Str,
	transport_attempt : U64,
	transport_output_path : Str,
	validation_attempt : U64,
	validation_error : Str,
	work : Str,
}

CurlOutputRecord : { exit_code : Str, http_status : U16, stderr : Str, stdout : Str }
HeaderRecord : { name : Str, value : Str }

experiment_dir = "experiments/gloss/deepseek-v4-flash-0731/experiment_4"
input_path = "experiments/gloss/deepseek-v4-flash-0731/experiment_4/inputs/iliad-1.1-20.txt"
input_sha256 = "1263ac162eea8365bd04261361668fab579c2f97299ac0a8b4429f7f33133807"
work_name = "iliad-1.1-20"

oga_evidence_legend = \\
	\\OGA v0.2.0 FEATS codes used here: Case a=accusative, d=dative, g=genitive, n=nominative, v=vocative; Gender f=feminine, m=masculine, n=neuter; Number d=dual, p=plural, s=singular; Mood i=indicative, m=imperative, p=participle; Tense a=aorist, i=imperfect, p=present; Voice a=active, e=medio-passive. Person is numeric.
	\\OGA dependency labels used here: OBJ=object, SBJ=subject, ATR=attributive, ADV=adverbial, PRED=predicate, OCOMP=object complement, COORD=coordination, AuxP=preposition, AuxY=particle, ExD=external/discourse. HEAD is a sentence-local OGA row ID, not an experiment token ID.

main! = |args| {
	displayed = List.map(args, OsStr.display)
	match List.drop_first(displayed, 1) {
		["--check"] => check_experiment!()
		["--construct"] => construct_experiment!()
		["--candidates-openinference"] => start_candidates_only!("openinference")
		["--candidates-sail-research"] => start_candidates_only!("sail-research")
		["--smoke-openinference"] => start_run!("smoke", "openinference")
		["--smoke-sail-research"] => start_run!("smoke", "sail-research")
		["--run-openinference"] => start_run!("full", "openinference")
		["--run-sail-research"] => start_run!("full", "sail-research")
		["--resume-openinference"] => resume_run!("full", "openinference")
		["--resume-sail-research"] => resume_run!("full", "sail-research")
		["--resume-smoke-openinference"] => resume_run!("smoke", "openinference")
		["--resume-smoke-sail-research"] => resume_run!("smoke", "sail-research")
		["--replay-latest-openinference"] => replay_latest_policy!("openinference")
		["--replay-latest-sail-research"] => replay_latest_policy!("sail-research")
		["--replay-policy", audit_path] => replay_policy!(audit_path, "")
		["--replay-policy", audit_path, policy_path] => replay_policy!(audit_path, policy_path)
		_ => {
			_ = Stderr.line!("usage: run-jev-gloss-experiment-4 [--check | --construct | --candidates-openinference | --candidates-sail-research | --smoke-openinference | --smoke-sail-research | --run-openinference | --run-sail-research | --resume-openinference | --resume-sail-research | --resume-smoke-openinference | --resume-smoke-sail-research | --replay-latest-openinference | --replay-latest-sail-research | --replay-policy <audit.json> [policy.json]]")?
			Err(Exit(2))
		}
	}
}

check_experiment! = || {
	prepared = prepare_experiment!()?
	open = provider_by_id(prepared.config.candidates.providers, "openinference")?
	sail = provider_by_id(prepared.config.candidates.providers, "sail-research")?
	open_body = candidate_request_body(prepared.config, open, prepared.source, prepared.target_rows, "")?
	sail_body = candidate_request_body(prepared.config, sail, prepared.source, prepared.target_rows, "")?
	_ = assert_provider_only_difference(open_body, sail_body)?
	fake = fake_candidates(prepared.target_rows)
	validated = validate_candidates(prepared.target_rows, fake)?
	_ = require_malformed_text("candidate embeds [uNrEsOlVeD] marker")?
	_ = jev_request_body(prepared.config, prepared.source, prepared.target_rows, validated, "")?
	_ = Stdout.line!("checked experiment 4: pinned input and OGA hashes, 50 aligned lexical targets, comparable provider requests, and 150 Noul questions; no API keys read and no requests sent")?
	Ok({})
}

construct_experiment! = || {
	prepared = prepare_experiment!()?
	open = provider_by_id(prepared.config.candidates.providers, "openinference")?
	sail = provider_by_id(prepared.config.candidates.providers, "sail-research")?
	open_body = candidate_request_body(prepared.config, open, prepared.source, prepared.target_rows, "")?
	sail_body = candidate_request_body(prepared.config, sail, prepared.source, prepared.target_rows, "")?
	_ = assert_provider_only_difference(open_body, sail_body)?
	fake = validate_candidates(prepared.target_rows, fake_candidates(prepared.target_rows))?
	fixture_notice = "SYNTHETIC FIXTURE — NO SPEND — NOT FOR SUBMISSION"
	jev_body = jev_request_body(prepared.config, prepared.source, prepared.target_rows, fake, fixture_notice)?
	root = "${experiment_dir}/constructed"
	_ = Path.create_all!(Path.utf8(root))?
	_ = write_atomic_or_verify!("${open_body}\n", "${root}/openinference.candidates.request.json")?
	_ = write_atomic_or_verify!("${sail_body}\n", "${root}/sail-research.candidates.request.json")?
	_ = write_atomic_or_verify!("${jev_body}\n", "${root}/jev.noul.synthetic-fixture.request.json")?
	_ = Stdout.line!("constructed deterministic experiment 4 request previews and synthetic Jev fixture; no API keys read and no requests sent; fixture is not for submission")?
	Ok({})
}

prepare_experiment! = || {
	config = read_config!()?
	_ = validate_config(config)?
	_ = verify_sha256!(config.input.source_path, config.input.source_sha256, |expected, actual| InputSha256Mismatch(expected, actual))?
	source = Path.read_utf8!(Path.utf8(config.input.source_path))?
	_ = validate_source(source)?
	all_tokens = tokenize_source(source)
	tokens = take_exact(all_tokens, config.execution.target_token_count, [])?
	rows = read_oga_rows!(config)?
	target_rows = align_targets(tokens, rows, source, config, all_tokens, 0, [])?
	Ok({ config, source, target_rows })
}

read_config! = || {
	raw = Path.read_utf8!(Path.utf8("${experiment_dir}/config.json"))?
	config : Config
	config = Json.parse(raw)?
	Ok(config)
}

validate_config = |config| {
	g = config.candidates.generation
	if config.experiment_name != "deepseek-v4-flash-0731-jev-gloss" or config.experiment_version != 4 {
		Err(InvalidExperimentIdentity)
	} else if config.input.source_path != input_path or config.input.source_sha256 != input_sha256 {
		Err(InvalidInputPins)
	} else if config.execution.candidate_count != 3 or config.execution.target_token_count != 50 {
		Err(InvalidExecutionPins)
	} else if config.candidates.provider.name != "ppq" or config.candidates.provider.base_url != "https://api.ppq.ai/v1" or config.candidates.provider.api_key_env != "PPQ_API_KEY" {
		Err(InvalidCandidateProviderPins)
	} else if config.candidates.model.id != "deepseek/deepseek-v4-flash-0731" {
		Err(InvalidCandidateModelPin)
	} else if g.profile != "full-sampling" or g.temperature != 1 or g.top_p != 1 or g.top_k != 0 or g.seed != 1 or g.max_tokens != 16384 or g.frequency_penalty != 0 or g.presence_penalty != 0 {
		Err(InvalidSamplingPins)
	} else if g.reasoning.enabled or !g.reasoning.exclude or g.include_reasoning or !g.require_parameters or g.allow_fallbacks {
		Err(InvalidGenerationPins)
	} else if config.candidates.validation.max_attempts != 2 or config.selector.validation.max_attempts != 2 {
		Err(InvalidValidationPins)
	} else if config.candidates.transport != config.selector.transport or config.selector.transport.max_retries != 2 or config.selector.transport.backoff_initial_ms != 500 or config.selector.transport.backoff_max_ms != 5000 or config.selector.transport.max_retry_after_ms != 60000 {
		Err(InvalidTransportPins)
	} else if config.candidates.providers != [
		{ id: "openinference", request_name: "OpenInference", response_name: "OpenInference" },
		{ id: "sail-research", request_name: "sail-research", response_name: "Sail Research" },
	] {
		Err(InvalidComparableProviderPins)
	} else if config.selector.provider.name != "typesafe" or config.selector.provider.endpoint != "https://api.typesafe.ai/v1/systemone" or config.selector.provider.api_key_env != "TYPESAFE_API_KEY" or config.selector.model.id != "jev-1.13.0" or config.selector.input_cost_per_million_tokens_usd != 0.042 {
		Err(InvalidSelectorPins)
	} else if config.oga.corpus != "oga-v0.2.0-corpus" or config.oga.source_sha256 != "59eea57f7017610dd10bf47a1dcbcd3f9cc7035eb8b491893a82c2dd7695c530" or config.oga.local_context_radius != 3 {
		Err(InvalidOgaPins)
	} else {
		Ok({})
	}
}

provider_by_id = |providers, wanted|
	match providers {
		[] => Err(UnknownProvider(wanted))
		[first, .. as rest] => if first.id == wanted Ok(first) else provider_by_id(rest, wanted)
	}

validate_source = |source|
	if Str.trim(source) == "" or Str.contains(source, "\r") or Str.contains(source, "\t") {
		Err(InvalidSource)
	} else {
		Ok({})
	}

tokenize_source = |source| tokenize_lines(Str.split_on(source, "\n"), 1, 1, []).tokens

tokenize_lines = |lines, line_number, next_id, found|
	match lines {
		[] => { next_id, tokens: found }
		[line, .. as rest] => {
			words = List.keep_if(Str.split_on(line, " "), |word| word != "")
			result = tokenize_words(words, line_number, next_id, found)
			tokenize_lines(rest, line_number + 1, result.next_id, result.tokens)
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

take_exact = |items, count, found|
	if count == 0 {
		Ok(found)
	} else {
		match items {
			[] => Err(SourceHasFewerThanFiftyTokens)
			[first, .. as rest] => take_exact(rest, count - 1, List.append(found, first))
		}
	}

verify_sha256! = |path, expected, mismatch| {
	output = Cmd.new_str("sha256sum").args_str([path]).exec_output!()?
	actual = match Str.split_on(Str.trim(output.stdout_utf8), " ") {
		[hash, ..] => Ok(hash)
		[] => Err(InvalidSha256Output)
	}?
	if actual == expected Ok({}) else Err(mismatch(expected, actual))
}

read_oga_rows! = |config| {
	_ = verify_sha256!(config.oga.source_path, config.oga.source_sha256, |expected, actual| OgaSha256Mismatch(expected, actual))?
	source = Path.read_utf8!(Path.utf8(config.oga.source_path))?
	parse_oga_lines(Str.split_on(Str.replace_each(source, "\r\n", "\n"), "\n"), [])
}

parse_oga_lines = |lines, found|
	match lines {
		[] => Ok(found)
		[line, .. as rest] => {
			trimmed = Str.trim(line)
			if trimmed == "" or Str.starts_with(trimmed, "#") {
				parse_oga_lines(rest, found)
			} else {
				row = parse_oga_row(line)?
				next = if Str.starts_with(row.misc, "t_") and !Str.starts_with(row.xpos, "u") List.append(found, row) else found
				parse_oga_lines(rest, next)
			}
		}
	}

parse_oga_row = |line|
	match Str.split_on(line, "\t") {
		[_, form, lemma, _, xpos, feats, head_text, deprel, _, misc] => {
			head = U64.from_str(head_text) ? |_| InvalidOgaHead(head_text)
			row : OgaRow
			row = { deprel, feats, form, head, lemma, misc, xpos }
			Ok(row)
		}
		_ => Err(InvalidOgaRow(line))
	}

align_targets = |tokens, rows, source, config, all_tokens, target_index, found|
	match tokens {
		[] => Ok(found)
		[token, .. as rest_tokens] =>
			match rows {
				[] => Err(OgaRowsExhausted(token.id))
				[row, .. as rest_rows] => {
					stripped = strip_terminal_punctuation(token.form)
					if stripped != row.form {
						Err(OgaFormMismatch(token.id, stripped, row.form, row.misc))
					} else {
						evidence : Evidence
						evidence = {
							corpus: config.oga.corpus,
							deprel: row.deprel,
							feats: row.feats,
							form: row.form,
							head: row.head,
							lemma: row.lemma,
							row_id: row.misc,
							source_path: config.oga.source_path,
							source_sha256: config.oga.source_sha256,
							xpos: row.xpos,
						}
						target : Target
						target = {
							evidence,
							form: token.form,
							id: token.id,
							line: token.line,
							local_context: context_window(all_tokens, target_index, config.oga.local_context_radius),
							source_line: source_line_at(source, token.line),
						}
						align_targets(rest_tokens, rest_rows, source, config, all_tokens, target_index + 1, List.append(found, target))
					}
				}
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

strip_terminal_punctuation = |form| {
	stripped = strip_one_terminal(form)
	if stripped == form form else strip_terminal_punctuation(stripped)
}

strip_one_terminal = |form|
	if Str.ends_with(form, ",") {
		Str.replace_last(form, ",", "")
	} else if Str.ends_with(form, ".") {
		Str.replace_last(form, ".", "")
	} else if Str.ends_with(form, ";") {
		Str.replace_last(form, ";", "")
	} else if Str.ends_with(form, "·") {
		Str.replace_last(form, "·", "")
	} else if Str.ends_with(form, "·") {
		Str.replace_last(form, "·", "")
	} else if Str.ends_with(form, ":") {
		Str.replace_last(form, ":", "")
	} else if Str.ends_with(form, "!") {
		Str.replace_last(form, "!", "")
	} else if Str.ends_with(form, "?") {
		Str.replace_last(form, "?", "")
	} else {
		form
	}

candidate_request_body = |config, provider, source, target_rows, feedback| {
	g : Generation
	g = config.candidates.generation
	model_id : Str
	model_id = config.candidates.model.id
	provider_request_name : Str
	provider_request_name = provider.request_name
	system_prompt = \\
		\\Act as an Ancient Greek philologist. Return only strict JSON containing independently inspectable contextual gloss candidates.
		\\OGA fields are corpus evidence, not generated claims. Your contextual_interpretation and rationale are generated claims and must remain separate from evidence_refs.
	instructions = \\
		\\For every target, produce exactly three candidates in order. candidate_index 1 has role primary-baseline. Indices 2 and 3 have role alternative and must each encode a genuinely contrastive grammatical or contextual interpretation, not a synonym, spelling variant, punctuation variant, or shallow canonical variant of another candidate.
		\\Each gloss must be natural English for the inflected token in context. It may contain spaces; do not pre-format it for display. Do not use apostrophe possessives. contextual_interpretation and rationale must be substantive and specific. evidence_refs must cite one or both exact IDs supplied for that target: its oga:t_N row and source:line:N. Do not treat generated claims as corpus evidence.
		\\A gloss must not begin or end with punctuation or a hyphen and must not contain tabs, line breaks, <=>, or [UNRESOLVED]. Copy IDs exactly, preserve target order, and omit nothing.
	retry = if feedback == "" "" else "RETRY: The previous response failed the fixed schema or deterministic validation. Regenerate every row from the unchanged source and evidence, obeying all original constraints. Do not repeat or discuss the invalid response."
	table = Str.join_with(List.map(target_rows, render_candidate_target), "\n")
	user_prompt = Str.join_with([instructions, retry, "", "COMPLETE ILIAD SOURCE PASSAGE (audit and context; only listed targets are in scope):", source, "OGA EVIDENCE LEGEND (deterministic corpus-code interpretation, not a model claim):", oga_evidence_legend, "TARGETS (id | exact form | source line number | source line | local context | independent OGA evidence):", table], "\n")
	ids = List.map(target_rows, |target| target.id)
	one : U64
	one = 1
	two : U64
	two = 2
	three : U64
	three = 3
	count = List.len(target_rows)
	response_format = {
		json_schema: {
			name: "three_structured_contextual_gloss_candidates",
			schema: {
				additionalProperties: Bool.False,
				properties: {
					tokens: {
						items: {
							additionalProperties: Bool.False,
							properties: {
								candidates: {
									items: {
										additionalProperties: Bool.False,
										properties: {
											candidate_index: { maximum: three, minimum: one, type: "integer" },
											contextual_interpretation: { minLength: one, type: "string" },
											evidence_refs: { items: { minLength: one, type: "string" }, maxItems: two, minItems: one, type: "array" },
											gloss: { minLength: one, type: "string" },
											rationale: { minLength: one, type: "string" },
											role: { enum: ["primary-baseline", "alternative"], type: "string" },
										},
										required: ["candidate_index", "role", "gloss", "contextual_interpretation", "rationale", "evidence_refs"],
										type: "object",
									},
									maxItems: three,
									minItems: three,
									type: "array",
								},
								id: { enum: ids, type: "string" },
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

render_candidate_target = |target| {
	e = target.evidence
	"${target.id} | ${target.form} | ${U64.to_str(target.line)} | source:line:${U64.to_str(target.line)}=${target.source_line} | context=${target.local_context} | oga:${e.row_id}={form:${e.form},lemma:${e.lemma},xpos:${e.xpos},feats:${e.feats},head:${U64.to_str(e.head)},deprel:${e.deprel},corpus:${e.corpus},sha256:${e.source_sha256}}"
}

assert_provider_only_difference = |open, sail| {
	expected = Str.replace_first(open, "\"only\":[\"OpenInference\"]", "\"only\":[\"sail-research\"]")
	if open == sail or expected != sail {
		Err(ProviderRequestsNotComparable)
	} else {
		Ok({})
	}
}

validate_candidate_content = |content, target_rows| {
	payload : CandidatePayload
	payload = Json.parse(content) ? |_| InvalidCandidateJson
	validate_candidates(target_rows, payload.tokens)
}

validate_candidates = |target_rows, rows|
	if List.len(target_rows) != List.len(rows) {
		Err(WrongCandidateTargetCount(List.len(target_rows), List.len(rows)))
	} else {
		validate_candidate_rows(target_rows, rows, [])
	}

validate_candidate_rows = |target_rows, rows, found|
	match (target_rows, rows) {
		([], []) => Ok(found)
		([target, .. as rest_targets], [row, .. as rest_rows]) => {
			if target.id != row.id {
				Err(WrongCandidateId(target.id, row.id))
			} else {
				valid = validate_three_candidates(target, row.candidates)?
				validate_candidate_rows(rest_targets, rest_rows, List.append(found, { candidates: valid, id: row.id }))
			}
		}
		_ => Err(CandidateCoverageMismatch)
	}

validate_three_candidates = |target, candidates|
	match candidates {
		[a, b, c] => {
			_ = validate_candidate(target, a, 1, "primary-baseline")?
			_ = validate_candidate(target, b, 2, "alternative")?
			_ = validate_candidate(target, c, 3, "alternative")?
			if canonically_equal(a.gloss, b.gloss) or canonically_equal(a.gloss, c.gloss) or canonically_equal(b.gloss, c.gloss) {
				Err(DuplicateOrShallowGloss(target.id))
			} else if canonically_equal(a.contextual_interpretation, b.contextual_interpretation) or canonically_equal(a.contextual_interpretation, c.contextual_interpretation) or canonically_equal(b.contextual_interpretation, c.contextual_interpretation) {
				Err(MissingInterpretiveContrast(target.id))
			} else {
				Ok([a, b, c])
			}
		}
		_ => Err(WrongCandidateCount(target.id, List.len(candidates)))
	}

validate_candidate = |target, candidate, index, role| {
	gloss = Str.trim(candidate.gloss)
	interpretation = Str.trim(candidate.contextual_interpretation)
	rationale = Str.trim(candidate.rationale)
	if candidate.candidate_index != index or candidate.role != role {
		Err(InvalidCandidateIdentity(target.id, index))
	} else if gloss == "" or interpretation == "" or rationale == "" {
		Err(EmptyCandidateField(target.id, index))
	} else if malformed_text(gloss) or malformed_text(interpretation) or malformed_text(rationale) {
		Err(MalformedCandidateText(target.id, index))
	} else if has_apostrophe_possessive(gloss) {
		Err(ApostrophePossessive(target.id, index))
	} else if dangling_gloss(gloss) {
		Err(DanglingGlossPunctuation(target.id, index))
	} else if List.is_empty(candidate.evidence_refs) or List.len(candidate.evidence_refs) > 2 {
		Err(MissingEvidenceRefs(target.id, index))
	} else {
		validate_evidence_refs(candidate.evidence_refs, target, index, [])
	}
}

require_malformed_text = |value| if malformed_text(value) Ok({}) else Err(UnresolvedContainmentCheckFailed)

malformed_text = |value| {
	trimmed = Str.trim(value)
	Str.contains(trimmed, "\t") or Str.contains(trimmed, "\n") or Str.contains(trimmed, "\r") or Str.contains(trimmed, "<=>") or caseless_ascii_contains(trimmed, "[UNRESOLVED]")
}

caseless_ascii_contains = |value, needle| caseless_bytes_contains(Str.to_utf8(value), Str.to_utf8(needle))

caseless_bytes_contains = |remaining, needle|
	if caseless_bytes_start_with(remaining, needle) {
		Bool.True
	} else {
		match remaining {
			[] => Bool.False
			[_, .. as rest] => caseless_bytes_contains(rest, needle)
		}
	}

caseless_bytes_start_with = |remaining, needle|
	match needle {
		[] => Bool.True
		[expected, .. as rest_expected] =>
			match remaining {
				[] => Bool.False
				[actual, .. as rest_actual] => ascii_lower(actual) == ascii_lower(expected) and caseless_bytes_start_with(rest_actual, rest_expected)
			}
	}

ascii_lower = |byte| if byte >= 65 and byte <= 90 byte + 32 else byte

has_apostrophe_possessive = |value| Str.contains(value, "'s") or Str.contains(value, "'S") or Str.contains(value, "’s") or Str.contains(value, "’S") or Str.contains(value, "ʼs") or Str.contains(value, "ʼS") or Str.contains(value, "‘s") or Str.contains(value, "‘S")

dangling_gloss = |value| {
	trimmed = Str.trim(value)
	punctuation = ["-", ",", ".", ";", ":", "!", "?", "·", "·", "'", "’", "ʼ", "\"", "(", ")", "[", "]", "{", "}", "/", "—", "–"]
	List.any(punctuation, |mark| Str.starts_with(trimmed, mark) or Str.ends_with(trimmed, mark))
}

validate_evidence_refs = |refs, target, index, seen|
	match refs {
		[] => Ok({})
		[ref, .. as rest] => {
			oga_ref = "oga:${target.evidence.row_id}"
			source_ref = "source:line:${U64.to_str(target.line)}"
			if ref != oga_ref and ref != source_ref {
				Err(InvalidEvidenceRef(target.id, index, ref))
			} else if List.contains(seen, ref) {
				Err(DuplicateEvidenceRef(target.id, index, ref))
			} else {
				validate_evidence_refs(rest, target, index, List.append(seen, ref))
			}
		}
	}

canonical_value = |value| {
	without_ascii = Str.replace_each(Str.replace_each(Str.replace_each(Str.replace_each(Str.replace_each(Str.replace_each(Str.replace_each(Str.replace_each(Str.replace_each(Str.trim(value), " ", ""), "-", ""), "_", ""), ".", ""), ",", ""), ";", ""), ":", ""), "'", ""), "’", "")
	Str.replace_each(without_ascii, "ʼ", "")
}

canonically_equal = |left, right| Str.caseless_ascii_equals(canonical_value(left), canonical_value(right))

display_gloss = |value| collapse_display_parts(List.keep_if(Str.split_on(Str.trim(value), " "), |part| part != ""), "")

collapse_display_parts = |parts, found|
	match parts {
		[] => found
		[part, .. as rest] => collapse_display_parts(rest, if found == "" part else "${found}-${part}")
	}

fake_candidates = |target_rows|
	List.map(target_rows, |target| {
		id: target.id,
		candidates: [
			{ candidate_index: 1, contextual_interpretation: "baseline interpretation ${target.id}", evidence_refs: ["oga:${target.evidence.row_id}"], gloss: "baseline ${target.id}", rationale: "baseline rationale ${target.id}", role: "primary-baseline" },
			{ candidate_index: 2, contextual_interpretation: "alternative grammatical interpretation ${target.id}", evidence_refs: ["source:line:${U64.to_str(target.line)}"], gloss: "alternative two ${target.id}", rationale: "second rationale ${target.id}", role: "alternative" },
			{ candidate_index: 3, contextual_interpretation: "alternative contextual interpretation ${target.id}", evidence_refs: ["oga:${target.evidence.row_id}", "source:line:${U64.to_str(target.line)}"], gloss: "alternative three ${target.id}", rationale: "third rationale ${target.id}", role: "alternative" },
		],
	})

jev_request_body = |config, source, target_rows, rows, fixture_notice| {
	source_text : Str
	source_text = source
	is_fixture = fixture_notice != ""
	notice : Str
	notice = if is_fixture fixture_notice else "LIVE REQUEST STATE — generated claims remain separate from OGA evidence"
	generated_notice = if is_fixture "SYNTHETIC FIXTURE generated claims — NO SPEND — NOT FOR SUBMISSION; not OGA evidence" else "contextual_interpretation and rationale are generated claims, not OGA evidence"
	task = if is_fixture "SYNTHETIC FIXTURE TASK — NO SPEND — NOT FOR SUBMISSION. Demonstrates independent candidate validity questions only; do not submit this fixture." else "Independently judge whether each exact generated candidate is a valid contextual English gloss. OGA morphology and dependency fields are external corpus evidence; candidate interpretation and rationale are model-generated claims. Do not rank candidates and do not infer a policy threshold."
	state = {
		evidence_legend: oga_evidence_legend,
		notice,
		source_passage: source_text,
		target_records: state_targets(target_rows, rows, generated_notice, []),
		task,
	}
	model_json = Json.to_str_try(config.selector.model.id)?
	raw_state_json = Json.to_str_try(state)?
	state_json = Str.replace_first(raw_state_json, "\"target_records\":", "\"targets\":")
	questions = jev_question_entries(target_rows, rows, 0, [])?
	Ok("{\"model\":${model_json},\"questions\":{${Str.join_with(questions, ",")}},\"state\":${state_json}}")
}

state_targets = |target_rows, rows, generated_notice, found|
	match (target_rows, rows) {
		([], []) => found
		([target, .. as rest_targets], [row, .. as rest_rows]) => {
			state_target : TargetState
			state_target = {
				candidates: List.map(row.candidates, |candidate| {
					candidate_index: candidate.candidate_index,
					contextual_interpretation: candidate.contextual_interpretation,
					display_gloss: display_gloss(candidate.gloss),
					evidence_refs: candidate.evidence_refs,
					generated_claims_notice: generated_notice,
					gloss: candidate.gloss,
					rationale: candidate.rationale,
					role: candidate.role,
				}),
				evidence: target.evidence,
				form: target.form,
				id: target.id,
				line: target.line,
				local_context: target.local_context,
				source_line: target.source_line,
			}
			state_targets(rest_targets, rest_rows, generated_notice, List.append(found, state_target))
		}
		_ => found
	}

jev_question_entries = |target_rows, rows, target_index, found|
	match (target_rows, rows) {
		([], []) => Ok(found)
		([target, .. as rest_targets], [row, .. as rest_rows]) => {
			entries = candidate_question_entries(target, row.candidates, target_index, 0, [])?
			jev_question_entries(rest_targets, rest_rows, target_index + 1, List.concat(found, entries))
		}
		_ => Err(JevQuestionCoverageMismatch)
	}

candidate_question_entries = |target, candidates, target_index, candidate_index, found|
	match candidates {
		[] => Ok(found)
		[candidate, .. as rest] => {
			path = "targets[${U64.to_str(target_index)}].candidates[${U64.to_str(candidate_index)}]"
			question : JevQuestion
			question = {
				criteria: {
					true: "True only if the candidate is a natural contextual gloss of this exact token: its morphology agrees with the target OGA evidence, its syntactic function is represented when English requires it, its sense fits the complete and local context, and using it would not produce a phrase-level mistranslation.",
					false: "False if the candidate conflicts with the target morphology or syntax, fits a different occurrence or sense, is unnatural as an English token gloss, ignores decisive context, or would create a phrase-level mistranslation.",
				},
				instructions: "Is the candidate at `${path}` a valid contextual gloss for the exact token record at `targets[${U64.to_str(target_index)}]`? Judge only this candidate independently. Use that target's form, source line, local context, and evidence; use `source_passage` only when long-range context is needed. Treat `targets[${U64.to_str(target_index)}].evidence` and `evidence_legend` as corpus-derived evidence, and the candidate interpretation/rationale as generated claims.",
				type: "noul",
			}
			key = question_key(target.id, candidate.candidate_index)
			key_json = Json.to_str_try(key)?
			question_json = Json.to_str_try(question)?
			candidate_question_entries(target, rest, target_index, candidate_index + 1, List.append(found, "${key_json}:${question_json}"))
		}
	}

question_key = |token_id, candidate_index| "token_${token_id}_candidate_${U64.to_str(candidate_index)}"

start_candidates_only! = |provider_id| {
	prepared = prepare_experiment!()?
	provider = provider_by_id(prepared.config.candidates.providers, provider_id)?
	api_key = read_key!(prepared.config.candidates.provider.api_key_env)?
	started = Utc.now!()
	run_id = "smoke-${provider_id}-${run_id_for(started, prepared.config.experiment_version)}"
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/smoke/${provider_id}/${run_id}"
	_ = create_run!(run_id, run_dir, output_dir, "smoke", provider_id, prepared.config)?
	_checkpoint = run_candidate_attempt!(prepared, provider, api_key, run_id, run_dir, 1, 1, empty_accounting, "", Bool.False)?
	_ = Stdout.line!("completed paid candidate generation only; Jev was not called\t${run_id}")?
	_ = Stdout.line!("resume this provider's latest smoke after authorization to reuse checkpoint\t${run_dir}/${work_name}.candidates.json")?
	Ok({})
}

start_run! = |mode, provider_id| {
	prepared = prepare_experiment!()?
	provider = provider_by_id(prepared.config.candidates.providers, provider_id)?
	keys = read_api_keys!(prepared.config)?
	started = Utc.now!()
	run_id = "${mode}-${provider_id}-${run_id_for(started, prepared.config.experiment_version)}"
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/${mode}/${provider_id}/${run_id}"
	_ = create_run!(run_id, run_dir, output_dir, mode, provider_id, prepared.config)?
	_ = execute_run!(prepared, provider, keys, run_id, run_dir, output_dir)?
	Ok({})
}

resume_run! = |mode, provider_id| {
	prepared = prepare_experiment!()?
	provider = provider_by_id(prepared.config.candidates.providers, provider_id)?
	prefix = "${mode}-${provider_id}-"
	run_id = latest_incomplete_run!(prefix)?
	run_dir = "${experiment_dir}/responses/${run_id}"
	output_dir = "${experiment_dir}/outputs/${mode}/${provider_id}/${run_id}"
	_ = validate_manifest!(run_id, run_dir, output_dir, mode, provider_id, prepared.config)?
	checkpoint_path = "${run_dir}/${work_name}.candidates.json"
	accepted_path = "${run_dir}/${work_name}.accepted.audit.json"
	checkpoint_exists = Path.exists!(Path.utf8(checkpoint_path))?
	accepted_exists = Path.exists!(Path.utf8(accepted_path))?
	_ = preflight_resume_artifacts!(run_dir, provider.id)?
	_ = if checkpoint_exists {
		checkpoint = read_candidate_checkpoint!(checkpoint_path)?
		_ = validate_candidate_checkpoint(checkpoint, prepared.target_rows, provider, prepared.config, run_id)?
		_ = validate_checkpoint_request!(checkpoint, prepared, provider, run_dir)?
		validate_stage_accounting!(run_dir, run_id, provider.id, "deepseek-candidates", checkpoint.call.client_request_id, checkpoint.accounting)?
	} else {}
	_ = if accepted_exists {
		checkpoint = read_candidate_checkpoint!(checkpoint_path)?
		audit = read_run_audit!(accepted_path)?
		_ = validate_run_audit(audit, prepared.target_rows, provider, prepared.config, run_id)?
		_ = validate_audit_checkpoint_equality(audit, checkpoint)?
		validate_stage_accounting!(run_dir, run_id, provider.id, "jev-noul-selection", audit.selector_call.client_request_id, audit.accounting.selector)?
	} else {}
	keys = if accepted_exists {
		{ ppq: "", typesafe: "" }
	} else if checkpoint_exists {
		{ ppq: "", typesafe: read_key!(prepared.config.selector.provider.api_key_env)? }
	} else {
		read_api_keys!(prepared.config)?
	}
	_ = execute_run!(prepared, provider, keys, run_id, run_dir, output_dir)?
	Ok({})
}

preflight_resume_artifacts! = |run_dir, provider_id| {
	entries = Path.list!(Path.utf8(run_dir))?
	_ = reject_orphan_attempt_artifacts!(entries, provider_id, "deepseek-candidates")?
	reject_orphan_attempt_artifacts!(entries, provider_id, "jev-noul-selection")
}

create_run! = |run_id, run_dir, output_dir, mode, provider_id, config| {
	if Path.exists!(Path.utf8(run_dir))? or Path.exists!(Path.utf8(output_dir))? {
		Err(RunAlreadyExists(run_id))
	} else {
		_ = Path.create_all!(Path.utf8(run_dir))?
		_ = Path.create_all!(Path.utf8(output_dir))?
		manifest : Manifest
		manifest = { experiment_version: config.experiment_version, mode, provider_id, run_id }
		json = Json.to_str_try(manifest)?
		write_new_utf8!("${json}\n", "${run_dir}/run.json")
	}
}

validate_manifest! = |run_id, run_dir, output_dir, mode, provider_id, config| {
	if !Path.exists!(Path.utf8(output_dir))? {
		Err(MissingOutputDirectory(output_dir))
	} else {
		raw = Path.read_utf8!(Path.utf8("${run_dir}/run.json"))?
		manifest : Manifest
		manifest = Json.parse(raw)?
		if manifest != { experiment_version: config.experiment_version, mode, provider_id, run_id } {
			Err(RunManifestMismatch(run_id))
		} else {
			Ok({})
		}
	}
}

execute_run! = |prepared, provider, keys, run_id, run_dir, output_dir| {
	checkpoint_path = "${run_dir}/${work_name}.candidates.json"
	checkpoint = if Path.exists!(Path.utf8(checkpoint_path))? {
		loaded = read_candidate_checkpoint!(checkpoint_path)?
		_ = validate_candidate_checkpoint(loaded, prepared.target_rows, provider, prepared.config, run_id)?
		_ = validate_checkpoint_request!(loaded, prepared, provider, run_dir)?
		_ = validate_stage_accounting!(run_dir, run_id, provider.id, "deepseek-candidates", loaded.call.client_request_id, loaded.accounting)?
		_ = Stdout.line!("reused accepted ${provider.id} candidate checkpoint")?
		loaded
	} else {
		state = resume_attempt_state!(run_dir, run_id, provider.id, "deepseek-candidates", prepared.config.candidates.validation.max_attempts, prepared.config.candidates.transport.max_retries)?
		run_candidate_attempt!(prepared, provider, keys.ppq, run_id, run_dir, state.validation_attempt, state.transport_attempt, state.accounting, state.feedback, state.duplicate_risk)?
	}
	accepted_path = "${run_dir}/${work_name}.accepted.audit.json"
	audit = if Path.exists!(Path.utf8(accepted_path))? {
		loaded = read_run_audit!(accepted_path)?
		_ = validate_run_audit(loaded, prepared.target_rows, provider, prepared.config, run_id)?
		_ = validate_audit_checkpoint_equality(loaded, checkpoint)?
		_ = validate_stage_accounting!(run_dir, run_id, provider.id, "jev-noul-selection", loaded.selector_call.client_request_id, loaded.accounting.selector)?
		loaded
	} else {
		body = jev_request_body(prepared.config, prepared.source, prepared.target_rows, checkpoint.candidates, "")?
		state = resume_attempt_state!(run_dir, run_id, provider.id, "jev-noul-selection", prepared.config.selector.validation.max_attempts, prepared.config.selector.transport.max_retries)?
		run_jev_attempt!(prepared, provider, checkpoint, keys.typesafe, run_id, run_dir, state.validation_attempt, state.transport_attempt, state.accounting, state.duplicate_risk, body)?
	}
	readable = render_output(audit.token_audits)
	audit_json = Json.to_str_try(audit)?
	_ = write_atomic_or_verify!(readable, "${output_dir}/${work_name}.txt")?
	_ = write_atomic_or_verify!("${audit_json}\n", "${output_dir}/${work_name}.audit.json")?
	_ = write_atomic_or_verify!("complete\n", "${run_dir}/run.complete")?
	_ = Stdout.line!("completed ${run_id}\t${output_dir}")?
	Ok({})
}

latest_incomplete_run! = |prefix| {
	root = "${experiment_dir}/responses"
	entries = Path.list!(Path.utf8(root))?
	find_latest_run!(entries, prefix, "")
}

find_latest_run! = |entries, prefix, latest|
	match entries {
		[] => if latest == "" Err(NoIncompleteRun(prefix)) else Ok(latest)
		[entry, .. as rest] => {
			path = Path.display(entry)
			name = Str.replace_first(path, "${experiment_dir}/responses/", "")
			is_dir = match Path.type!(entry)? {
				IsDir => Bool.True
				_ => Bool.False
			}
			eligible = is_dir and Str.starts_with(name, prefix) and Str.ends_with(name, "-v4") and Path.exists!(Path.utf8("${path}/run.json"))? and !Path.exists!(Path.utf8("${path}/run.complete"))?
			next = if eligible and (latest == "" or compare_str(latest, name) == Before) name else latest
			find_latest_run!(rest, prefix, next)
		}
	}

resume_attempt_state! = |run_dir, run_id, provider_id, stage, max_validation_attempts, max_retries| {
	entries = Path.list!(Path.utf8(run_dir))?
	_ = reject_orphan_attempt_artifacts!(entries, provider_id, stage)?
	records = read_attempt_records!(entries, run_id, provider_id, stage, [])?
	match latest_attempt_record(records) {
		Err(NoAttempt) => Ok({ accounting: empty_accounting, duplicate_risk: Bool.False, feedback: "", transport_attempt: 1, validation_attempt: 1 })
		Ok(record) => {
			if record.status == "rejected" {
				if record.validation_attempt >= max_validation_attempts {
					Err(RecordedValidationAttemptsExhausted(stage))
				} else {
					Ok({ accounting: record.accounting_after_attempt, duplicate_risk: Bool.False, feedback: record.validation_error, transport_attempt: 1, validation_attempt: record.validation_attempt + 1 })
				}
			} else if record.status == "transport-failed" or record.status == "http-rejected" {
				if record.retry_delay_ms == 0 or record.transport_attempt > max_retries {
					Err(RecordedTransportAttemptsExhausted(stage))
				} else {
					feedback = if stage == "deepseek-candidates" and record.validation_attempt > 1 "fixed-validation-retry" else ""
					Ok({ accounting: record.accounting_after_attempt, duplicate_risk: record.ambiguous_possible_charge, feedback, transport_attempt: record.transport_attempt + 1, validation_attempt: record.validation_attempt })
				}
			} else {
				Err(IncompleteAcceptedCheckpoint(stage))
			}
		}
	}
}

reject_orphan_attempt_artifacts! = |entries, provider_id, stage|
	match entries {
		[] => Ok({})
		[entry, .. as rest] => {
			path = Path.display(entry)
			stem = attempt_artifact_stem(path)
			prefix = if stage == "deepseek-candidates" "deepseek-${provider_id}-" else "jev-${provider_id}-"
			if stem != "" and Str.starts_with(path_file_name(path), prefix) and !Path.exists!(Path.utf8("${stem}.attempt.json"))? {
				Err(OrphanAttemptArtifact(stage, path))
			} else {
				reject_orphan_attempt_artifacts!(rest, provider_id, stage)
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

path_file_name = |path|
	match List.last(Str.split_on(path, "/")) {
		Ok(name) => name
		Err(_) => path
	}

read_attempt_records! = |entries, run_id, provider_id, stage, found|
	match entries {
		[] => Ok(found)
		[entry, .. as rest] => {
			path = Path.display(entry)
			if Str.ends_with(path, ".attempt.json") {
				raw = Path.read_utf8!(entry)?
				record : AttemptRecord
				record = Json.parse(raw)?
				if record.provider_id == provider_id and record.stage == stage {
					if record.run_id != run_id or record.work != work_name {
						Err(AttemptRecordIdentityMismatch(path))
					} else {
						read_attempt_records!(rest, run_id, provider_id, stage, List.append(found, record))
					}
				} else {
					read_attempt_records!(rest, run_id, provider_id, stage, found)
				}
			} else {
				read_attempt_records!(rest, run_id, provider_id, stage, found)
			}
		}
	}

latest_attempt_record = |records|
	match records {
		[] => Err(NoAttempt)
		[first, .. as rest] => Ok(latest_attempt_loop(rest, first))
	}

validate_stage_accounting! = |run_dir, run_id, provider_id, stage, expected_client_request_id, expected_accounting| {
	entries = Path.list!(Path.utf8(run_dir))?
	records = read_attempt_records!(entries, run_id, provider_id, stage, [])?
	record = latest_attempt_record(records)?
	if record.status != "valid" or record.client_request_id != expected_client_request_id or record.accounting_after_attempt != expected_accounting {
		Err(StageAccountingMismatch(stage, expected_client_request_id))
	} else {
		Ok({})
	}
}

latest_attempt_loop = |records, latest|
	match records {
		[] => latest
		[first, .. as rest] => {
			next = if compare_str(latest.client_request_id, first.client_request_id) == Before first else latest
			latest_attempt_loop(rest, next)
		}
	}

read_api_keys! = |config| {
	env = Path.read_utf8!(Path.utf8(".env"))?
	ppq = env_value(env, config.candidates.provider.api_key_env)?
	typesafe = env_value(env, config.selector.provider.api_key_env)?
	Ok({ ppq, typesafe })
}

read_key! = |name| {
	env = Path.read_utf8!(Path.utf8(".env"))?
	env_value(env, name)
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

run_candidate_attempt! = |prepared, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt, accounting, feedback, duplicate_risk| {
	body = candidate_request_body(prepared.config, provider, prepared.source, prepared.target_rows, feedback)?
	captured = send_candidate_request!(prepared.config, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt, body, accounting, duplicate_risk)?
	parsed : Try(DeepResponse, _)
	parsed = decode_json_bytes(captured.raw)
	match parsed {
		Err(_) => {
			next_accounting = note_ambiguous_validation(captured.accounting, 0)
			_ = write_attempt!({ ..captured, accounting: next_accounting }, provider.id, run_id, "deepseek-candidates", validation_attempt, "rejected", "captured response was not the required PPQ completion envelope", 0, Bool.True, 0, work_name)?
			retry_candidate_validation!(prepared, provider, api_key, run_id, run_dir, validation_attempt, next_accounting, "captured response was not the required PPQ completion envelope")
		}
		Ok(decoded) => {
			usage : Usage
			usage = {
				input_tokens: decoded.usage.prompt_tokens,
				output_tokens: decoded.usage.completion_tokens,
				reasoning_tokens: decoded.usage.completion_tokens_details.reasoning_tokens,
				total_tokens: decoded.usage.total_tokens,
			}
			usage_reported = decoded.usage.cost > 0 and usage.input_tokens > 0 and usage.output_tokens > 0 and valid_token_usage(usage)
			with_cost = if usage_reported note_known_validation(captured.accounting, decoded.usage.cost, captured.possible_duplicate_billing) else note_ambiguous_validation(captured.accounting, 0)
			validation = if !usage_reported {
				Err("candidate response omitted positive cost or consistent nonzero token usage")
			} else match decoded.choices {
				[] => Err("captured response contained no completion choice")
				[choice, ..] => {
					if choice.finish_reason != "stop" {
						Err("finish reason was ${choice.finish_reason}, not stop")
					} else if decoded.model != prepared.config.candidates.model.id {
						Err("resolved model ${decoded.model} did not match the pin")
					} else if decoded.provider != provider.response_name {
						Err("resolved provider ${decoded.provider} did not match ${provider.response_name}")
					} else {
						match validate_candidate_content(choice.message.content, prepared.target_rows) {
							Ok(rows) => Ok(rows)
							Err(problem) => Err(candidate_error_text(problem))
						}
					}
				}
			}
			match validation {
				Err(error_text) => {
					recorded_cost = if usage_reported decoded.usage.cost else 0
					_ = write_attempt!({ ..captured, accounting: with_cost }, provider.id, run_id, "deepseek-candidates", validation_attempt, "rejected", error_text, recorded_cost, !usage_reported, 0, work_name)?
					retry_candidate_validation!(prepared, provider, api_key, run_id, run_dir, validation_attempt, with_cost, error_text)
				}
				Ok(rows) => {
					call = deep_call_audit(prepared.config, provider, decoded, captured)
					checkpoint : CandidateCheckpoint
					checkpoint = { accounting: with_cost, call, candidates: rows, experiment_version: prepared.config.experiment_version, provider_id: provider.id, run_id, source_path: prepared.config.input.source_path, target_count: List.len(prepared.target_rows), work: work_name }
					json = Json.to_str_try(checkpoint)?
					_ = write_atomic_new!("${json}\n", "${run_dir}/${work_name}.candidates.json")?
					_ = write_attempt!({ ..captured, accounting: with_cost }, provider.id, run_id, "deepseek-candidates", validation_attempt, "valid", "", decoded.usage.cost, Bool.False, 0, work_name)?
					Ok(checkpoint)
				}
			}
		}
	}
}

retry_candidate_validation! = |prepared, provider, api_key, run_id, run_dir, attempt, accounting, error_text| {
	_ = Stdout.line!("rejected ${provider.id} candidates attempt ${U64.to_str(attempt)}: ${error_text}")?
	if attempt < prepared.config.candidates.validation.max_attempts {
		run_candidate_attempt!(prepared, provider, api_key, run_id, run_dir, attempt + 1, 1, accounting, error_text, Bool.False)
	} else {
		Err(CandidateValidationAttemptsExhausted(error_text))
	}
}

send_candidate_request! = |config, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt, body, accounting, duplicate_risk| {
	requested_at = Utc.now!()
	nonce = U128.to_str(Utc.to_nanos_since_epoch(requested_at))
	client_request_id = "deepseek-${provider.id}-validation-${U64.to_str(validation_attempt)}-transport-${U64.to_str(transport_attempt)}-${nonce}"
	request_path = "${run_dir}/${client_request_id}.request.json"
	raw_path = "${run_dir}/${client_request_id}.raw.json"
	headers_path = "${run_dir}/${client_request_id}.headers.json"
	_ = write_new_utf8!(body, request_path)?
	request = Request.from_method(POST)
		.with_uri("${config.candidates.provider.base_url}/chat/completions")
		.with_timeout(TimeoutMilliseconds(300000))
		.add_header("Authorization", "Bearer ${api_key}")
		.add_header("Content-Type", "application/json")
		.with_body(Str.to_utf8(body))
	next_accounting = note_transport(accounting)
	match Http.send!(request) {
		Err(problem) => {
			received_at = Utc.now!()
			error = http_transport_error(problem, api_key)
			ambiguous = error.ambiguous
			failed_accounting = if ambiguous note_ambiguous_transport(next_accounting) else next_accounting
			_ = write_new_bytes!([], raw_path)?
			_ = write_new_utf8!("[]\n", headers_path)?
			captured = empty_capture(client_request_id, request_path, raw_path, headers_path, requested_at, received_at, failed_accounting, duplicate_risk or ambiguous, "basic-cli", transport_attempt)
			delay = if error.retryable and transport_attempt <= config.candidates.transport.max_retries retry_backoff_ms(config.candidates.transport, transport_attempt) else 0
			_ = write_attempt!(captured, provider.id, run_id, "deepseek-candidates", validation_attempt, "transport-failed", error.message, 0, ambiguous, delay, work_name)?
			if error.retryable and transport_attempt <= config.candidates.transport.max_retries {
				_ = Sleep.millis!(delay)
				send_candidate_request!(config, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt + 1, body, failed_accounting, duplicate_risk or ambiguous)
			} else {
				Err(CandidateTransportFailure(error.category))
			}
		}
		Ok(response) => {
			received_at = Utc.now!()
			raw = Response.body(response)
			headers = Response.headers(response)
			status = Response.status(response)
			_ = write_new_bytes!(raw, raw_path)?
			_ = write_headers!(headers, headers_path)?
			captured = {
				accounting: next_accounting,
				client_request_id,
				elapsed_ms: Utc.delta_as_millis(received_at, requested_at),
				headers,
				headers_path,
				possible_duplicate_billing: duplicate_risk,
				raw,
				raw_path,
				received_at: Utc.to_iso_8601(received_at),
				requested_at: Utc.to_iso_8601(requested_at),
				request_path,
				status,
				transport: "basic-cli",
				transport_attempt,
				transport_output_path: "",
			}
			if status >= 200 and status < 300 {
				Ok(captured)
			} else {
				retryable = is_transient_status(status)
				ambiguous = retryable
				failed_accounting = if ambiguous note_ambiguous_transport(next_accounting) else next_accounting
				delay = if retryable and transport_attempt <= config.candidates.transport.max_retries retry_delay_ms!(headers, config.candidates.transport, transport_attempt)? else 0
				_ = write_attempt!({ ..captured, accounting: failed_accounting }, provider.id, run_id, "deepseek-candidates", validation_attempt, "http-rejected", "provider returned HTTP ${U16.to_str(status)}", 0, ambiguous, delay, work_name)?
				if retryable and transport_attempt <= config.candidates.transport.max_retries {
					_ = Sleep.millis!(delay)
					send_candidate_request!(config, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt + 1, body, failed_accounting, duplicate_risk or ambiguous)
				} else {
					Err(CandidateHttpFailure(status))
				}
			}
		}
	}
}

deep_call_audit = |config, provider, decoded, captured| {
	call : CallAudit
	call = {
		client_request_id: captured.client_request_id,
		cost_usd: decoded.usage.cost,
		elapsed_ms: captured.elapsed_ms,
		provider_request_id: response_request_id(captured.headers),
		received_at: captured.received_at,
		requested_at: captured.requested_at,
		requested_model: config.candidates.model.id,
		requested_provider: "ppq/${provider.id}",
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

run_jev_attempt! = |prepared, provider, checkpoint, api_key, run_id, run_dir, validation_attempt, transport_attempt, accounting, duplicate_risk, body| {
	captured = send_jev_request!(prepared.config, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt, body, accounting, duplicate_risk)?
	parsed : Try(JevResponse, _)
	parsed = decode_json_bytes(captured.raw)
	match parsed {
		Err(_) => retry_jev_validation!(prepared, provider, checkpoint, api_key, run_id, run_dir, validation_attempt, note_ambiguous_validation(captured.accounting, 0), captured.possible_duplicate_billing, body, captured, "captured response was not the direct TypeSafe Noul schema", empty_jev_response)
		Ok(decoded) => {
			cost = selector_cost(prepared.config, decoded.usage.input_tokens)
			usage_reported = decoded.usage.input_tokens > 0 and decoded.usage.output_tokens > 0 and cost > 0
			with_cost = if usage_reported note_known_validation(captured.accounting, cost, captured.possible_duplicate_billing) else note_ambiguous_validation(captured.accounting, 0)
			validation = if !usage_reported {
				Err("Jev response omitted positive cost basis or nonzero token usage")
			} else if decoded.model != prepared.config.selector.model.id {
				Err("resolved Jev model ${decoded.model} did not match the pin")
			} else {
				match validate_jev_answers(prepared.target_rows, checkpoint.candidates, decoded.answers) {
					Ok(audits) => Ok(audits)
					Err(problem) => Err(jev_error_text(problem))
				}
			}
			match validation {
				Err(error_text) => retry_jev_validation!(prepared, provider, checkpoint, api_key, run_id, run_dir, validation_attempt, with_cost, captured.possible_duplicate_billing, body, captured, error_text, decoded)
				Ok(token_audits) => {
					call = jev_call_audit(prepared.config, decoded, captured, cost)
					total = add_accounting(checkpoint.accounting, with_cost)
					audit : RunAudit
					audit = {
						accounting: { candidates: checkpoint.accounting, selector: with_cost, total },
						candidate_call: checkpoint.call,
						experiment_version: prepared.config.experiment_version,
						provider_id: provider.id,
						run_id,
						selector_call: call,
						source_path: input_path,
						token_audits,
						work: work_name,
					}
					json = Json.to_str_try(audit)?
					_ = write_atomic_new!("${json}\n", "${run_dir}/${work_name}.accepted.audit.json")?
					_ = write_attempt!({ ..captured, accounting: with_cost }, provider.id, run_id, "jev-noul-selection", validation_attempt, "valid", "", cost, Bool.False, 0, work_name)?
					Ok(audit)
				}
			}
		}
	}
}

retry_jev_validation! = |prepared, provider, checkpoint, api_key, run_id, run_dir, attempt, accounting, _duplicate_risk, body, captured, error_text, decoded| {
	cost = selector_cost(prepared.config, decoded.usage.input_tokens)
	usage_reported = decoded.usage.input_tokens > 0 and decoded.usage.output_tokens > 0 and cost > 0
	_ = write_attempt!({ ..captured, accounting }, provider.id, run_id, "jev-noul-selection", attempt, "rejected", error_text, if usage_reported cost else 0, !usage_reported, 0, work_name)?
	_ = Stdout.line!("rejected Jev Noul response attempt ${U64.to_str(attempt)}: ${error_text}")?
	if attempt < prepared.config.selector.validation.max_attempts {
		run_jev_attempt!(prepared, provider, checkpoint, api_key, run_id, run_dir, attempt + 1, 1, accounting, Bool.False, body)
	} else {
		Err(JevValidationAttemptsExhausted(error_text))
	}
}

# Work around basic-cli's HTTP/1-only Hyper transport failure for this valid TypeSafe POST.
# Upstream: https://github.com/roc-lang/basic-cli/issues/455 and https://github.com/roc-lang/basic-cli/issues/438
# Remove curl after a released compatible basic-cli transport completes the retained request and exposes safe diagnostics.
send_jev_request! = |config, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt, body, accounting, duplicate_risk| {
	requested_at = Utc.now!()
	nonce = U128.to_str(Utc.to_nanos_since_epoch(requested_at))
	client_request_id = "jev-${provider.id}-validation-${U64.to_str(validation_attempt)}-transport-${U64.to_str(transport_attempt)}-${nonce}"
	request_path = "${run_dir}/${client_request_id}.request.json"
	raw_path = "${run_dir}/${client_request_id}.raw.json"
	headers_path = "${run_dir}/${client_request_id}.headers"
	transport_output_path = "${run_dir}/${client_request_id}.transport.json"
	_ = write_new_utf8!(body, request_path)?
	next_accounting = note_transport(accounting)
	result = Cmd.new_str("curl")
		.args_str([
			"--silent", "--show-error", "--request", "POST", "--connect-timeout", "30", "--max-time", "300", "--proto", "=https",
			"--header", "Content-Type: application/json", "--header", "Expect:", "--variable", "%ARISTOS_TYPESAFE_API_KEY",
			"--expand-header", "Authorization: Bearer {{ARISTOS_TYPESAFE_API_KEY}}", "--data-binary", "@${request_path}",
			"--dump-header", headers_path, "--output", raw_path, "--write-out", "%{http_code}", config.selector.provider.endpoint,
		])
		.env_str("ARISTOS_TYPESAFE_API_KEY", api_key)
		.exec_output!()
	match result {
		Ok(output) => {
			status = curl_http_status(output.stdout_utf8)
			_ = write_curl_output!(transport_output_path, "0", status, output.stdout_utf8, safe_transport_message(output.stderr_utf8_lossy, api_key))?
			_ = ensure_bytes_artifact!(raw_path)?
			_ = ensure_bytes_artifact!(headers_path)?
			received_at = Utc.now!()
			raw = Path.read_bytes!(Path.utf8(raw_path))?
			headers = read_curl_headers!(headers_path)?
			captured = {
				accounting: next_accounting,
				client_request_id,
				elapsed_ms: Utc.delta_as_millis(received_at, requested_at),
				headers,
				headers_path,
				possible_duplicate_billing: duplicate_risk,
				raw,
				raw_path,
				received_at: Utc.to_iso_8601(received_at),
				requested_at: Utc.to_iso_8601(requested_at),
				request_path,
				status,
				transport: "curl-workaround",
				transport_attempt,
				transport_output_path,
			}
			if status >= 200 and status < 300 {
				Ok(captured)
			} else {
				retryable = is_transient_status(status)
				ambiguous = retryable
				failed_accounting = if ambiguous note_ambiguous_transport(next_accounting) else next_accounting
				delay = if retryable and transport_attempt <= config.selector.transport.max_retries retry_delay_ms!(headers, config.selector.transport, transport_attempt)? else 0
				_ = write_attempt!({ ..captured, accounting: failed_accounting }, provider.id, run_id, "jev-noul-selection", validation_attempt, "http-rejected", "TypeSafe returned HTTP ${U16.to_str(status)}", 0, ambiguous, delay, work_name)?
				if retryable and transport_attempt <= config.selector.transport.max_retries {
					_ = Sleep.millis!(delay)
					send_jev_request!(config, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt + 1, body, failed_accounting, duplicate_risk or ambiguous)
				} else {
					Err(JevHttpFailure(status))
				}
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
			failed_accounting = if error.ambiguous note_ambiguous_transport(next_accounting) else next_accounting
			captured = empty_curl_capture(client_request_id, request_path, raw_path, headers_path, transport_output_path, requested_at, received_at, failed_accounting, duplicate_risk or error.ambiguous, transport_attempt, status)
			delay = if error.retryable and transport_attempt <= config.selector.transport.max_retries retry_backoff_ms(config.selector.transport, transport_attempt) else 0
			_ = write_attempt!(captured, provider.id, run_id, "jev-noul-selection", validation_attempt, "transport-failed", error.message, 0, error.ambiguous, delay, work_name)?
			if error.retryable and transport_attempt <= config.selector.transport.max_retries {
				_ = Sleep.millis!(delay)
				send_jev_request!(config, provider, api_key, run_id, run_dir, validation_attempt, transport_attempt + 1, body, failed_accounting, duplicate_risk or error.ambiguous)
			} else {
				Err(JevTransportFailure(error.category))
			}
		}
		Err(_) => {
			_ = write_curl_output!(transport_output_path, "not-started", 0, "", "curl process could not be started")?
			_ = ensure_bytes_artifact!(raw_path)?
			_ = ensure_bytes_artifact!(headers_path)?
			received_at = Utc.now!()
			captured = empty_curl_capture(client_request_id, request_path, raw_path, headers_path, transport_output_path, requested_at, received_at, next_accounting, duplicate_risk, transport_attempt, 0)
			_ = write_attempt!(captured, provider.id, run_id, "jev-noul-selection", validation_attempt, "transport-failed", "curl process could not be started", 0, Bool.False, 0, work_name)?
			Err(JevTransportFailure("process-start"))
		}
	}
}

selector_cost = |config, input_tokens| U64.to_dec(input_tokens) * config.selector.input_cost_per_million_tokens_usd / 1000000

jev_call_audit = |config, decoded, captured, cost| {
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

validate_jev_answers = |target_rows, rows, answers| {
	expected = List.len(target_rows) * 3
	if Dict.len(answers) != expected {
		Err(WrongJevAnswerCount(expected, Dict.len(answers)))
	} else {
		validate_jev_rows(target_rows, rows, answers, [])
	}
}

validate_jev_rows = |target_rows, rows, answers, found|
	match (target_rows, rows) {
		([], []) => Ok(found)
		([target, .. as rest_targets], [row, .. as rest_rows]) => {
			probabilities = read_three_nouls(target, answers)?
			ranking = rank_three(probabilities.one, probabilities.two, probabilities.three)
			baseline = candidate_at(row.candidates, 1)?
			top = candidate_at(row.candidates, ranking.top_index)?
			audit : TokenAudit
			audit = {
				baseline_candidate_index: 1,
				baseline_display_gloss: display_gloss(baseline.gloss),
				candidates: row.candidates,
				effective_display_gloss: display_gloss(baseline.gloss),
				effective_policy_status: "baseline-pending-human-calibrated-policy",
				flags: ["calibration_required"],
				form: target.form,
				id: target.id,
				line: target.line,
				no_valid_candidate_status: "not-assessed-without-human-calibrated-policy",
				probabilities: { candidate_1: probabilities.one, candidate_2: probabilities.two, candidate_3: probabilities.three },
				runner_up_candidate_index: ranking.runner_index,
				selector_baseline_probability_difference: ranking.top_probability - probabilities.one,
				selector_differs_from_baseline: ranking.top_index != 1,
				selector_top_candidate_index: ranking.top_index,
				selector_top_display_gloss: display_gloss(top.gloss),
				top_probability: ranking.top_probability,
				top_runner_up_margin: ranking.top_probability - ranking.runner_probability,
			}
			validate_jev_rows(rest_targets, rest_rows, answers, List.append(found, audit))
		}
		_ => Err(JevAnswerCoverageMismatch)
	}

read_three_nouls = |target, answers| {
	one = read_noul(target.id, 1, answers)?
	two = read_noul(target.id, 2, answers)?
	three = read_noul(target.id, 3, answers)?
	Ok({ one, three, two })
}

read_noul = |token_id, candidate_index, answers| {
	key = question_key(token_id, candidate_index)
	answer = Dict.get(answers, key) ? |_| MissingJevAnswer(key)
	if answer.type != "noul" {
		Err(WrongJevAnswerType(key, answer.type))
	} else if answer.noul < 0 or answer.noul > 1 {
		Err(NoulOutOfRange(key))
	} else {
		Ok(answer.noul)
	}
}

# Stable tie-breaking preserves the lower candidate index.
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

candidate_at = |candidates, wanted|
	match candidates {
		[] => Err(MissingCandidateIndex(wanted))
		[first, .. as rest] => if first.candidate_index == wanted Ok(first) else candidate_at(rest, wanted)
	}

render_output = |audits| {
	result = render_token_audits(audits, 0, "")
	"${result.rendered}\n"
}

render_token_audits = |audits, previous_line, rendered|
	match audits {
		[] => { previous_line, rendered }
		[audit, .. as rest] => {
			spacing = line_spacing(previous_line, audit.line)
			prefix = if rendered == "" "" else "\n"
			next = "${rendered}${prefix}${spacing}${audit.form} <=> ${audit.effective_display_gloss}"
			render_token_audits(rest, audit.line, next)
		}
	}

line_spacing = |previous, current|
	if previous == 0 or current <= previous "" else blank_lines(current - previous, "")

blank_lines = |count, found|
	if count == 0 found else blank_lines(count - 1, "${found}\n")

replay_latest_policy! = |provider_id| {
	root = "${experiment_dir}/outputs/full/${provider_id}"
	if !Path.exists!(Path.utf8(root))? {
		Err(NoCompletedRun(provider_id))
	} else {
		entries = Path.list!(Path.utf8(root))?
		audit_path = latest_completed_output_audit!(entries, provider_id, "")?
		if audit_path == "" Err(NoCompletedRun(provider_id)) else replay_policy!(audit_path, "")
	}
}

latest_completed_output_audit! = |entries, provider_id, latest|
	match entries {
		[] => Ok(latest)
		[entry, .. as rest] => {
			path = Path.display(entry)
			run_id = path_file_name(path)
			audit_path = "${path}/${work_name}.audit.json"
			complete_path = "${experiment_dir}/responses/${run_id}/run.complete"
			eligible = Path.exists!(Path.utf8(audit_path))? and Path.exists!(Path.utf8(complete_path))?
			next = if eligible and (latest == "" or compare_str(latest, audit_path) == Before) audit_path else latest
			latest_completed_output_audit!(rest, provider_id, next)
		}
	}

replay_policy! = |audit_path, supplied_policy_path| {
	prepared = prepare_experiment!()?
	config = prepared.config
	policy_path = if supplied_policy_path == "" config.policy.default_path else supplied_policy_path
	if !Path.exists!(Path.utf8(policy_path))? {
		_ = Stdout.line!("no human-calibrated policy is available at ${policy_path}; no threshold was assumed and no replay was written")?
		Ok({})
	} else {
		policy_raw = Path.read_utf8!(Path.utf8(policy_path))?
		policy : Policy
		policy = Json.parse(policy_raw)?
		_ = validate_policy(policy)?
		audit = read_run_audit!(audit_path)?
		provider = provider_by_id(config.candidates.providers, audit.provider_id)?
		_ = validate_run_audit(audit, prepared.target_rows, provider, config, audit.run_id)?
		replayed = List.map(audit.token_audits, |target| apply_policy(target, policy))
		replay : ReplayAudit
		replay = { experiment_version: audit.experiment_version, provider_id: audit.provider_id, token_audits: replayed }
		json = Json.to_str_try(replay)?
		output_path = "${audit_path}.policy-${policy.policy_id}.json"
		_ = write_atomic_or_verify!("${json}\n", output_path)?
		_ = Stdout.line!("replayed human-calibrated policy ${policy.policy_id}\t${output_path}")?
		Ok({})
	}
}

validate_policy = |policy|
	if !policy.human_calibrated {
		Err(PolicyNotHumanCalibrated(policy.policy_id))
	} else if !valid_path_segment(policy.policy_id) or policy.minimum_margin < 0 or policy.minimum_margin > 1 or policy.minimum_probability < 0 or policy.minimum_probability > 1 or policy.no_valid_candidate_below_probability < 0 or policy.no_valid_candidate_below_probability > 1 {
		Err(InvalidPolicy(policy.policy_id))
	} else {
		Ok({})
	}

apply_policy = |target, policy| {
	no_valid = target.top_probability < policy.no_valid_candidate_below_probability
	replace = !no_valid and target.selector_top_candidate_index != 1 and target.top_probability >= policy.minimum_probability and target.top_runner_up_margin >= policy.minimum_margin
	effective = if no_valid {
		"[UNRESOLVED]"
	} else if replace {
		target.selector_top_display_gloss
	} else {
		target.baseline_display_gloss
	}
	status = if no_valid {
		"human-calibrated-no-valid-candidate"
	} else if replace {
		"human-calibrated-selector-replacement"
	} else {
		"human-calibrated-baseline-retained"
	}
	no_valid_status = if no_valid "human-calibrated-no-valid-candidate" else "human-calibrated-valid-candidate-present"
	{ ..target, effective_display_gloss: effective, effective_policy_status: status, flags: [], no_valid_candidate_status: no_valid_status }
}

validate_checkpoint_request! = |checkpoint, prepared, provider, run_dir| {
	path = "${run_dir}/${checkpoint.call.client_request_id}.request.json"
	raw = Path.read_utf8!(Path.utf8(path))?
	request : {
		frequency_penalty : Dec,
		include_reasoning : Bool,
		max_tokens : U64,
		messages : List({ content : Str, role : Str }),
		model : Str,
		presence_penalty : Dec,
		provider : { allow_fallbacks : Bool, only : List(Str), require_parameters : Bool },
		reasoning : { enabled : Bool, exclude : Bool },
		response_format : { type : Str },
		seed : U64,
		temperature : Dec,
		top_k : U64,
		top_p : Dec,
	}
	request = Json.parse(raw)?
	g = prepared.config.candidates.generation
	table = Str.join_with(List.map(prepared.target_rows, render_candidate_target), "\n")
	expected_source = "COMPLETE ILIAD SOURCE PASSAGE (audit and context; only listed targets are in scope):\n${prepared.source}"
	expected_legend = "OGA EVIDENCE LEGEND (deterministic corpus-code interpretation, not a model claim):\n${oga_evidence_legend}"
	expected_targets = "TARGETS (id | exact form | source line number | source line | local context | independent OGA evidence):\n${table}"
	if request.model != prepared.config.candidates.model.id or request.provider != { allow_fallbacks: Bool.False, only: [provider.request_name], require_parameters: Bool.True } or request.frequency_penalty != g.frequency_penalty or request.include_reasoning != g.include_reasoning or request.max_tokens != g.max_tokens or request.presence_penalty != g.presence_penalty or request.reasoning != g.reasoning or request.response_format.type != "json_schema" or request.seed != g.seed or request.temperature != g.temperature or request.top_k != g.top_k or request.top_p != g.top_p or !request_messages_contain(request.messages, expected_source, expected_legend, expected_targets) {
		Err(CandidateCheckpointRequestMismatch(path))
	} else {
		Ok({})
	}
}

request_messages_contain = |messages, expected_source, expected_legend, expected_targets|
	match messages {
		[] => Bool.False
		[message, .. as rest] => if message.role == "user" and Str.contains(message.content, expected_source) and Str.contains(message.content, expected_legend) and Str.contains(message.content, expected_targets) Bool.True else request_messages_contain(rest, expected_source, expected_legend, expected_targets)
	}

validate_candidate_checkpoint = |checkpoint, target_rows, provider, config, run_id| {
	if checkpoint.experiment_version != config.experiment_version or checkpoint.provider_id != provider.id or checkpoint.run_id != run_id or checkpoint.source_path != config.input.source_path or checkpoint.target_count != List.len(target_rows) or checkpoint.work != work_name {
		Err(CandidateCheckpointMismatch)
	} else if checkpoint.call.requested_model != config.candidates.model.id or checkpoint.call.resolved_model != config.candidates.model.id or checkpoint.call.requested_provider != "ppq/${provider.id}" or checkpoint.call.resolved_provider != provider.response_name {
		Err(CandidateCheckpointCallMismatch)
	} else if checkpoint.call.cost_usd < 0 or !valid_token_usage(checkpoint.call.token_usage) {
		Err(CandidateCheckpointUsageMismatch)
	} else {
		_ = validate_candidates(target_rows, checkpoint.candidates)?
		Ok({})
	}
}

validate_run_audit = |audit, target_rows, provider, config, run_id| {
	if audit.experiment_version != config.experiment_version or audit.provider_id != provider.id or audit.run_id != run_id or audit.source_path != config.input.source_path or audit.work != work_name or List.len(audit.token_audits) != List.len(target_rows) {
		Err(RunAuditMismatch)
	} else if audit.candidate_call.requested_model != config.candidates.model.id or audit.candidate_call.resolved_model != config.candidates.model.id or audit.candidate_call.requested_provider != "ppq/${provider.id}" or audit.candidate_call.resolved_provider != provider.response_name or audit.selector_call.requested_model != config.selector.model.id or audit.selector_call.resolved_model != config.selector.model.id or audit.selector_call.requested_provider != config.selector.provider.name or audit.selector_call.resolved_provider != config.selector.provider.name {
		Err(RunAuditCallMismatch)
	} else if !valid_token_usage(audit.candidate_call.token_usage) or !valid_token_usage(audit.selector_call.token_usage) or audit.selector_call.token_usage.reasoning_tokens != 0 {
		Err(RunAuditUsageMismatch)
	} else if audit.accounting.total != add_accounting(audit.accounting.candidates, audit.accounting.selector) {
		Err(RunAuditAccountingMismatch)
	} else {
		validate_audit_targets(audit.token_audits, target_rows)
	}
}

valid_token_usage = |usage| usage.total_tokens == usage.input_tokens + usage.output_tokens and usage.reasoning_tokens <= usage.output_tokens

validate_audit_checkpoint_equality = |audit, checkpoint| {
	rows = audit_candidate_rows(audit.token_audits, [])
	if audit.candidate_call != checkpoint.call or audit.accounting.candidates != checkpoint.accounting or rows != checkpoint.candidates {
		Err(RunAuditCheckpointMismatch)
	} else {
		Ok({})
	}
}

audit_candidate_rows = |audits, found|
	match audits {
		[] => found
		[first, .. as rest] => audit_candidate_rows(rest, List.append(found, { candidates: first.candidates, id: first.id }))
	}

validate_audit_targets = |audits, target_rows|
	match (audits, target_rows) {
		([], []) => Ok({})
		([audit, .. as rest_audits], [target, .. as rest_targets]) => {
			_ = validate_probability_value(audit.probabilities.candidate_1)?
			_ = validate_probability_value(audit.probabilities.candidate_2)?
			_ = validate_probability_value(audit.probabilities.candidate_3)?
			validated = validate_three_candidates(target, audit.candidates)?
			ranking = rank_three(audit.probabilities.candidate_1, audit.probabilities.candidate_2, audit.probabilities.candidate_3)
			baseline = candidate_at(validated, 1)?
			top = candidate_at(validated, ranking.top_index)?
			expected_baseline_display = display_gloss(baseline.gloss)
			expected_top_display = display_gloss(top.gloss)
			if audit.id != target.id or audit.form != target.form or audit.line != target.line {
				Err(AuditTargetMismatch(target.id))
			} else if audit.baseline_candidate_index != 1 or audit.baseline_display_gloss != expected_baseline_display or audit.selector_top_candidate_index != ranking.top_index or audit.selector_top_display_gloss != expected_top_display or audit.runner_up_candidate_index != ranking.runner_index or audit.top_probability != ranking.top_probability or audit.top_runner_up_margin != ranking.top_probability - ranking.runner_probability or audit.selector_baseline_probability_difference != ranking.top_probability - audit.probabilities.candidate_1 or audit.selector_differs_from_baseline != (ranking.top_index != 1) {
				Err(AuditDerivedValueMismatch(target.id))
			} else if audit.effective_policy_status != "baseline-pending-human-calibrated-policy" or audit.effective_display_gloss != expected_baseline_display or audit.no_valid_candidate_status != "not-assessed-without-human-calibrated-policy" or audit.flags != ["calibration_required"] {
				Err(AuditPolicyMismatch(target.id))
			} else {
				validate_audit_targets(rest_audits, rest_targets)
			}
		}
		_ => Err(AuditCoverageMismatch)
	}

validate_probability_value = |value| if value < 0 or value > 1 Err(InvalidStoredProbability) else Ok({})

read_candidate_checkpoint! = |path| {
	raw = Path.read_utf8!(Path.utf8(path))?
	value : CandidateCheckpoint
	value = Json.parse(raw)?
	Ok(value)
}

read_run_audit! = |path| {
	raw = Path.read_utf8!(Path.utf8(path))?
	value : RunAudit
	value = Json.parse(raw)?
	Ok(value)
}

candidate_error_text = |problem|
	match problem {
		ApostrophePossessive(id, index) => "token ${id} candidate ${U64.to_str(index)} used an apostrophe possessive"
		CandidateCoverageMismatch => "candidate rows and target coverage diverged"
		DanglingGlossPunctuation(id, index) => "token ${id} candidate ${U64.to_str(index)} had dangling punctuation or a hyphen"
		DuplicateEvidenceRef(id, index, ref) => "token ${id} candidate ${U64.to_str(index)} duplicated evidence ref ${ref}"
		DuplicateOrShallowGloss(id) => "token ${id} contained duplicate or shallow canonical gloss variants"
		EmptyCandidateField(id, index) => "token ${id} candidate ${U64.to_str(index)} had an empty required field"
		InvalidCandidateIdentity(id, index) => "token ${id} candidate ${U64.to_str(index)} had the wrong index or role"
		InvalidCandidateJson => "assistant content was not the required candidate JSON"
		InvalidEvidenceRef(id, index, ref) => "token ${id} candidate ${U64.to_str(index)} used invalid evidence ref ${ref}"
		MalformedCandidateText(id, index) => "token ${id} candidate ${U64.to_str(index)} contained a malformed value"
		MissingEvidenceRefs(id, index) => "token ${id} candidate ${U64.to_str(index)} lacked valid evidence refs"
		MissingInterpretiveContrast(id) => "token ${id} alternatives lacked genuine structured interpretive contrast"
		WrongCandidateCount(id, actual) => "token ${id} had ${U64.to_str(actual)} candidates instead of 3"
		WrongCandidateId(expected, actual) => "expected token ID ${expected} but received ${actual}"
		WrongCandidateTargetCount(expected, actual) => "expected ${U64.to_str(expected)} candidate rows but received ${U64.to_str(actual)}"
	}

jev_error_text = |problem|
	match problem {
		JevAnswerCoverageMismatch => "Jev answers and candidate targets diverged"
		MissingCandidateIndex(index) => "validated candidates omitted index ${U64.to_str(index)}"
		MissingJevAnswer(key) => "missing Jev answer ${key}"
		NoulOutOfRange(key) => "${key} returned noul outside [0,1]"
		WrongJevAnswerCount(expected, actual) => "expected ${U64.to_str(expected)} Jev answers but received ${U64.to_str(actual)}"
		WrongJevAnswerType(key, actual) => "${key} returned type ${actual}, not noul"
	}

empty_jev_response : JevResponse
empty_jev_response = { answers: Dict.empty(), model: "", usage: { input_tokens: 0, output_tokens: 0 } }

empty_accounting : Accounting
empty_accounting = {
	ambiguous_possible_charge_attempts: 0,
	ambiguous_possible_cost_usd: 0,
	known_charged_attempts: 0,
	known_charged_cost_usd: 0,
	transport_attempts: 0,
	validation_attempts: 0,
}

note_transport = |accounting| { ..accounting, transport_attempts: accounting.transport_attempts + 1 }

note_ambiguous_transport = |accounting| { ..accounting, ambiguous_possible_charge_attempts: accounting.ambiguous_possible_charge_attempts + 1 }

note_ambiguous_validation = |accounting, possible_cost| {
	..accounting,
	ambiguous_possible_charge_attempts: accounting.ambiguous_possible_charge_attempts + 1,
	ambiguous_possible_cost_usd: accounting.ambiguous_possible_cost_usd + possible_cost,
	validation_attempts: accounting.validation_attempts + 1,
}

note_known_validation = |accounting, cost, duplicate_risk| {
	..accounting,
	ambiguous_possible_cost_usd: if duplicate_risk accounting.ambiguous_possible_cost_usd + cost else accounting.ambiguous_possible_cost_usd,
	known_charged_attempts: accounting.known_charged_attempts + 1,
	known_charged_cost_usd: accounting.known_charged_cost_usd + cost,
	validation_attempts: accounting.validation_attempts + 1,
}

add_accounting = |a, b| {
	ambiguous_possible_charge_attempts: a.ambiguous_possible_charge_attempts + b.ambiguous_possible_charge_attempts,
	ambiguous_possible_cost_usd: a.ambiguous_possible_cost_usd + b.ambiguous_possible_cost_usd,
	known_charged_attempts: a.known_charged_attempts + b.known_charged_attempts,
	known_charged_cost_usd: a.known_charged_cost_usd + b.known_charged_cost_usd,
	transport_attempts: a.transport_attempts + b.transport_attempts,
	validation_attempts: a.validation_attempts + b.validation_attempts,
}

write_attempt! = |captured, provider_id, run_id, stage, validation_attempt, status, error_text, cost, ambiguous, retry_delay_ms, work| {
	record : AttemptRecord
	record = {
		accounting_after_attempt: captured.accounting,
		ambiguous_possible_charge: ambiguous or captured.possible_duplicate_billing,
		client_request_id: captured.client_request_id,
		cost_usd: cost,
		elapsed_ms: captured.elapsed_ms,
		headers_path: captured.headers_path,
		http_status: captured.status,
		provider_id,
		provider_request_id: response_request_id(captured.headers),
		raw_response_path: captured.raw_path,
		received_at: captured.received_at,
		request_path: captured.request_path,
		requested_at: captured.requested_at,
		retry_delay_ms,
		run_id,
		stage,
		status,
		transport: captured.transport,
		transport_attempt: captured.transport_attempt,
		transport_output_path: captured.transport_output_path,
		validation_attempt,
		validation_error: error_text,
		work,
	}
	json = Json.to_str_try(record)?
	write_new_utf8!("${json}\n", Str.replace_last(captured.request_path, ".request.json", ".attempt.json"))
}

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

empty_capture = |client_request_id, request_path, raw_path, headers_path, requested_at, received_at, accounting, duplicate, transport, transport_attempt| {
	accounting,
	client_request_id,
	elapsed_ms: Utc.delta_as_millis(received_at, requested_at),
	headers: [],
	headers_path,
	possible_duplicate_billing: duplicate,
	raw: [],
	raw_path,
	received_at: Utc.to_iso_8601(received_at),
	requested_at: Utc.to_iso_8601(requested_at),
	request_path,
	status: 0,
	transport,
	transport_attempt,
	transport_output_path: "",
}

empty_curl_capture = |client_request_id, request_path, raw_path, headers_path, transport_output_path, requested_at, received_at, accounting, duplicate, transport_attempt, status| {
	accounting,
	client_request_id,
	elapsed_ms: Utc.delta_as_millis(received_at, requested_at),
	headers: [],
	headers_path,
	possible_duplicate_billing: duplicate,
	raw: [],
	raw_path,
	received_at: Utc.to_iso_8601(received_at),
	requested_at: Utc.to_iso_8601(requested_at),
	request_path,
	status,
	transport: "curl-workaround",
	transport_attempt,
	transport_output_path,
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
			next = match parts {
				[name, value, .. as remaining] => List.append(found, { name: Str.trim(name), value: Str.trim(Str.join_with(List.prepend(remaining, value), ":")) })
				_ => found
			}
			parse_curl_header_lines(rest, next)
		}
	}

is_transient_status = |status| status == 408 or status == 429 or status >= 500

retry_backoff_ms = |transport, retry_number| {
	uncapped = retry_backoff_uncapped(transport.backoff_initial_ms, retry_number)
	if uncapped > transport.backoff_max_ms transport.backoff_max_ms else uncapped
}

retry_backoff_uncapped : U64, U64 -> U64
retry_backoff_uncapped = |delay, retry_number|
	if retry_number <= 1 delay else retry_backoff_uncapped(delay * 2, retry_number - 1)

retry_delay_ms! = |headers, transport, retry_number| {
	fallback = retry_backoff_ms(transport, retry_number)
	milliseconds = response_header_value(headers, "retry-after-ms")
	seconds = response_header_value(headers, "retry-after")
	if milliseconds != "" {
		Ok(retry_header_delay(milliseconds, 1, fallback, transport.max_retry_after_ms))
	} else if seconds == "" {
		Ok(fallback)
	} else {
		match U64.from_str(seconds) {
			Ok(value) => Ok(retry_header_delay(U64.to_str(value), 1000, fallback, transport.max_retry_after_ms))
			Err(_) => retry_after_date_ms!(seconds, fallback, transport.max_retry_after_ms)
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

response_header_value = |headers, expected|
	match headers {
		[] => ""
		[header, .. as rest] => if Str.caseless_ascii_equals(header.name, expected) header.value else response_header_value(rest, expected)
	}

response_request_id = |headers|
	match headers {
		[] => ""
		[header, .. as rest] => {
			if Str.caseless_ascii_equals(header.name, "x-request-id") or Str.caseless_ascii_equals(header.name, "request-id") header.value else response_request_id(rest)
		}
	}

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
		_ = write_new_utf8!(content, temporary)?
		Path.rename!(Path.utf8(temporary), Path.utf8(path))
	}
}

run_id_for = |timestamp, version| {
	compact = Str.replace_each(Str.replace_each(Utc.to_iso_8601(timestamp), "-", ""), ":", "")
	"${compact}-${U128.to_str(Utc.to_nanos_since_epoch(timestamp))}-v${U64.to_str(version)}"
}

valid_path_segment = |segment| segment != "" and !Str.contains(segment, "/") and !Str.contains(segment, "\\") and !Str.contains(segment, "..")

compare_str = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if x < y Before else if x > y After else compare_bytes(xs, ys)
	}
