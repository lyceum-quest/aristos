app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.22.2/9zUBxb1LtXYVc4eR4hAtd1WQDwBYDhM6HQdZz1UFCm2m.tar.zst" }

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	preload_manifest : Path
	preload_manifest = "preload/corpora.json"

	if !preload_manifest.exists!()? {
		Stderr.line!("preload/corpora.json is missing; run the Kai preload task first")?
		Stderr.line!("Corpus preload is missing.")?
		Err(Exit(1))
	} else {
		dist : Path
		dist = "dist"

		if dist.exists!()? {
			dist.delete_all!()?
		} else {
			{}
		}

		dist.create_all!()?
		Cmd.exec!("elm", ["make", "src/Main.elm", "--optimize", "--output=dist/elm.js"])?
		copy_file!("index.html", dist.join("index.html"))?
		copy_file!("styles.css", dist.join("styles.css"))?
		copy_file!("browser-bridge.js", dist.join("browser-bridge.js"))?
		Cmd.exec!("cp", ["-R", "preload", "dist/preload"])?
		Stdout.line!("built dist")?
		Ok({})
	}
}

copy_file! : Path, Path => Try({}, _)
copy_file! = |source, destination| {
	content = source.read_bytes!()?
	destination.write_bytes!(content)
}
