app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst",
}

import cli.Cmd
import cli.Env
import cli.OsStr exposing [OsStr]
import cli.Path
import cli.Sleep
import cli.Stderr
import cli.Stdout

main! : List(OsStr) => Try({}, _)
main! = |args| {
	displayed = args.map(OsStr.display)
	provision = displayed.contains("infrastructure")
	target = Env.var_str!("TARGET_HOST") ?? "lyceum-staging"
	remote_dir = Env.var_str!("REMOTE_DIR") ?? "/var/www/aristos"
	deploy_state = Env.var_str!("DEPLOY_STATE") ?? "/var/lib/aristos-deploy"
	lyceum_source = Env.var_str!("LYCEUM_SOURCE") ?? "/home/blu/src/greek/lyceum/website"
	configure_ci_ssh!({})?

	if Bool.not(Path.exists!("dist/preload/corpora.json")?) {
		exit_with_message!(1, "Release bundle is missing; run the Kai release workflow first.")
	} else {
		require_head!("https://conllu.lyceum.quest/")?
		require_head!("https://demo.lyceum.quest/")?
		Cmd.new_str("ssh")
			.args_str([target, "install", "-d", remote_dir])
			.exec_cmd!()?
		Cmd.new_str("rsync")
			.args_str(["-az", "--delete", "dist/", "${target}:${remote_dir}/"])
			.exec_cmd!()?
		Cmd.new_str("ssh")
			.args_str([target, "chown", "-R", "root:root", remote_dir])
			.exec_cmd!()?
		Cmd.new_str("ssh")
			.args_str([target, "chmod", "-R", "a=rX", remote_dir])
			.exec_cmd!()?

		if provision {
			provision_infrastructure!(target, deploy_state, lyceum_source)?
		} else {
			{}
		}

		verify_remote!(target)?
		wait_for_public!(12)?
		require_contains!("https://aristos.lyceum.quest/", "browser-bridge.js")?
		require_contains!("https://aristos.lyceum.quest/elm.js", "Elm.Main")?
		require_contains!("https://aristos.lyceum.quest/browser-bridge.js", "storageRequest")?
		require_head!("https://conllu.lyceum.quest/")?
		require_head!("https://demo.lyceum.quest/")?
		Stdout.line!("deployed Aristos to https://aristos.lyceum.quest/ via ${target}:${remote_dir}")?
		Ok({})
	}
}

configure_ci_ssh! = |{}| {
	match Env.var_str!("DEPLOY_SSH_KEY") {
		Err(_) => Ok({})
		Ok(key) => {
			if key == "" {
				exit_with_message!(1, "DEPLOY_SSH_KEY is empty.")
			} else {
				home = Env.var_str!("HOME")?
				ssh_dir_str = "${home}/.ssh"
				ssh_dir = Path.utf8(ssh_dir_str)
				key_path = Path.join(ssh_dir, "id_ed25519")
				known_hosts_path = Path.join(ssh_dir, "known_hosts")
				known_host = "144.202.31.40 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFApJvwYXLciqCBurHXaaevKJMVOUgBZNpRgwvuyj8yR"
				Path.create_all!(ssh_dir)?
				Path.write_utf8!(key_path, "${key}\n")?
				Cmd.new_str("chmod")
					.args_str(["700", ssh_dir_str])
					.exec_cmd!()?
				Cmd.new_str("chmod")
					.args_str(["600", "${ssh_dir_str}/id_ed25519"])
					.exec_cmd!()?
				existing = if Path.exists!(known_hosts_path)? {
					Path.read_utf8!(known_hosts_path)?
				} else {
					""
				}
				if Str.contains(existing, known_host) {
					{}
				} else {
					Path.write_utf8!(known_hosts_path, "${existing}${known_host}\n")?
				}
				Ok({})
			}
		}
	}
}

provision_infrastructure! = |target, deploy_state, lyceum_source| {
	Cmd.new_str("ssh")
		.args_str([target, "install", "-d", "${deploy_state}/lyceum-website"])
		.exec_cmd!()?
	Cmd.new_str("rsync")
		.args_str(["-az", "${lyceum_source}/flake.nix", "${lyceum_source}/flake.lock", "${target}:${deploy_state}/lyceum-website/"])
		.exec_cmd!()?
	Cmd.new_str("rsync")
		.args_str(["-az", "deploy/flake.nix", "${target}:${deploy_state}/flake.nix"])
		.exec_cmd!()?
	Cmd.new_str("ssh")
		.args_str([target, "chown", "-R", "root:root", deploy_state])
		.exec_cmd!()?
	Cmd.new_str("ssh")
		.args_str([target, "nix", "flake", "lock", deploy_state])
		.exec_cmd!()?
	Cmd.new_str("ssh")
		.args_str([target, "nixos-rebuild", "switch", "--impure", "--flake", "path:${deploy_state}#staging"])
		.exec_cmd!()?
	remote_exec!(target, ["systemctl", "is-active", "--quiet", "lyceum"])?
	remote_exec!(target, ["systemctl", "is-active", "--quiet", "lyceum-admin"])?
	remote_exec!(target, ["systemctl", "is-active", "--quiet", "caddy"])?
	remote_exec!(target, ["systemctl", "is-active", "--quiet", "aristos-caddy"])?
	Ok({})
}

verify_remote! = |target| {
	index = remote_get!(target, "http://127.0.0.1:8092/")?
	bundle = remote_get!(target, "http://127.0.0.1:8092/elm.js")?
	bridge = remote_get!(target, "http://127.0.0.1:8092/browser-bridge.js")?
	manifest = remote_get!(target, "http://127.0.0.1:8092/preload/corpora.json")?
	corpus = remote_get!(target, "http://127.0.0.1:8092/preload/corpora/anabasis.conllu")?

	if Bool.not(Str.contains(index, "browser-bridge.js")) {
		exit_with_message!(1, "Remote index verification failed.")
	} else if Bool.not(Str.contains(bundle, "Elm.Main")) {
		exit_with_message!(1, "Remote Elm bundle verification failed.")
	} else if Bool.not(Str.contains(bridge, "storageRequest")) {
		exit_with_message!(1, "Remote bridge verification failed.")
	} else if Bool.not(Str.contains(manifest, "anabasis")) {
		exit_with_message!(1, "Remote manifest verification failed.")
	} else if Bool.not(Str.contains(corpus, "sentence_id")) {
		exit_with_message!(1, "Remote corpus verification failed.")
	} else {
		Ok({})
	}
}

remote_exec! = |target, command|
	Cmd.new_str("ssh")
		.args_str(List.prepend(command, target))
		.exec_cmd!()

remote_get! = |target, url| {
	output = Cmd.new_str("ssh")
		.args_str([target, "curl", "--fail", "--silent", "--show-error", url])
		.exec_output!()?
	Ok(output.stdout_utf8)
}

require_head! = |url|
	Cmd.new_str("curl")
		.args_str(["--fail", "--silent", "--show-error", "--head", url])
		.exec_cmd!()

require_contains! = |url, expected| {
	output = Cmd.new_str("curl")
		.args_str(["--fail", "--silent", "--show-error", url])
		.exec_output!()?

	if Str.contains(output.stdout_utf8, expected) {
		Ok({})
	} else {
		exit_with_message!(1, "Deployment response from ${url} did not contain ${expected}.")
	}
}

wait_for_public! = |attempts| {
	public_ready = Cmd.new_str("curl")
		.args_str(["--fail", "--silent", "--show-error", "https://aristos.lyceum.quest/preload/corpora.json"])
		.exec_output!()
		.map_ok(|output| Str.contains(output.stdout_utf8, "anabasis"))
		?? Bool.False

	if public_ready {
		Ok({})
	} else if attempts <= 1 {
		exit_with_message!(1, "Aristos HTTPS verification failed.")
	} else {
		Sleep.millis!(5000)
		wait_for_public!(attempts - 1)
	}
}

exit_with_message! = |code, message| {
	Stderr.line!(message) ?? {}
	Err(Exit(code))
}
