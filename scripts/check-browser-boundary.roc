app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br"
}

import cli.Cmd
import cli.File
import cli.Stderr
import cli.Stdout

max_bridge_bytes = 4096

main! = \_args ->
    bridge = File.read_utf8!("browser-bridge.js")?
    index = File.read_utf8!("index.html")?
    listed =
        Cmd.new("git")
        |> Cmd.args(["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.js"])
        |> Cmd.exec_output!()?
    candidates =
        listed.stdout_utf8
        |> Str.split_on("\n")
        |> List.keep_if \path -> path != ""
    existing = existing_files!(candidates)?
    forbidden_listed =
        Cmd.new("git")
        |> Cmd.args(["ls-files", "--cached", "--others", "--exclude-standard", "--", "*.py", "*.sh"])
        |> Cmd.exec_output!()?
    forbidden_candidates =
        forbidden_listed.stdout_utf8
        |> Str.split_on("\n")
        |> List.keep_if \path -> path != ""
    forbidden_existing = existing_files!(forbidden_candidates)?

    if !(List.is_empty forbidden_existing) then
        fail!("maintained Python or shell source is forbidden; found $(Inspect.to_str forbidden_existing)")
    else if existing != ["browser-bridge.js"] then
        fail!("maintained JavaScript must be exactly browser-bridge.js; found $(Inspect.to_str existing)")
    else if List.len (Str.to_utf8 bridge) > max_bridge_bytes then
        fail!("browser-bridge.js exceeds the explicit $(Num.to_str max_bridge_bytes)-byte architecture limit")
    else if List.any forbidden_bridge_terms \term -> Str.contains bridge term then
        fail!("browser-bridge.js contains an operation reserved for Elm or Roc")
    else if Str.contains index "<script>" || Str.contains index "<script\n" then
        fail!("index.html contains inline JavaScript")
    else if List.len (Str.split_on index "<script") != 3 then
        fail!("index.html must contain exactly two external script elements")
    else if !(Str.contains index "<script src=\"elm.js\"></script>") || !(Str.contains index "<script src=\"browser-bridge.js\"></script>") then
        fail!("index.html must load only the generated Elm bundle and browser bridge")
    else
        Stdout.line!("browser boundary OK: one $(Num.to_str (List.len (Str.to_utf8 bridge)))-byte bridge")

existing_files! = \paths ->
    when paths is
        [] -> Ok []
        [path, .. as rest] ->
            remaining = existing_files!(rest)?
            if File.exists!(path)? then
                Ok (List.prepend remaining path)
            else
                Ok remaining

forbidden_bridge_terms =
    [ "fetch("
    , "XMLHttpRequest"
    , "localStorage"
    , "corpora.json"
    , "parseConllu"
    , "sentenceIndex"
    , "attemptCount"
    ]

fail! = \message ->
    _ = Stderr.line!(message)?
    Err (Exit 1 message)
