app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumWebsite

# Publishes a release that publish-archeion committed, tagged, and staged.
#   git:    pushes ARCHEION_DIR's master and the release tag to each of ARCHEION_REMOTES (default `rad`).
#   github: creates the GitHub release from ARCHEION_RELEASE_DIR/<version>/, only for a production snapshot whose tag
#           is already on GitHub (push it to the GitHub remote first).
# The release is ARCHEION_VERSION, or else the newest v* tag in ARCHEION_DIR.
# Usage: roc scripts/push-archeion.roc git|github
main! = |args| {
	archeion = setting!("ARCHEION_DIR")
	_ = require(archeion != "" and (Path.is_dir!(Path.utf8(archeion)) ?? Bool.False), "set ARCHEION_DIR to the Archeion checkout, in the environment or in .env (see .env.example)")?
	version = match setting!("ARCHEION_VERSION") {
		"" => run!("git", ["-C", archeion, "describe", "--tags", "--abbrev=0", "--match", "v*"])?
		value => value
	}
	_ = run!("git", ["-C", archeion, "rev-parse", "--verify", "--quiet", "refs/tags/${version}"]) ? |_| Publish("${archeion} has no tag ${version}; run publish-archeion first")
	match args.map(OsStr.display) {
		[_, "git"] => {
			_ = require(switch!("ARCHEION_PUSH"), "Pushing requires ARCHEION_PUSH=1")?
			remotes = Str.split_on(if setting!("ARCHEION_REMOTES") == "" "rad" else setting!("ARCHEION_REMOTES"), " ").keep_if(|remote| remote != "")
			push!(archeion, version, remotes)
		}
		[_, "github"] => {
			_ = require(switch!("ARCHEION_GITHUB_RELEASE"), "Creating a GitHub release requires ARCHEION_GITHUB_RELEASE=1")?
			release = "${if setting!("ARCHEION_RELEASE_DIR") == "" "/var/tmp/archeion-releases" else setting!("ARCHEION_RELEASE_DIR")}/${version}"
			manifest : { version : Str, verified_against : { target : Str } }
			manifest = Json.parse(Path.read_utf8!(Path.utf8("${release}/manifest.json"))?)?
			_ = require(manifest.version == version, "${release}/manifest.json is for ${manifest.version}")?
			_ = require(manifest.verified_against.target == "production", "${version} was verified against ${manifest.verified_against.target}; only a production snapshot becomes a GitHub release")?
			repo = if setting!("ARCHEION_GITHUB_REPO") == "" "lyceum-quest/archeion" else setting!("ARCHEION_GITHUB_REPO")
			sums = Str.split_on(Path.read_utf8!(Path.utf8("${release}/SHA256SUMS.txt"))?, "\n").keep_if(|line| Str.trim(line) != "")
			_ = run!("sha256sum", ["--check", "--quiet", "--", "${release}/SHA256SUMS.txt"]) ? |_| Publish("${release} fails its SHA256SUMS.txt")
			assets = List.append(sums.map(|line| "${release}/${List.last(Str.split_on(line, " ")) ?? ""}"), "${release}/SHA256SUMS.txt")
			_ = Cmd.new_str("gh").args_str(List.concat(["release", "create", version, "--repo", repo, "--verify-tag", "--title", version, "--notes-file", "${release}/NOTES.md"], assets)).exec_cmd!()?
			Stdout.line!("Created the GitHub release ${version} in ${repo}")
		}
		_ => Err(Publish("Usage: push-archeion git|github"))
	}
}

push! = |archeion, version, remotes| match remotes {
	[] => Ok({})
	[remote, .. as rest] => {
		_ = Cmd.new_str("git").args_str(["-C", archeion, "push", remote, "master", "refs/tags/${version}"]).exec_cmd!()?
		_ = Stdout.line!("Pushed master and ${version} to ${remote}")?
		push!(archeion, version, rest)
	}
}

require = |condition, message| if condition Ok({}) else Err(Publish(message))

# Per-run switches come only from the environment, never from .env, so a publication is always deliberate.
switch! = |name| (Env.var_str!(OsStr.from_str(name)) ?? "") == "1"

run! = |program, args| {
	output = Cmd.new_str(program).args_str(args).exec_output!() ? |err| Publish("${program}: ${Str.inspect(err)}")
	Ok(Str.trim(output.stdout_utf8))
}

setting! = |key| LyceumWebsite.setting(key, Env.var_str!(OsStr.from_str(key)) ?? "", Path.read_utf8!(Path.utf8(LyceumWebsite.dotenv_path)) ?? "")
