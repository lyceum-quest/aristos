app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout
import Citation

main! : List(OsStr) => Try({}, _)
main! = |args| {
	outcome = build_preload!(args.drop_first(1))

	match outcome {
		Ok({}) => Ok({})
		Err(Usage) => {
			Stderr.line!("usage: build-corpus-preload <output-dir> (<generated-dir> | <corpus-id> <source.conllu> [<corpus-id> <source.conllu> ...])")?
			Stderr.line!("Invalid preload arguments.")?
			Err(Exit(2))
		}
		Err(InvalidCorpus(path, problem)) => {
			Stderr.line!("${path.display()}: ${problem}")?
			Stderr.line!("Corpus validation failed.")?
			Err(Exit(1))
		}
		Err(_) => {
			Stderr.line!("Could not generate corpus preload assets.")?
			Err(Exit(1))
		}
	}
}

build_preload! = |args|
	match args {
		[output_dir_arg, generated_arg] => write_preload!(Path.from_os_str(output_dir_arg), discover_specs!(Path.from_os_str(generated_arg))?)
		[output_dir_arg, id, path, .. as rest] => write_preload!(Path.from_os_str(output_dir_arg), parse_specs(List.prepend(List.prepend(rest, path), id))?)
		_ => Err(Usage)
	}

# Every <work>-<model>/ folder written by scripts/generate/loop.roc becomes the corpus <work>, in work order.
discover_specs! = |generated_dir| {
	specs = discover_folders!(generated_dir.list!()?, [])?
	if List.is_empty(specs) {
		Err(NoGeneratedCorpora)
	} else {
		Ok(List.sort_with(specs, |a, b| compare_str(a.id, b.id)))
	}
}

discover_folders! = |entries, found|
	match entries {
		[] => Ok(found)
		[entry, .. as rest] => {
			output = entry.join("output.conllu")
			config = entry.join("config.json")
			if output.exists!()? and config.exists!()? {
				settings : { model : Str }
				settings = Json.parse(config.read_utf8!()?)?
				folder = folder_name(entry)
				suffix = "-${Str.replace_each(settings.model, "/", "-")}"
				id = if Str.ends_with(folder, suffix) and folder != suffix { Str.replace_last(folder, suffix, "") } else { folder }
				if invalid_id(id) or List.any(found, |spec| spec.id == id) {
					Err(InvalidCorpus(entry, "duplicate or invalid generated corpus id ${id}"))
				} else {
					discover_folders!(rest, List.append(found, { id, path: output }))
				}
			} else {
				discover_folders!(rest, found)
			}
		}
	}

folder_name = |path| List.last(Str.split_on(path.display(), "/")) ?? path.display()

compare_str = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) => if x < y Before else if x > y After else compare_bytes(xs, ys)
	}

write_preload! = |output_dir, specs| {
	table = Path.utf8(Citation.table_path).read_utf8!()?
	assets = prepare_assets!(specs, table)?

	if output_dir.exists!()? {
		output_dir.delete_all!()?
	} else {
		{}
	}

	corpora_dir = output_dir.join("corpora")
	corpora_dir.create_all!()?
	write_assets!(assets, corpora_dir)?
	manifest = "{\"version\":1,\"corpora\":[${Str.join_with(assets.map(asset_json), ",")}]}\n"
	output_dir.join("corpora.json").write_utf8!(manifest)?
	Stdout.line!("wrote ${output_dir.display()}: ${assets.len().to_str()} corpus asset(s)")?
	Ok({})
}

parse_specs = |args|
	match args {
		[id_arg, path_arg, .. as rest] => {
			id = OsStr.display(id_arg)

			if invalid_id(id) {
				Err(Usage)
			} else {
				remaining = parse_specs(rest)?
				Ok(List.prepend(remaining, { id, path: Path.from_os_str(path_arg) }))
			}
		}

		[] => Ok([])
		_ => Err(Usage)
	}

invalid_id = |id| id == "" or id.contains("/") or id.contains("\\") or id.contains("..")

prepare_assets! = |specs, table|
	match specs {
		[] => Ok([])
		[spec, .. as rest] => {
			content = spec.path.read_utf8!()?

			match validate_corpus(content) {
				Err(problem) => Err(InvalidCorpus(spec.path, problem))
				Ok(valid_stats) => {
					cited = cite!(spec.path, table)?
					text = cited.citation.text
					source = {
						name: "${Citation.annotation_name} ${Citation.annotation_version}",
						url: text.reader_url,
						commit: "${text.repository}@${text.snapshot}",
						license: text.license,
						edition: text.edition,
					}
					units = units!(spec.path, content)?
					remaining = prepare_assets!(rest, table)?
					Ok(List.prepend(remaining, { id: spec.id, title: cited.title, content, source, citation: cited.citation, stats: valid_stats, units }))
				}
			}
		}
	}

# Every corpus needs a sibling config.json (written by scripts/generate/loop.roc) naming its OGA input and model.
# The citation is derived from those alone; a work without a complete citation fails the build.
cite! = |corpus_path, table| {
	config_path = Path.utf8("${Str.join_with(List.drop_last(Str.split_on(corpus_path.display(), "/"), 1), "/")}/config.json")
	text = config_path.read_utf8!() ? |_| InvalidCorpus(corpus_path, "missing ${config_path.display()} naming the work's input and model")
	settings : Try({ input : Str, model : Str }, _)
	settings = Json.parse(text)
	match settings {
		Err(_) => Err(InvalidCorpus(config_path, "config must name the work's input and model"))
		Ok(config) =>
			match Citation.build(table, config.input, config.model, config_path.display()) {
				Err(problem) => Err(InvalidCorpus(config_path, "incomplete citation: ${Str.inspect(problem)}"))
				Ok(citation) => {
					# The display title is the only hand-chosen label; it defaults to the printed edition's title.
					titled : Try({ title : Str }, _)
					titled = Json.parse(text)
					title = match titled {
						Ok(record) => if record.title == "" citation.text.title else record.title
						Err(_) => citation.text.title
					}
					Ok({ title, citation })
				}
			}
	}
}

write_assets! = |assets, corpora_dir|
	match assets {
		[] => Ok({})
		[asset, .. as rest] => {
			corpora_dir.join("${asset.id}.conllu").write_utf8!(asset.content)?
			corpora_dir.join("${asset.id}.units.json").write_utf8!("[${Str.join_with(asset.units.lines, ",")}]\n")?
			write_assets!(rest, corpora_dir)
		}
	}

validate_corpus = |content| {
	lines = content.replace_each("\r\n", "\n").split_on("\n")
	initial = {
		sentence_count: 0.U64,
		token_count: 0.U64,
		block_tokens: 0.U64,
		roots: 0.U64,
		ids: [],
		heads: [],
		has_sentence_id: Bool.False,
	}
	completed = validate_lines(lines, initial)?
	stats = finish_block(completed)?

	if stats.sentence_count == 0 {
		Err("corpus contains no sentences")
	} else {
		Ok(stats)
	}
}

validate_lines = |lines, state|
	match lines {
		[] => Ok(state)
		[line, .. as rest] => {
			if line == "" {
				next = finish_block(state)?
				validate_lines(rest, next)
			} else if line.starts_with("#") {
				has_id = state.has_sentence_id or line.starts_with("# sent_id = ") or line.starts_with("# sentence_id = ")
				validate_lines(rest, { ..state, has_sentence_id: has_id })
			} else {
				match line.split_on("\t") {
					[id, _, _, _, _, _, head, _, _, misc] =>
						match U64.from_str(id) {
							Ok(token_id) => {
								if state.ids.contains(token_id) {
									Err("duplicate token ID ${id}")
								} else {
									match U64.from_str(head) {
										Ok(head_id) => {
											next = {
												..state,
												# OGA placeholder rows (MISC `e_…`) are never shown, so they are not counted as tokens.
												token_count: if misc.starts_with("e_") state.token_count else state.token_count + 1,
												block_tokens: state.block_tokens + 1,
												roots: if head_id == 0 {
													state.roots + 1
												} else {
													state.roots
												},
												ids: state.ids.append(token_id),
												heads: state.heads.append(head_id),
											}
											validate_lines(rest, next)
										}
										Err(_) => Err("token ${id} has non-numeric HEAD ${head}")
									}
								}
							}
							Err(_) =>
								if valid_non_syntactic_id(id) {
									validate_lines(rest, state)
								} else {
									Err("invalid token ID ${id}")
								}
							}

					_ => Err("expected 10 tab-separated columns")
				}
			}
		}
	}

finish_block = |state| {
	if state.block_tokens == 0 {
		Ok(state)
	} else if !state.has_sentence_id {
		Err("sentence is missing # sent_id or # sentence_id")
	} else if state.roots != 1 {
		Err("sentence must have exactly one dependency root; found ${state.roots.to_str()}")
	} else if !state.heads.all(|head| head == 0 or state.ids.contains(head)) {
		Err("sentence has a HEAD that does not name a token in its block")
	} else if !state.ids.all(|token_id| reaches_root(token_id, state.ids, state.heads, [])) {
		Err("sentence dependency graph contains a cycle or disconnected component")
	} else {
		Ok({
			..state,
			sentence_count: state.sentence_count + 1,
			block_tokens: 0,
			roots: 0,
			ids: [],
			heads: [],
			has_sentence_id: Bool.False,
		})
	}
}

reaches_root = |token_id, ids, heads, visited| {
	if token_id == 0 {
		Bool.True
	} else if visited.contains(token_id) {
		Bool.False
	} else {
		match head_for(token_id, ids, heads) {
			Just(head) => reaches_root(head, ids, heads, visited.append(token_id))
			Nothing => Bool.False
		}
	}
}

head_for = |wanted, ids, heads|
	match (ids, heads) {
		([token_id, .. as rest_ids], [head, .. as rest_heads]) =>
			if token_id == wanted {
				Just(head)
			} else {
				head_for(wanted, rest_ids, rest_heads)
			}

		_ => Nothing
	}

valid_non_syntactic_id = |id|
	match id.split_on("-") {
		[first, last] =>
			match (U64.from_str(first), U64.from_str(last)) {
				(Ok(a), Ok(b)) => a < b
				_ => Bool.False
			}
		_ =>
			match id.split_on(".") {
				[first, last] =>
					match (U64.from_str(first), U64.from_str(last)) {
						(Ok(_), Ok(_)) => Bool.True
						_ => Bool.False
					}
				_ => Bool.False
			}
		}

asset_json = |asset| {
	source = asset.source
	asset_path = "corpora/${asset.id}.conllu"
	"{\"id\":${json_string(asset.id)},\"title\":${json_string(asset.title)},\"path\":${json_string(asset_path)},\"sentenceCount\":${asset.stats.sentence_count.to_str()},\"unitsPath\":${json_string("corpora/${asset.id}.units.json")},\"passageCount\":${asset.units.refs.len().to_str()},\"passages\":[${Str.join_with(asset.units.refs.map(json_string), ",")}],\"tokenCount\":${asset.stats.token_count.to_str()},\"source\":{\"name\":${json_string(source.name)},\"url\":${json_string(source.url)},\"commit\":${json_string(source.commit)},\"license\":${json_string(source.license)},\"edition\":${json_string(source.edition)}},\"citation\":${Citation.to_json(asset.citation)}}"
}

json_string = |value| {
	escaped = value
		.replace_each("\\", "\\\\")
		.replace_each("\"", "\\\"")
		.replace_each("\n", "\\n")
		.replace_each("\r", "\\r")
		.replace_each("\t", "\\t")

	"\"${escaped}\""
}

# Canonical passages come from the sibling units.jsonl written by scripts/generate/loop.roc (one JSON object per
# passage: ref, label, tokens, prose, literal). Every passage token must be a glossed row of the corpus.
units! = |corpus_path, content| {
	units_path = Path.utf8("${Str.join_with(List.drop_last(Str.split_on(corpus_path.display(), "/"), 1), "/")}/units.jsonl")
	text = units_path.read_utf8!() ? |_| InvalidCorpus(corpus_path, "missing ${units_path.display()}; run the generation loop to translate its canonical passages")
	lines = List.keep_if(List.map(Str.split_on(text, "\n"), Str.trim), |line| line != "")
	glossed = glossed_tokens(content.split_on("\n"), Dict.empty())
	check_units!(units_path, lines, glossed, [])
}

check_units! = |units_path, lines, glossed, refs|
	match lines {
		[] => Ok({ lines: lines_of(refs), refs: List.map(refs, |unit| unit.ref) })
		[line, .. as rest] => {
			parsed : Try({ ref : Str, tokens : List(Str) }, _)
			parsed = Json.parse(line)
			match parsed {
				Err(_) => Err(InvalidCorpus(units_path, "unreadable passage line: ${line}"))
				Ok(unit) =>
					match List.first(List.keep_if(unit.tokens, |token| !Dict.contains(glossed, token))) {
						Ok(token) => Err(InvalidCorpus(units_path, "passage ${unit.ref} token ${token} is not a glossed corpus token"))
						Err(_) => check_units!(units_path, rest, glossed, List.append(refs, { ref: unit.ref, line }))
					}
			}
		}
	}

lines_of = |units| List.map(units, |unit| unit.line)

# `t_N` ids of rows whose MISC carries a gloss.
glossed_tokens = |lines, found|
	match lines {
		[] => found
		[line, .. as rest] =>
			match line.split_on("\t") {
				[_, _, _, _, _, _, _, _, _, misc] =>
					if misc.contains("gloss=") {
						glossed_tokens(rest, Dict.insert(found, List.first(misc.split_on("|")) ?? "", {}))
					} else {
						glossed_tokens(rest, found)
					}
				_ => glossed_tokens(rest, found)
			}
	}
