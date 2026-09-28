app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.OsStr
import cli.Path
import cli.Stdout
import Citation
import Passages

# Writes scripts/lyceum-imports/<folder>.json, the import-lyceum config for a generated work, adding a new
# aristos-<model> edition. Each sentence is cited by its first token's canonical citation (data/oga/refs), cut to
# the reader's citation depth: Meditations is cited book.chapter (2) though OGA adds sections, a Bible book
# chapter.verse (2), Plato by Stephanus page (1). Sentences sharing a citation become one reader passage.
# Usage: roc scripts/lyceum-import-config.roc <conllu/generated/work-model> <levels>
main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[dir, levels_text] => {
		levels = U64.from_str(levels_text) ? |_| Usage("levels must be a positive integer")
		_ = (if levels == 0 Err(Usage("levels must be a positive integer")) else Ok({}))?
		folder = List.last(List.keep_if(Str.split_on(dir, "/"), |part| part != "")) ?? dir
		settings : { input : Str, model : Str }
		settings = Json.parse(Path.read_utf8!(Path.utf8("${dir}/config.json"))?)?
		cts_id = Citation.cts_id(settings.input)?
		work_urn = match Str.split_on(cts_id, ".") {
			[group, work, ..] => Ok("urn:cts:greekLit:${group}.${work}")
			_ => Err(NoCtsId(cts_id))
		}?
		refs = Passages.citations(Path.read_utf8!(Path.utf8(Passages.refs_path(cts_id)))?).refs
		input = "${dir}/output.conllu"
		source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
		blocks = List.keep_if(List.map(Str.split_on(Str.trim(source), "\n\n"), Str.trim), |block| block != "")
		references = cite(blocks, refs, levels, [])?
		slug = Str.from_utf8(List.map(Str.to_utf8(Str.with_ascii_lowercased(settings.model)), |byte| if (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) byte else 45)) ?? "generated"
		rows = List.map(references, |entry| "    { \"sentence_id\": ${json(entry.sentence_id)}, \"reference\": ${json(entry.reference)} }")
		config = Str.join_with(
			[
				"{",
				"  \"input\": ${json(input)},",
				"  \"sql_output\": ${json("/tmp/aristos-lyceum-${folder}.sql")},",
				"  \"work_urn\": ${json(work_urn)},",
				"  \"edition_slug\": ${json("aristos-${slug}")},",
				# The generator is part of the edition marker a re-import must match: keep it the bare model.
				"  \"generator\": ${json(settings.model)},",
				"  \"references\": [",
				Str.join_with(rows, ",\n"),
				"  ]",
				"}",
				"",
			],
			"\n",
		)
		output = "scripts/lyceum-imports/${folder}.json"
		_ = Path.create_all!(Path.utf8("scripts/lyceum-imports"))?
		_ = Path.write_utf8!(Path.utf8(output), config)?
		first = (List.first(references) ?? { sentence_id: "", reference: "" }).reference
		last = (List.last(references) ?? { sentence_id: "", reference: "" }).reference
		Stdout.line!("wrote ${output}: ${U64.to_str(List.len(references))} sentence(s), ${U64.to_str(List.len(distinct(references, [])))} passage(s), ${first} to ${last}")
	}
	_ => Err(Usage("lyceum-import-config.roc <conllu/generated/work-model> <levels>"))
}

cite = |blocks, refs, levels, found| match blocks {
	[] => if List.is_empty(found) Err(EmptyOutput) else Ok(found)
	[block, .. as rest] => {
		lines = Str.split_on(block, "\n")
		sentence_id = List.first(List.keep_oks(lines, |line| sentence_id_of(line))) ? |_| MissingSentenceId(block)
		# OGA placeholder rows (MISC `e_…`) have no citation; the first real token does.
		token = List.first(List.keep_oks(lines, |line| first_token(line))) ? |_| NoCitedToken(sentence_id)
		ref = Dict.get(refs, token) ? |_| MissingCitation(token)
		parts = Str.split_on(ref, "_")
		if List.len(parts) < levels {
			Err(ShallowCitation(token, ref))
		} else {
			cite(rest, refs, levels, List.append(found, { sentence_id, reference: Str.join_with(List.take_first(parts, levels), ".") }))
		}
	}
}

sentence_id_of = |line|
	if Str.starts_with(line, "#") {
		match Str.split_on(Str.drop_prefix(line, "#"), "=") {
			[key, .. as value] if List.contains(["sentence_id", "sent_id"], Str.trim(key)) and Str.trim(Str.join_with(value, "=")) != "" => Ok(Str.trim(Str.join_with(value, "=")))
			_ => Err(NotSentenceId)
		}
	} else {
		Err(NotSentenceId)
	}

first_token = |line|
	if Str.starts_with(line, "#") {
		Err(Comment)
	} else {
		match Str.split_on(line, "\t") {
			[_, _, _, _, _, _, _, _, _, misc] => {
				token = List.first(Str.split_on(misc, "|")) ?? ""
				if Str.starts_with(token, "t_") Ok(token) else Err(Placeholder)
			}
			_ => Err(NotARow)
		}
	}

distinct = |references, seen| match references {
	[] => seen
	[entry, .. as rest] => distinct(rest, if List.contains(seen, entry.reference) seen else List.append(seen, entry.reference))
}

json = |value| "\"${Str.replace_each(Str.replace_each(value, "\\", "\\\\"), "\"", "\\\"")}\""
