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
			words = List.keep_if(Str.split_on(Str.replace_each(Str.trim(source), "\n", " "), " "), |word| word != "")
			first_sent_id : U64
			first_sent_id = 1
			rows = rows_for(words, first_sent_id, [], [])
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

rows_for = |words, sent_id, pending, found|
	match words {
		[] => List.concat(found, sentence_rows(pending, sent_id))
		[word, .. as rest] => {
			next = List.append(pending, word)
			if sentence_end(word) {
				rows_for(rest, sent_id + 1, [], List.concat(found, sentence_rows(next, sent_id)))
			} else {
				rows_for(rest, sent_id, next, found)
			}
		}
	}

sentence_rows = |words, sent_id| {
	sentence = Str.join_with(words, " ")
	List.map(words, |word| { word, sentence, sent_id, gloss: "" })
}

sentence_end = |word| Str.ends_with(word, ".") or Str.ends_with(word, ";") or Str.ends_with(word, "·") or Str.ends_with(word, "·") or Str.ends_with(word, "!") or Str.ends_with(word, "?")
