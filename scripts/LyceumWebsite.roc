# Locates the Lyceum website checkout from LYCEUM_WEBSITE_DIR, set in the environment or in the repository's
# git-ignored .env (see .env.example). The environment wins. There is no default: a guessed sibling path would
# let an import or deployment act on the wrong checkout.
LyceumWebsite :: [].{

	name : Str
	name = "LYCEUM_WEBSITE_DIR"

	dotenv_path : Str
	dotenv_path = ".env"

	# `environment` is the variable's value and `dotenv` the contents of .env, each "" when absent.
	dir : Str, Str -> Try(Str, [MissingWebsiteDir(Str), ..])
	dir = |environment, dotenv| {
		value = if Str.trim(environment) != "" Str.trim(environment) else dotenv_value(Str.split_on(dotenv, "\n"), "")
		if value == "" {
			Err(MissingWebsiteDir("set ${name} to the Lyceum website checkout, in the environment or in .env (see .env.example)"))
		} else {
			trimmed = if Str.ends_with(value, "/") and value != "/" Str.drop_suffix(value, "/") else value
			# `nix develop website` would name a flake registry entry, not a folder.
			Ok(if Str.starts_with(trimmed, "/") or Str.starts_with(trimmed, "./") or Str.starts_with(trimmed, "../") or trimmed == "." or trimmed == ".." trimmed else "./${trimmed}")
		}
	}

	# `KEY=value` lines, optionally `export`ed or quoted; `#` comments. The last assignment wins, as in a shell.
	dotenv_value = |lines, found|
		match lines {
			[] => found
			[line, .. as rest] => {
				trimmed = Str.trim(Str.drop_prefix(Str.trim(line), "export "))
				match Str.split_on(trimmed, "=") {
					[key, .. as value] if !Str.starts_with(trimmed, "#") and Str.trim(key) == name =>
						dotenv_value(rest, unquote(Str.trim(Str.join_with(value, "="))))
					_ => dotenv_value(rest, found)
				}
			}
		}

	unquote = |value| {
		bytes = Str.to_utf8(value)
		match (List.first(bytes), List.last(bytes)) {
			(Ok(first), Ok(last)) if List.len(bytes) >= 2 and first == last and (first == 34 or first == 39) =>
				Str.from_utf8(List.drop_last(List.drop_first(bytes, 1), 1)) ?? value
			_ => value
		}
	}
}
