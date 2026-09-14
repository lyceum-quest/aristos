app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br"
}

import cli.Arg
import cli.Cmd
import cli.Dir
import cli.Env
import cli.File
import cli.Sleep
import cli.Stdout

main! = \args ->
    displayed = List.map args Arg.display
    provision = List.contains displayed "infrastructure"
    target = Env.var!("TARGET_HOST") |> Result.with_default("lyceum-staging")
    remote_dir = Env.var!("REMOTE_DIR") |> Result.with_default("/var/www/aristos")
    deploy_state = Env.var!("DEPLOY_STATE") |> Result.with_default("/var/lib/aristos-deploy")
    lyceum_source = Env.var!("LYCEUM_SOURCE") |> Result.with_default("/home/blu/src/greek/lyceum/website")
    _ = configure_ci_ssh!({})?

    if !(File.exists!("dist/preload/corpora.json")?) then
        Err (Exit 1 "Release bundle is missing; run the Kai release workflow first.")
    else
        _ = require_head!("https://conllu.lyceum.quest/")?
        _ = require_head!("https://demo.lyceum.quest/")?
        _ = Cmd.exec!("ssh", [target, "install", "-d", remote_dir])?
        _ = Cmd.exec!("rsync", ["-az", "--delete", "dist/", "$(target):$(remote_dir)/"])?
        _ = Cmd.exec!("ssh", [target, "chown", "-R", "root:root", remote_dir])?
        _ = Cmd.exec!("ssh", [target, "chmod", "-R", "a=rX", remote_dir])?

        _ =
            if provision then
                provision_infrastructure!(target, deploy_state, lyceum_source)?
            else
                {}

        _ = verify_remote!(target)?
        _ = wait_for_public!(12)?
        _ = require_contains!("https://aristos.lyceum.quest/", "browser-bridge.js")?
        _ = require_contains!("https://aristos.lyceum.quest/elm.js", "Elm.Main")?
        _ = require_contains!("https://aristos.lyceum.quest/browser-bridge.js", "storageRequest")?
        _ = require_head!("https://conllu.lyceum.quest/")?
        _ = require_head!("https://demo.lyceum.quest/")?
        _ = Stdout.line!("deployed Aristos to https://aristos.lyceum.quest/ via $(target):$(remote_dir)")?
        Ok {}

configure_ci_ssh! = \{} ->
    when Env.var!("DEPLOY_SSH_KEY") is
        Err _ -> Ok {}
        Ok key ->
            if key == "" then
                Err (Exit 1 "DEPLOY_SSH_KEY is empty.")
            else
                home = Env.var!("HOME")?
                ssh_dir = "$(home)/.ssh"
                key_path = "$(ssh_dir)/id_ed25519"
                known_hosts_path = "$(ssh_dir)/known_hosts"
                known_host = "144.202.31.40 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFApJvwYXLciqCBurHXaaevKJMVOUgBZNpRgwvuyj8yR"
                _ = Dir.create_all!(ssh_dir)?
                _ = File.write_utf8!("$(key)\n", key_path)?
                _ = Cmd.exec!("chmod", ["700", ssh_dir])?
                _ = Cmd.exec!("chmod", ["600", key_path])?
                existing =
                    if File.exists!(known_hosts_path)? then
                        File.read_utf8!(known_hosts_path)?
                    else
                        ""
                _ =
                    if Str.contains existing known_host then
                        {}
                    else
                        File.write_utf8!("$(existing)$(known_host)\n", known_hosts_path)?
                Ok {}

provision_infrastructure! = \target, deploy_state, lyceum_source ->
    _ = Cmd.exec!("ssh", [target, "install", "-d", "$(deploy_state)/lyceum-website"])?
    _ = Cmd.exec!("rsync", ["-az", "$(lyceum_source)/flake.nix", "$(lyceum_source)/flake.lock", "$(target):$(deploy_state)/lyceum-website/"])?
    _ = Cmd.exec!("rsync", ["-az", "deploy/flake.nix", "$(target):$(deploy_state)/flake.nix"])?
    _ = Cmd.exec!("ssh", [target, "chown", "-R", "root:root", deploy_state])?
    _ = Cmd.exec!("ssh", [target, "nix", "flake", "lock", deploy_state])?
    _ = Cmd.exec!("ssh", [target, "nixos-rebuild", "switch", "--impure", "--flake", "path:$(deploy_state)#staging"])?
    _ = remote_exec!(target, ["systemctl", "is-active", "--quiet", "lyceum"])?
    _ = remote_exec!(target, ["systemctl", "is-active", "--quiet", "lyceum-admin"])?
    _ = remote_exec!(target, ["systemctl", "is-active", "--quiet", "caddy"])?
    _ = remote_exec!(target, ["systemctl", "is-active", "--quiet", "aristos-caddy"])?
    Ok {}

verify_remote! = \target ->
    index = remote_get!(target, "http://127.0.0.1:8092/")?
    bundle = remote_get!(target, "http://127.0.0.1:8092/elm.js")?
    bridge = remote_get!(target, "http://127.0.0.1:8092/browser-bridge.js")?
    manifest = remote_get!(target, "http://127.0.0.1:8092/preload/corpora.json")?
    corpus = remote_get!(target, "http://127.0.0.1:8092/preload/corpora/anabasis.conllu")?

    if !(Str.contains index "browser-bridge.js") then Err (Exit 1 "Remote index verification failed.")
    else if !(Str.contains bundle "Elm.Main") then Err (Exit 1 "Remote Elm bundle verification failed.")
    else if !(Str.contains bridge "storageRequest") then Err (Exit 1 "Remote bridge verification failed.")
    else if !(Str.contains manifest "anabasis") then Err (Exit 1 "Remote manifest verification failed.")
    else if !(Str.contains corpus "sentence_id") then Err (Exit 1 "Remote corpus verification failed.")
    else Ok {}

remote_exec! = \target, command ->
    Cmd.exec!("ssh", List.prepend command target)

remote_get! = \target, url ->
    output =
        Cmd.new("ssh")
        |> Cmd.args([target, "curl", "--fail", "--silent", "--show-error", url])
        |> Cmd.exec_output!()?
    Ok output.stdout_utf8

require_head! = \url ->
    Cmd.exec!("curl", ["--fail", "--silent", "--show-error", "--head", url])

require_contains! = \url, expected ->
    output =
        Cmd.new("curl")
        |> Cmd.args(["--fail", "--silent", "--show-error", url])
        |> Cmd.exec_output!()?

    if Str.contains output.stdout_utf8 expected then
        Ok {}
    else
        Err (Exit 1 "Deployment response from $(url) did not contain $(expected).")

wait_for_public! = \attempts ->
    result =
        Cmd.new("curl")
        |> Cmd.args(["--fail", "--silent", "--show-error", "https://aristos.lyceum.quest/preload/corpora.json"])
        |> Cmd.exec_output!()

    when result is
        Ok output ->
            if Str.contains output.stdout_utf8 "anabasis" then
                Ok {}
            else if attempts <= 1 then
                Err (Exit 1 "Aristos HTTPS verification failed.")
            else
                _ = Sleep.millis!(5000)
                wait_for_public!(attempts - 1)

        Err _ ->
            if attempts <= 1 then
                Err (Exit 1 "Aristos HTTPS verification failed.")
            else
                _ = Sleep.millis!(5000)
                wait_for_public!(attempts - 1)
