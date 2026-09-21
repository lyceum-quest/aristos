app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stdout
Question : { criteria : { false : Str, true : Str }, instructions : Str, type : Str }
Answer : { noul : Dec, type : Str }
Response : { answers : Dict(Str, Answer), model : Str, usage : { input_tokens : U64, output_tokens : U64 } }
Config : { api_key_env : Str, endpoint : Str, model : Str, output_path : Str, sentence_questions : Dict(Str, Question), state : Dict(Str, Str), token_questions : Dict(Str, Question) }
main! = |args| match List.drop_first(args, 1) {
	[input_arg] => {
		input = OsStr.display(input_arg)
		config : Config
		config = Json.parse(Path.read_utf8!(Path.utf8("experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/config/audit.config.json"))?)?
		source = Path.read_utf8!(Path.utf8(input))?
		sentences = List.keep_if(Str.split_on(Str.trim(source), "\n\n"), |block| Str.trim(block) != "")
		env = Path.read_utf8!(Path.utf8(".env"))?
		prefix = "${config.api_key_env}="
		key = match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
		audits = audit!(sentences, config, key, 1, [])?
		Path.write_utf8!(Path.utf8(config.output_path), "${Json.to_str_try({ audits, source: input, state: config.state })?}\n")
	}
	_ => Err(Usage("audit.roc <file.conllu>"))
}
audit! = |sentences, config, key, index, found| match sentences {
	[] => Ok(found)
	[sentence, .. as rest] => {
		rows = List.keep_if(Str.split_on(sentence, "\n"), |line| line != "" and !Str.starts_with(line, "#"))
		base = Dict.from_list(List.map(Dict.to_list(config.sentence_questions), |(name, question)| ("s${U64.to_str(index)}.${name}", question)))
		questions = token_questions(rows, Dict.to_list(config.token_questions), index, base)
		body = Json.to_str_try({ model: config.model, questions, state: Dict.insert(config.state, "conllu", sentence) })?
		request_path = "/tmp/aristos-oga-audit-request.json"
		response_path = "/tmp/aristos-oga-audit-response.json"
		_ = Path.write_utf8!(Path.utf8(request_path), body)?
		_ = Cmd.new_str("curl").args_str(["--silent", "--show-error", "--fail-with-body", "--request", "POST", "--header", "Content-Type: application/json", "--variable", "%ARISTOS_TYPESAFE_API_KEY", "--expand-header", "Authorization: Bearer {{ARISTOS_TYPESAFE_API_KEY}}", "--data-binary", "@${request_path}", "--output", response_path, config.endpoint]).env_str("ARISTOS_TYPESAFE_API_KEY", key).exec_output!()?
		reply : Response
		reply = Json.parse(Path.read_utf8!(Path.utf8(response_path))?)?
		_ = (if reply.model != config.model or Dict.len(reply.answers) != Dict.len(questions) Err(InvalidJevResponse(index)) else Ok({}))?
		_ = Stdout.line!("audited sentence ${U64.to_str(index)}")?
		audit!(rest, config, key, index + 1, List.append(found, { questions, response: reply, sentence, sentence_index: index }))
	}
}
token_questions = |rows, templates, sentence_index, found| match rows { [] => found, [row, .. as rest] => add_templates(rest, row, templates, templates, sentence_index, found) }
add_templates = |rows, row, templates, remaining, sentence_index, found| match remaining {
	[] => token_questions(rows, templates, sentence_index, found)
	[(name, question), .. as rest] => {
		id = match Str.split_on(row, "\t") { [token_id, ..] => token_id, _ => "invalid" }
		next = { criteria: question.criteria, instructions: "${question.instructions} Target row: ${row}", type: question.type }
		add_templates(rows, row, templates, rest, sentence_index, Dict.insert(found, "s${U64.to_str(sentence_index)}.t${id}.${name}", next))
	}
}
