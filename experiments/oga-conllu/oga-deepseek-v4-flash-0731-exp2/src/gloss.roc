app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst", http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst" }
import cli.Http
import cli.OsStr
import cli.Path
import cli.Stdout
import http.Request
import http.Response
Config : { allow_fallbacks : Bool, api_key_env : Str, base_url : Str, max_tokens : U64, model : Str, output_dir : Str, prompt : Str, send_temperature : Bool, structured_schema : Bool, temperature : Dec }
Completion : { choices : List({ message : { content : Str } }) }
ConlluRow : { deprel : Str, deps : Str, feats : Str, form : Str, head : Str, id : Str, lemma : Str, misc : Str, upos : Str, xpos : Str }
GlossPatch : { glosses : List(TokenGloss) }
TokenGloss : { gloss : Str, id : Str }
main! = |args| match List.drop_first(args, 1) {
	[input] => run!(OsStr.display(input), 0)
	[input, count] => run!(OsStr.display(input), U64.from_str(OsStr.display(count))?)
	_ => Err(Usage("gloss.roc <file.conllu> [sentence-count]"))
}
run! = |input, count| {
	config : Config
	config = Json.parse(Path.read_utf8!(Path.utf8("experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/config/gloss.config.json"))?)?
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	blocks = List.keep_if(Str.split_on(Str.trim(source), "\n\n"), |block| Str.trim(block) != "")
	selected_blocks = if count == 0 blocks else take(blocks, count, [])
	env = Path.read_utf8!(Path.utf8(".env"))?
	prefix = "${config.api_key_env}="
	key = match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
	completed = complete!(selected_blocks, config, key, 1, [])?
	output = Str.join_with(completed, "\n\n")
	_ = Path.create_all!(Path.utf8(config.output_dir))?
	path = "${config.output_dir}/gloss-output.conllu"
	_ = Path.write_utf8!(Path.utf8(path), "${output}\n")?
	Stdout.line!("wrote ${path}")
}
complete! : List(Str), Config, Str, U64, List(Str) => Try(List(Str), _)
complete! = |blocks, config, key, index, found| match blocks {
	[] => Ok(found)
	[block, .. as rest] => {
		input = semantic_input!(block, index)?
		context = Json.to_str_try(input)?
		token_ids = List.map(input.tokens, |row| row.id)
		item_schema = { additionalProperties: Bool.False, properties: { gloss: { minLength: 1, type: "string" }, id: { enum: token_ids, type: "string" } }, required: ["id", "gloss"], type: "object" }
		schema = { additionalProperties: Bool.False, properties: { glosses: { items: item_schema, maxItems: List.len(token_ids), minItems: List.len(token_ids), type: "array" } }, required: ["glosses"], type: "object" }
		body = if config.structured_schema {
			if config.send_temperature {
				Json.to_str_try({ include_reasoning: Bool.False, max_tokens: config.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, provider: { allow_fallbacks: config.allow_fallbacks }, reasoning: { enabled: Bool.False, exclude: Bool.True }, response_format: { json_schema: { name: "contextual_glosses", schema, strict: Bool.True }, type: "json_schema" }, temperature: config.temperature })?
			} else {
				Json.to_str_try({ include_reasoning: Bool.False, max_tokens: config.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, provider: { allow_fallbacks: config.allow_fallbacks }, reasoning: { enabled: Bool.False, exclude: Bool.True }, response_format: { json_schema: { name: "contextual_glosses", schema, strict: Bool.True }, type: "json_schema" } })?
			}
		} else if config.send_temperature {
			Json.to_str_try({ include_reasoning: Bool.False, max_tokens: config.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, provider: { allow_fallbacks: config.allow_fallbacks }, reasoning: { enabled: Bool.False, exclude: Bool.True }, response_format: { type: "json_object" }, temperature: config.temperature })?
		} else {
			Json.to_str_try({ include_reasoning: Bool.False, max_tokens: config.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, provider: { allow_fallbacks: config.allow_fallbacks }, reasoning: { enabled: Bool.False, exclude: Bool.True }, response_format: { type: "json_object" } })?
		}
		response = Http.send!(Request.from_method(POST).with_uri("${config.base_url}/chat/completions").add_header("Authorization", "Bearer ${key}").add_header("Content-Type", "application/json").with_body(Str.to_utf8(body)))?
		raw_response = Str.from_utf8(Response.body(response))?
		_ = Path.write_utf8!(Path.utf8("${config.output_dir}/gloss-api-response.json"), raw_response)?
		reply : Completion
		reply = Json.parse(raw_response)?
		content = match reply.choices { [choice] => Ok(Str.trim(choice.message.content)), _ => Err(InvalidResponse) }?
		_ = Path.write_utf8!(Path.utf8("${config.output_dir}/gloss-response.txt"), "${content}\n")?
		patch : GlossPatch
		patch = Json.parse(structured_content(content))?
		glosses = gloss_dict!(patch.glosses, Dict.empty(), index)?
		completed = apply_glosses!(Str.split_on(block, "\n"), glosses, index, [])?
		_ = Stdout.line!("glossed sentence ${U64.to_str(index)}")?
		complete!(rest, config, key, index + 1, List.append(found, Str.join_with(completed, "\n")))
	}
}
structured_content = |content| if Str.starts_with(content, "```json\n") and Str.ends_with(content, "\n```") {
	Str.replace_last(Str.replace_first(content, "```json\n", ""), "\n```", "")
} else {
	content
}
semantic_input! = |block, sentence_index| collect_input!(Str.split_on(block, "\n"), sentence_index, [], [], [])
collect_input! = |lines, sentence_index, comments, omitted, tokens| match lines {
	[] => Ok({ context_comments: comments, omitted_structure: omitted, tokens })
	[line, .. as rest] => if Str.starts_with(line, "#") {
		collect_input!(rest, sentence_index, List.append(comments, line), omitted, tokens)
	} else match Str.split_on(line, "\t") {
		[id, form, lemma, upos, xpos, feats, head, deprel, deps, misc] => {
			row : ConlluRow
			row = { deprel, deps, feats, form, head, id, lemma, misc, upos, xpos }
			if Str.starts_with(misc, "e_") {
				collect_input!(rest, sentence_index, comments, List.append(omitted, row), tokens)
			} else {
				collect_input!(rest, sentence_index, comments, omitted, List.append(tokens, row))
			}
		}
		_ => Err(InvalidSourceRow(sentence_index))
	}
}
take = |items, count, found| if count == 0 found else match items { [] => found, [item, .. as rest] => take(rest, count - 1, List.append(found, item)) }
gloss_dict! = |items, found, sentence_index| match items {
	[] => Ok(found)
	[item, .. as rest] => if item.id == "" or Dict.contains(found, item.id) or !valid_gloss(item.gloss) {
		Err(InvalidGloss(sentence_index, item.id))
	} else {
		gloss_dict!(rest, Dict.insert(found, item.id, item.gloss), sentence_index)
	}
}
apply_glosses! = |lines, glosses, sentence_index, found| match lines {
	[] => if Dict.is_empty(glosses) { Ok(found) } else { Err(UnknownGlossIds(sentence_index)) }
	[line, .. as rest] => if Str.starts_with(line, "#") {
		apply_glosses!(rest, glosses, sentence_index, List.append(found, line))
	} else match Str.split_on(line, "\t") {
		[a, b, c, d, e, f, g, h, i, misc] => if Str.starts_with(misc, "e_") {
			apply_glosses!(rest, glosses, sentence_index, List.append(found, line))
		} else {
			gloss = Dict.get(glosses, a) ? |_| MissingGloss(sentence_index, a)
			_ = (if d != "u" and gloss == b { Err(CopiedGreekForm(sentence_index, a)) } else { Ok({}) })?
			next_misc = if misc == "_" { "gloss=${gloss}" } else { "${misc}|gloss=${gloss}" }
			next_line = Str.join_with([a, b, c, d, e, f, g, h, i, next_misc], "\t")
			apply_glosses!(rest, Dict.remove(glosses, a), sentence_index, List.append(found, next_line))
		}
		_ => Err(InvalidSourceRow(sentence_index))
	}
}
valid_gloss = |gloss| Str.trim(gloss) != "" and !Str.contains(gloss, "|") and !Str.contains(gloss, "\t") and !Str.contains(gloss, "\n") and !Str.contains(gloss, "\r")
