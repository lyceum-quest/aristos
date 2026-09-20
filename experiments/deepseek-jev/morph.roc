app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
Item : { gloss : Str, sent_id : U64, sentence : Str, word : Str }
Marked : { gloss : Str, morphology : Dict(Str, Str), sent_id : U64, sentence : Str, word : Str }
Question : { criteria : Dict(Str, Str), instructions : Str, type : Str }
Config : { model : Str, questions : Dict(Str, Question), state : { sentence : Str, word : Str } }
Answer : { choice : Str, confidence : Dec, probabilities : Dict(Str, Dec), type : Str }
JevResponse : { answers : Dict(Str, Answer), model : Str, usage : { input_tokens : U64, output_tokens : U64 } }
main! = |args| match List.drop_first(args, 1) {
	[input_arg] => {
		input = OsStr.display(input_arg)
		config : Config
		config = Json.parse(Path.read_utf8!(Path.utf8("experiments/deepseek-jev/morph.config.json"))?)?
		items : List(Item)
		items = Json.parse(Path.read_utf8!(Path.utf8(input))?)?
		key = Env.var_str!(OsStr.from_str("TYPESAFE_API_KEY")) ?? ""
		_ = (if key == "" Err(MissingTypesafeApiKey) else Ok({}))?
		result = run!(items, config, key, [], [])?
		_ = Path.write_utf8!(Path.utf8(Str.replace_last(input, ".json", ".morph.jev.json")), "${Json.to_str_try(result.responses)?}\n")?
		Path.write_utf8!(Path.utf8(input), "${Json.to_str_try(result.items)?}\n")
	}
	_ => Err(Usage)
}
run! : List(Item), Config, Str, List(Marked), List({ response : JevResponse, sentence : Str, word : Str }) => Try({ items : List(Marked), responses : List({ response : JevResponse, sentence : Str, word : Str }) }, _)
run! = |items, config, key, marked, responses| match items {
	[] => Ok({ items: marked, responses })
	[item, .. as rest] => {
		body = Json.to_str_try({ model: config.model, questions: config.questions, state: { sentence: item.sentence, word: item.word } })?
		_ = Path.write_utf8!(Path.utf8("/tmp/aristos-morph-request.json"), "${body}\n")?
		# Remove curl when a released basic-cli fixes https://github.com/roc-lang/basic-cli/issues/455.
		_ = Cmd.new_str("curl").args_str(["--silent", "--show-error", "--fail-with-body", "--request", "POST", "--header", "Content-Type: application/json", "--variable", "%ARISTOS_TYPESAFE_API_KEY", "--expand-header", "Authorization: Bearer {{ARISTOS_TYPESAFE_API_KEY}}", "--data-binary", "@/tmp/aristos-morph-request.json", "--output", "/tmp/aristos-morph-response.json", "https://api.typesafe.ai/v1/systemone"]).env_str("ARISTOS_TYPESAFE_API_KEY", key).exec_output!()?
		reply : JevResponse
		reply = Json.parse(Path.read_utf8!(Path.utf8("/tmp/aristos-morph-response.json"))?)?
		_ = (if reply.model != config.model or Dict.len(reply.answers) != Dict.len(config.questions) Err(InvalidJevResponse) else Ok({}))?
		morphology = clean!(["part_of_speech", "case", "gender", "number", "person", "tense", "mood", "voice", "verb_form", "degree"], reply.answers, Dict.empty())?
		next = { gloss: item.gloss, morphology, sent_id: item.sent_id, sentence: item.sentence, word: item.word }
		run!(rest, config, key, List.append(marked, next), List.append(responses, { response: reply, sentence: item.sentence, word: item.word }))
	}
}
clean! = |fields, answers, found| match fields {
	[] => Ok(found)
	[field, .. as rest] => {
		answer = Dict.get(answers, field) ? |_| MissingAnswer(field)
		_ = (if answer.type != "choice" or answer.confidence < 0 or answer.confidence > 1 Err(InvalidAnswer(field)) else Ok({}))?
		clean!(rest, answers, if answer.choice == "not_applicable" found else Dict.insert(found, field, answer.choice))
	} }
