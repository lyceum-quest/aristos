app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout

main! = |args|
	match List.drop_first(args, 1) {
		[input_arg] => {
			input = OsStr.display(input_arg)
			source = Path.read_utf8!(Path.utf8(input))?
			lines = Str.split_on(Str.trim_end(source), "\n")
			first_sent_id : U64
			first_sent_id = 1
			rows = rows_for(lines, first_sent_id, [])
			output = if Str.ends_with(input, ".txt") Str.replace_last(input, ".txt", ".json") else "${input}.json"
			json = Json.to_str_try(rows)?
			_ = Path.write_utf8!(Path.utf8(output), "${json}\n")?
			Stdout.line!("wrote ${output}")
		}
		_ => {
			_ = Stderr.line!("usage: deepseek <file.txt>")?
			Err(Exit(2))
		}
	}

rows_for = |lines, sent_id, found|
	match lines {
		[] => found
		[sentence, .. as rest] => {
			words = List.keep_if(Str.split_on(sentence, " "), |word| word != "")
			rows = List.map(words, |word| { word, sentence, sent_id, gloss: "" })
			rows_for(rest, sent_id + 1, List.concat(found, rows))
		}
	}
