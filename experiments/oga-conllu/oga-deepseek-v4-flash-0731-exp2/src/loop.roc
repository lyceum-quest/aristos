app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stdout
root = "experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2"
scratch = "${root}/outputs"
result_dir = "conllu/generated/claude-sonnet-5/meditations"
Config : { allow_fallbacks : Bool, api_key_env : Str, base_url : Str, max_tokens : U64, model : Str, output_dir : Str, prompt : Str, send_temperature : Bool, structured_schema : Bool, temperature : Dec }
main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[input, count] => run!(input, U64.from_str(count)?)
	_ => Err(Usage("loop.roc <file.conllu> <sentence-count>"))
}
run! = |input, count| {
	_ = (if count == 0 { Err(EmptySelection) } else { Ok({}) })?
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	blocks = take(blocks_from(source), count, [])
	_ = (if List.is_empty(blocks) { Err(EmptyInput) } else { Ok({}) })?
	_ = Path.create_all!(Path.utf8(result_dir))?
	_ = Path.create_all!(Path.utf8(scratch))?
	_ = bind_file!("${result_dir}/source.conllu", "${Str.join_with(blocks, "\n\n")}\n")?
	_ = bind_config!("translate")?
	_ = bind_config!("gloss")?
	translated = read_blocks!("${result_dir}/translations.conllu")?
	glossed = read_blocks!("${result_dir}/output.conllu")?
	_ = (if List.len(translated) > List.len(blocks) or List.len(glossed) > List.len(translated) { Err(InconsistentCheckpoint) } else { Ok({}) })?
	_ = Stdout.line!("selected ${U64.to_str(List.len(blocks))} sentences; checkpoints: translate ${U64.to_str(List.len(translated))}, gloss ${U64.to_str(List.len(glossed))}")?
	completed = process!(blocks, translated, glossed, 1)?
	Stdout.line!("checkpointed ${U64.to_str(completed)} new sentence(s); result: ${result_dir}/output.conllu")
}
bind_config! = |stage| {
	text = Path.read_utf8!(Path.utf8("${root}/config/${stage}.config.json"))?
	config : Config
	config = Json.parse(text)?
	_ = (if config.model != "claude-sonnet-5" or config.output_dir != scratch { Err(InvalidSonnetConfig(stage)) } else { Ok({}) })?
	bind_file!("${result_dir}/${stage}.config.json", text)
}
bind_file! = |path, content| if Path.exists!(Path.utf8(path))? {
	if Path.read_utf8!(Path.utf8(path))? == content { Ok({}) } else { Err(CheckpointInputChanged(path)) }
} else {
	has_checkpoints = Path.exists!(Path.utf8("${result_dir}/translations.conllu"))? or Path.exists!(Path.utf8("${result_dir}/output.conllu"))?
	if has_checkpoints { Err(MissingCheckpointSnapshot(path)) } else { Path.write_utf8!(Path.utf8(path), content) }
}
process! = |sources, translated, glossed, index| match sources {
	[] => Ok(0)
	[source, .. as source_rest] => {
		needs_work = List.is_empty(translated) or List.is_empty(glossed)
		translation_state = match translated {
			[saved, .. as rest] => Ok({ conllu: saved, rest })
			[] => {
				result = translate!(source, index)?
				Ok({ conllu: result, rest: [] })
			}
		}?
		gloss_rest = match glossed {
			[_saved, .. as rest] => Ok(rest)
			[] => {
				_ = gloss!(translation_state.conllu, index)?
				Ok([])
			}
		}?
		rest_completed = process!(source_rest, translation_state.rest, gloss_rest, index + 1)?
		Ok(if needs_work { rest_completed + 1 } else { rest_completed })
	}
}
translate! = |source, index| {
	current = "${scratch}/current.conllu"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	_ = run_roc!("${root}/src/translate.roc", [current])?
	translated = Str.replace_first(Path.read_utf8!(Path.utf8("${scratch}/output.conllu"))?, "# sentence_id = 1", "# sentence_id = ${U64.to_str(index)}")
	_ = append_block!("${result_dir}/translations.conllu", translated)?
	_ = Stdout.line!("sentence ${U64.to_str(index)}: translate returned and checkpointed")?
	Ok(Str.trim(translated))
}
gloss! = |source, index| {
	current = "${scratch}/current.conllu"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	_ = run_roc!("${root}/src/gloss.roc", [current])?
	result = Path.read_utf8!(Path.utf8("${scratch}/gloss-output.conllu"))?
	_ = append_block!("${result_dir}/output.conllu", result)?
	Stdout.line!("sentence ${U64.to_str(index)}: gloss returned and checkpointed")
}
run_roc! = |script, args| run_roc_attempt!(script, args, 3)
run_roc_attempt! = |script, args, attempts| {
	command_args = List.concat(["180", "roc", script], args)
	match Cmd.new_str("timeout").args_str(command_args).exec_output!() {
		Ok(_) => Ok({})
		Err(NonZeroExitCode(failure)) => if non_retryable_response(failure.stderr_utf8_lossy) or attempts <= 1 {
			Err(NonZeroExitCode(failure))
		} else {
			_ = Stdout.line!("retrying ${script}; ${U64.to_str(attempts - 1)} attempts remain")?
			run_roc_attempt!(script, args, attempts - 1)
		}
		Err(error) => if attempts > 1 {
			_ = Stdout.line!("retrying ${script}; ${U64.to_str(attempts - 1)} attempts remain")?
			run_roc_attempt!(script, args, attempts - 1)
		} else {
			Err(error)
		}
	}
}
non_retryable_response = |stderr| List.any(["InvalidGlossLine", "InvalidGloss(", "CopiedGreekForm", "MissingGloss", "UnknownGlossIds"], |name| Str.contains(stderr, name))
read_blocks! = |path| if Path.exists!(Path.utf8(path))? { Ok(blocks_from(Path.read_utf8!(Path.utf8(path))?)) } else { Ok([]) }
blocks_from = |text| List.keep_if(List.map(Str.split_on(Str.trim(text), "\n\n"), Str.trim), |block| block != "")
take = |items, count, found| if count == 0 found else match items { [] => found, [item, .. as rest] => take(rest, count - 1, List.append(found, item)) }
append_block! = |path, content| {
	target = Path.utf8(path)
	chunk = if Path.exists!(target)? { "\n\n${Str.trim(content)}\n" } else { "${Str.trim(content)}\n" }
	temp_path = "${path}.append"
	_ = Path.write_utf8!(Path.utf8(temp_path), chunk)?
	_ = Cmd.new_str("dd").args_str(["if=${temp_path}", "of=${path}", "oflag=append", "conv=notrunc", "status=none"]).exec_output!()?
	Path.delete!(Path.utf8(temp_path))
}
