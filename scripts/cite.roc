app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout
import Citation

# Prints the citation build-corpus-preload.roc attaches to a work, so a new work's input can be checked before generation.
main! : List(OsStr) => Try({}, _)
main! = |args|
	match List.map(List.drop_first(args, 1), OsStr.display) {
		[input, model] => {
			table = Path.utf8(Citation.table_path).read_utf8!()?
			match Citation.build(table, input, model, "(not generated yet)") {
				Ok(citation) => Stdout.line!(Citation.to_json(citation))
				Err(problem) => {
					Stderr.line!("incomplete citation: ${Str.inspect(problem)}")?
					Err(Exit(1))
				}
			}
		}
		_ => {
			Stderr.line!("usage: cite <oga-input.conllu> <model>")?
			Err(Exit(2))
		}
	}
