app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stdout
root = "experiments/oga-conllu/oga-deepseek-v4-flash-0731-exp2"
scratch = "${root}/outputs"
Steps : { audit : Bool, gloss : Bool, improve : Bool, translate : Bool }
main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[input] => run!(input, all_steps, 0)
	[input, "reset"] => reset!(input)
	[input, steps] => run!(input, parse_steps!(steps)?, 0)
	[input, steps, batch_size] => run!(input, parse_steps!(steps)?, U64.from_str(batch_size)?)
	_ => Err(Usage("loop.roc <file.conllu> [translate,gloss,audit,improve|all|reset] [batch-size]"))
}
all_steps : Steps
all_steps = { audit: Bool.True, gloss: Bool.True, improve: Bool.True, translate: Bool.True }
parse_steps! = |text| {
	names = if text == "all" { ["translate", "gloss", "audit", "improve"] } else { List.keep_if(Str.split_on(text, ","), |name| name != "") }
	_ = validate_steps!(names, [])?
	if List.is_empty(names) {
		Err(NoStepsSelected)
	} else {
		Ok({ audit: List.contains(names, "audit"), gloss: List.contains(names, "gloss"), improve: List.contains(names, "improve"), translate: List.contains(names, "translate") })
	}
}
validate_steps! = |names, seen| match names {
	[] => Ok({})
	[name, .. as rest] => if !List.contains(["translate", "gloss", "audit", "improve"], name) {
		Err(UnknownStep(name))
	} else if List.contains(seen, name) {
		Err(DuplicateStep(name))
	} else {
		validate_steps!(rest, List.append(seen, name))
	}
}
run! = |input, steps, batch_size| {
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	blocks = blocks_from(source)
	_ = (if List.is_empty(blocks) { Err(EmptyInput) } else { Ok({}) })?
	loop_dir = loop_dir_for!(input, source)?
	_ = Path.create_all!(Path.utf8(loop_dir))?
	snapshot_path = "${loop_dir}/source.conllu"
	_ = (if Path.exists!(Path.utf8(snapshot_path))? {
		if Path.read_utf8!(Path.utf8(snapshot_path))? == "${Str.trim(source)}\n" { Ok({}) } else { Err(SourceChanged) }
	} else {
		_ = Path.write_utf8!(Path.utf8(snapshot_path), "${Str.trim(source)}\n")?
		Ok({})
	})?
	translated = read_blocks!("${loop_dir}/output.conllu")?
	glossed = read_blocks!("${loop_dir}/gloss-output.conllu")?
	audits = read_lines!("${loop_dir}/audit.jsonl")?
	improved = read_blocks!("${loop_dir}/improved-output.conllu")?
	resolutions = read_lines!("${loop_dir}/improve-resolutions.jsonl")?
	_ = validate_counts!(List.len(blocks), translated, glossed, audits, improved, resolutions)?
	_ = Stdout.line!("loaded ${U64.to_str(List.len(blocks))} sentences; checkpoints: translate ${U64.to_str(List.len(translated))}, gloss ${U64.to_str(List.len(glossed))}, audit ${U64.to_str(List.len(audits))}, improve ${U64.to_str(List.len(improved))}")?
	completed = process!(blocks, translated, glossed, audits, improved, resolutions, 1, steps, batch_size != 0, batch_size, loop_dir)?
	Stdout.line!("checkpointed ${U64.to_str(completed)} new sentence(s)")
}
reset! = |input| {
	source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
	loop_dir = loop_dir_for!(input, source)?
	snapshot_path = "${loop_dir}/source.conllu"
	if Path.exists!(Path.utf8(snapshot_path))? {
		_ = (if Path.read_utf8!(Path.utf8(snapshot_path))? == "${Str.trim(source)}\n" { Ok({}) } else { Err(SourceChanged) })?
		_ = Path.delete_all!(Path.utf8(loop_dir))?
		Stdout.line!("reset checkpoints for ${input}")
	} else {
		Stdout.line!("no checkpoints to reset for ${input}")
	}
}
loop_dir_for! = |input, source| {
	file_name = match List.last(Str.split_on(input, "/")) { Ok(name) => name, Err(_) => "input.conllu" }
	legacy_dir = "${scratch}/loop"
	legacy_snapshot = "${legacy_dir}/source.conllu"
	use_legacy = if Path.exists!(Path.utf8(legacy_snapshot))? { Path.read_utf8!(Path.utf8(legacy_snapshot))? == "${Str.trim(source)}\n" } else { Bool.False }
	Ok(if use_legacy { legacy_dir } else { "${legacy_dir}/${file_name}" })
}
validate_counts! = |source_count, translated, glossed, audits, improved, resolutions| {
	within_source = List.len(translated) <= source_count and List.len(glossed) <= source_count and List.len(audits) <= source_count and List.len(improved) <= source_count
	if !within_source or List.len(improved) != List.len(resolutions) { Err(InconsistentCheckpoint) } else { Ok({}) }
}
process! = |sources, translated, glossed, audits, improved, resolutions, index, steps, limited, remaining, loop_dir| {
	if limited and remaining == 0 {
		Ok(0)
	} else match sources {
		[] => Ok(0)
		[source, .. as source_rest] => {
			needs_work = (steps.translate and List.is_empty(translated)) or (steps.gloss and List.is_empty(glossed)) or (steps.audit and List.is_empty(audits)) or (steps.improve and List.is_empty(improved))
			translation_state = match translated {
				[saved, .. as rest] => Ok({ conllu: saved, rest })
				[] => if steps.translate {
					result = translate!(source, index, loop_dir)?
					Ok({ conllu: result, rest: [] })
				} else {
					Ok({ conllu: source, rest: [] })
				}
			}?
			gloss_state = match glossed {
				[saved, .. as rest] => Ok({ conllu: saved, rest })
				[] => if steps.gloss {
					result = gloss!(translation_state.conllu, index, loop_dir)?
					Ok({ conllu: result, rest: [] })
				} else {
					Ok({ conllu: translation_state.conllu, rest: [] })
				}
			}?
			audit_state = match audits {
				[saved, .. as rest] => Ok({ json: saved, rest })
				[] => if steps.audit {
					result = audit!(gloss_state.conllu, index, loop_dir)?
					Ok({ json: result, rest: [] })
				} else {
					Ok({ json: "", rest: [] })
				}
			}?
			improve_state = match (improved, resolutions) {
				([_saved, .. as improved_rest], [_, .. as resolution_rest]) => Ok({ improved_rest, resolution_rest })
				([], []) => if steps.improve {
					_ = (if audit_state.json == "" { Err(MissingAudit(index)) } else { Ok({}) })?
					_ = improve!(gloss_state.conllu, audit_state.json, index, loop_dir)?
					Ok({ improved_rest: [], resolution_rest: [] })
				} else {
					Ok({ improved_rest: [], resolution_rest: [] })
				}
				_ => Err(InconsistentCheckpoint)
			}?
			next_remaining = if limited and needs_work { remaining - 1 } else { remaining }
			rest_completed = process!(source_rest, translation_state.rest, gloss_state.rest, audit_state.rest, improve_state.improved_rest, improve_state.resolution_rest, index + 1, steps, limited, next_remaining, loop_dir)?
			Ok(if needs_work { rest_completed + 1 } else { rest_completed })
		}
	}
}
translate! = |source, index, loop_dir| {
	current = "${loop_dir}/current.conllu"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	_ = run_roc!("${root}/src/translate.roc", [current])?
	path = "${scratch}/output.conllu"
	translated = Str.replace_first(Path.read_utf8!(Path.utf8(path))?, "# sentence_id = 1", "# sentence_id = ${U64.to_str(index)}")
	_ = Path.write_utf8!(Path.utf8(path), translated)?
	_ = append_block!("${loop_dir}/output.conllu", translated)?
	_ = Stdout.line!("sentence ${U64.to_str(index)}: translate returned and checkpointed")?
	Ok(Str.trim(translated))
}
gloss! = |source, index, loop_dir| {
	current = "${loop_dir}/current.conllu"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	_ = run_roc!("${root}/src/gloss.roc", [current])?
	result = Path.read_utf8!(Path.utf8("${scratch}/gloss-output.conllu"))?
	_ = append_block!("${loop_dir}/gloss-output.conllu", result)?
	_ = Stdout.line!("sentence ${U64.to_str(index)}: gloss returned and checkpointed")?
	Ok(Str.trim(result))
}
audit! = |source, index, loop_dir| {
	current = "${loop_dir}/current.conllu"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	_ = run_roc!("${root}/src/audit.roc", [current])?
	result = Path.read_utf8!(Path.utf8("${scratch}/audit.json"))?
	_ = append_json!("${loop_dir}/audit.jsonl", result)?
	_ = Stdout.line!("sentence ${U64.to_str(index)}: audit returned and checkpointed")?
	Ok(Str.trim(result))
}
improve! = |source, audit_json, index, loop_dir| {
	current = "${loop_dir}/current.conllu"
	audit_path = "${loop_dir}/current-audit.json"
	_ = Path.write_utf8!(Path.utf8(current), "${source}\n")?
	_ = Path.write_utf8!(Path.utf8(audit_path), "${audit_json}\n")?
	_ = run_roc!("${root}/src/improve.roc", [current, audit_path])?
	improved = Path.read_utf8!(Path.utf8("${scratch}/improved-output.conllu"))?
	resolutions = Path.read_utf8!(Path.utf8("${scratch}/improve-resolutions.json"))?
	_ = append_block!("${loop_dir}/improved-output.conllu", improved)?
	_ = append_json!("${loop_dir}/improve-resolutions.jsonl", resolutions)?
	_ = Stdout.line!("sentence ${U64.to_str(index)}: improve returned and checkpointed")?
	Ok({})
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
read_lines! = |path| if Path.exists!(Path.utf8(path))? { Ok(List.keep_if(Str.split_on(Str.trim(Path.read_utf8!(Path.utf8(path))?), "\n"), |line| Str.trim(line) != "")) } else { Ok([]) }
blocks_from = |text| List.keep_if(Str.split_on(Str.trim(text), "\n\n"), |block| Str.trim(block) != "")
append_block! = |path, content| append!(path, Str.trim(content), "\n\n")
append_json! = |path, content| append!(path, Str.trim(content), "\n")
append! = |path, content, separator| {
	target = Path.utf8(path)
	chunk = if Path.exists!(target)? { "${separator}${content}\n" } else { "${content}\n" }
	temp_path = "${path}.append"
	_ = Path.write_utf8!(Path.utf8(temp_path), chunk)?
	_ = Cmd.new_str("dd").args_str(["if=${temp_path}", "of=${path}", "oflag=append", "conv=notrunc", "status=none"]).exec_output!()?
	Path.delete!(Path.utf8(temp_path))
}
