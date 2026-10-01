# Settings for the Lyceum website, each read from the environment or else the repository's git-ignored .env (see
# .env.example). LYCEUM_WEBSITE_DIR has no default: a guessed sibling path would let an import or deployment act on
# the wrong checkout. Deploy targets default to the tailnet staging host and the production host.
LyceumWebsite :: [].{

	name : Str
	name = "LYCEUM_WEBSITE_DIR"

	dotenv_path : Str
	dotenv_path = ".env"

	Target : { host : Str, url : Str }

	staging_host : Str
	staging_host = "LYCEUM_STAGING_HOST"

	staging_url : Str
	staging_url = "LYCEUM_STAGING_URL"

	production_host : Str
	production_host = "LYCEUM_PROD_HOST"

	production_url : Str
	production_url = "LYCEUM_PROD_URL"

	# `environment` is the variable's value and `dotenv` the contents of .env, each "" when absent.
	setting : Str, Str, Str -> Str
	setting = |key, environment, dotenv| if Str.trim(environment) != "" Str.trim(environment) else dotenv_value(Str.split_on(dotenv, "\n"), key, "")

	# `value` is the LYCEUM_WEBSITE_DIR setting.
	dir : Str -> Try(Str, [MissingWebsiteDir(Str), ..])
	dir = |value|
		if value == "" {
			Err(MissingWebsiteDir("set ${name} to the Lyceum website checkout, in the environment or in .env (see .env.example)"))
		} else {
			trimmed = if Str.ends_with(value, "/") and value != "/" Str.drop_suffix(value, "/") else value
			# `nix develop website` would name a flake registry entry, not a folder.
			Ok(if Str.starts_with(trimmed, "/") or Str.starts_with(trimmed, "./") or Str.starts_with(trimmed, "../") or trimmed == "." or trimmed == ".." trimmed else "./${trimmed}")
		}

	# Staging is reached over the tailnet: its URL defaults to plain HTTP on the SSH host's name, not a public domain.
	staging : Str, Str -> Try(Target, [InvalidTarget(Str), ..])
	staging = |host, url| {
		ssh = if host == "" "lyceum-staging" else host
		target(ssh, if url == "" "http://${List.last(Str.split_on(ssh, "@")) ?? ssh}" else url)
	}

	production : Str, Str -> Try(Target, [InvalidTarget(Str), ..])
	production = |host, url| target(if host == "" "lyceum-prod" else host, if url == "" "https://lyceum.quest" else url)

	# The host reaches ssh and scp as an argument (`host:path`), so it must not look like an option or a path.
	target = |host, url| {
		bytes = Str.to_utf8(host)
		at_signs = List.len(List.keep_if(bytes, |byte| byte == 64))
		host_ok = !List.is_empty(bytes) and !Str.starts_with(host, "-") and at_signs <= 1 and List.all(bytes, |byte| (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or List.contains([45, 46, 64, 95], byte))
		url_ok = (Str.starts_with(url, "http://") or Str.starts_with(url, "https://")) and List.all(Str.to_utf8(url), |byte| byte > 32 and byte < 127 and byte != 34 and byte != 39)
		if !host_ok {
			Err(InvalidTarget("invalid SSH host: ${host}"))
		} else if !url_ok {
			Err(InvalidTarget("invalid reader URL: ${url}"))
		} else {
			Ok({ host, url: if Str.ends_with(url, "/") Str.drop_suffix(url, "/") else url })
		}
	}

	# `KEY=value` lines, optionally `export`ed or quoted; `#` comments. The last assignment wins, as in a shell.
	dotenv_value = |lines, key, found|
		match lines {
			[] => found
			[line, .. as rest] => {
				trimmed = Str.trim(Str.drop_prefix(Str.trim(line), "export "))
				match Str.split_on(trimmed, "=") {
					[left, .. as value] if !Str.starts_with(trimmed, "#") and Str.trim(left) == key =>
						dotenv_value(rest, key, unquote(Str.trim(Str.join_with(value, "="))))
					_ => dotenv_value(rest, key, found)
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
