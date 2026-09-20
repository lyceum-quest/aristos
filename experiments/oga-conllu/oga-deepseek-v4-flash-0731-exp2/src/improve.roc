app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst", http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst" }
import cli.Http
import cli.OsStr
import cli.Path
import cli.Stdout
import http.Request
import http.Response
Question : { criteria : { false : Str, true : Str }, instructions : Str, type : Str }
Answer : { noul : Dec, type : Str }
Audit : { questions : Dict(Str, Question), response : { answers : Dict(Str, Answer) } }
Config : { api_key_env : Str, base_url : Str, max_tokens : U64, model : Str, output_path : Str, prompt : Str, temperature : Dec, threshold : Dec }
Completion : { choices : List({ message : { content : Str } }) }
main! = |args| match List.drop_first(args, 1) {
	[input_arg, audit_arg] => {
		input = OsStr.display(input_arg)
		config : Config
		config = Json.parse(Path.read_utf8!(Path.utf8("experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/config/improve.config.json"))?)?
		audit : Audit
		audit = Json.parse(Path.read_utf8!(Path.utf8(OsStr.display(audit_arg)))?)?
		answers = Dict.keep_if(audit.response.answers, |(_, answer)| answer.noul < config.threshold)
		questions = Dict.keep_if(audit.questions, |(name, _)| Dict.contains(answers, name))
		_ = (if Dict.is_empty(answers) Err(NoFailedAuditFindings) else Ok({}))?
		env = Path.read_utf8!(Path.utf8(".env"))?
		prefix = "${config.api_key_env}="
		key = match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
		conllu = Path.read_utf8!(Path.utf8(input))?
		context = Json.to_str_try({ audit: { answers, questions, threshold: config.threshold }, conllu })?
		body = Json.to_str_try({ max_tokens: config.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, temperature: config.temperature })?
		response = Http.send!(Request.from_method(POST).with_uri("${config.base_url}/chat/completions").add_header("Authorization", "Bearer ${key}").add_header("Content-Type", "application/json").with_body(Str.to_utf8(body)))?
		reply : Completion
		reply = Json.parse(Str.from_utf8(Response.body(response))?)?
		output = match reply.choices { [choice] => Ok(Str.trim(choice.message.content)), _ => Err(InvalidResponse) }?
		_ = (if nonempty_lines(conllu) != nonempty_lines(output) Err(LineCountChanged) else Ok({}))?
		_ = Path.write_utf8!(Path.utf8(config.output_path), "${output}\n")?
		Stdout.line!("wrote ${config.output_path}")
	}
	_ => Err(Usage("improve.roc <file.conllu> <audit.json>"))
}
nonempty_lines = |text| List.len(List.keep_if(Str.split_on(Str.trim(text), "\n"), |line| Str.trim(line) != ""))
