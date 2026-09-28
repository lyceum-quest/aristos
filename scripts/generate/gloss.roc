app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst", http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst" }
import cli.Cmd
import cli.Http
import cli.OsStr
import cli.Path
import http.Request
import http.Response
import Backend
# Gloss stage of scripts/generate/loop.roc. Reads the work config's shared API settings and its `gloss` section.
Config : { allow_fallbacks : Bool, api_key_env : Str, base_url : Str, model : Str, send_temperature : Bool, structured_schema : Bool, temperature : Dec, gloss : { max_tokens : U64, prompt : Str } }
Completion : { choices : List({ message : { content : Str } }) }
ConlluRow : { deprel : Str, deps : Str, feats : Str, form : Str, head : Str, id : Str, lemma : Str, misc : Str, upos : Str, xpos : Str }
GlossPatch : { glosses : List(TokenGloss) }
TokenGloss : { gloss : Str, id : Str }
main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[config_path, input, scratch] => run!(config_path, input, scratch, "api")
	[config_path, input, scratch, backend] => run!(config_path, input, scratch, backend)
	_ => Err(Usage("gloss.roc <config.json> <file.conllu> <scratch-dir> [api|subscription]"))
}
run! = |config_path, input, scratch, backend| {
	config : Config
	config = Json.parse(Path.read_utf8!(Path.utf8(config_path))?)?
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	blocks = List.keep_if(Str.split_on(Str.trim(source), "\n\n"), |block| Str.trim(block) != "")
	# The subscription backend uses the local Claude Code login and needs no API key.
	key = if backend == "subscription" "" else {
		env = Path.read_utf8!(Path.utf8(".env"))?
		prefix = "${config.api_key_env}="
		match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
	}
	completed = complete!(blocks, config, key, backend, scratch, 1, [])?
	Path.write_utf8!(Path.utf8("${scratch}/gloss-output.conllu"), "${Str.join_with(completed, "\n\n")}\n")
}
complete! : List(Str), Config, Str, Str, Str, U64, List(Str) => Try(List(Str), _)
complete! = |blocks, config, key, backend, scratch, index, found| match blocks {
	[] => Ok(found)
	[block, .. as rest] => {
		input = semantic_input!(block, index)?
		token_ids = List.map(input.tokens, |row| row.id)
		stage = config.gloss
		# Synthetic rows remain in the source, but are not gloss request targets or context.
		context = Json.to_str_try({
			request_protocol: "real-tokens-only-v2",
			context_comments: input.context_comments,
			tokens: input.tokens,
			allowed_token_ids: token_ids,
			output_contract: "Return a JSON object with a glosses array of {id, gloss} objects. Return exactly one object for each allowed_token_ids entry, including punctuation. The IDs are strings and may have gaps. Do not fill gaps or return any other IDs. Only tokens listed here may receive glosses.",
		})?
		item_schema = { additionalProperties: Bool.False, properties: { gloss: { minLength: 1, type: "string" }, id: { enum: token_ids, type: "string" } }, required: ["id", "gloss"], type: "object" }
		schema = { additionalProperties: Bool.False, properties: { glosses: { items: item_schema, maxItems: List.len(token_ids), minItems: List.len(token_ids), type: "array" } }, required: ["glosses"], type: "object" }
		body = if config.structured_schema {
			if config.send_temperature {
				Json.to_str_try({ include_reasoning: Bool.False, max_tokens: stage.max_tokens, messages: [{ content: stage.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, provider: { allow_fallbacks: config.allow_fallbacks }, reasoning: { enabled: Bool.False, exclude: Bool.True }, response_format: { json_schema: { name: "contextual_glosses", schema, strict: Bool.True }, type: "json_schema" }, temperature: config.temperature })?
			} else {
				Json.to_str_try({ include_reasoning: Bool.False, max_tokens: stage.max_tokens, messages: [{ content: stage.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, provider: { allow_fallbacks: config.allow_fallbacks }, reasoning: { enabled: Bool.False, exclude: Bool.True }, response_format: { json_schema: { name: "contextual_glosses", schema, strict: Bool.True }, type: "json_schema" } })?
			}
		} else if config.send_temperature {
			Json.to_str_try({ include_reasoning: Bool.False, max_tokens: stage.max_tokens, messages: [{ content: stage.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, provider: { allow_fallbacks: config.allow_fallbacks }, reasoning: { enabled: Bool.False, exclude: Bool.True }, response_format: { type: "json_object" }, temperature: config.temperature })?
		} else {
			Json.to_str_try({ include_reasoning: Bool.False, max_tokens: stage.max_tokens, messages: [{ content: stage.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, provider: { allow_fallbacks: config.allow_fallbacks }, reasoning: { enabled: Bool.False, exclude: Bool.True }, response_format: { type: "json_object" } })?
		}
		raw_response = if backend == "subscription" subscription!(config.model, stage.prompt, context)? else Str.from_utf8(Response.body(Http.send!(Request.from_method(POST).with_uri("${config.base_url}/chat/completions").add_header("Authorization", "Bearer ${key}").add_header("Content-Type", "application/json").with_body(Str.to_utf8(body)))?))?
		# loop.roc reads the usage cost from this file after every attempt.
		_ = Path.write_utf8!(Path.utf8("${scratch}/gloss-api-response.json"), raw_response)?
		reply : Completion
		reply = Json.parse(raw_response)?
		content = match reply.choices { [choice] => Ok(Str.trim(choice.message.content)), _ => Err(InvalidResponse) }?
		_ = Path.write_utf8!(Path.utf8("${scratch}/gloss-response.txt"), "${content}\n")?
		patch : GlossPatch
		patch = Json.parse(structured_content(content))?
		glosses = gloss_dict!(patch.glosses, Dict.empty(), index)?
		completed = apply_glosses!(Str.split_on(block, "\n"), glosses, index, [])?
		complete!(rest, config, key, backend, scratch, index + 1, List.append(found, Str.join_with(completed, "\n")))
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
subscription! = |model, system, user| {
	output = Cmd.new_str("env").args_str(Backend.claude_args(model, system, user)).exec_output!()?
	Backend.completion(output.stdout_utf8)
}
