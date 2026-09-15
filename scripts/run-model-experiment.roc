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
import json.Option

main! = \args ->
    displayed = List.map args Arg.display

    when List.drop_first displayed 1 is
        [experiment_name] -> run_named_experiment!(experiment_name)
        [experiment_name, "--check"] -> check_named_experiment!(experiment_name)
        _ ->
            _ = Stderr.line!("usage: run-model-experiment <experiment-name> [--check]")?
            Err (Exit 2 "Invalid experiment arguments.")

check_named_experiment! = \experiment_name ->
    experiment_dir = experiment_dir_for(experiment_name)?
    config = read_config!(experiment_dir)?
    _ = validate_config(config, experiment_name)?
    inputs = discover_inputs!(experiment_dir)?
    _ = build_requests!(inputs, config, experiment_dir)?
    _ = Stdout.line!("checked $(experiment_name) experiment: $(Num.to_str (List.len inputs)) input(s)")?
    Ok {}

run_named_experiment! = \experiment_name ->
    experiment_dir = experiment_dir_for(experiment_name)?
    config = read_config!(experiment_dir)?
    _ = validate_config(config, experiment_name)?
    api_key = read_api_key!(config.provider.api_key_env)?
    inputs = discover_inputs!(experiment_dir)?
    started = Utc.now!({})
    run_id = run_id_for started config.experiment_version
    run_dir = "$(experiment_dir)/responses/$(run_id)"

    if File.exists!(run_dir)? then
        Err (RunAlreadyExists run_dir)
    else
        _ = Dir.create_all!(run_dir)?
        _ = Dir.create_all!("$(experiment_dir)/outputs")?
        _ = File.write_utf8!("$(run_id)\n", "$(run_dir)/run-id")?
        _ = run_inputs!(inputs, config, api_key, run_id, run_dir, experiment_dir)?
        _ = Stdout.line!("completed run $(run_id)")?
        Ok {}

experiment_dir_for = \experiment_name ->
    if experiment_name == "" || Str.contains experiment_name "/" || Str.contains experiment_name "\\" || Str.contains experiment_name ".." then
        Err (InvalidExperimentName experiment_name)
    else
        Ok "experiments/$(experiment_name)"

read_config! = \experiment_dir ->
    raw = File.read_bytes!("$(experiment_dir)/config.json")?
    config :
        { experiment_name : Str
        , experiment_version : U64
        , generation :
            { frequency_penalty : Option.Option Dec
            , include_reasoning : Bool
            , max_tokens : U64
            , presence_penalty : Option.Option Dec
            , profile : Str
            , provider : { allow_fallbacks : Bool, only : List Str, require_parameters : Bool }
            , reasoning : { enabled : Bool, exclude : Bool }
            , seed : Option.Option U64
            , temperature : Option.Option Dec
            , top_k : Option.Option U64
            , top_p : Option.Option Dec
            }
        , model : { id : Str }
        , provider : { api_key_env : Str, base_url : Str, name : Str }
        , validation : { max_attempts : U64 }
        }
    config = Decode.from_bytes(raw, Json.utf8)?
    Ok config

validate_config = \config, experiment_name ->
    if config.experiment_name != experiment_name then
        Err (ExperimentNameMismatch experiment_name config.experiment_name)
    else if config.validation.max_attempts == 0 then
        Err ValidationAttemptsMustBePositive
    else
        Ok {}

read_api_key! = \variable ->
    env = File.read_utf8!(".env")?
    prefix = "$(variable)="

    when List.keep_if (Str.split_on env "\n") \line -> Str.starts_with line prefix is
        [line, ..] ->
            key = Str.replace_first line prefix ""
            if key == "" then Err EmptyApiKey else Ok key
        [] -> Err MissingApiKey

discover_inputs! = \experiment_dir ->
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

build_requests! = \inputs, config, experiment_dir ->
    when inputs is
        [] -> Ok {}
        [path, .. as rest] ->
            source = File.read_utf8!(path)?
            tokens = tokenize_source(source)
            work = work_name(experiment_dir, path)
            if List.is_empty tokens then
                Err (NoTokens path)
            else
                _ = request_body(config, work, source, tokens, "")?
                build_requests!(rest, config, experiment_dir)

run_inputs! = \inputs, config, api_key, run_id, run_dir, experiment_dir ->
    when inputs is
        [] -> Ok {}
        [path, .. as rest] ->
            _ = run_input!(path, config, api_key, run_id, run_dir, experiment_dir)?
            run_inputs!(rest, config, api_key, run_id, run_dir, experiment_dir)

run_input! = \input_path, config, api_key, run_id, run_dir, experiment_dir ->
    work = work_name(experiment_dir, input_path)
    source = File.read_utf8!(input_path)?
    tokens = tokenize_source(source)

    if List.is_empty tokens then
        Err (NoTokens input_path)
    else
        run_attempt!(
            work,
            source,
            tokens,
            config,
            api_key,
            run_id,
            run_dir,
            experiment_dir,
            1,
            "",
        )

run_attempt! = \work, source, tokens, config, api_key, run_id, run_dir, experiment_dir, attempt, feedback ->
    request_id = "$(work)-v$(Num.to_str config.experiment_version)-attempt-$(Num.to_str attempt)"
    requested_at = Utc.now!({})
    timestamp = Utc.to_iso_8601(requested_at)
    body = request_body(config, work, source, tokens, feedback)?
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

    # A transport failure may follow a dispatched, billable request, so only
    # captured responses that fail validation are eligible for retry.
    response = Http.send!(request)?
    received_at = Utc.now!({})
    response_body = response.body

    # Preserve the exact response bytes before decoding or validation.
    _ = write_new_bytes!(response_body, raw_response_path)?

    when decode_response(response_body) is
        Ok decoded ->
            when decoded.choices is
                [choice, ..] ->
                    validation =
                        if choice.finish_reason != "stop" then
                            Err (IncompleteFinish choice.finish_reason)
                        else
                            validate_content(choice.message.content, work, tokens)

                    when validation is
                        Ok rendered ->
                            _ = write_attempt_record!(
                                response_path,
                                attempt,
                                body,
                                decoded,
                                choice.finish_reason,
                                response,
                                response_body,
                                request_id,
                                timestamp,
                                requested_at,
                                received_at,
                                run_id,
                                work,
                                "valid",
                                "",
                            )?
                            output_path = "$(experiment_dir)/outputs/$(work).txt"
                            _ = write_output!(rendered, output_path)?
                            _ = Stdout.line!(
                                "$(work)\tattempt $(Num.to_str attempt)\t$(decoded.model)\t$(decoded.provider)\t$(Num.to_str decoded.usage.prompt_tokens)/$(Num.to_str decoded.usage.completion_tokens)/$(Num.to_str decoded.usage.total_tokens)\t$(choice.finish_reason)\t$(response_path)\t$(output_path)",
                            )?
                            Ok {}

                        Err validation_error ->
                            error_text = validation_error_text(validation_error)
                            _ = write_attempt_record!(
                                response_path,
                                attempt,
                                body,
                                decoded,
                                choice.finish_reason,
                                response,
                                response_body,
                                request_id,
                                timestamp,
                                requested_at,
                                received_at,
                                run_id,
                                work,
                                "rejected",
                                error_text,
                            )?
                            retry_rejected!(work, source, tokens, config, api_key, run_id, run_dir, experiment_dir, attempt, error_text)

                [] ->
                    error_text = validation_error_text(MissingResponseChoice)
                    _ = write_attempt_record!(
                        response_path,
                        attempt,
                        body,
                        decoded,
                        "",
                        response,
                        response_body,
                        request_id,
                        timestamp,
                        requested_at,
                        received_at,
                        run_id,
                        work,
                        "rejected",
                        error_text,
                    )?
                    retry_rejected!(work, source, tokens, config, api_key, run_id, run_dir, experiment_dir, attempt, error_text)

        Err _ ->
            error_text = validation_error_text(InvalidResponseEnvelope)
            _ = write_attempt_record!(
                response_path,
                attempt,
                body,
                empty_decoded_response,
                "",
                response,
                response_body,
                request_id,
                timestamp,
                requested_at,
                received_at,
                run_id,
                work,
                "rejected",
                error_text,
            )?
            retry_rejected!(work, source, tokens, config, api_key, run_id, run_dir, experiment_dir, attempt, error_text)

retry_rejected! = \work, source, tokens, config, api_key, run_id, run_dir, experiment_dir, attempt, error_text ->
    _ = Stdout.line!("rejected $(work) attempt $(Num.to_str attempt): $(error_text)")?

    if attempt < config.validation.max_attempts then
        run_attempt!(
            work,
            source,
            tokens,
            config,
            api_key,
            run_id,
            run_dir,
            experiment_dir,
            attempt + 1,
            error_text,
        )
    else
        Err (ValidationAttemptsExhausted work attempt error_text)

empty_decoded_response =
    { choices: []
    , id: ""
    , model: ""
    , provider: ""
    , usage:
        { completion_tokens: 0
        , completion_tokens_details: { reasoning_tokens: 0 }
        , cost: 0
        , prompt_tokens: 0
        , total_tokens: 0
        }
    }

decode_response = \response_body ->
    decoded = Decode.from_bytes(response_body, Json.utf8)
    when decoded is
        Ok value ->
            response :
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
            response = value
            Ok response
        Err _ -> Err InvalidResponseEnvelope

write_attempt_record! = \path, attempt, body, decoded, finish_reason, response, raw_response_bytes, request_id, timestamp, requested_at, received_at, run_id, work, validation_status, validation_error ->
    elapsed_ms = Utc.delta_as_millis(received_at, requested_at)
    record =
        { attempt
        , elapsed_ms
        , finish_reason
        , http_status: response.status
        , raw_request_body: body
        , raw_response_bytes
        , request_body: body
        , request_id
        , requested_at: timestamp
        , resolved_model: decoded.model
        , resolved_provider: decoded.provider
        , response_headers: response.headers
        , response_id: decoded.id
        , run_id
        , token_usage: decoded.usage
        , validation_error
        , validation_status
        , work
        }
    record_json = Encode.to_bytes(record, Json.utf8)
    write_new_bytes!(List.append record_json 10, path)

request_body = \config, work, source, tokens, feedback ->
    system_prompt = "Produce concise contextual English word glosses for Ancient Greek tokens. Return only the requested JSON. Do not return Greek text, lemmas, morphology, commentary, or a prose translation."
    token_table =
        List.map tokens \token -> "$(token.id) | $(Num.to_str token.line) | $(token.form)"
        |> \rows -> Str.join_with rows "\n"
    retry_instruction =
        if feedback == "" then
            ""
        else
            "RETRY: The previous captured response was rejected: $(feedback)\nCorrect that structural error."
    user_prompt =
        Str.join_with
            [ "Return a JSON object with item_id and glosses."
            , "Set item_id to exactly $(work)."
            , "Return exactly one glosses array item for every target token, in the listed order."
            , "Each item must contain exactly id and gloss. Copy each listed ID exactly; supply only its concise contextual English gloss."
            , "Glosses may contain spaces but must be nonempty and must not contain line breaks or the <=> delimiter."
            , retry_instruction
            , ""
            , "SOURCE CONTEXT:"
            , source
            , "TARGET TOKENS (id | source line | immutable Greek form):"
            , token_table
            ]
            "\n"

    generation = config.generation
    token_count = List.len tokens
    response_format =
        { json_schema:
            { name: "contextual_glosses"
            , schema:
                { additionalProperties: Bool.false
                , properties:
                    { glosses:
                        { items:
                            { additionalProperties: Bool.false
                            , properties:
                                { gloss: { type: "string" }
                                , id: { type: "string" }
                                }
                            , required: ["id", "gloss"]
                            , type: "object"
                            }
                        , maxItems: token_count
                        , minItems: token_count
                        , type: "array"
                        }
                    , item_id: { type: "string" }
                    }
                , required: ["item_id", "glosses"]
                , type: "object"
                }
            , strict: Bool.true
            }
        , type: "json_schema"
        }
    messages =
        [ { content: system_prompt, role: "system" }
        , { content: user_prompt, role: "user" }
        ]
    encoded =
        when generation.profile is
            "full-sampling" ->
                frequency_penalty = required_generation_parameter(generation.frequency_penalty, "frequency_penalty")?
                presence_penalty = required_generation_parameter(generation.presence_penalty, "presence_penalty")?
                seed = required_generation_parameter(generation.seed, "seed")?
                temperature = required_generation_parameter(generation.temperature, "temperature")?
                top_k = required_generation_parameter(generation.top_k, "top_k")?
                top_p = required_generation_parameter(generation.top_p, "top_p")?
                body =
                    { frequency_penalty
                    , include_reasoning: generation.include_reasoning
                    , max_tokens: generation.max_tokens
                    , messages
                    , model: config.model.id
                    , presence_penalty
                    , provider: generation.provider
                    , reasoning: generation.reasoning
                    , response_format
                    , seed
                    , temperature
                    , top_k
                    , top_p
                    }
                Ok (Encode.to_bytes(body, Json.utf8))
            "anthropic-non-thinking" ->
                temperature = required_generation_parameter(generation.temperature, "temperature")?
                body =
                    { include_reasoning: generation.include_reasoning
                    , max_tokens: generation.max_tokens
                    , messages
                    , model: config.model.id
                    , provider: generation.provider
                    , reasoning: generation.reasoning
                    , response_format
                    , temperature
                    }
                Ok (Encode.to_bytes(body, Json.utf8))
            "openai-non-thinking" ->
                seed = required_generation_parameter(generation.seed, "seed")?
                body =
                    { include_reasoning: generation.include_reasoning
                    , max_tokens: generation.max_tokens
                    , messages
                    , model: config.model.id
                    , provider: generation.provider
                    , reasoning: generation.reasoning
                    , response_format
                    , seed
                    }
                Ok (Encode.to_bytes(body, Json.utf8))
            other -> Err (UnsupportedGenerationProfile other)

    Str.from_utf8(encoded?)

required_generation_parameter = \option, name ->
    when Option.get_result(option) is
        Some value -> Ok value
        None -> Err (MissingGenerationParameter name)

validate_content = \content, work, tokens ->
    decoded = Decode.from_bytes(Str.to_utf8(content), Json.utf8)
    when decoded is
        Ok value ->
            payload : { glosses : List { gloss : Str, id : Str }, item_id : Str }
            payload = value
            if payload.item_id != work then
                Err (WrongItemId work payload.item_id)
            else if List.len payload.glosses != List.len tokens then
                Err (WrongGlossCount (List.len tokens) (List.len payload.glosses))
            else
                validate_glosses(tokens, payload.glosses, 0, [])
        Err _ -> Err InvalidContentJson

validate_glosses = \tokens, glosses, previous_line, rendered_lines ->
    when (tokens, glosses) is
        ([], []) -> Ok "$(Str.join_with rendered_lines "\n")\n"
        ([token, .. as rest_tokens], [entry, .. as rest_glosses]) ->
            gloss = Str.trim(entry.gloss)
            if entry.id != token.id then
                Err (WrongGlossId token.id entry.id)
            else if gloss == "" then
                Err (EmptyGloss token.id)
            else if Str.contains gloss "\n" || Str.contains gloss "\r" || Str.contains gloss "<=>" then
                Err (UnsafeGloss token.id)
            else
                line = "$(token.form) <=> $(gloss)"
                next_lines =
                    if previous_line == 0 || previous_line == token.line then
                        List.append rendered_lines line
                    else
                        List.append (List.append rendered_lines "") line
                validate_glosses(rest_tokens, rest_glosses, token.line, next_lines)
        _ -> Err InternalGlossLengthMismatch

validation_error_text = \error ->
    when error is
        EmptyGloss token_id -> "empty gloss for token $(token_id)"
        IncompleteFinish finish_reason -> "finish reason was $(finish_reason), not stop"
        InternalGlossLengthMismatch -> "token and gloss lengths diverged during validation"
        InvalidContentJson -> "assistant content was not the required JSON object"
        InvalidResponseEnvelope -> "captured response was not the required PPQ completion envelope"
        MissingResponseChoice -> "captured response contained no completion choice"
        UnsafeGloss token_id -> "gloss for token $(token_id) contained a line break or <=> delimiter"
        WrongGlossCount expected actual -> "expected $(Num.to_str expected) glosses but received $(Num.to_str actual)"
        WrongGlossId expected actual -> "expected token ID $(expected) but received $(actual)"
        WrongItemId expected actual -> "expected item_id $(expected) but received $(actual)"

tokenize_source = \source ->
    normalized =
        Str.replace_each source "\r\n" "\n"
        |> Str.replace_each "\t" " "
    tokenize_lines(Str.split_on normalized "\n", 1, 1, []).tokens

tokenize_lines = \lines, line_number, next_id, found ->
    when lines is
        [] -> { next_id, tokens: found }
        [line, .. as rest] ->
            words = List.keep_if (Str.split_on line " ") \word -> word != ""
            line_result = tokenize_words(words, line_number, next_id, found)
            tokenize_lines(rest, line_number + 1, line_result.next_id, line_result.tokens)

tokenize_words = \words, line_number, next_id, found ->
    when words is
        [] -> { next_id, tokens: found }
        [word, .. as rest] ->
            token = { form: word, id: Num.to_str(next_id), line: line_number }
            tokenize_words(rest, line_number, next_id + 1, List.append found token)

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

work_name = \experiment_dir, path ->
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
