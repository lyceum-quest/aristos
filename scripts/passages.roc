app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.OsStr
import cli.Path
import cli.Stdout
import Citation
import Passages
# Prints the canonical passages of an OGA input as JSON: `[{ "ref", "label", "tokens": ["t_N", …] }, …]`.
# scripts/generate/loop.roc runs this, since a Roc app can only import modules from its own folder.
main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[input] => {
		cts_id = Citation.cts_id(input)?
		tsv = Path.read_utf8!(Path.utf8(Passages.refs_path(cts_id)))?
		source = Str.replace_each(Path.read_utf8!(Path.utf8(input))?, "\r\n", "\n")
		blocks = List.keep_if(List.map(Str.split_on(Str.trim(source), "\n\n"), Str.trim), |block| block != "")
		passages = Passages.build(cts_id, tsv, blocks)?
		Stdout.line!(Json.to_str_try(passages)?)
	}
	_ => Err(Usage("passages.roc <oga-input.conllu>"))
}
