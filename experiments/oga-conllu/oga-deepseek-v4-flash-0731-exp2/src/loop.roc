app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stdout
root = "experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2"
scratch = "${root}/outputs"
loop_dir = "${scratch}/loop"
main! = |args| match List.drop_first(args, 1) {
	[input_arg] => run!(OsStr.display(input_arg))
	_ => Err(Usage("loop.roc <file.conllu>"))
}
run! = |input| {
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	blocks = List.keep_if(Str.split_on(Str.trim(source), "\n\n"), |block| Str.trim(block) != "")
	_ = (if List.is_empty(blocks) { Err(EmptyInput) } else { Ok({}) })?
	_ = Path.create_all!(Path.utf8(loop_dir))?
	snapshot_path = "${loop_dir}/source.conllu"
	_ = (if Path.exists!(Path.utf8(snapshot_path))? {
		if Path.read_utf8!(Path.utf8(snapshot_path))? == "${Str.trim(source)}\n" { Ok({}) } else { Err(SourceChanged) }
	} else {
		_ = Path.write_utf8!(Path.utf8(snapshot_path), "${Str.trim(source)}\n")?
		Ok({})
	})?
	completed = completed_count!()?
	_ = validate_counts!(completed)?
	_ = Stdout.line!("resuming after ${U64.to_str(completed)} of ${U64.to_str(List.len(blocks))} sentence blocks")?
	_ = process!(blocks, 1, completed)?
	Stdout.line!("completed ${U64.to_str(List.len(blocks))} sentence blocks")
}
completed_count! = || {
	path = "${loop_dir}/improved-output.conllu"
	if Path.exists!(Path.utf8(path))? { Ok(block_count(Path.read_utf8!(Path.utf8(path))?)) } else { Ok(0) }
}
validate_counts! = |completed| {
	valid_conllu = conllu_counts_match!(["${loop_dir}/output.conllu", "${loop_dir}/gloss-output.conllu"], completed)?
	valid_jsonl = jsonl_counts_match!(["${loop_dir}/audit.jsonl", "${loop_dir}/improve-resolutions.jsonl"], completed)?
	if valid_conllu and valid_jsonl { Ok({}) } else { Err(InconsistentCheckpoint) }
}
conllu_counts_match! = |paths, completed| match paths {
	[] => Ok(Bool.True)
	[path, .. as rest] => {
		matches = if Path.exists!(Path.utf8(path))? { block_count(Path.read_utf8!(Path.utf8(path))?) == completed } else { completed == 0 }
		if matches { conllu_counts_match!(rest, completed) } else { Ok(Bool.False) }
	}
}
jsonl_counts_match! = |paths, completed| match paths {
	[] => Ok(Bool.True)
	[path, .. as rest] => {
		matches = if Path.exists!(Path.utf8(path))? { line_count(Path.read_utf8!(Path.utf8(path))?) == completed } else { completed == 0 }
		if matches { jsonl_counts_match!(rest, completed) } else { Ok(Bool.False) }
	}
}
process! = |blocks, index, completed| match blocks {
	[] => Ok({})
	[block, .. as rest] => if index <= completed {
		process!(rest, index + 1, completed)
	} else {
		_ = Stdout.line!("sentence ${U64.to_str(index)}: prep")?
		current = "${loop_dir}/current.conllu"
		_ = Path.write_utf8!(Path.utf8(current), "${block}\n")?
		_ = run_roc!("${root}/src/prep.roc", [current])?
		prepared_path = "${scratch}/output.conllu"
		prepared = Str.replace_first(Path.read_utf8!(Path.utf8(prepared_path))?, "# sentence_id = 1", "# sentence_id = ${U64.to_str(index)}")
		_ = Path.write_utf8!(Path.utf8(prepared_path), prepared)?
		_ = Stdout.line!("sentence ${U64.to_str(index)}: gloss")?
		_ = run_roc!("${root}/src/gloss.roc", [prepared_path])?
		gloss_path = "${scratch}/gloss-output.conllu"
		_ = Stdout.line!("sentence ${U64.to_str(index)}: audit")?
		_ = run_roc!("${root}/src/audit.roc", [gloss_path])?
		audit_path = "${scratch}/audit.json"
		_ = Stdout.line!("sentence ${U64.to_str(index)}: improve")?
		improved = run_roc_optional!("${root}/src/improve.roc", [gloss_path, audit_path])?
		_ = (if improved { Ok({}) } else {
			_ = Path.write_utf8!(Path.utf8("${scratch}/improved-output.conllu"), Path.read_utf8!(Path.utf8(gloss_path))?)?
			_ = Path.write_utf8!(Path.utf8("${scratch}/improve-resolutions.json"), "{\"resolutions\":[],\"status\":\"failed\"}\n")?
			_ = Stdout.line!("sentence ${U64.to_str(index)}: improve failed; checkpointing audited gloss output")?
			Ok({})
		})?
		_ = append_block!("${loop_dir}/output.conllu", Path.read_utf8!(Path.utf8(prepared_path))?)?
		_ = append_block!("${loop_dir}/gloss-output.conllu", Path.read_utf8!(Path.utf8(gloss_path))?)?
		_ = append_json!("${loop_dir}/audit.jsonl", Path.read_utf8!(Path.utf8(audit_path))?)?
		_ = append_json!("${loop_dir}/improve-resolutions.jsonl", Path.read_utf8!(Path.utf8("${scratch}/improve-resolutions.json"))?)?
		_ = append_block!("${loop_dir}/improved-output.conllu", Path.read_utf8!(Path.utf8("${scratch}/improved-output.conllu"))?)?
		_ = Stdout.line!("sentence ${U64.to_str(index)}: checkpointed")?
		process!(rest, index + 1, completed)
	}
}
run_roc! = |script, args| run_roc_attempt!(script, args, 3)
run_roc_optional! = |script, args| match run_roc_attempt!(script, args, 1) {
	Ok(_) => Ok(Bool.True)
	Err(_) => Ok(Bool.False)
}
run_roc_attempt! = |script, args, attempts| {
	command_args = List.concat(["180", "roc", script], args)
	match Cmd.new_str("timeout").args_str(command_args).exec_output!() {
		Ok(_) => Ok({})
		Err(error) => if attempts > 1 {
			_ = Stdout.line!("retrying ${script}; ${U64.to_str(attempts - 1)} attempts remain")?
			run_roc_attempt!(script, args, attempts - 1)
		} else {
			Err(error)
		}
	}
}
append_block! = |path, content| append!(path, Str.trim(content), "\n\n")
append_json! = |path, content| append!(path, Str.trim(content), "\n")
append! = |path, content, separator| {
	existing = if Path.exists!(Path.utf8(path))? { Path.read_utf8!(Path.utf8(path))? } else { "" }
	prefix = if existing == "" { "" } else { "${Str.trim(existing)}${separator}" }
	Path.write_utf8!(Path.utf8(path), "${prefix}${content}\n")
}
block_count = |text| List.len(List.keep_if(Str.split_on(Str.trim(text), "\n\n"), |block| Str.trim(block) != ""))
line_count = |text| List.len(List.keep_if(Str.split_on(Str.trim(text), "\n"), |line| Str.trim(line) != ""))
