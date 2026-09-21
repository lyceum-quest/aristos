app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.OsStr
import cli.Path
import cli.Stdout
main! = |args| match List.drop_first(args, 1) {
	[source_arg, output_arg] => {
		source = Str.replace_each(Path.read_utf8!(Path.utf8(OsStr.display(source_arg)))?, "\r\n", "\n")
		blocks = List.keep_if(Str.split_on(Str.trim(source), "\n\n"), |block| Str.starts_with(block, "# sent_id = lxx/genesis01_"))
		if List.is_empty(blocks) {
			Err(MissingGenesisChapterOne)
		} else {
			output = Str.join_with(List.map(blocks, strip_block), "\n\n")
			path = OsStr.display(output_arg)
			_ = Path.write_utf8!(Path.utf8(path), "${output}\n")?
			Stdout.line!("wrote ${path}")
		}
	}
	_ => Err(Usage("prepare-genesis-sample.roc <source.conllu> <output.conllu>"))
}
strip_block = |block| Str.join_with(List.map(Str.split_on(block, "\n"), strip_line), "\n")
strip_line = |line| if Str.starts_with(line, "#") { line } else match Str.split_on(line, "\t") {
	[a, b, c, d, e, f, g, h, i, misc] => Str.join_with([a, b, c, d, e, f, g, h, i, strip_gloss(misc)], "\t")
	_ => line
}
strip_gloss = |misc| {
	kept = List.keep_if(Str.split_on(misc, "|"), |field| !Str.starts_with(field, "Gloss=") and !Str.starts_with(field, "gloss="))
	if List.is_empty(kept) { "_" } else { Str.join_with(kept, "|") }
}
