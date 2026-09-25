app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.OsStr
import cli.Path
import cli.Sleep
import cli.Stderr
import cli.Stdout

host = "lyceum-staging"

lock = "/var/lib/lyceum/data/.aristos-deploy-lock"

# NixOS links /etc/systemd/system into the read-only store. system.control is
# systemd's higher-priority persistent override path, outside that generated tree.
override_root = "/etc/systemd/system.control"

override_dir = "${override_root}/lyceum.service.d"

override_name = "60-aristos-reader.conf"

override = "${override_dir}/${override_name}"

recovery_dir = "/var/lib/aristos-reader-deploy"

main! = |args| {
	_ = match args.map(OsStr.display) {
		[_, "staging"] => Ok({})
		_ => Err(Deploy("Usage: deploy-lyceum-reader staging (production unsupported)"))
	}?
	# Use the Git flake, never path: (which imports untracked secrets/databases).
	artifact = run!("nix", ["build", "--no-link", "--print-out-paths", "../lyceum/website-private#default"])?
	_ = require(
		match Str.split_on(artifact, "/") {
			["", "nix", "store", name] => name != "" and name != "." and name != ".." and safe_component(name)
			_ => Bool.False
		},
		"Expected one safe /nix/store package path",
	)?
	_ = run!("test", ["-x", "${artifact}/bin/lyceum"])?
	_ = remote!(["mkdir", "--mode=700", "--", lock])?
	result = deploy_locked!(artifact)
	_ = match result {
		Err(RecoveryNeeded(message)) => {
			Stderr.line!("Recovery failed; retaining ${lock}. ${message}") ?? {}
			Err(Deploy(message))
		}
		_ => Ok({})
	}?
	unlock = remote!(["rmdir", "--", lock])
	match (result, unlock) {
		(Ok(_), Ok(_)) => Stdout.line!("Deployed reader only to https://demo.lyceum.quest/")
		(Err(problem), Ok(_)) => Err(problem)
		(_, Err(problem)) => {
			Stderr.line!("Lock cleanup failed: ${lock}; deployment result: ${Str.inspect(result)}. Inspect retained deployment before manually removing lock.") ?? {}
			Err(problem)
		}
	}
}

safe_component = |name| List.all(Str.to_utf8(name), |byte| (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or List.contains([46, 45, 95, 43], byte))

require = |condition, message| if condition Ok({}) else Err(Deploy(message))

quote = |arg| "'${Str.replace_each(arg, "'", "'\\''")}'"

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Deploy(Str.inspect(err))
	Ok(Str.trim(output.stdout_utf8))
}

# SSH joins words into a command; no shell scripts or unquoted arguments.
remote! = |args| run!("ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", host, Str.join_with(args.map(quote), " ")])

deploy_locked! = |artifact| {
	# Systemd configuration must never pass through a service-writable ancestor.
	_ = remote!(["test", "!", "-L", recovery_dir])?
	_ = remote!(["install", "-d", "-o", "root", "-g", "root", "-m", "0700", "--", recovery_dir])?
	stage = remote!(["mktemp", "-d", "${recovery_dir}/reader-deploy.XXXXXXXX"])?
	_ = require(
		match Str.split_on(stage, "/") {
			["", "var", "lib", "aristos-reader-deploy", name] => Str.starts_with(name, "reader-deploy.") and safe_component(name)
			_ => Bool.False
		},
		"Unexpected remote staging path",
	)?
	Stdout.line!("Retained recovery directory: ${stage}; package root: ${stage}/package; new binary: ${artifact}/bin/lyceum. Interrupted deployments may require manual recovery and removal of ${lock}.") ?? {}
	_ = run!("nix", ["copy", "--to", "ssh://${host}", artifact])?
	_ = remote!(["nix-store", "--realise", "--add-root", "${stage}/package", artifact])?
	_ = remote!(["test", "!", "-L", override_root])?
	_ = remote!(["test", "!", "-L", override_dir])?
	_ = remote!(["mkdir", "-p", "--", override_dir])?
	_ = remote!(["test", "!", "-L", override])?
	# Successful find distinguishes absence from transport/permission failures.
	existing = remote!(["find", override_dir, "-maxdepth", "1", "-name", override_name, "-print"])?
	_ = require(existing == "" or existing == override, "Unexpected override discovery result")?
	had_override = existing == override
	_ = (
		if had_override {
			_ = remote!(["test", "-f", override])?
			remote!(["cp", "--preserve=all", "--", override, "${stage}/previous.conf"])
		} else {
			remote!(["touch", "--", "${stage}/override-was-absent"])
		}
	)?
	old_paths = remote!(["systemctl", "show", "lyceum", "--property=FragmentPath", "--property=DropInPaths"])
	Stdout.line!("Previous service paths: ${Str.inspect(old_paths)}; prior override present: ${Str.inspect(had_override)}; backup: ${stage}/previous.conf") ?? {}
	_ = stage_config!(stage, artifact)?
	# An SSH error during install can still mean the override was changed.
	match apply!(stage, artifact) {
		Ok(_) => Ok({})
		Err(problem) => {
			recovery = rollback!(stage, had_override)
			Stderr.line!("Reader deploy failed: ${Str.inspect(problem)}; rollback result: ${Str.inspect(recovery)}. Recovery files retained in ${stage}; dedicated override: ${override}") ?? {}
			match recovery {
				Ok(_) => Err(problem)
				Err(_) => Err(RecoveryNeeded("Inspect ${stage} and ${override} before removing the deployment lock."))
			}
		}
	}
}

stage_config! = |stage, artifact| {
	local = run!("mktemp", ["/tmp/aristos-reader.XXXXXXXX"])?
	config =
		\\[Service]
		\\ExecStart=
		\\ExecStart=${artifact}/bin/lyceum
		\\
	result = match Path.write_utf8!(Path.utf8(local), config) {
		Err(problem) => Err(Deploy(Str.inspect(problem)))
		Ok(_) => run!("scp", ["-B", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2", local, "${host}:${stage}/incoming.conf"])
	}
	cleanup = run!("rm", ["-f", "--", local])
	match (result, cleanup) {
		(Ok(_), Ok(_)) => Ok({})
		(Err(problem), _) => Err(problem)
		(_, Err(problem)) => Err(problem)
	}
}

apply! = |stage, artifact| {
	_ = remote!(["install", "-m", "0644", "--", "${stage}/incoming.conf", override])?
	_ = restart_healthy!({})?
	pid = remote!(["systemctl", "show", "lyceum", "--property=MainPID", "--value"])?
	_ = require(pid != "" and List.all(Str.to_utf8(pid), |byte| byte >= 48 and byte <= 57), "Invalid reader MainPID")?
	running = remote!(["readlink", "-f", "--", "/proc/${pid}/exe"])?
	require(running == "${artifact}/bin/lyceum", "Running reader does not match the deployed package")
}

rollback! = |stage, had_override| {
	_ = (
		if had_override {
			remote!(["cp", "--preserve=all", "--", "${stage}/previous.conf", override])
		} else {
			remote!(["rm", "-f", "--", override])
		}
	)?
	restart_healthy!({})
}

restart_healthy! = |{}| {
	_ = remote!(["systemctl", "daemon-reload"])?
	_ = remote!(["systemctl", "restart", "lyceum"])?
	health!(12)
}

health! = |attempts| match probe!({}) {
	Ok(_) => Ok({})
	Err(problem) => if attempts <= 1 {
		Err(problem)
	} else {
		Sleep.millis!(2000)
		health!(attempts - 1)
	}
}

probe! = |{}| {
	_ = remote!(["systemctl", "is-active", "--quiet", "lyceum"])?
	_ = remote!(["curl", "--fail", "--silent", "--show-error", "--max-time", "10", "--output", "/dev/null", "http://127.0.0.1:8080/health"])?
	_ = run!("curl", ["--fail", "--silent", "--show-error", "--max-time", "15", "--output", "/dev/null", "https://demo.lyceum.quest/health"])?
	Ok({})
}
