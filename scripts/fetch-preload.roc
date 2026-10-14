app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout

# Replaces preload/ with the Archeion preload release pinned in preload.lock.json, after checking its SHA-256.
# ARISTOS_PRELOAD_ARCHIVE names a local archive to use instead of downloading (still checked against the pin), e.g. one
# built by Archeion's release-preload before it is published.
# Usage: roc scripts/fetch-preload.roc
lock_path = "preload.lock.json"

main! = |_args| {
	lock : { release : Str, url : Str, sha256 : Str }
	lock = Json.parse(Path.read_utf8!(Path.utf8(lock_path))?)?
	scratch = run!("mktemp", ["-d", "preload.fetch-XXXXXXXXXX"])?
	archive = match Env.var_str!(OsStr.from_str("ARISTOS_PRELOAD_ARCHIVE")) ?? "" {
		"" => {
			_ = run!("curl", ["--fail", "--silent", "--show-error", "--location", "--output", "${scratch}/preload.tar.zst", "--", lock.url])?
			"${scratch}/preload.tar.zst"
		}
		path => path
	}
	sum = List.first(Str.split_on(run!("sha256sum", ["--", archive])?, " ")) ?? ""
	if sum != lock.sha256 {
		_ = run!("rm", ["-rf", "--", scratch])?
		Err(Fetch("${archive} has SHA-256 ${sum}, but ${lock_path} pins ${lock.sha256}"))
	} else {
		_ = run!("mkdir", ["--", "${scratch}/preload"])?
		_ = run!("tar", ["--use-compress-program=zstd -d", "-C", "${scratch}/preload", "-xf", archive])?
		_ = require(Path.exists!(Path.utf8("${scratch}/preload/corpora.json")) ?? Bool.False, "${lock.release} has no corpora.json")?
		_ = run!("rm", ["-rf", "--", "preload"])?
		_ = run!("mv", ["--", "${scratch}/preload", "preload"])?
		_ = run!("rm", ["-rf", "--", scratch])?
		Stdout.line!("preload/ is ${lock.release} (${sum})")
	}
}

require = |condition, message| if condition Ok({}) else Err(Fetch(message))

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Fetch("${program}: ${Str.inspect(err)}")
	Ok(Str.trim(output.stdout_utf8))
}
