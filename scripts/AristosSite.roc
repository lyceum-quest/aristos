# Static Aristos releases (scripts/build-release.roc) and their deployment (scripts/deploy-site.roc).
# A release is dist/aristos/<target>/<version>/; dist/aristos/<target>/latest names the newest one.
AristosSite :: [].{

	# The Lyceum account API each target's config.json names. Aristos shows sign-in only when it has one,
	# so a local release ({}) behaves as before accounts existed.
	account_api : Str -> Try(Str, [Release(Str), ..])
	account_api = |target|
		match target {
			"production" => Ok("https://lyceum.quest")
			"staging" => Ok("https://lyceum.internal.blu.cx")
			"local" => Ok("")
			_ => Err(Release("unknown target ${target}: expected production, staging, or local"))
		}

	config_json : Str -> Str
	config_json = |api| if api == "" "{}\n" else "{\"accountApi\":\"${api}\"}\n"

	dist : Str -> Str
	dist = |target| "dist/aristos/${target}"

	# Release names reach ssh, rsync, and rm -rf on the host: letters, digits, '.', '-', and '_' only, never
	# starting with '.' (in-progress uploads do).
	valid_version : Str -> Bool
	valid_version = |version| {
		bytes = Str.to_utf8(version)
		!List.is_empty(bytes) and !Str.starts_with(version, ".") and List.all(bytes, |byte| (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or List.contains([45, 46, 95], byte))
	}
}
