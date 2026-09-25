app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Sleep
import cli.Stderr
import cli.Stdout

source = "../lyceum/website-private/data"

data = "/var/lib/lyceum/data"

files = ["texts.db", "editions.db"]

lock = "/var/lib/lyceum/data/.aristos-deploy-lock"

main! = |args| {
	(host, domain) = match args.map(OsStr.display) {
		[_, "staging"] => Ok(("lyceum-staging", "demo.lyceum.quest"))
		[_, "production"] => {
			_ = require((Env.var_str!("LYCEUM_DEPLOY_PRODUCTION") ?? "") == "1", "Production requires LYCEUM_DEPLOY_PRODUCTION=1")?
			Ok(("lyceum-prod", "lyceum.quest"))
		}
		_ => Err(Deploy("Usage: deploy-lyceum-data staging|production"))
	}?
	# Validate the complete pair before even acquiring the remote lock.
	_ = local_check!(files)?
	expected = hashes(run!("sha256sum", paths(source))?)
	_ = remote!(host, ["mkdir", "--mode=700", "--", lock])?
	result = deploy_locked!(host, domain, expected)
	unlock = remote!(host, ["rmdir", "--", lock])
	match (result, unlock) {
		(Ok(_), Ok(_)) => Stdout.line!("Deployed reader data to https://${domain}/")
		(Err(problem), Ok(_)) => Err(problem)
		(_, Err(problem)) => {
			Stderr.line!("Lock cleanup failed: ${lock}; deployment result: ${Str.inspect(result)}") ?? {}
			Err(problem)
		}
	}
}

paths = |dir| files.map(|file| "${dir}/${file}")

quote = |arg| "'${Str.replace_each(arg, "'", "'\\''")}'"

hashes = |output| Str.split_on(Str.trim(output), "\n").map(|line| List.first(Str.split_on(line, " ")) ?? "")

require = |condition, message| if condition Ok({}) else Err(Deploy(message))

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Deploy(Str.inspect(err))
	Ok(Str.trim(output.stdout_utf8))
}

# SSH joins arguments into a remote command string: quote every word, not only paths.
remote! = |host, args| run!("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=15", host, Str.join_with(args.map(quote), " ")])

local_check! = |remaining| match remaining {
	[] => Ok({})
	[file, .. as rest] => {
		path = "${source}/${file}"
		_ = run!("test", ["-f", path])?
		_ = local_sidecars!(path, ["-wal", "-shm", "-journal"])?
		checked = run!("sqlite3", ["-readonly", "-bail", path, "PRAGMA integrity_check; PRAGMA journal_mode;"])?
		_ = require(List.contains(["ok\ndelete", "ok\ntruncate", "ok\npersist"], checked), "Unsafe SQLite database ${path}: ${checked}")?
		local_check!(rest)
	}
}

local_sidecars! = |path, suffixes| match suffixes {
	[] => Ok({})
	[suffix, .. as rest] => {
		_ = run!("test", ["!", "-e", "${path}${suffix}"])?
		local_sidecars!(path, rest)
	}
}

remote_clean! = |host, remaining| match remaining {
	[] => Ok({})
	[file, .. as rest] => {
		_ = remote!(host, ["test", "!", "-e", "${data}/${file}-wal"])?
		_ = remote!(host, ["test", "!", "-e", "${data}/${file}-shm"])?
		_ = remote!(host, ["test", "!", "-e", "${data}/${file}-journal"])?
		remote_clean!(host, rest)
	}
}

verify! = |host, dir, expected| {
	actual = hashes(remote!(host, List.prepend(paths(dir), "sha256sum"))?)
	require(actual == expected, "SHA256 mismatch in ${dir}")
}

services! = |host, action| remote!(host, ["systemctl", action, "lyceum", "lyceum-admin"])

deploy_locked! = |host, domain, expected| {
	baseline = hashes(remote!(host, List.prepend(paths(data), "sha256sum"))?)
	stage = remote!(host, ["mktemp", "-d", "${data}/.aristos-deploy.XXXXXXXXXX"])?
	# mktemp's output is used by scp as well as SSH: constrain it to this template.
	_ = require(Str.starts_with(stage, "${data}/.aristos-deploy.") and List.all(Str.to_utf8(stage), |byte| (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or List.contains([47, 46, 45], byte)), "Unexpected remote staging path")?
	incoming = "${stage}/incoming"
	backup = "${stage}/backup"
	_ = remote!(host, ["mkdir", "--mode=700", "--", incoming, backup])?
	_ = Stdout.line!("Retained deployment directory: ${stage}; backup pair: ${backup}")?
	_ = run!("scp", ["-B", "${source}/texts.db", "${source}/editions.db", "${host}:${incoming}/"])?
	_ = verify!(host, incoming, expected)?
	_ = local_check!(files)?
	_ = require(hashes(run!("sha256sum", paths(source))?) == expected, "Local databases changed during staging")?

	# Any failure from stop onward may mean services are stopped, even if SSH failed.
	match prepare!(host, backup, baseline) {
		Err(problem) => {
			recovery = start_healthy!(host, domain)
			Stderr.line!("Deployment aborted before install; restart result: ${Str.inspect(recovery)}; retained ${backup}") ?? {}
			Err(problem)
		}
		Ok(_) => match install!(host, domain, incoming, expected) {
			Ok(_) => Ok({})
			Err(problem) => {
				match rollback!(host, domain, backup, baseline) {
					Ok(_) => Stderr.line!("Previous database pair restored; backups retained: ${backup}") ?? {}
					Err(recovery) => {
						stopped = services!(host, "stop")
						Stderr.line!("ROLLBACK FAILED: ${Str.inspect(recovery)}; stop result: ${Str.inspect(stopped)}. Do not restart until repaired; backups: ${backup}") ?? {}
					}
				}
				Err(problem)
			}
		}
	}
}

prepare! = |host, backup, baseline| {
	_ = services!(host, "stop")?
	_ = remote_clean!(host, files)?
	_ = verify!(host, data, baseline)?
	_ = remote!(host, ["cp", "--preserve=all", "--reflink=auto", "--", "${data}/texts.db", "${data}/editions.db", backup])?
	verify!(host, backup, baseline)
}

install! = |host, domain, incoming, expected| {
	_ = remote!(host, ["install", "-o", "lyceum", "-g", "lyceum", "-m", "0644", "--", "${incoming}/texts.db", "${incoming}/editions.db", data])?
	_ = verify!(host, data, expected)?
	_ = start_healthy!(host, domain)?
	verify!(host, data, expected)
}

rollback! = |host, domain, backup, baseline| {
	_ = services!(host, "stop")?
	# Never overwrite a live journal, including one unexpectedly created on restart.
	_ = remote_clean!(host, files)?
	_ = remote!(host, ["cp", "--preserve=all", "--", "${backup}/texts.db", "${backup}/editions.db", data])?
	_ = verify!(host, data, baseline)?
	_ = start_healthy!(host, domain)?
	verify!(host, data, baseline)
}

start_healthy! = |host, domain| {
	_ = services!(host, "start")?
	health!(host, domain, 12)
}

health! = |host, domain, attempts| {
	result = probe!(host, domain)
	match result {
		Ok(_) => Ok({})
		Err(problem) => if attempts <= 1 {
			Err(problem)
		} else {
			Sleep.millis!(2000)
			health!(host, domain, attempts - 1)
		}
	}
}

probe! = |host, domain| {
	_ = remote!(host, ["systemctl", "is-active", "--quiet", "lyceum"])?
	_ = remote!(host, ["systemctl", "is-active", "--quiet", "lyceum-admin"])?
	_ = remote!(host, ["curl", "--fail", "--silent", "--show-error", "--max-time", "10", "--output", "/dev/null", "http://127.0.0.1:8080/health"])?
	_ = run!("curl", ["--fail", "--silent", "--show-error", "--max-time", "15", "--output", "/dev/null", "https://${domain}/health"])?
	Ok({})
}
