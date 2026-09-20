app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst", http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst" }
import cli.Http
import cli.OsStr
import cli.Path
import cli.Stdout
import http.Request
import http.Response
Config : { api_key_env : Str, base_url : Str, max_tokens : U64, model : Str, output_dir : Str, prompt : Str, temperature : Dec }
Completion : { choices : List({ message : { content : Str } }) }
fields = ["sentence_id", "translation_lang", "prose_translation", "literal_translation"]
main! = |args| match List.drop_first(args, 1) {
	[input] => run!(OsStr.display(input), 0)
	[input, count] => run!(OsStr.display(input), U64.from_str(OsStr.display(count))?)
	_ => Err(Usage("prep.roc <file.conllu> [sentence-count]"))
}
run! = |input, count| {
	config : Config
	config = Json.parse(Path.read_utf8!(Path.utf8("experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/config.json"))?)?
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	blocks = List.keep_if(Str.split_on(Str.trim(source), "\n\n"), |block| Str.trim(block) != "")
	selected_blocks = if count == 0 blocks else take(blocks, count, [])
	selected = Str.join_with(selected_blocks, "\n\n")
	env = Path.read_utf8!(Path.utf8(".env"))?
	prefix = "${config.api_key_env}="
	key = match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
	body = Json.to_str_try({ max_tokens: config.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: selected, role: "user" }], model: config.model, temperature: config.temperature })?
	response = Http.send!(Request.from_method(POST).with_uri("${config.base_url}/chat/completions").add_header("Authorization", "Bearer ${key}").add_header("Content-Type", "application/json").with_body(Str.to_utf8(body)))?
	reply : Completion
	reply = Json.parse(Str.from_utf8(Response.body(response))?)?
	output = match reply.choices { [choice] => Ok(Str.trim(choice.message.content)), _ => Err(InvalidResponse) }?
	output_blocks = List.keep_if(Str.split_on(output, "\n\n"), |block| Str.trim(block) != "")
	if List.len(output_blocks) != List.len(selected_blocks) or !List.all(output_blocks, valid_block) {
		Err(InvalidSentenceComments)
	} else if strip_added(output) != selected {
		Err(SourceRowsChanged)
	} else {
		_ = Path.create_all!(Path.utf8(config.output_dir))?
		path = "${config.output_dir}/output.conllu"
		_ = Path.write_utf8!(Path.utf8(path), "${output}\n")?
		Stdout.line!("wrote ${path}")
	}
}
take = |items, count, found| if count == 0 found else match items { [] => found, [item, .. as rest] => take(rest, count - 1, List.append(found, item)) }
is_added = |line| List.any(fields, |field| Str.starts_with(line, "# ${field} = "))
strip_added = |text| Str.join_with(List.keep_if(Str.split_on(Str.trim(text), "\n"), |line| !is_added(line)), "\n")
valid_block = |block| List.all(fields, |field| {
	prefix = "# ${field} = "
	List.len(List.keep_if(Str.split_on(block, "\n"), |line| Str.starts_with(line, prefix) and line != prefix)) == 1
})
