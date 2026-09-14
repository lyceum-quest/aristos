app [main!] {
    cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.20.0/X73hGh05nNTkDHU06FHC0YfFaQB1pimX7gncRcao5mU.tar.br"
}

import cli.Cmd
import cli.Dir
import cli.File
import cli.Stderr
import cli.Stdout

main! = \_args ->
    if !(File.exists!("preload/corpora.json")?) then
        _ = Stderr.line!("preload/corpora.json is missing; run the Kai preload task first")?
        Err (Exit 1 "Corpus preload is missing.")
    else
        _ =
            if File.exists!("dist")? then
                Dir.delete_all!("dist")?
            else
                {}

        _ = Dir.create_all!("dist")?
        _ = Cmd.exec!("elm", ["make", "src/Main.elm", "--optimize", "--output=dist/elm.js"])?
        _ = copy_file!("index.html", "dist/index.html")?
        _ = copy_file!("styles.css", "dist/styles.css")?
        _ = copy_file!("browser-bridge.js", "dist/browser-bridge.js")?
        _ = Cmd.exec!("cp", ["-R", "preload", "dist/preload"])?
        _ = Stdout.line!("built dist")?
        Ok {}

copy_file! = \source, destination ->
    content = File.read_bytes!(source)?
    File.write_bytes!(content, destination)
