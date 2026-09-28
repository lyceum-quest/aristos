app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import LyceumWebsite

# Runs a command in the Lyceum website's pinned development environment, since a Kaifile cannot read variables:
# `roc scripts/lyceum-website.roc <command>...` runs `nix develop <website> --command <command>...`, with every
# `{website}` in the command replaced by the checkout LYCEUM_WEBSITE_DIR names.
main! = |args| match List.map(List.drop_first(args, 1), OsStr.display) {
	[] => Err(Usage("lyceum-website.roc <command>..."))
	command => {
		website = website_dir!({})?
		Cmd.new_str("nix").args_str(List.concat(["develop", website, "--command"], List.map(command, |arg| Str.replace_each(arg, "{website}", website)))).exec_cmd!()
	}
}

website_dir! = |{}| {
	dir = LyceumWebsite.dir(Env.var_str!(OsStr.from_str(LyceumWebsite.name)) ?? "", Path.read_utf8!(Path.utf8(LyceumWebsite.dotenv_path)) ?? "")?
	if Path.is_dir!(Path.utf8(dir)) ?? Bool.False Ok(dir) else Err(MissingWebsiteDir("${LyceumWebsite.name}=${dir} is not a directory"))
}
