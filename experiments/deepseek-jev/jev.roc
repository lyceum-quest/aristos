app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
Item : { gloss : Str, morphology : Dict(Str, Str), sent_id : U64, sentence : Str, word : Str }
Marked : { gloss : Str, morphology : Dict(Str, Str), noul : Dec, sent_id : U64, sentence : Str, valid : Bool, word : Str }
Question : { criteria : { false : Str, true : Str }, instructions : Str, type : Str }
Answer : { noul : Dec, type : Str }
JevResponse : { answers : Dict(Str, Answer), model : Str, usage : { input_tokens : U64, output_tokens : U64 } }
main! = |args| match List.drop_first(args, 1) {
	[input_arg] => {
		input = OsStr.display(input_arg)
		items : List(Item)
		items = Json.parse(Path.read_utf8!(Path.utf8(input))?)?
		key = Env.var_str!(OsStr.from_str("TYPESAFE_API_KEY")) ?? ""
		_ = (if key == "" Err(MissingTypesafeApiKey) else Ok({}))?
		questions = questions_for(items, 0, Dict.empty())
		state = { source_passage: passage(items, 0, ""), tokens: items, task: "Judge each token/gloss pair independently. Do not compare tokens or propose replacements." }
		body = Json.to_str_try({ model: "jev-1.13.0", questions, state })?
		request_path = "experiments/deepseek-jev/calls/jev/requests/request.json"
		response_path = "experiments/deepseek-jev/calls/jev/responses/response.json"
		_ = Path.create_all!(Path.utf8("experiments/deepseek-jev/calls/jev/requests"))?
		_ = Path.create_all!(Path.utf8("experiments/deepseek-jev/calls/jev/responses"))?
		_ = Path.write_utf8!(Path.utf8(request_path), "${body}\n")?
		# Remove curl when a released basic-cli fixes https://github.com/roc-lang/basic-cli/issues/455.
		_ = Cmd.new_str("curl").args_str(["--silent", "--show-error", "--fail-with-body", "--request", "POST", "--header", "Content-Type: application/json", "--variable", "%ARISTOS_TYPESAFE_API_KEY", "--expand-header", "Authorization: Bearer {{ARISTOS_TYPESAFE_API_KEY}}", "--data-binary", "@${request_path}", "--output", response_path, "https://api.typesafe.ai/v1/systemone"]).env_str("ARISTOS_TYPESAFE_API_KEY", key).exec_output!()?
		reply : JevResponse
		reply = Json.parse(Path.read_utf8!(Path.utf8(response_path))?)?
		_ = (if reply.model != "jev-1.13.0" or Dict.len(reply.answers) != List.len(items) Err(InvalidJevResponse) else Ok({}))?
		marked = mark!(items, 0, reply.answers, [])?
		Path.write_utf8!(Path.utf8(input), "${Json.to_str_try(marked)?}\n")
	}
	_ => Err(Usage)
}
questions_for : List(Item), U64, Dict(Str, Question) => Dict(Str, Question)
questions_for = |items, index, found| match items { [] => found, [_, .. as rest] => questions_for(rest, index + 1, Dict.insert(found, "token_${U64.to_str(index + 1)}", { criteria: { true: "True if the gloss conveys the correct contextual lexical sense and does not contradict the token's morphology or syntactic role. Reasonable synonyms and concise omissions are allowed.", false: "False if the gloss has the wrong sense, referent, number, person, tense, mood, voice, case contribution, or syntactic force; adds unsupported meaning; or would materially mislead a reader about the passage." }, instructions: "Given `source_passage` as context, is `tokens[${U64.to_str(index)}].gloss` an acceptable concise contextual English gloss for this exact occurrence of `tokens[${U64.to_str(index)}].word`? Judge only this pair and do not propose an alternative.", type: "noul" })) }
passage = |items, last_id, found| match items { [] => found, [item, .. as rest] => if item.sent_id == last_id passage(rest, last_id, found) else passage(rest, item.sent_id, if found == "" item.sentence else "${found}\n${item.sentence}") }
mark! : List(Item), U64, Dict(Str, Answer), List(Marked) => Try(List(Marked), _)
mark! = |items, index, answers, found| match items {
	[] => Ok(found)
	[item, .. as rest] => {
		answer = Dict.get(answers, "token_${U64.to_str(index + 1)}") ? |_| MissingJevAnswer(index + 1)
		_ = (if answer.type != "noul" or answer.noul < 0 or answer.noul > 1 Err(InvalidJevAnswer(index + 1)) else Ok({}))?
		next = { gloss: item.gloss, morphology: item.morphology, noul: answer.noul, sent_id: item.sent_id, sentence: item.sentence, valid: answer.noul >= 0.5, word: item.word }
		mark!(rest, index + 1, answers, List.append(found, next))
	}
}
