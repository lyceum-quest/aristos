app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
Question : { criteria : { false : Str, true : Str }, instructions : Str, type : Str }
AuditItem : { questions : Dict(Str, Question), response : { answers : Dict(Str, { noul : Dec, type : Str }) }, sentence : Str }
Config : { api_key_env : Str, endpoint : Str, model : Str, output_path : Str, prompt : Str, request : { frequency_penalty : Dec, include_reasoning : Bool, max_tokens : U64, presence_penalty : Dec, provider : { allow_fallbacks : Bool, only : List(Str), require_parameters : Bool }, reasoning : { enabled : Bool, exclude : Bool }, seed : U64, temperature : Dec, top_k : U64, top_p : Dec }, threshold : Dec }
main! = |args| match List.drop_first(args, 1) {
	[input_arg, audit_arg] => {
		input = OsStr.display(input_arg)
		config : Config
		config = Json.parse(Path.read_utf8!(Path.utf8("experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2/config/improve.config.json"))?)?
		audit : { audits : List(AuditItem) }
		audit = Json.parse(Path.read_utf8!(Path.utf8(OsStr.display(audit_arg)))?)?
		source = Str.trim(Path.read_utf8!(Path.utf8(input))?)
		_ = (if source != Str.join_with(List.map(audit.audits, |item| item.sentence), "\n\n") Err(StaleAudit) else Ok({}))?
		env = Path.read_utf8!(Path.utf8(".env"))?
		prefix = "${config.api_key_env}="
		key = match List.keep_if(Str.split_on(env, "\n"), |line| Str.starts_with(line, prefix)) { [line, ..] => Ok(Str.replace_first(line, prefix, "")), [] => Err(MissingApiKey(config.api_key_env)) }?
		improved = improve!(audit.audits, config, key, [])?
		_ = Path.write_utf8!(Path.utf8(config.output_path), "${Str.join_with(improved, "\n\n")}\n")?
		Ok({})
	}
	_ => Err(Usage("improve.roc <file.conllu> <audit.json>"))
}
improve! : List(AuditItem), Config, Str, List(Str) => Try(List(Str), _)
improve! = |audits, config, key, found| match audits {
	[] => Ok(found)
	[item, .. as rest] => {
		answers = Dict.keep_if(item.response.answers, |(_, answer)| answer.noul < config.threshold)
		questions = Dict.keep_if(item.questions, |(name, _)| Dict.contains(answers, name))
		if Dict.is_empty(answers) { improve!(rest, config, key, List.append(found, item.sentence)) } else {
			context = Json.to_str_try({ audit: { answers, questions, threshold: config.threshold }, conllu: item.sentence })?
			schema = { additionalProperties: Bool.False, properties: { changes: { items: { additionalProperties: Bool.False, properties: { finding: { type: "string" }, new_line: { type: "string" }, old_line: { type: "string" } }, required: ["finding", "old_line", "new_line"], type: "object" }, type: "array" } }, required: ["changes"], type: "object" }
			body = Json.to_str_try({ frequency_penalty: config.request.frequency_penalty, include_reasoning: config.request.include_reasoning, max_tokens: config.request.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, presence_penalty: config.request.presence_penalty, provider: config.request.provider, reasoning: config.request.reasoning, response_format: { json_schema: { name: "conllu_line_patch", schema, strict: Bool.True }, type: "json_schema" }, seed: config.request.seed, temperature: config.request.temperature, top_k: config.request.top_k, top_p: config.request.top_p })?
			_ = Path.write_utf8!(Path.utf8("/tmp/aristos-oga-improve-request.json"), body)?
			_ = Cmd.new_str("curl").args_str(["--silent", "--show-error", "--fail-with-body", "--request", "POST", "--header", "Content-Type: application/json", "--variable", "%ARISTOS_PPQ_API_KEY", "--expand-header", "Authorization: Bearer {{ARISTOS_PPQ_API_KEY}}", "--data-binary", "@/tmp/aristos-oga-improve-request.json", "--output", "/tmp/aristos-oga-improve-response.json", config.endpoint]).env_str("ARISTOS_PPQ_API_KEY", key).exec_output!()?
			reply : { choices : List({ finish_reason : Str, message : { content : Try(Str, [Missing]) } }) }
			reply = Json.parse(Path.read_utf8!(Path.utf8("/tmp/aristos-oga-improve-response.json"))?)?
			patch : { changes : List({ finding : Str, new_line : Str, old_line : Str }) }
			patch = match reply.choices { [choice] => if choice.finish_reason != "stop" Err(IncompleteCompletion(choice.finish_reason)) else match choice.message.content { Ok(content) => Json.parse(content), Err(Missing) => Err(MissingCompletionContent) }, _ => Err(InvalidResponse) }?
			improve!(rest, config, key, List.append(found, apply!(item.sentence, patch.changes, answers)?))
		}
	}
}
apply! = |sentence, changes, answers| match changes { [] => Ok(sentence), [change, .. as rest] => if !Dict.contains(answers, change.finding) Err(UnauthorizedFinding(change.finding)) else if !List.contains(Str.split_on(sentence, "\n"), change.old_line) or !allowed(change) Err(InvalidChange(change.finding)) else apply!(Str.replace_first(sentence, change.old_line, change.new_line), rest, answers) }
allowed = |change| if change.old_line == change.new_line or Str.contains(change.new_line, "\n") or Str.contains(change.new_line, "\r") { Bool.False } else if Str.ends_with(change.finding, ".prose_accuracy") or Str.ends_with(change.finding, ".prose_fluency") { Str.starts_with(change.old_line, "# prose_translation = ") and Str.starts_with(change.new_line, "# prose_translation = ") } else if Str.ends_with(change.finding, ".literal_accuracy") or Str.ends_with(change.finding, ".literal_structure") { Str.starts_with(change.old_line, "# literal_translation = ") and Str.starts_with(change.new_line, "# literal_translation = ") } else if Str.ends_with(change.finding, ".metadata") { Str.starts_with(change.old_line, "#") and Str.starts_with(change.new_line, "#") and !Str.contains(change.old_line, "translation = ") } else { allowed_row(change.finding, Str.split_on(change.old_line, "\t"), Str.split_on(change.new_line, "\t")) }
allowed_row = |finding, old, new| match (old, new) { ([a,b,c,d,e,f,g,h,i,j], [aa,bb,cc,dd,ee,ff,gg,hh,ii,jj]) => a == aa and b == bb and if Str.ends_with(finding, ".lemma") { d == dd and e == ee and f == ff and g == gg and h == hh and i == ii and j == jj } else if Str.ends_with(finding, ".pos") { c == cc and f == ff and g == gg and h == hh and i == ii and j == jj } else if Str.ends_with(finding, ".morphology") { c == cc and d == dd and g == gg and h == hh and i == ii and j == jj } else if Str.ends_with(finding, ".head") { c == cc and d == dd and e == ee and f == ff and h == hh and i == ii and j == jj } else if Str.ends_with(finding, ".deprel") { c == cc and d == dd and e == ee and f == ff and g == gg and j == jj } else if Str.ends_with(finding, ".gloss_lexical") or Str.ends_with(finding, ".gloss_grammar") { c == cc and d == dd and e == ee and f == ff and g == gg and h == hh and i == ii and misc_without_gloss(j) == misc_without_gloss(jj) and (Str.starts_with(j, "e_") or List.any(Str.split_on(jj, "|"), |field| Str.starts_with(field, "gloss=") and field != "gloss=")) } else { Bool.False }, _ => Bool.False }
misc_without_gloss = |misc| Str.join_with(List.keep_if(Str.split_on(misc, "|"), |field| !Str.starts_with(field, "gloss=")), "|")
