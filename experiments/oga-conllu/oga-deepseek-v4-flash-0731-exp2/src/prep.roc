app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst", http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst" }
import cli.Http
import cli.OsStr
import cli.Path
import cli.Stdout
import http.Request
import http.Response
Config : { api_key_env : Str, base_url : Str, max_tokens : U64, model : Str, output_dir : Str, prompt : Str, temperature : Dec }
Completion : { choices : List({ message : { content : Str } }) }
Translation : { literal_translation : Str, prose_translation : Str }
main! = |args| match List.drop_first(args, 1) {
	[input] => run!(OsStr.display(input), 0)
	[input, count] => run!(OsStr.display(input), U64.from_str(OsStr.display(count))?)
	_ => Err(Usage("prep.roc <file.conllu> [sentence-count]"))
}
run! = |input, count| {
	config : Config
	config = Json.parse(Path.read_utf8!(Path.utf8("experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/config/prep.config.json"))?)?
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	blocks = List.keep_if(Str.split_on(Str.trim(source), "\n\n"), |block| Str.trim(block) != "")
	selected_blocks = if count == 0 blocks else take(blocks, count, [])
	env = Path.read_utf8!(Path.utf8(".env"))?
	prefix = "${config.api_key_env}="
	key = match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
	completed = complete!(selected_blocks, config, key, 1, [])?
	output = Str.join_with(completed, "\n\n")
	_ = Path.create_all!(Path.utf8(config.output_dir))?
	path = "${config.output_dir}/output.conllu"
	_ = Path.write_utf8!(Path.utf8(path), "${output}\n")?
	Stdout.line!("wrote ${path}")
}
complete! : List(Str), Config, Str, U64, List(Str) => Try(List(Str), _)
complete! = |blocks, config, key, index, found| match blocks {
	[] => Ok(found)
	[block, .. as rest] => {
		body = Json.to_str_try({ include_reasoning: Bool.False, max_tokens: config.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: block, role: "user" }], model: config.model, reasoning: { enabled: Bool.False, exclude: Bool.True }, temperature: config.temperature })?
		response = Http.send!(Request.from_method(POST).with_uri("${config.base_url}/chat/completions").add_header("Authorization", "Bearer ${key}").add_header("Content-Type", "application/json").with_body(Str.to_utf8(body)))?
		raw_response = Str.from_utf8(Response.body(response))?
		_ = Path.write_utf8!(Path.utf8("${config.output_dir}/prep-api-response.json"), raw_response)?
		reply : Completion
		reply = Json.parse(raw_response)?
		content = match reply.choices { [choice] => Ok(Str.trim(choice.message.content)), _ => Err(InvalidResponse) }?
		_ = Path.write_utf8!(Path.utf8("${config.output_dir}/prep-response.txt"), "${content}\n")?
		translation = parse_translation!(content, index)?
		completed = add_translations(block, translation, index)
		complete!(rest, config, key, index + 1, List.append(found, completed))
	}
}
parse_translation! = |content, index| match Str.split_on(content, "\n") {
	[prose_line, literal_line] => match (Str.split_on(prose_line, "\t"), Str.split_on(literal_line, "\t")) {
		(["PROSE", prose_translation], ["LITERAL", literal_translation]) => if single_line(prose_translation) and single_line(literal_translation) {
			Ok({ prose_translation, literal_translation })
		} else {
			Err(InvalidTranslation(index))
		}
		_ => Err(InvalidTranslation(index))
	}
	_ => Err(InvalidTranslation(index))
}
take = |items, count, found| if count == 0 found else match items { [] => found, [item, .. as rest] => take(rest, count - 1, List.append(found, item)) }
single_line = |text| Str.trim(text) != "" and !Str.contains(text, "\n") and !Str.contains(text, "\r")
add_translations = |block, translations, index| {
	metadata = ["# sentence_id = ${U64.to_str(index)}", "# translation_lang = en", "# prose_translation = ${Str.trim(translations.prose_translation)}", "# literal_translation = ${Str.trim(translations.literal_translation)}"]
	match Str.split_on(block, "\n") {
		[first, .. as rest] => Str.join_with(List.concat([first], List.concat(metadata, rest)), "\n")
		[] => Str.join_with(metadata, "\n")
	}
}
