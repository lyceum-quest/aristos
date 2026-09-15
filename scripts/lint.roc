app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	if List.len(args) != 1 {
		Stderr.line!("usage: lint")?
		Err(Exit(2))
	} else {
		root : Path
		root = "."
		match discover!(root) {
			Err(_) => {
				Stderr.line!("FAIL .: could not traverse current directory")?
				Stderr.line!("CoNLL-U discovery failed.")?
				Err(Exit(1))
			}

			Ok(found) => {
				files = List.sort_with(found.files, compare_path)
				skipped = List.sort_with(found.skipped, compare_path)
				print_skipped!(skipped)?

				if List.is_empty(files) and List.is_empty(skipped) {
					Stdout.line!("NONE no .conllu files found under .")?
					Ok({})
				} else {
					stats = lint_files!(files, { passed: 0.U64, failed: 0.U64 })?
					Stdout.line!("SUMMARY ${U64.to_str(stats.passed)} passed, ${U64.to_str(stats.failed)} failed, ${List.len(skipped).to_str()} skipped")?
					if stats.failed == 0 {
						Ok({})
					} else {
						Stderr.line!("CoNLL-U lint failed.")?
						Err(Exit(1))
					}
				}
			}
		}
	}
}

discover! = |dir| {
	entries = Path.list!(dir)?
	discover_entries!(entries, { files: [], skipped: [] })
}

discover_entries! = |entries, found|
	match entries {
		[] => Ok(found)
		[entry, .. as rest] => {
			path = Path.display(entry)
			match Path.type!(entry)? {
				IsDir => {
					nested = discover!(entry)?
					next = {
						files: List.concat(found.files, nested.files),
						skipped: List.concat(found.skipped, nested.skipped),
					}
					discover_entries!(rest, next)
				}

				IsFile => {
					files = if Str.ends_with(path, ".conllu") List.append(found.files, entry) else found.files
					discover_entries!(rest, { ..found, files })
				}

				IsSymLink => {
					skipped = if Str.ends_with(path, ".conllu") List.append(found.skipped, entry) else found.skipped
					discover_entries!(rest, { ..found, skipped })
				}

				IsOther => discover_entries!(rest, found)
			}
		}
	}

print_skipped! = |paths|
	match paths {
		[] => Ok({})
		[path, .. as rest] => {
			Stdout.line!("SKIP ${Path.display(path)} (symlink)")?
			print_skipped!(rest)
		}
	}

lint_files! = |files, stats|
	match files {
		[] => Ok(stats)
		[path, .. as rest] => {
			displayed = Path.display(path)
			Stdout.line!("LINT ${displayed}")?
			match lint_file!(path) {
				Ok({}) => {
					Stdout.line!("PASS ${displayed}")?
					lint_files!(rest, { ..stats, passed: stats.passed + 1 })
				}

				Err(problem) => {
					Stderr.line!("FAIL ${displayed}: ${problem}")?
					lint_files!(rest, { ..stats, failed: stats.failed + 1 })
				}
			}
		}
	}

lint_file! = |path|
	match Path.read_utf8!(path) {
		Ok(content) => lint(content)
		Err(_) => Err("could not read UTF-8 file")
	}

lint = |raw| {
	content = raw.replace_each("\r\n", "\n").replace_each("\r", "\n")
	require_comments(content, file_fields, "file")?
	lint_blocks(Str.split_on(content, "\n\n"), False)
}

file_fields = [
	"global.columns",
	"source",
	"source_edition",
	"source_url",
	"source_revision",
	"cts_urn",
	"encoder",
	"editor",
	"project",
	"conversion_method",
	"gloss_type",
	"date_modified",
	"license",
	"contact",
]

sentence_fields = ["sentence_id", "translation_lang", "prose_translation", "literal_translation"]

require_comments = |content, fields, scope| {
	lines = Str.split_on(content, "\n")
	match fields {
		[] => Ok({})
		[field, .. as rest] => {
			prefix = "# ${field} = "
			if List.any(lines, |line| Str.starts_with(line, prefix) and line != prefix) {
				require_comments(content, rest, scope)
			} else {
				Err("missing ${scope} field: ${field}")
			}
		}
	}
}

lint_blocks = |blocks, found_sentence|
	match blocks {
		[] => if found_sentence Ok({}) else Err("file contains no sentences")
		[block, .. as rest] => {
			rows = Str.split_on(block, "\n")
				.keep_if(|line| line != "" and !Str.starts_with(line, "#"))

			if List.is_empty(rows) {
				lint_blocks(rest, found_sentence)
			} else {
				require_comments(block, sentence_fields, "sentence")?
				lint_rows(rows)?
				lint_blocks(rest, True)
			}
		}
	}

lint_rows = |rows|
	match rows {
		[] => Ok({})
		[row, .. as rest] => {
			columns = Str.split_on(row, "\t")
			if List.any(columns, |field| field == "") {
				Err("token row contains an empty column")
			} else {
				match columns {
					[id, _, _, _, _, _, head, _, _, misc] =>
						match U64.from_str(id) {
							Err(_) => Err("token ID is not an unsigned integer: ${id}")
							Ok(_) =>
								match U64.from_str(head) {
									Err(_) => Err("token ${id} HEAD is not an unsigned integer: ${head}")
									Ok(_) =>
										if !has_misc(misc, "Ref") {
											Err("token ${id} is missing Ref")
										} else if !has_misc(misc, "gloss") {
											Err("token ${id} is missing gloss")
										} else {
											lint_rows(rest)
										}
									}
							}

					_ => Err("expected 10 tab-separated columns")
				}
			}
		}
	}

has_misc = |misc, key| {
	prefix = "${key}="
	List.any(Str.split_on(misc, "|"), |field| Str.starts_with(field, prefix) and field != prefix)
}

compare_path = |a, b| compare_str(Path.display(a), Path.display(b))

compare_str = |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes = |a, b|
	match (a, b) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([x, .. as xs], [y, .. as ys]) =>
			if x < y Before else if x > y After else compare_bytes(xs, ys)
		}
