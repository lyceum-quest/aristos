app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
Question : { criteria : { false : Str, true : Str }, instructions : Str, type : Str }
AuditItem : { questions : Dict(Str, Question), response : { answers : Dict(Str, { noul : Dec, type : Str }) }, sentence : Str }
Resolution : { action : Str, finding : Str, new_line : Str, old_line : Str, reason : Str }
Config : { api_key_env : Str, endpoint : Str, model : Str, output_path : Str, prompt : Str, request : { frequency_penalty : Dec, include_reasoning : Bool, max_tokens : U64, presence_penalty : Dec, provider : { allow_fallbacks : Bool, only : List(Str), require_parameters : Bool }, reasoning : { enabled : Bool, exclude : Bool }, seed : U64, temperature : Dec, top_k : U64, top_p : Dec }, resolutions_path : Str, threshold : Dec }
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
		empty : List(Resolution)
		empty = []
		_ = Path.write_utf8!(Path.utf8(config.resolutions_path), "${Json.to_str_try({ resolutions: empty, status: "pending" })?}\n")?
		result = improve!(audit.audits, config, key, [], [])?
		_ = Path.write_utf8!(Path.utf8(config.output_path), "${Str.join_with(result.improved, "\n\n")}\n")?
		_ = Path.write_utf8!(Path.utf8(config.resolutions_path), "${Json.to_str_try({ resolutions: result.resolutions, status: "applied" })?}\n")?
		Ok({})
	}
	_ => Err(Usage("improve.roc <file.conllu> <audit.json>"))
}
improve! : List(AuditItem), Config, Str, List(Str), List(Resolution) => Try({ improved : List(Str), resolutions : List(Resolution) }, _)
improve! = |audits, config, key, found, resolved| match audits {
	[] => Ok({ improved: found, resolutions: resolved })
	[item, .. as rest] => {
		answers = Dict.keep_if(item.response.answers, |(_, answer)| answer.noul < config.threshold)
		questions = Dict.keep_if(item.questions, |(name, _)| Dict.contains(answers, name))
		if Dict.is_empty(answers) { improve!(rest, config, key, List.append(found, item.sentence), resolved) } else {
			context = Json.to_str_try({ audit: { answers, questions, threshold: config.threshold }, conllu: item.sentence })?
			resolution_schema = { additionalProperties: Bool.False, properties: { action: { enum: ["patch", "reject"], type: "string" }, finding: { type: "string" }, new_line: { type: "string" }, old_line: { type: "string" }, reason: { type: "string" } }, required: ["finding", "action", "old_line", "new_line", "reason"], type: "object" }
			schema = { additionalProperties: Bool.False, properties: { resolutions: { items: resolution_schema, type: "array" } }, required: ["resolutions"], type: "object" }
			body = Json.to_str_try({ frequency_penalty: config.request.frequency_penalty, include_reasoning: config.request.include_reasoning, max_tokens: config.request.max_tokens, messages: [{ content: config.prompt, role: "system" }, { content: context, role: "user" }], model: config.model, presence_penalty: config.request.presence_penalty, provider: config.request.provider, reasoning: config.request.reasoning, response_format: { json_schema: { name: "conllu_audit_resolutions", schema, strict: Bool.True }, type: "json_schema" }, seed: config.request.seed, temperature: config.request.temperature, top_k: config.request.top_k, top_p: config.request.top_p })?
			_ = Path.write_utf8!(Path.utf8("/tmp/aristos-oga-improve-request.json"), body)?
			_ = Cmd.new_str("curl").args_str(["--silent", "--show-error", "--fail-with-body", "--request", "POST", "--header", "Content-Type: application/json", "--variable", "%ARISTOS_PPQ_API_KEY", "--expand-header", "Authorization: Bearer {{ARISTOS_PPQ_API_KEY}}", "--data-binary", "@/tmp/aristos-oga-improve-request.json", "--output", "/tmp/aristos-oga-improve-response.json", config.endpoint]).env_str("ARISTOS_PPQ_API_KEY", key).exec_output!()?
			reply : { choices : List({ finish_reason : Str, message : { content : Try(Str, [Missing]) } }) }
			reply = Json.parse(Path.read_utf8!(Path.utf8("/tmp/aristos-oga-improve-response.json"))?)?
			patch : { resolutions : List(Resolution) }
			patch = match reply.choices { [choice] => if choice.finish_reason != "stop" Err(IncompleteCompletion(choice.finish_reason)) else match choice.message.content { Ok(content) => Json.parse(content), Err(Missing) => Err(MissingCompletionContent) }, _ => Err(InvalidResponse) }?
			next_resolved = List.concat(resolved, patch.resolutions)
			_ = Path.write_utf8!(Path.utf8(config.resolutions_path), "${Json.to_str_try({ resolutions: next_resolved, status: "proposed" })?}\n")?
			_ = validate_resolutions!(patch.resolutions, answers, Dict.empty())?
			improved = apply!(item.sentence, patch.resolutions, answers)?
			improve!(rest, config, key, List.append(found, improved), next_resolved)
		}
	}
}
validate_resolutions! = |resolutions, answers, seen| match resolutions {
	[] => if Dict.len(seen) == Dict.len(answers) Ok({}) else Err(MissingResolutions)
	[resolution, .. as rest] => if !Dict.contains(answers, resolution.finding) { Err(UnauthorizedFinding(resolution.finding)) } else if Dict.contains(seen, resolution.finding) { Err(DuplicateResolution(resolution.finding)) } else if Str.trim(resolution.reason) == "" { Err(MissingResolutionReason(resolution.finding)) } else if resolution.action == "patch" { validate_resolutions!(rest, answers, Dict.insert(seen, resolution.finding, Bool.True)) } else if resolution.action == "reject" and resolution.old_line == "" and resolution.new_line == "" { validate_resolutions!(rest, answers, Dict.insert(seen, resolution.finding, Bool.True)) } else { Err(InvalidResolution(resolution.finding)) }
}
apply! = |sentence, resolutions, answers| match resolutions {
	[] => Ok(sentence)
	[resolution, .. as rest] => if resolution.action == "reject" { apply!(sentence, rest, answers) } else if !Dict.contains(answers, resolution.finding) { Err(UnauthorizedFinding(resolution.finding)) } else if List.contains(Str.split_on(sentence, "\n"), resolution.new_line) { apply!(sentence, rest, answers) } else if !List.contains(Str.split_on(sentence, "\n"), resolution.old_line) or !allowed(resolution) { Err(InvalidChange(resolution.finding)) } else { apply!(Str.replace_first(sentence, resolution.old_line, resolution.new_line), rest, answers) }
}
allowed = |resolution| if resolution.old_line == resolution.new_line or Str.contains(resolution.new_line, "\n") or Str.contains(resolution.new_line, "\r") { Bool.False } else if Str.ends_with(resolution.finding, ".prose_accuracy") or Str.ends_with(resolution.finding, ".prose_fluency") { Str.starts_with(resolution.old_line, "# prose_translation = ") and Str.starts_with(resolution.new_line, "# prose_translation = ") } else if Str.ends_with(resolution.finding, ".literal_accuracy") or Str.ends_with(resolution.finding, ".literal_structure") { Str.starts_with(resolution.old_line, "# literal_translation = ") and Str.starts_with(resolution.new_line, "# literal_translation = ") } else if Str.ends_with(resolution.finding, ".metadata") { Str.starts_with(resolution.old_line, "#") and Str.starts_with(resolution.new_line, "#") and !Str.contains(resolution.old_line, "translation = ") } else { allowed_row(resolution.finding, Str.split_on(resolution.old_line, "\t"), Str.split_on(resolution.new_line, "\t")) }
allowed_row = |finding, old, new| match (old, new) { ([a,b,c,d,e,f,g,h,i,j], [aa,bb,cc,dd,ee,ff,gg,hh,ii,jj]) => a == aa and b == bb and if Str.ends_with(finding, ".lemma") { d == dd and e == ee and f == ff and g == gg and h == hh and i == ii and j == jj } else if Str.ends_with(finding, ".pos") { c == cc and g == gg and h == hh and i == ii and j == jj } else if Str.ends_with(finding, ".morphology") { c == cc and d == dd and g == gg and h == hh and i == ii and j == jj } else if Str.ends_with(finding, ".head") or Str.ends_with(finding, ".deprel") { c == cc and d == dd and e == ee and f == ff and j == jj } else if Str.ends_with(finding, ".gloss_lexical") or Str.ends_with(finding, ".gloss_grammar") { c == cc and d == dd and e == ee and f == ff and g == gg and h == hh and i == ii and misc_without_gloss(j) == misc_without_gloss(jj) and (Str.starts_with(j, "e_") or List.any(Str.split_on(jj, "|"), |field| Str.starts_with(field, "gloss=") and field != "gloss=")) } else { Bool.False }, _ => Bool.False }
misc_without_gloss = |misc| Str.join_with(List.keep_if(Str.split_on(misc, "|"), |field| !Str.starts_with(field, "gloss=")), "|")
