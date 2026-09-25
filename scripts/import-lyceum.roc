app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stdout
import LyceumConllu
import LyceumImportSql

main! = |_args| {
	config_path = Env.var_str!("LYCEUM_IMPORT_CONFIG") ? |_| MissingConfig("set LYCEUM_IMPORT_CONFIG to an import JSON config; LYCEUM_IMPORT_APPLY=1 opts into database writes")
	config : LyceumImportSql.Config
	config = Json.parse(Path.read_utf8!(Path.utf8(config_path))?)?
	target = validate_config(config)?
	input = absolute!(config.input)?
	texts_db = absolute!(config.texts_db)?
	editions_db = absolute!(config.editions_db)?
	sql_output = absolute!(config.sql_output)?
	_ = (
		if input != texts_db and input != editions_db and input != sql_output and texts_db != editions_db and texts_db != sql_output and editions_db != sql_output {
			Ok({})
		} else {
			Err(PathsMustBeDistinct)
		}
	)?
	resolved = { ..config, input, texts_db, editions_db, sql_output }
	references = match config.references {
		Ok(values) => values
		Err(Missing) => []
	}
	verses = LyceumConllu.parse_with_references(Path.read_utf8!(Path.utf8(input))?, config.work_urn, references)?
	apply = switch!("LYCEUM_IMPORT_APPLY", "0")?
	backup = switch!("LYCEUM_IMPORT_BACKUP", "1")?
	_ = Path.write_utf8!(Path.utf8(sql_output), "${LyceumImportSql.build(resolved, verses, target)}\n")?
	_ = Stdout.line!("wrote ${sql_output}: ${U64.to_str(List.len(verses))} verse(s)")?
	_ = (
		if target.replace {
			Stdout.line!("FULL REPLACEMENT: ${target.greek_urn} + ${target.english_urn}; unmentioned passages will be removed from both databases")
		} else {
			Ok({})
		}
	)?
	edition_code = Str.replace_first(target.greek_urn, "urn:cts:greekLit:", "")
	translation_code = Str.replace_first(target.english_urn, "urn:cts:greekLit:", "")
	# An explicit translation override avoids the reader choosing an older English edition.
	_ = Stdout.line!("reader path after import/deployment: /read/${edition_code}?layout=row&trans=${translation_code}")?
	if apply {
		_ = check_database!(texts_db)?
		editions_exist = Path.exists!(Path.utf8(editions_db))?
		_ = (
			if editions_exist {
				check_database!(editions_db)
			} else if target.replace {
				Err(MissingDatabase(editions_db))
			} else {
				Ok({})
			}
		)?
		_ = (
			if backup {
				_ = backup!(texts_db)?
				if editions_exist backup!(editions_db) else Ok({})
			} else {
				Stdout.line!("backups explicitly disabled by LYCEUM_IMPORT_BACKUP=0")
			}
		)?
		_ = Cmd.new_str("sqlite3").args_str(["-bail", texts_db, ".read ${dot_quote(sql_output)}"]).exec_cmd!()?
		Stdout.line!(if target.replace "replaced the selected editions in texts.db and editions.db; existing IDs and URLs preserved" else "imported generated editions into texts.db and editions.db; existing source editions were not changed")
	} else {
		Stdout.line!("export only; no database writes. Set LYCEUM_IMPORT_APPLY=1 to apply; backups default on (LYCEUM_IMPORT_BACKUP=0 disables them).")
	}
}

validate_config = |config| {
	fields = [config.input, config.texts_db, config.editions_db, config.sql_output, config.work_urn, config.generator]
	work_code = Str.replace_first(config.work_urn, "urn:cts:greekLit:", "")
	if List.any(fields, |value| Str.trim(value) == "" or List.any(Str.to_utf8(value), |byte| byte < 32 or byte == 127)) {
		Err(InvalidConfig("fields must be nonempty and contain no control characters"))
	} else if !Str.ends_with(config.texts_db, "/texts.db") or !Str.ends_with(config.editions_db, "/editions.db") or !Str.ends_with(config.sql_output, ".sql") {
		Err(InvalidConfig("use explicit texts.db and editions.db paths and a .sql output"))
	} else if !Str.starts_with(config.work_urn, "urn:cts:greekLit:") or List.len(Str.split_on(config.work_urn, ":")) != 4 or List.len(Str.split_on(work_code, ".")) != 2 or List.any(Str.split_on(work_code, "."), |part| part == "") or !List.all(Str.to_utf8(work_code), |byte| slug_byte(byte) or byte == 46 or (byte >= 65 and byte <= 90)) {
		Err(InvalidConfig("work_urn must identify a Greek CTS work, not an edition or passage"))
	} else {
		match (config.edition_slug, config.replace_editions) {
			(Ok(slug), Err(Missing)) => {
				if !Str.starts_with(slug, "aristos-") or !List.all(Str.to_utf8(slug), slug_byte) {
					Err(InvalidConfig("edition_slug must start aristos- and use lowercase ASCII letters, digits, or hyphens"))
				} else {
					Ok({ greek_urn: "${config.work_urn}.${slug}-grc1", english_urn: "${config.work_urn}.${slug}-versified-eng1", replace: Bool.False })
				}
			}
			(Err(Missing), Ok(editions)) => {
				if editions.greek_urn == editions.english_urn or !List.all([editions.greek_urn, editions.english_urn], |urn| valid_edition_urn(urn, config.work_urn)) {
					Err(InvalidConfig("replace_editions must name two distinct edition URNs belonging to work_urn"))
				} else {
					Ok({ greek_urn: editions.greek_urn, english_urn: editions.english_urn, replace: Bool.True })
				}
			}
			_ => Err(InvalidConfig("specify exactly one of edition_slug or replace_editions"))
		}
	}
}

valid_edition_urn = |urn, work_urn| {
	prefix = "${work_urn}."
	suffix = Str.replace_first(urn, prefix, "")
	Str.starts_with(urn, prefix) and suffix != "" and List.all(Str.to_utf8(suffix), |byte| slug_byte(byte) or (byte >= 65 and byte <= 90) or byte == 95)
}

switch! = |name, default| {
	value = match Env.var_str!(OsStr.from_str(name)) {
		Ok(found) => found
		Err(_) => default
	}
	match value {
		"0" => Ok(Bool.False)
		"1" => Ok(Bool.True)
		_ => Err(InvalidConfig("${name} must be 0 or 1"))
	}
}

slug_byte = |byte| (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) or byte == 45

absolute! = |path| {
	result = Cmd.new_str("realpath").args_str(["-m", "--", path]).exec_output!()?
	Ok(Str.trim(result.stdout_utf8))
}

dot_quote = |path| "\"${Str.replace_each(Str.replace_each(path, "\\", "\\\\"), "\"", "\\\"")}\""

check_database! = |path| {
	_ = (
		if Path.exists!(Path.utf8(path))? {
			Ok({})
		} else {
			Err(MissingDatabase(path))
		}
	)?
	journal = Cmd.new_str("sqlite3").args_str(["-readonly", path, "PRAGMA journal_mode;"]).exec_output!()?
	if List.contains(["delete", "truncate", "persist"], Str.trim(journal.stdout_utf8)) {
		Ok({})
	} else {
		Err(UnsupportedJournalMode(path, journal.stdout_utf8))
	}
}

backup! = |path| {
	stamp = Cmd.new_str("date").args_str(["+%s-%N"]).exec_output!()?
	backup = "${path}.before-aristos-${Str.trim(stamp.stdout_utf8)}"
	_ = (
		if Path.exists!(Path.utf8(backup))? {
			Err(BackupAlreadyExists(backup))
		} else {
			Ok({})
		}
	)?
	_ = Cmd.new_str("sqlite3").args_str(["-readonly", path, ".backup ${dot_quote(backup)}"]).exec_cmd!()?
	Stdout.line!("backup: ${backup}")
}
