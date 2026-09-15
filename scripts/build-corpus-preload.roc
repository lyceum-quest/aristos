app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	outcome = build_preload!(args.drop_first(1))

	match outcome {
		Ok({}) => Ok({})
		Err(Usage) => {
			Stderr.line!("usage: build-corpus-preload <output-dir> <corpus-id> <source.conllu> [<corpus-id> <source.conllu> ...]")?
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
		[output_dir_arg, id, path, .. as rest] => {
			output_dir = Path.from_os_str(output_dir_arg)
			corpus_args = List.prepend(List.prepend(rest, path), id)
			specs = parse_specs(corpus_args)?
			assets = prepare_assets!(specs)?

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

		_ => Err(Usage)
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

prepare_assets! = |specs|
	match specs {
		[] => Ok([])
		[spec, .. as rest] => {
			content = spec.path.read_utf8!()?

			match validate_corpus(content) {
				Err(problem) => Err(InvalidCorpus(spec.path, problem))
				Ok(valid_stats) => {
					source = {
						name: metadata_or(content, "project", metadata_or(content, "source", spec.id)),
						url: metadata_value(content, "source_url"),
						commit: metadata_value(content, "source_revision"),
						license: metadata_value(content, "license"),
						edition: metadata_value(content, "source_edition"),
					}
					remaining = prepare_assets!(rest)?
					Ok(List.prepend(remaining, { id: spec.id, content, source, stats: valid_stats }))
				}
			}
		}
	}

write_assets! = |assets, corpora_dir|
	match assets {
		[] => Ok({})
		[asset, .. as rest] => {
			corpora_dir.join("${asset.id}.conllu").write_utf8!(asset.content)?
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
					[id, _, _, _, _, _, head, _, _, _] =>
						match U64.from_str(id) {
							Ok(token_id) => {
								if state.ids.contains(token_id) {
									Err("duplicate token ID ${id}")
								} else {
									match U64.from_str(head) {
										Ok(head_id) => {
											next = {
												..state,
												token_count: state.token_count + 1,
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

metadata_value = |content, key| {
	prefix = "# ${key} = "

	match content.split_on("\n").keep_if(|line| line.starts_with(prefix)) {
		[line, ..] => line.replace_first(prefix, "")
		[] => ""
	}
}

metadata_or = |content, key, fallback| {
	value = metadata_value(content, key)
	if value == "" {
		fallback
	} else {
		value
	}
}

asset_json = |asset| {
	source = asset.source
	asset_path = "corpora/${asset.id}.conllu"
	"{\"id\":${json_string(asset.id)},\"path\":${json_string(asset_path)},\"sentenceCount\":${asset.stats.sentence_count.to_str()},\"tokenCount\":${asset.stats.token_count.to_str()},\"source\":{\"name\":${json_string(source.name)},\"url\":${json_string(source.url)},\"commit\":${json_string(source.commit)},\"license\":${json_string(source.license)},\"edition\":${json_string(source.edition)}}}"
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
