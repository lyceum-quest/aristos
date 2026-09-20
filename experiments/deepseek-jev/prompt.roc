app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst", http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst" }
import cli.Env
import cli.Http
import cli.OsStr
import cli.Path
import http.Request
import http.Response
Item : { gloss : Str, morphology : Dict(Str, Str), sent_id : U64, sentence : Str, word : Str }
Generation : { frequency_penalty : Dec, include_reasoning : Bool, max_tokens : U64, presence_penalty : Dec, provider : { allow_fallbacks : Bool, only : List(Str), require_parameters : Bool }, reasoning : { enabled : Bool, exclude : Bool }, seed : U64, temperature : Dec, top_k : U64, top_p : Dec }
Config : { batch_size : U64, model : Str, prompt : Str, request : Generation }
main! = |args| match List.drop_first(args, 1) {
		[input_arg] => {
			input = OsStr.display(input_arg)
			config : Config
			config = Json.parse(Path.read_utf8!(Path.utf8("experiments/deepseek-jev/prompt.config.json"))?)?
			items = Json.parse(Path.read_utf8!(Path.utf8(input))?)?
			key = Env.var_str!(OsStr.from_str("PPQ_API_KEY")) ?? ""
			_ = Path.create_all!(Path.utf8("experiments/deepseek-jev/calls/requests"))?
			_ = Path.create_all!(Path.utf8("experiments/deepseek-jev/calls/responses"))?
			filled = fill!(items, config, key, 1, [])?
			Path.write_utf8!(Path.utf8(input), "${Json.to_str_try(filled)?}\n")
		}
		_ => Err(Usage)
	}
fill! : List(Item), Config, Str, U64, List(Item) => Try(List(Item), _)
fill! = |items, config, key, index, found|
	if List.is_empty(items) Ok(found) else {
		batch = take(items, config.batch_size, [])
		rest = drop(items, config.batch_size)
		context = Json.to_str_try(List.map(batch, |item| { morphology: item.morphology, sent_id: item.sent_id, sentence: item.sentence, word: item.word }))?
		body = Json.to_str_try({ frequency_penalty: config.request.frequency_penalty, include_reasoning: config.request.include_reasoning, max_tokens: config.request.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, presence_penalty: config.request.presence_penalty, provider: config.request.provider, reasoning: config.request.reasoning, response_format: { json_schema: { name: "batch_glosses", schema: { additionalProperties: Bool.False, properties: { glosses: { items: { minLength: 1, type: "string" }, maxItems: List.len(batch), minItems: List.len(batch), type: "array" } }, required: ["glosses"], type: "object" }, strict: Bool.True }, type: "json_schema" }, seed: config.request.seed, temperature: config.request.temperature, top_k: config.request.top_k, top_p: config.request.top_p })?
		_ = Path.write_utf8!(Path.utf8("experiments/deepseek-jev/calls/requests/batch-${U64.to_str(index)}.json"), "${body}\n")?
		response = Http.send!(Request.from_method(POST).with_uri("https://api.ppq.ai/v1/chat/completions").add_header("Authorization", "Bearer ${key}").add_header("Content-Type", "application/json").with_body(Str.to_utf8(body)))?
		raw = Response.body(response)
		_ = Path.write_bytes!(Path.utf8("experiments/deepseek-jev/calls/responses/batch-${U64.to_str(index)}.json"), raw)?
		reply : { choices : List({ message : { content : Str } }), model : Str, provider : Str }
		reply = Json.parse(Str.from_utf8(raw)?)?
		match reply.choices {
			[choice] => {
				payload : { glosses : List(Str) }
				payload = Json.parse(choice.message.content)?
				fill!(rest, config, key, index + 1, List.concat(found, apply(batch, payload.glosses, [])?))
			}
			_ => Err(InvalidResponse(index))
		}
	}
take = |items, count, found| if count == 0 found else match items { [] => found, [item, .. as rest] => take(rest, count - 1, List.append(found, item)) }
drop = |items, count| if count == 0 items else match items { [] => [], [_, .. as rest] => drop(rest, count - 1) }
apply = |items, glosses, found| match (items, glosses) { ([], []) => Ok(found), ([item, .. as rest], [gloss, .. as more]) => apply(rest, more, List.append(found, { gloss: Str.trim(gloss), morphology: item.morphology, sent_id: item.sent_id, sentence: item.sentence, word: item.word })), _ => Err(GlossCountMismatch) }
