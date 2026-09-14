app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br"
}

import cli.Arg
import cli.Dir
import cli.File
import cli.Stderr
import cli.Stdout

main! = \args ->
    displayed_args = List.map args Arg.display
    outcome = build_preload! (List.drop_first displayed_args 1)

    when outcome is
        Ok {} -> Ok {}
        Err Usage ->
            _ = Stderr.line!("usage: build-corpus-preload <output-dir> <corpus-id> <source.conllu> [<corpus-id> <source.conllu> ...]")?
            Err (Exit 2 "Invalid preload arguments.")
        Err (InvalidCorpus path problem) ->
            _ = Stderr.line!("$(path): $(problem)")?
            Err (Exit 1 "Corpus validation failed.")
        Err _ -> Err (Exit 1 "Could not generate corpus preload assets.")

build_preload! = \args ->
    when args is
        [output_dir, id, path, .. as rest] ->
            corpus_args = List.prepend (List.prepend rest path) id
            specs = parse_specs(corpus_args)?
            assets = prepare_assets!(specs)?

            _ =
                if File.exists!(output_dir)? then
                    Dir.delete_all!(output_dir)?
                else
                    {}

            _ = Dir.create_all!("$(output_dir)/corpora")?
            _ = write_assets!(assets, output_dir)?
            manifest = "{\"version\":1,\"corpora\":[$(Str.join_with (List.map assets asset_json) ",")]}\n"
            _ = File.write_utf8!(manifest, "$(output_dir)/corpora.json")?
            _ = Stdout.line!("wrote $(output_dir): $(Num.to_str (List.len assets)) corpus asset(s)")?
            Ok {}

        _ -> Err Usage

parse_specs = \args ->
    when args is
        [id, path, .. as rest] ->
            if invalid_id id then
                Err Usage
            else
                remaining = parse_specs(rest)?
                Ok (List.prepend remaining { id, path })

        [] -> Ok []
        _ -> Err Usage

invalid_id = \id ->
    id == "" || Str.contains id "/" || Str.contains id "\\" || Str.contains id ".."

prepare_assets! = \specs ->
    when specs is
        [] -> Ok []
        [spec, .. as rest] ->
            content = File.read_utf8!(spec.path)?

            when validate_corpus(content) is
                Err problem -> Err (InvalidCorpus spec.path problem)
                Ok valid_stats ->
                    source =
                        { name: metadata_or content "project" (metadata_or content "source" spec.id)
                        , url: metadata_value content "source_url"
                        , commit: metadata_value content "source_revision"
                        , license: metadata_value content "license"
                        , edition: metadata_value content "source_edition"
                        }
                    remaining = prepare_assets!(rest)?
                    Ok (List.prepend remaining { id: spec.id, content, source, stats: valid_stats })

write_assets! = \assets, output_dir ->
    when assets is
        [] -> Ok {}
        [asset, .. as rest] ->
            _ = File.write_utf8!(asset.content, "$(output_dir)/corpora/$(asset.id).conllu")?
            write_assets!(rest, output_dir)

validate_corpus = \content ->
    lines = Str.split_on (Str.replace_each content "\r\n" "\n") "\n"
    initial =
        { sentence_count: 0
        , token_count: 0
        , block_tokens: 0
        , roots: 0
        , ids: []
        , heads: []
        , has_sentence_id: Bool.false
        }
    completed = validate_lines(lines, initial)?
    stats = finish_block(completed)?

    if stats.sentence_count == 0 then
        Err "corpus contains no sentences"
    else
        Ok stats

validate_lines = \lines, state ->
    when lines is
        [] -> Ok state
        [line, .. as rest] ->
            if line == "" then
                next = finish_block(state)?
                validate_lines(rest, next)
            else if Str.starts_with line "#" then
                has_id =
                    state.has_sentence_id
                    || Str.starts_with line "# sent_id = "
                    || Str.starts_with line "# sentence_id = "
                validate_lines rest { state & has_sentence_id: has_id }
            else
                when Str.split_on line "\t" is
                    [id, _, _, _, _, _, head, _, _, _] ->
                        when Str.to_u64 id is
                            Ok token_id ->
                                if List.contains state.ids token_id then
                                    Err "duplicate token ID $(id)"
                                else
                                    when Str.to_u64 head is
                                        Ok head_id ->
                                            next =
                                                { state
                                                    & token_count: state.token_count + 1
                                                    , block_tokens: state.block_tokens + 1
                                                    , roots: if head_id == 0 then state.roots + 1 else state.roots
                                                    , ids: List.append state.ids token_id
                                                    , heads: List.append state.heads head_id
                                                }
                                            validate_lines rest next
                                        Err _ -> Err "token $(id) has non-numeric HEAD $(head)"
                            Err _ ->
                                if valid_non_syntactic_id id then
                                    validate_lines rest state
                                else
                                    Err "invalid token ID $(id)"

                    _ -> Err "expected 10 tab-separated columns"

finish_block = \state ->
    if state.block_tokens == 0 then
        Ok state
    else if !(state.has_sentence_id) then
        Err "sentence is missing # sent_id or # sentence_id"
    else if state.roots != 1 then
        Err "sentence must have exactly one dependency root; found $(Num.to_str state.roots)"
    else if !(List.all state.heads \head -> head == 0 || List.contains state.ids head) then
        Err "sentence has a HEAD that does not name a token in its block"
    else if !(List.all state.ids \token_id -> reaches_root token_id state.ids state.heads []) then
        Err "sentence dependency graph contains a cycle or disconnected component"
    else
        Ok
            { state
                & sentence_count: state.sentence_count + 1
                , block_tokens: 0
                , roots: 0
                , ids: []
                , heads: []
                , has_sentence_id: Bool.false
            }

reaches_root = \token_id, ids, heads, visited ->
    if token_id == 0 then
        Bool.true
    else if List.contains visited token_id then
        Bool.false
    else
        when head_for token_id ids heads is
            Just head -> reaches_root head ids heads (List.append visited token_id)
            Nothing -> Bool.false

head_for = \wanted, ids, heads ->
    when (ids, heads) is
        ([token_id, .. as rest_ids], [head, .. as rest_heads]) ->
            if token_id == wanted then
                Just head
            else
                head_for wanted rest_ids rest_heads

        _ -> Nothing

valid_non_syntactic_id = \id ->
    when Str.split_on id "-" is
        [first, last] ->
            when (Str.to_u64 first, Str.to_u64 last) is
                (Ok a, Ok b) -> a < b
                _ -> Bool.false
        _ ->
            when Str.split_on id "." is
                [first, last] ->
                    when (Str.to_u64 first, Str.to_u64 last) is
                        (Ok _, Ok _) -> Bool.true
                        _ -> Bool.false
                _ -> Bool.false

metadata_value = \content, key ->
    prefix = "# $(key) = "

    when List.keep_if (Str.split_on content "\n") \line -> Str.starts_with line prefix is
        [line, ..] -> Str.replace_first line prefix ""
        [] -> ""

metadata_or = \content, key, fallback ->
    value = metadata_value content key
    if value == "" then fallback else value

asset_json = \asset ->
    source = asset.source
    asset_path = "corpora/$(asset.id).conllu"
    "{\"id\":$(json_string asset.id),\"path\":$(json_string asset_path),\"sentenceCount\":$(Num.to_str asset.stats.sentence_count),\"tokenCount\":$(Num.to_str asset.stats.token_count),\"source\":{\"name\":$(json_string source.name),\"url\":$(json_string source.url),\"commit\":$(json_string source.commit),\"license\":$(json_string source.license),\"edition\":$(json_string source.edition)}}"

json_string = \value ->
    escaped =
        value
        |> Str.replace_each "\\" "\\\\"
        |> Str.replace_each "\"" "\\\""
        |> Str.replace_each "\n" "\\n"
        |> Str.replace_each "\r" "\\r"
        |> Str.replace_each "\t" "\\t"

    "\"$(escaped)\""
