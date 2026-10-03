app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.OsStr
import cli.Path
import cli.Stdout
import Citation

# Prepares a generated work for import-lyceum so Lyceum shows the same passages as Aristos: one reader passage per
# canonical passage in units.jsonl (a verse, a section, a Stephanus page part), with that passage's own prose and
# literal translations and its glossed rows from output.conllu.
# Writes /tmp/aristos-lyceum-<folder>.conllu (one block per passage, `# ref` set, rows renumbered) and
# scripts/lyceum-imports/<folder>.json, which adds a `lyceum` edition (`<work>.lyceum-grc1` and `-versified-eng1`), or with --replace overwrites two
# existing editions wholesale (as for Meditations, whose Lyceum edition predates Aristos passages).
# Lyceum references are dotted numbers, so a split unit's `43~2` becomes `43.2`.
# Usage: roc scripts/lyceum-import-config.roc <conllu/generated/work-model> [--replace <greek-urn> <english-urn>]
Unit : { ref : Str, tokens : List(Str), prose : Str, literal : Str }

main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[dir] => run!(dir, Err(NoReplacement))
	[dir, "--replace", greek_urn, english_urn] => run!(dir, Ok({ greek_urn, english_urn }))
	_ => Err(Usage("lyceum-import-config.roc <conllu/generated/work-model> [--replace <greek-urn> <english-urn>]"))
}

run! = |dir, replacement| {
	folder = List.last(List.keep_if(Str.split_on(dir, "/"), |part| part != "")) ?? dir
	settings : { input : Str, model : Str }
	settings = Json.parse(Path.read_utf8!(Path.utf8("${dir}/config.json"))?)?
	cts_id = Citation.cts_id(settings.input)?
	work_urn = match Str.split_on(cts_id, ".") {
		[group, work, ..] => Ok("urn:cts:greekLit:${group}.${work}")
		_ => Err(NoCtsId(cts_id))
	}?
	rows = glossed_rows(Str.split_on(Str.replace_each(Path.read_utf8!(Path.utf8("${dir}/output.conllu"))?, "\r\n", "\n"), "\n"), Dict.empty())
	units = parse_units(List.keep_if(Str.split_on(Path.read_utf8!(Path.utf8("${dir}/units.jsonl"))?, "\n"), |line| Str.trim(line) != ""), [])?
	blocks = passage_blocks(units, rows, 1, [], [])?
	passages = "/tmp/aristos-lyceum-${folder}.conllu"
	_ = Path.write_utf8!(Path.utf8(passages), "${Str.join_with(blocks, "\n\n")}\n")?
	target = match replacement {
		Ok(urns) => "  \"replace_editions\": { \"greek_urn\": ${json(urns.greek_urn)}, \"english_urn\": ${json(urns.english_urn)} },"
		Err(_) => "  \"edition_slug\": \"lyceum\","
	}
	config = Str.join_with(
		[
			"{",
			"  \"input\": ${json(passages)},",
			"  \"sql_output\": ${json("/tmp/aristos-lyceum-${folder}.sql")},",
			"  \"work_urn\": ${json(work_urn)},",
			target,
			# The generator is part of the edition marker a re-import must match: keep it the bare model.
			"  \"generator\": ${json(settings.model)}",
			"}",
			"",
		],
		"\n",
	)
	output = "scripts/lyceum-imports/${folder}.json"
	_ = Path.create_all!(Path.utf8("scripts/lyceum-imports"))?
	_ = Path.write_utf8!(Path.utf8(output), config)?
	first = (List.first(units) ?? { ref: "", tokens: [], prose: "", literal: "" }).ref
	last = (List.last(units) ?? { ref: "", tokens: [], prose: "", literal: "" }).ref
	Stdout.line!("wrote ${output} and ${passages}: ${U64.to_str(List.len(units))} passage(s), ${lyceum_ref(first)} to ${lyceum_ref(last)}")
}

# OGA token id (`t_N`, the first MISC field) -> its glossed row; placeholder rows (`e_…`) are not passage tokens.
glossed_rows = |lines, found| match lines {
	[] => found
	[line, .. as rest] =>
		match Str.split_on(line, "\t") {
			[_, _, _, _, _, _, _, _, _, misc] if !Str.starts_with(line, "#") => {
				token = List.first(Str.split_on(misc, "|")) ?? ""
				glossed_rows(rest, if Str.starts_with(token, "t_") Dict.insert(found, token, line) else found)
			}
			_ => glossed_rows(rest, found)
		}
}

parse_units = |lines, found| match lines {
	[] => if List.is_empty(found) Err(NoPassages) else Ok(found)
	[line, .. as rest] => {
		unit : Unit
		unit = Json.parse(line)?
		parse_units(rest, List.append(found, unit))
	}
}

passage_blocks = |units, rows, index, refs, found| match units {
	[] => Ok(found)
	[unit, .. as rest] => {
		ref = lyceum_ref(unit.ref)
		_ = (if List.contains(refs, ref) Err(DuplicateReference(ref)) else Ok({}))?
		lines = renumber(unit.tokens, rows, 1, [])?
		comments = ["# sentence_id = ${U64.to_str(index)}", "# ref = ${ref}", "# prose_translation = ${unit.prose}", "# literal_translation = ${unit.literal}"]
		passage_blocks(rest, rows, index + 1, List.append(refs, ref), List.append(found, Str.join_with(List.concat(comments, lines), "\n")))
	}
}

# A passage can join tokens of two OGA sentences, whose numbering restarts; Lyceum needs ascending IDs.
renumber = |tokens, rows, id, found| match tokens {
	[] => Ok(found)
	[token, .. as rest] =>
		match Dict.get(rows, token) {
			Ok(line) =>
				match Str.split_on(line, "\t") {
					[_, .. as columns] => renumber(rest, rows, id + 1, List.append(found, Str.join_with(List.prepend(columns, U64.to_str(id)), "\t")))
					[] => Err(MissingRow(token))
				}
			Err(_) => Err(MissingRow(token))
		}
}

lyceum_ref = |ref| Str.replace_each(ref, "~", ".")

json = |value| "\"${Str.replace_each(Str.replace_each(value, "\\", "\\\\"), "\"", "\\\"")}\""
