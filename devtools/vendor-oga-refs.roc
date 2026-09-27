app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }
import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Stdout
# Vendors OGA's canonical citation layer for chosen works into data/oga/refs/<cts-id>.tsv (`t_N<TAB>citation`).
# The layer lives only in the PAULA files (`<cts-id>.tok01_cts01.xml`) of the nested workspace/oga.zip, so this
# extracts that inner archive once into a scratch folder and reads each requested work's file from it.
# Usage: roc devtools/vendor-oga-refs.roc <opera_graeca_adnotata_v0.2.0.zip> <cts-id>...
scratch = "/tmp/aristos-oga-refs"
inner = "opera_graeca_adnotata_v0.2.0/workspace/oga.zip"
out_dir = "data/oga/refs"
main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[zip, first, .. as rest] => run!(zip, List.prepend(rest, first))
	_ => Err(Usage("vendor-oga-refs.roc <opera_graeca_adnotata_v0.2.0.zip> <cts-id>..."))
}
run! = |zip, ids| {
	inner_zip = "${scratch}/${inner}"
	_ = (
		if Path.exists!(Path.utf8(inner_zip))? {
			Ok({})
		} else {
			_ = Path.create_all!(Path.utf8(scratch))?
			_ = Stdout.line!("extracting ${inner} (about 3 GB)…")?
			_ = Cmd.new_str("unzip").args_str(["-q", "-o", zip, inner, "-d", scratch]).exec_output!()?
			Ok({})
		}
	)?
	listing = Cmd.new_str("unzip").args_str(["-Z1", inner_zip]).exec_output!()?
	_ = Path.create_all!(Path.utf8(out_dir))?
	vendor!(inner_zip, Str.split_on(listing.stdout_utf8, "\n"), ids)
}
vendor! = |inner_zip, entries, ids| match ids {
	[] => Ok({})
	[id, .. as rest] => {
		suffix = "/${id}/${id}.tok01_cts01.xml"
		entry = List.first(List.keep_if(entries, |name| Str.ends_with(Str.trim(name), suffix))) ? |_| MissingCitationLayer(id)
		xml = Cmd.new_str("unzip").args_str(["-p", inner_zip, Str.trim(entry)]).exec_output!()?
		rows = citations(Str.split_on(xml.stdout_utf8, "\n"), [])
		_ = (if List.is_empty(rows) { Err(EmptyCitationLayer(id)) } else { Ok({}) })?
		path = "${out_dir}/${id}.tsv"
		_ = Path.write_utf8!(Path.utf8(path), "${Str.join_with(rows, "\n")}\n")?
		_ = Stdout.line!("wrote ${path}: ${U64.to_str(List.len(rows))} tokens")?
		vendor!(inner_zip, entries, rest)
	}
}
# `<feat id="u_3" xlink:href="#t_3" value="1_1"/>` -> `t_3<TAB>1_1`; placeholder rows (`#e_N`) are never shown, so skipped.
citations = |lines, found| match lines {
	[] => found
	[line, .. as rest] =>
		match Str.split_on(line, "xlink:href=\"#t_") {
			[_, tail] =>
				match Str.split_on(tail, "\" value=\"") {
					[number, value_tail] =>
						match Str.split_on(value_tail, "\"") {
							[value, ..] => citations(rest, List.append(found, "t_${number}\t${value}"))
							_ => citations(rest, found)
						}
					_ => citations(rest, found)
				}
			_ => citations(rest, found)
		}
}
