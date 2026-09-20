app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
Question : { criteria : { false : Str, true : Str }, instructions : Str, type : Str }
Answer : { noul : Dec, type : Str }
Response : { answers : Dict(Str, Answer), model : Str, usage : { input_tokens : U64, output_tokens : U64 } }
Config : { api_key_env : Str, endpoint : Str, model : Str, output_path : Str, questions : Dict(Str, Question), state : Dict(Str, Str) }
main! = |args| match List.drop_first(args, 1) {
	[input_arg] => {
		input = OsStr.display(input_arg)
		config : Config
		config = Json.parse(Path.read_utf8!(Path.utf8("experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/config/audit.config.json"))?)?
		env = Path.read_utf8!(Path.utf8(".env"))?
		prefix = "${config.api_key_env}="
		key = match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
		state = Dict.insert(config.state, "conllu", Path.read_utf8!(Path.utf8(input))?)
		body = Json.to_str_try({ model: config.model, questions: config.questions, state })?
		request_path = "/tmp/aristos-oga-audit-request.json"
		response_path = "/tmp/aristos-oga-audit-response.json"
		_ = Path.write_utf8!(Path.utf8(request_path), body)?
		# Remove curl when a released basic-cli fixes https://github.com/roc-lang/basic-cli/issues/455.
		_ = Cmd.new_str("curl").args_str(["--silent", "--show-error", "--fail-with-body", "--request", "POST", "--header", "Content-Type: application/json", "--variable", "%ARISTOS_TYPESAFE_API_KEY", "--expand-header", "Authorization: Bearer {{ARISTOS_TYPESAFE_API_KEY}}", "--data-binary", "@${request_path}", "--output", response_path, config.endpoint]).env_str("ARISTOS_TYPESAFE_API_KEY", key).exec_output!()?
		reply : Response
		reply = Json.parse(Path.read_utf8!(Path.utf8(response_path))?)?
		_ = (if reply.model != config.model or Dict.len(reply.answers) != Dict.len(config.questions) Err(InvalidJevResponse) else Ok({}))?
		audit = Json.to_str_try({ questions: config.questions, response: reply, source: input, state: config.state })?
		Path.write_utf8!(Path.utf8(config.output_path), "${audit}\n")
	}
	_ => Err(Usage("audit.roc <file.conllu>"))
}
