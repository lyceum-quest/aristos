app [main!] { cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import cli.Cmd
import cli.Env
import cli.Path
import cli.Stdout
import LyceumConllu
import LyceumImportSql

main! = |_args| {
	config_path = Env.var_str!("LYCEUM_IMPORT_CONFIG") ? |_| MissingConfig("set LYCEUM_IMPORT_CONFIG to an import JSON config; LYCEUM_IMPORT_APPLY=1 opts into database writes")
	config : LyceumImportSql.Config
	config = Json.parse(Path.read_utf8!(Path.utf8(config_path))?)?
	_ = validate_config(config)?
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
	verses = LyceumConllu.parse(Path.read_utf8!(Path.utf8(input))?, config.work_urn)?
	mode = match Env.var_str!("LYCEUM_IMPORT_APPLY") {
		Ok(value) => value
		Err(_) => "0"
	}
	_ = (
		if mode == "0" or mode == "1" {
			Ok({})
		} else {
			Err(InvalidApplyMode)
		}
	)?
	_ = Path.write_utf8!(Path.utf8(sql_output), "${LyceumImportSql.build(resolved, verses)}\n")?
	_ = Stdout.line!("wrote ${sql_output}: ${U64.to_str(List.len(verses))} verse(s)")?
	edition_code = "${Str.replace_first(config.work_urn, "urn:cts:greekLit:", "")}.${config.edition_slug}"
	# An explicit translation override avoids the reader choosing an older English edition.
	_ = Stdout.line!("reader path after import/deployment: /read/${edition_code}-grc1?layout=row&trans=${edition_code}-versified-eng1")?
	if mode == "1" {
		_ = backup!(texts_db)?
		_ = (
			if Path.exists!(Path.utf8(editions_db))? {
				backup!(editions_db)
			} else {
				Ok({})
			}
		)?
		_ = Cmd.new_str("sqlite3").args_str(["-bail", texts_db, ".read ${dot_quote(sql_output)}"]).exec_cmd!()?
		Stdout.line!("imported generated editions into texts.db and editions.db; existing source editions were not changed")
	} else {
		Stdout.line!("export only; no database writes. Set LYCEUM_IMPORT_APPLY=1 to back up and apply.")
	}
}

validate_config = |config| {
	fields = [config.input, config.texts_db, config.editions_db, config.sql_output, config.work_urn, config.edition_slug, config.generator]
	work_code = Str.replace_first(config.work_urn, "urn:cts:greekLit:", "")
	if List.any(fields, |value| Str.trim(value) == "" or List.any(Str.to_utf8(value), |byte| byte < 32 or byte == 127)) {
		Err(InvalidConfig("fields must be nonempty and contain no control characters"))
	} else if !Str.ends_with(config.texts_db, "/texts.db") or !Str.ends_with(config.editions_db, "/editions.db") or !Str.ends_with(config.sql_output, ".sql") {
		Err(InvalidConfig("use explicit texts.db and editions.db paths and a .sql output"))
	} else if !Str.starts_with(config.work_urn, "urn:cts:greekLit:") or List.len(Str.split_on(config.work_urn, ":")) != 4 or List.len(Str.split_on(work_code, ".")) != 2 or List.any(Str.split_on(work_code, "."), |part| part == "") or !List.all(Str.to_utf8(work_code), |byte| slug_byte(byte) or byte == 46 or (byte >= 65 and byte <= 90)) {
		Err(InvalidConfig("work_urn must identify a Greek CTS work, not an edition or passage"))
	} else if !Str.starts_with(config.edition_slug, "aristos-") or !List.all(Str.to_utf8(config.edition_slug), slug_byte) {
		Err(InvalidConfig("edition_slug must start aristos- and use lowercase ASCII letters, digits, or hyphens"))
	} else {
		Ok({})
	}
}

slug_byte = |byte| (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) or byte == 45

absolute! = |path| {
	result = Cmd.new_str("realpath").args_str(["-m", "--", path]).exec_output!()?
	Ok(Str.trim(result.stdout_utf8))
}

dot_quote = |path| "\"${Str.replace_each(Str.replace_each(path, "\\", "\\\\"), "\"", "\\\"")}\""

backup! = |path| {
	_ = (
		if Path.exists!(Path.utf8(path))? {
			Ok({})
		} else {
			Err(MissingDatabase(path))
		}
	)?
	journal = Cmd.new_str("sqlite3").args_str(["-readonly", path, "PRAGMA journal_mode;"]).exec_output!()?
	_ = (
		if List.contains(["delete", "truncate", "persist"], Str.trim(journal.stdout_utf8)) {
			Ok({})
		} else {
			Err(UnsupportedJournalMode(path, journal.stdout_utf8))
		}
	)?
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
