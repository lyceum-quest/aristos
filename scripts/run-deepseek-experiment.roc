app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.13.0/RqendgZw5e1RsQa3kFhgtnMP8efWoqGRsAvubx4-zus.tar.br",
}

import cli.Arg
import cli.Dir
import cli.File
import cli.Http
import cli.Path
import cli.Stderr
import cli.Stdout
import cli.Utc
import json.Json

experiment_dir = "experiments/deepseek"

main! = \args ->
    displayed = List.map args Arg.display

    when List.drop_first displayed 1 is
        [] -> run_experiment!({})
        ["--check"] -> check_experiment!({})
        _ ->
            _ = Stderr.line!("usage: run-deepseek-experiment [--check]")?
            Err (Exit 2 "Invalid experiment arguments.")

check_experiment! = \{} ->
    config = read_config!({})?
    inputs = discover_inputs!({})?
    _ = build_requests!(inputs, config)?
    _ = Stdout.line!("checked DeepSeek experiment: $(Num.to_str (List.len inputs)) input(s)")?
    Ok {}

run_experiment! = \{} ->
    config = read_config!({})?
    api_key = read_api_key!(config.provider.api_key_env)?
    inputs = discover_inputs!({})?
    started = Utc.now!({})
    run_id = run_id_for started config.experiment_version
    run_dir = "$(experiment_dir)/responses/$(run_id)"

    if File.exists!(run_dir)? then
        Err (RunAlreadyExists run_dir)
    else
        _ = Dir.create_all!(run_dir)?
        _ = Dir.create_all!("$(experiment_dir)/outputs")?
        _ = File.write_utf8!("$(run_id)\n", "$(run_dir)/run-id")?
        _ = run_inputs!(inputs, config, api_key, run_id, run_dir)?
        _ = Stdout.line!("completed run $(run_id)")?
        Ok {}

read_config! = \{} ->
    raw = File.read_bytes!("$(experiment_dir)/config.json")?
    config :
        { experiment_version : U64
        , generation :
            { frequency_penalty : Dec
            , include_reasoning : Bool
            , max_tokens : U64
            , presence_penalty : Dec
            , provider : { allow_fallbacks : Bool, only : List Str, require_parameters : Bool }
            , reasoning : { enabled : Bool, exclude : Bool }
            , response_format :
                { json_schema :
                    { name : Str
                    , schema :
                        { additionalProperties : Bool
                        , properties : { glossed_text : { type : Str } }
                        , required : List Str
                        , type : Str
                        }
                    , strict : Bool
                    }
                , type : Str
                }
            , seed : U64
            , temperature : Dec
            , top_p : Dec
            }
        , model : { id : Str }
        , provider : { api_key_env : Str, base_url : Str, name : Str }
        }
    config = Decode.from_bytes(raw, Json.utf8)?
    Ok config

read_api_key! = \variable ->
    env = File.read_utf8!(".env")?
    prefix = "$(variable)="

    when List.keep_if (Str.split_on env "\n") \line -> Str.starts_with line prefix is
        [line, ..] ->
            key = Str.replace_first line prefix ""
            if key == "" then Err EmptyApiKey else Ok key
        [] -> Err MissingApiKey

discover_inputs! = \{} ->
    input_dir = "$(experiment_dir)/inputs"
    entries = Dir.list!(input_dir)?
    paths = discover_input_files!(entries, [])? |> List.sort_with compare_str

    if List.is_empty paths then Err NoInputs else Ok paths

discover_input_files! = \entries, found ->
    when entries is
        [] -> Ok found
        [entry, .. as rest] ->
            path = Path.display entry
            next =
                when File.type!(path)? is
                    IsFile -> if Str.ends_with path ".txt" then List.append found path else found
                    IsDir -> found
                    IsSymLink -> found
            discover_input_files!(rest, next)

build_requests! = \inputs, config ->
    when inputs is
        [] -> Ok {}
        [path, .. as rest] ->
            source = File.read_utf8!(path)?
            _ = request_body(config, source)?
            build_requests!(rest, config)

run_inputs! = \inputs, config, api_key, run_id, run_dir ->
    when inputs is
        [] -> Ok {}
        [path, .. as rest] ->
            _ = run_input!(path, config, api_key, run_id, run_dir)?
            run_inputs!(rest, config, api_key, run_id, run_dir)

run_input! = \input_path, config, api_key, run_id, run_dir ->
    work = work_name(input_path)
    request_id = "$(work)-v$(Num.to_str config.experiment_version)"
    requested_at = Utc.now!({})
    timestamp = Utc.to_iso_8601(requested_at)
    source = File.read_utf8!(input_path)?
    body = request_body(config, source)?
    request_path = "$(run_dir)/$(request_id).request.json"
    raw_response_path = "$(run_dir)/$(request_id).raw.json"
    response_path = "$(run_dir)/$(request_id).json"

    _ = write_new_utf8!(body, request_path)?

    request =
        { Http.default_request &
            method: POST
            , uri: "$(config.provider.base_url)/chat/completions"
            , timeout_ms: TimeoutMilliseconds(300000)
            , headers:
                [ Http.header(("Authorization", "Bearer $(api_key)"))
                , Http.header(("Content-Type", "application/json"))
                ]
            , body: Str.to_utf8(body)
        }

    # PPQ completions are billable, so the runner deliberately sends once and
    # never retries an uncertain transport result.
    response = Http.send!(request)?
    received_at = Utc.now!({})
    response_body = response.body

    # Preserve the exact response bytes before decoding or extracting output.
    _ = write_new_bytes!(response_body, raw_response_path)?
    raw_response = Str.from_utf8(response_body)?

    decoded :
        { choices : List { finish_reason : Str, message : { content : Str } }
        , id : Str
        , model : Str
        , provider : Str
        , usage :
            { completion_tokens : U64
            , completion_tokens_details : { reasoning_tokens : U64 }
            , cost : Dec
            , prompt_tokens : U64
            , total_tokens : U64
            }
        }
    decoded = Decode.from_bytes(response_body, Json.utf8)?

    when decoded.choices is
        [choice, ..] ->
            content : { glossed_text : Str }
            content = Decode.from_bytes(Str.to_utf8(choice.message.content), Json.utf8)?
            elapsed_ms = Utc.delta_as_millis(received_at, requested_at)
            record =
                { elapsed_ms
                , finish_reason: choice.finish_reason
                , http_status: response.status
                , raw_request_body: body
                , raw_response_body: raw_response
                , request_body: body
                , request_id
                , requested_at: timestamp
                , resolved_model: decoded.model
                , resolved_provider: decoded.provider
                , response_headers: response.headers
                , response_id: decoded.id
                , run_id
                , token_usage: decoded.usage
                , work
                }
            record_json = Encode.to_bytes(record, Json.utf8)
            _ = write_new_bytes!(List.append record_json 10, response_path)?
            output_path = "$(experiment_dir)/outputs/$(work).txt"
            _ = write_output!(content.glossed_text, output_path)?
            _ = Stdout.line!(
                "$(work)\t$(decoded.model)\t$(decoded.provider)\t$(Num.to_str decoded.usage.prompt_tokens)/$(Num.to_str decoded.usage.completion_tokens)/$(Num.to_str decoded.usage.total_tokens)\t$(choice.finish_reason)\t$(response_path)\t$(output_path)",
            )?
            Ok {}

        [] -> Err (MissingChoice work)

request_body = \config, source ->
    system_prompt = "Produce contextual English word-by-word glosses for Ancient Greek.\nReturn JSON only, with exactly one key named glossed_text and a string value.\nDo not provide lemmas, morphology, commentary, or a prose translation."

    user_prompt =
        Str.join_with
            [ "Place the original Greek and its concise contextual English word glosses side by side in glossed_text."
            , "Keep Greek words in source order. Sentence punctuation may be omitted from the displayed Greek words."
            , "Prefer one Greek word and one English gloss per line, written as Greek <=> English gloss."
            , "Use blank lines to preserve source line boundaries when practical."
            , "The result is for human review, so prioritize valid contextual English word-by-word translation over machine-oriented token formatting."
            , "Return a JSON object containing only glossed_text."
            , ""
            , "SOURCE:"
            , source
            ]
            "\n"

    generation = config.generation
    body =
        { frequency_penalty: generation.frequency_penalty
        , include_reasoning: generation.include_reasoning
        , max_tokens: generation.max_tokens
        , messages:
            [ { content: system_prompt, role: "system" }
            , { content: user_prompt, role: "user" }
            ]
        , model: config.model.id
        , presence_penalty: generation.presence_penalty
        , provider: generation.provider
        , reasoning: generation.reasoning
        , response_format: generation.response_format
        , seed: generation.seed
        , temperature: generation.temperature
        , top_p: generation.top_p
        }

    encoded = Encode.to_bytes(body, Json.utf8)
    Str.from_utf8(encoded)

write_new_utf8! = \content, path ->
    if File.exists!(path)? then
        Err (RefuseOverwrite path)
    else
        File.write_utf8!(content, path)

write_new_bytes! = \content, path ->
    if File.exists!(path)? then
        Err (RefuseOverwrite path)
    else
        File.write_bytes!(content, path)

write_output! = \content, path ->
    temporary = "$(path).tmp"
    _ = File.write_utf8!(content, temporary)?
    File.rename!(temporary, path)

run_id_for = \timestamp, version ->
    compact =
        Utc.to_iso_8601(timestamp)
        |> Str.replace_each "-" ""
        |> Str.replace_each ":" ""
    nanos = Utc.to_nanos_since_epoch(timestamp)

    "$(compact)-$(Num.to_str nanos)-v$(Num.to_str version)"

work_name = \path ->
    prefix = "$(experiment_dir)/inputs/"
    relative = Str.replace_first path prefix ""
    Str.replace_last relative ".txt" ""

compare_str = \a, b -> compare_bytes(Str.to_utf8(a), Str.to_utf8(b))

compare_bytes = \a, b ->
    when (a, b) is
        ([], []) -> EQ
        ([], _) -> LT
        (_, []) -> GT
        ([x, .. as xs], [y, .. as ys]) ->
            if x < y then LT else if x > y then GT else compare_bytes(xs, ys)
