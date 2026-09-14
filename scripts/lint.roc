app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br"
}

import cli.Dir
import cli.File
import cli.Path
import cli.Stderr
import cli.Stdout

main! = \args ->
    if List.len args != 1 then
        Err (Exit 2 "usage: lint")
    else
        when discover!(".") is
            Err _ ->
                _ = Stderr.line!("FAIL .: could not traverse current directory")?
                Err (Exit 1 "CoNLL-U discovery failed.")

            Ok found ->
                files = List.sort_with found.files compare_str
                skipped = List.sort_with found.skipped compare_str
                _ = print_skipped!(skipped)?

                if List.is_empty files && List.is_empty skipped then
                    _ = Stdout.line!("NONE no .conllu files found under .")?
                    Ok {}
                else
                    stats = lint_files!(files, { passed: 0, failed: 0 })?
                    _ = Stdout.line!("SUMMARY $(Num.to_str stats.passed) passed, $(Num.to_str stats.failed) failed, $(Num.to_str (List.len skipped)) skipped")?
                    if stats.failed == 0 then Ok {} else Err (Exit 1 "CoNLL-U lint failed.")

discover! = \dir ->
    entries = Dir.list!(dir)?
    discover_entries!(entries, { files: [], skipped: [] })

discover_entries! = \entries, found ->
    when entries is
        [] -> Ok found
        [entry, .. as rest] ->
            path = Path.display entry
            when Path.type!(entry)? is
                IsDir ->
                    nested = discover!(path)?
                    next =
                        { files: List.concat found.files nested.files
                        , skipped: List.concat found.skipped nested.skipped
                        }
                    discover_entries!(rest, next)

                IsFile ->
                    files = if Str.ends_with path ".conllu" then List.append found.files path else found.files
                    discover_entries!(rest, { found & files })

                IsSymLink ->
                    skipped = if Str.ends_with path ".conllu" then List.append found.skipped path else found.skipped
                    discover_entries!(rest, { found & skipped })

print_skipped! = \paths ->
    when paths is
        [] -> Ok {}
        [path, .. as rest] ->
            _ = Stdout.line!("SKIP $(path) (symlink)")?
            print_skipped!(rest)

lint_files! = \files, stats ->
    when files is
        [] -> Ok stats
        [path, .. as rest] ->
            _ = Stdout.line!("LINT $(path)")?
            when lint_file!(path) is
                Ok {} ->
                    _ = Stdout.line!("PASS $(path)")?
                    lint_files!(rest, { stats & passed: stats.passed + 1 })

                Err problem ->
                    _ = Stderr.line!("FAIL $(path): $(problem)")?
                    lint_files!(rest, { stats & failed: stats.failed + 1 })

lint_file! = \path ->
    when File.read_utf8!(path) is
        Ok content -> lint(content)
        Err _ -> Err "could not read UTF-8 file"

lint = \raw ->
    content = raw |> Str.replace_each "\r\n" "\n" |> Str.replace_each "\r" "\n"
    _ = require_comments(content, file_fields, "file")?
    lint_blocks(Str.split_on content "\n\n", Bool.false)

file_fields =
    [ "global.columns", "source", "source_edition", "source_url"
    , "source_revision", "cts_urn", "encoder", "editor", "project"
    , "conversion_method", "gloss_type", "date_modified", "license", "contact"
    ]

sentence_fields = ["sentence_id", "translation_lang", "prose_translation", "literal_translation"]

require_comments = \content, fields, scope ->
    lines = Str.split_on content "\n"
    when fields is
        [] -> Ok {}
        [field, .. as rest] ->
            prefix = "# $(field) = "
            if List.any lines \line -> Str.starts_with line prefix && line != prefix then
                require_comments(content, rest, scope)
            else
                Err "missing $(scope) field: $(field)"

lint_blocks = \blocks, found_sentence ->
    when blocks is
        [] -> if found_sentence then Ok {} else Err "file contains no sentences"
        [block, .. as rest] ->
            rows =
                Str.split_on block "\n"
                |> List.keep_if \line -> line != "" && !(Str.starts_with line "#")

            if List.is_empty rows then
                lint_blocks(rest, found_sentence)
            else
                _ = require_comments(block, sentence_fields, "sentence")?
                _ = lint_rows(rows)?
                lint_blocks(rest, Bool.true)

lint_rows = \rows ->
    when rows is
        [] -> Ok {}
        [row, .. as rest] ->
            columns = Str.split_on row "\t"
            if List.any columns \field -> field == "" then
                Err "token row contains an empty column"
            else
                when columns is
                    [id, _, _, _, _, _, head, _, _, misc] ->
                        when Str.to_u64 id is
                            Err _ -> Err "token ID is not an unsigned integer: $(id)"
                            Ok _ ->
                                when Str.to_u64 head is
                                    Err _ -> Err "token $(id) HEAD is not an unsigned integer: $(head)"
                                    Ok _ ->
                                        if !(has_misc(misc, "Ref")) then Err "token $(id) is missing Ref"
                                        else if !(has_misc(misc, "gloss")) then Err "token $(id) is missing gloss"
                                        else lint_rows(rest)

                    _ -> Err "expected 10 tab-separated columns"

has_misc = \misc, key ->
    prefix = "$(key)="
    List.any (Str.split_on misc "|") \field -> Str.starts_with field prefix && field != prefix

compare_str = \a, b -> compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes = \a, b ->
    when (a, b) is
        ([], []) -> EQ
        ([], _) -> LT
        (_, []) -> GT
        ([x, .. as xs], [y, .. as ys]) ->
            if x < y then LT else if x > y then GT else compare_bytes(xs, ys)
