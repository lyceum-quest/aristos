app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst", http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst" }
import cli.Http
import cli.OsStr
import cli.Path
import cli.Stdout
import http.Request
import http.Response
Config : { api_key_env : Str, base_url : Str, max_tokens : U64, model : Str, output_dir : Str, prompt : Str, temperature : Dec }
Completion : { choices : List({ message : { content : Str } }) }
main! = |args| match List.drop_first(args, 1) {
	[input] => run!(OsStr.display(input), 0)
	[input, count] => run!(OsStr.display(input), U64.from_str(OsStr.display(count))?)
	_ => Err(Usage("gloss.roc <file.conllu> [sentence-count]"))
}
run! = |input, count| {
	config : Config
	config = Json.parse(Path.read_utf8!(Path.utf8("experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/gloss.config.json"))?)?
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	blocks = List.keep_if(Str.split_on(Str.trim(source), "\n\n"), |block| Str.trim(block) != "")
	selected = Str.join_with(if count == 0 blocks else take(blocks, count, []), "\n\n")
	env = Path.read_utf8!(Path.utf8(".env"))?
	prefix = "${config.api_key_env}="
	key = match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
	body = Json.to_str_try({ max_tokens: config.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: selected, role: "user" }], model: config.model, temperature: config.temperature })?
	response = Http.send!(Request.from_method(POST).with_uri("${config.base_url}/chat/completions").add_header("Authorization", "Bearer ${key}").add_header("Content-Type", "application/json").with_body(Str.to_utf8(body)))?
	reply : Completion
	reply = Json.parse(Str.from_utf8(Response.body(response))?)?
	output = match reply.choices { [choice] => Ok(Str.trim(choice.message.content)), _ => Err(InvalidResponse) }?
	if !valid_lines(Str.split_on(selected, "\n"), Str.split_on(output, "\n")) {
		Err(SourceRowsChanged)
	} else {
		_ = Path.create_all!(Path.utf8(config.output_dir))?
		path = "${config.output_dir}/gloss-output.conllu"
		_ = Path.write_utf8!(Path.utf8(path), "${output}\n")?
		Stdout.line!("wrote ${path}")
	}
}
take = |items, count, found| if count == 0 found else match items { [] => found, [item, .. as rest] => take(rest, count - 1, List.append(found, item)) }
artificial = |line| Str.contains(line, "\te_")
valid_lines = |source, output| match (source, output) {
	([], []) => Bool.True
	([original, .. as more], [generated, .. as rest]) => {
		prefix = "${original}|gloss="
		gloss = if Str.starts_with(generated, prefix) Str.replace_first(generated, prefix, "") else ""
		valid = if original == "" or Str.starts_with(original, "#") or artificial(original) generated == original else gloss != "" and !Str.contains(gloss, "|") and !Str.contains(gloss, "\t")
		valid and valid_lines(more, rest)
	}
	_ => Bool.False
}
