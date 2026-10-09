app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumWebsite

# Snapshots what a Lyceum host serves into an Archeion release: the reader databases, verified byte for byte against
# the host, and every imported Aristos work's output.conllu, units.jsonl, and config.json, cut to the passages the
# host's editions.db holds. Writes compressed release assets to ARCHEION_RELEASE_DIR/<version>/, copies the works to
# ARCHEION_DIR/conllu/lyceum/, and commits and tags the release there. Nothing leaves this machine: push-archeion
# publishes it.
# Usage: roc scripts/publish-archeion.roc staging|production
databases = ["texts.db", "editions.db", "morph.db", "lsj.db"]

remote_data = "/var/lib/lyceum/data"

import_configs = "scripts/lyceum-imports"

published = "conllu/lyceum"

ImportConfig : { work_urn : Str, edition_slug : Try(Str, [Missing]), replace_editions : Try({ greek_urn : Str, english_urn : Str }, [Missing]) }

Unit : { ref : Str, tokens : List(Str) }

Work : { folder : Str, title : Str, model : Str, edition : Str, passages : U64, generated : U64 }

main! = |args| {
	# The release records which host it matches; push-archeion only makes a GitHub release of a production match.
	target = match args.map(OsStr.display) {
		[_, "staging"] => {
			found = LyceumWebsite.staging(setting!(LyceumWebsite.staging_host), setting!(LyceumWebsite.staging_url))?
			Ok({ name: "staging", host: found.host, url: found.url })
		}
		[_, "production"] => {
			found = LyceumWebsite.production(setting!(LyceumWebsite.production_host), setting!(LyceumWebsite.production_url))?
			Ok({ name: "production", host: found.host, url: found.url })
		}
		_ => Err(Publish("Usage: publish-archeion staging|production"))
	}?
	website = directory!(LyceumWebsite.name, LyceumWebsite.dir(setting!(LyceumWebsite.name))?)?
	archeion = directory!("ARCHEION_DIR", setting!("ARCHEION_DIR"))?
	release_version = match setting!("ARCHEION_VERSION") {
		"" => run!("date", ["-u", "+v%Y.%m.%d"])?
		value => value
	}
	_ = require(valid_version(release_version), "ARCHEION_VERSION must look like vYYYY.MM.DD or vYYYY.MM.DD.N, not ${release_version}")?
	# A staging rehearsal keeps the day's release name free for production.
	version = if target.name == "staging" "${release_version}-staging" else release_version
	releases = match setting!("ARCHEION_RELEASE_DIR") {
		"" => "/var/tmp/archeion-releases"
		value => value
	}
	release = "${releases}/${version}"
	_ = require(run!("git", ["-C", archeion, "status", "--porcelain"])? == "", "${archeion} has uncommitted changes")?
	_ = match run!("git", ["-C", archeion, "rev-parse", "--verify", "--quiet", "refs/tags/${version}"]) {
		Ok(_) => Err(Publish("${archeion} already has tag ${version}; set ARCHEION_VERSION"))
		Err(_) => Ok({})
	}?
	_ = require(!(Path.exists!(Path.utf8(release)) ?? Bool.False), "${release} already exists")?

	data = "${website}/data"
	_ = no_sidecars!(data, databases)?
	local = hashes(run!("sha256sum", paths(data))?)
	served = hashes(remote!(target.host, List.prepend(paths(remote_data), "sha256sum"))?)
	_ = require(local == served, "${data} does not match ${target.host}:${remote_data}; deploy or fetch the served databases first")?
	_ = Stdout.line!("${target.name} (${target.host}) serves the local ${Str.join_with(databases, ", ")}")?

	works = collect_works!(website, sort_strs(config_names!({})?), [])?
	_ = sync_works!(archeion, works)?
	_ = Stdout.line!("copied ${U64.to_str(List.len(works))} work(s) to ${archeion}/${published}")?

	_ = run!("mkdir", ["-p", "--", release])?
	_ = compress!(data, release, databases)?
	assets = List.concat(databases.map(|file| "${file}.zst"), ["DATA_PROVENANCE.md", "manifest.json", "NOTES.md"])
	_ = run!("cp", ["--", "${website}/DATA_PROVENANCE.md", "${release}/DATA_PROVENANCE.md"])?
	compressed = hashes(run!("sha256sum", databases.map(|file| "${release}/${file}.zst"))?)
	sources = {
		aristos: run!("git", ["rev-parse", "HEAD"])?,
		aristos_clean: run!("git", ["status", "--porcelain", "--", "conllu/generated", import_configs])? == "",
		website: run!("git", ["-C", website, "rev-parse", "HEAD"])?,
	}
	sizes = Str.split_on(run!("stat", List.prepend(paths(data), "--format=%s"))?, "\n")
	manifest = manifest_json(version, target, sources, zip3(databases, local, compressed, sizes, []), works)
	_ = Path.write_utf8!(Path.utf8("${release}/manifest.json"), manifest)?
	_ = Path.write_utf8!(Path.utf8("${release}/NOTES.md"), notes(version, target, works))?
	sums = run!("sha256sum", assets.map(|file| "${release}/${file}"))?
	_ = Path.write_utf8!(Path.utf8("${release}/SHA256SUMS.txt"), "${Str.replace_each(sums, "${release}/", "")}\n")?

	_ = run!("mkdir", ["-p", "--", "${archeion}/releases"])?
	_ = Path.write_utf8!(Path.utf8("${archeion}/releases/${version}.json"), manifest)?
	_ = run!("git", ["-C", archeion, "add", "--all", "--", published, "releases"])?
	_ = run!("git", ["-C", archeion, "commit", "--quiet", "--message", "data: publish ${version} from Lyceum ${target.name}"])?
	_ = run!("git", ["-C", archeion, "tag", "--annotate", version, "--message", "Lyceum ${target.name} data, ${version}"])?
	Stdout.line!("Committed and tagged ${version} in ${archeion}; release assets in ${release}. Publish with push-archeion.")
}

valid_version = |version| match Str.split_on(Str.drop_prefix(version, "v"), ".") {
	[year, month, day] => Str.starts_with(version, "v") and digits(year, 4) and digits(month, 2) and digits(day, 2)
	[year, month, day, n] => Str.starts_with(version, "v") and digits(year, 4) and digits(month, 2) and digits(day, 2) and digits(n, List.len(Str.to_utf8(n))) and n != ""
	_ => Bool.False
}

digits = |text, count| List.len(Str.to_utf8(text)) == count and List.all(Str.to_utf8(text), |byte| byte >= 48 and byte <= 57)

config_names! = |{}| {
	entries = Path.utf8(import_configs).list!()?
	Ok(List.keep_if(entries.map(|entry| List.last(Str.split_on(entry.display(), "/")) ?? ""), |name| Str.ends_with(name, ".json")))
}

# Every work with an import config is on the site. Its units.jsonl lists Lyceum's passages in order; a partly
# imported work is published only through the passages the served editions.db holds.
collect_works! = |website, names, found| match names {
	[] => if List.is_empty(found) Err(Publish("no import configs in ${import_configs}")) else Ok(found)
	[name, .. as rest] => {
		folder = Str.drop_suffix(name, ".json")
		dir = "conllu/generated/${folder}"
		config : ImportConfig
		config = Json.parse(Path.read_utf8!(Path.utf8("${import_configs}/${name}"))?)?
		edition = match (config.edition_slug, config.replace_editions) {
			(Ok(slug), _) => "${config.work_urn}.${slug}-grc1"
			(Err(Missing), Ok(editions)) => editions.greek_urn
			_ => ""
		}
		_ = require(edition != "" and List.all(Str.to_utf8(edition), urn_byte), "${import_configs}/${name}: no valid Greek edition")?
		settings : { title : Str, model : Str }
		settings = Json.parse(Path.read_utf8!(Path.utf8("${dir}/config.json"))?)?
		units = parse_units(non_empty(Path.read_utf8!(Path.utf8("${dir}/units.jsonl"))?), [])?
		imported = non_empty(run!("sqlite3", ["-readonly", "-bail", "${website}/data/editions.db", "SELECT s.reference FROM segments s JOIN editions e ON e.id = s.edition_id WHERE e.urn = '${edition}' ORDER BY s.id;"])?)
		kept = List.take_first(units, List.len(imported))
		refs = kept.map(|unit| Str.replace_each(unit.ref, "~", "."))
		_ = require(!List.is_empty(imported) and List.len(imported) <= List.len(units) and List.all(imported, |ref| List.contains(refs, ref)), "${edition} in editions.db is not a prefix of ${dir}/units.jsonl; re-import ${folder}")?
		work = { folder, title: settings.title, model: settings.model, edition, passages: List.len(kept), generated: List.len(units) }
		collect_works!(website, rest, List.append(found, work))
	}
}

parse_units = |lines, found| match lines {
	[] => Ok(found)
	[line, .. as rest] => {
		unit : Unit
		unit = Json.parse(line)?
		parse_units(rest, List.append(found, unit))
	}
}

non_empty = |text| List.keep_if(Str.split_on(text, "\n"), |line| Str.trim(line) != "")

urn_byte = |byte| (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or List.contains([45, 46, 58, 95], byte)

# Replaces conllu/lyceum wholesale, so works dropped from the site leave the next release too.
sync_works! = |archeion, works| {
	root = "${archeion}/${published}"
	_ = run!("rm", ["-rf", "--", root])?
	_ = copy_works!(root, works)?
	Path.write_utf8!(Path.utf8("${root}/README.md"), index(works))
}

copy_works! = |root, works| match works {
	[] => Ok({})
	[work, .. as rest] => {
		source = "conllu/generated/${work.folder}"
		target = "${root}/${work.folder}"
		_ = run!("mkdir", ["-p", "--", target])?
		_ = run!("cp", ["--", "${source}/config.json", "${target}/config.json"])?
		lines = non_empty(Path.read_utf8!(Path.utf8("${source}/units.jsonl"))?)
		kept = List.take_first(lines, work.passages)
		_ = Path.write_utf8!(Path.utf8("${target}/units.jsonl"), "${Str.join_with(kept, "\n")}\n")?
		output = Path.read_utf8!(Path.utf8("${source}/output.conllu"))?
		_ = (
			if work.passages == work.generated {
				Path.write_utf8!(Path.utf8("${target}/output.conllu"), output)
			} else {
				units = parse_units(kept, [])?
				Path.write_utf8!(Path.utf8("${target}/output.conllu"), sentences_with(output, unit_tokens(units, [])))
			}
		)?
		copy_works!(root, rest)
	}
}

unit_tokens = |units, found| match units {
	[] => found
	[unit, .. as rest] => unit_tokens(rest, List.concat(found, unit.tokens))
}

# The sentence blocks holding any kept token; a sentence the last kept passage ends inside stays whole.
sentences_with = |text, tokens| {
	blocks = List.keep_if(Str.split_on(Str.replace_each(text, "\r\n", "\n"), "\n\n"), |block| Str.trim(block) != "")
	kept = List.keep_if(blocks, |block| List.any(Str.split_on(block, "\n"), |line| List.contains(tokens, row_token(line))))
	"${Str.join_with(kept.map(Str.trim), "\n\n")}\n"
}

row_token = |line| match Str.split_on(line, "\t") {
	[_, _, _, _, _, _, _, _, _, misc] if !Str.starts_with(line, "#") => List.first(Str.split_on(misc, "|")) ?? ""
	_ => ""
}

index = |works| {
	rows = works.map(|work| "| [`${work.folder}`](${work.folder}/) | ${work.title} | `${work.edition}` | ${U64.to_str(work.passages)} of ${U64.to_str(work.generated)} | ${work.model} |")
	header =
		\\# Lyceum editions
		\\
		\\Generated by `kai run publish-archeion` in Aristos; do not edit by hand.
		\\
		\\Each folder holds an Aristos work as Lyceum serves it: `output.conllu` (Greek tokens with lemmata, morphology,
		\\dependency trees, contextual glosses, and sentence translations), `units.jsonl` (the canonical passages Lyceum
		\\shows, each with its token IDs and prose and literal translations), and `config.json` (the model, source corpus,
		\\and prompts that generated them). Glosses and translations are machine-generated and not yet reviewed.
		\\A partly imported work holds only the passages Lyceum serves, and the sentences they touch.
		\\
		\\| Folder | Title | Lyceum edition | Passages | Model |
		\\|---|---|---|---:|---|
	"${header}\n${Str.join_with(rows, "\n")}\n"
}

notes = |version, target, works| {
	rows = works.map(|work| "- ${work.title} (`${work.edition}`): ${U64.to_str(work.passages)} passages")
	"# Archeion ${version}\n\nThe databases and Lyceum editions served by ${target.url} (${target.name}) on ${Str.drop_prefix(version, "v")}.\n\n## Lyceum editions\n\n${Str.join_with(rows, "\n")}\n\nThe CoNLL-U, passages, and generation configs are in `conllu/lyceum/` at this tag.\n\n## Databases\n\n`texts.db`, `editions.db`, `morph.db`, and `lsj.db`, compressed with zstd (`zstd -d texts.db.zst`). `manifest.json` lists their SHA-256 before compression; check the downloads with `sha256sum -c SHA256SUMS.txt`. See `DATA_PROVENANCE.md` for sources and licenses.\n"
}

manifest_json = |version, target, sources, dbs, works| {
	db_rows = dbs.map(|db| "    { \"name\": ${json(db.name)}, \"sha256\": ${json(db.sha256)}, \"bytes\": ${db.bytes}, \"asset\": ${json("${db.name}.zst")}, \"asset_sha256\": ${json(db.asset_sha256)} }")
	work_rows = works.map(|work| "    { \"folder\": ${json(work.folder)}, \"title\": ${json(work.title)}, \"model\": ${json(work.model)}, \"edition\": ${json(work.edition)}, \"passages\": ${U64.to_str(work.passages)}, \"generated_passages\": ${U64.to_str(work.generated)} }")
	Str.join_with(
		[
			"{",
			"  \"version\": ${json(version)},",
			"  \"verified_against\": { \"target\": ${json(target.name)}, \"host\": ${json(target.host)}, \"url\": ${json(target.url)} },",
			"  \"sources\": { \"aristos\": ${json(sources.aristos)}, \"aristos_generated_clean\": ${if sources.aristos_clean "true" else "false"}, \"website\": ${json(sources.website)} },",
			"  \"databases\": [",
			Str.join_with(db_rows, ",\n"),
			"  ],",
			"  \"lyceum_editions\": [",
			Str.join_with(work_rows, ",\n"),
			"  ]",
			"}",
			"",
		],
		"\n",
	)
}

zip3 = |names, sums, assets, sizes, found| match (names, sums, assets, sizes) {
	([name, .. as names_rest], [sha256, .. as sums_rest], [asset_sha256, .. as assets_rest], [bytes, .. as sizes_rest]) =>
		zip3(names_rest, sums_rest, assets_rest, sizes_rest, List.append(found, { name, sha256, asset_sha256, bytes }))
	_ => found
}

compress! = |data, release, remaining| match remaining {
	[] => Ok({})
	[file, .. as rest] => {
		_ = Stdout.line!("compressing ${file}")?
		_ = run!("zstd", ["--quiet", "--force", "-T0", "-10", "-o", "${release}/${file}.zst", "--", "${data}/${file}"])?
		compress!(data, release, rest)
	}
}

# A WAL or journal beside a database means its file alone is not what the reader sees.
no_sidecars! = |dir, remaining| match remaining {
	[] => Ok({})
	[file, .. as rest] => {
		_ = run!("test", ["!", "-e", "${dir}/${file}-wal", "-a", "!", "-e", "${dir}/${file}-shm", "-a", "!", "-e", "${dir}/${file}-journal"]) ? |_| Publish("${dir}/${file} has a WAL or journal file")
		no_sidecars!(dir, rest)
	}
}

sort_strs = |names| List.sort_with(names, |a, b| compare_bytes(Str.to_utf8(a), Str.to_utf8(b)))

compare_bytes = |a, b| match (a, b) {
	([], []) => Same
	([], _) => Before
	(_, []) => After
	([x, .. as xs], [y, .. as ys]) => if x < y Before else if x > y After else compare_bytes(xs, ys)
}

paths = |dir| databases.map(|file| "${dir}/${file}")

hashes = |output| Str.split_on(Str.trim(output), "\n").map(|line| List.first(Str.split_on(line, " ")) ?? "")

json = |value| "\"${Str.replace_each(Str.replace_each(value, "\\", "\\\\"), "\"", "\\\"")}\""

quote = |arg| "'${Str.replace_each(arg, "'", "'\\''")}'"

require = |condition, message| if condition Ok({}) else Err(Publish(message))

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Publish("${program}: ${Str.inspect(err)}")
	Ok(Str.trim(output.stdout_utf8))
}

# SSH joins arguments into a remote command string: quote every word, not only paths.
remote! = |host, args| run!("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=15", host, Str.join_with(args.map(quote), " ")])

setting! = |key| LyceumWebsite.setting(key, Env.var_str!(OsStr.from_str(key)) ?? "", Path.read_utf8!(Path.utf8(LyceumWebsite.dotenv_path)) ?? "")

directory! = |name, dir| {
	_ = require(dir != "", "set ${name}, in the environment or in .env (see .env.example)")?
	if Path.is_dir!(Path.utf8(dir)) ?? Bool.False Ok(dir) else Err(Publish("${name}=${dir} is not a directory"))
}
