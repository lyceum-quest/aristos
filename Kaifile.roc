app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.8/9b3Nr3mzNr1rEm3xPgFaaAFaizQS1SfcvHUsSDnEcy2S.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.8/std-96MVndfriX4HRuFzHn5735BuvzH1mYdhkm5JeuoTDg96.tar.zst",
}

import std.Std

kaifile = Std.kaifile([
	Name("aristos"),
	Overlay("roc", "github:roc-lang/roc-overlay"),
	Environment(
		"dev",
		[
			Tools([
				"bashInteractive",
				"coreutils",
				"curl",
				"elmPackages.elm",
				"elmPackages.elm-live",
				"elmPackages.elm-test",
				"git",
				"gnugrep",
				"openssh",
				"rocpkgs.nightly-2026-09-19-d025939",
				"rsync",
				"sqlite",
				"unzip",
			]),
			Overlays(["roc"]),
		],
	),
	Shell("default", [Use("dev")]),

	# kai run generate -- <work> <config.json> <passage-count|all>
	# e.g. kai run generate -- 1peter scripts/generate/works/1peter.json 25
	# Glosses sentences and translates canonical passages (verses, sections; see
	# scripts/Passages.roc) into conllu/generated/<work>-<model>/, resuming its
	# checkpoints; missing work makes model calls. Meditations Book 1 is 42.
	# A work config's optional "backend" picks how calls are made: "api" (the
	# default; paid per call through base_url) or "subscription" (`claude -p` on
	# this machine's Claude Code login; see scripts/generate/Backend.roc). Works
	# can switch between runs; costs.tsv records each call's backend.
	# SIGINT is ignored so Ctrl-C stops the current stage and the loop reports;
	# see ../roc-issues/improvements/IMPROVEMENT-002-basic-cli-sigint-handling.
	Task("generate", [Use("dev"), Run(["env", "--ignore-signal=INT", "roc", "scripts/generate/loop.roc"])]),

	# Export SQL by default. Configs: scripts/lyceum-{import,replace}.example.json. The databases are
	# LYCEUM_WEBSITE_DIR/data/{texts,editions}.db (see .env.example).
	# LYCEUM_IMPORT_CONFIG selects the config; LYCEUM_IMPORT_APPLY=1 writes.
	# Backups default on; LYCEUM_IMPORT_BACKUP=0 explicitly skips them.
	Task("import-lyceum", [Use("dev"), Run(["roc", "scripts/import-lyceum.roc"])]),

	# Stage, verify, back up, and replace only the reader's two content databases.
	Task("deploy-lyceum-data", [Use("dev"), Run(["roc", "scripts/deploy-lyceum-data.roc", "staging"])]),

	# Requires LYCEUM_DEPLOY_PRODUCTION=1; never rebuilds the shared host.
	Task("deploy-lyceum-data-prod", [Use("dev"), Run(["roc", "scripts/deploy-lyceum-data.roc", "production"])]),

	Task("check-lyceum-data-deploy", [Use("dev"), Run(["roc", "check", "scripts/deploy-lyceum-data.roc"])]),

	Task("format-lyceum-data-deploy", [Use("dev"), Run(["roc", "fmt", "scripts/deploy-lyceum-data.roc"])]),

	Task("format-lyceum-import", [Use("dev"), Run(["roc", "fmt", "scripts/import-lyceum.roc", "scripts/LyceumConllu.roc", "scripts/LyceumImportSql.roc", "scripts/LyceumWebsite.roc", "scripts/lyceum-import-config.roc", "scripts/lyceum-website.roc"])]),

	Task("check-lyceum-import", [Use("dev"), Run(["roc", "check", "scripts/import-lyceum.roc"])]),

	# kai run lyceum-import-config -- <conllu/generated/work-model> [--replace <greek-urn> <english-urn>]
	# Writes the work's passages (one Lyceum passage per units.jsonl passage) to /tmp and
	# scripts/lyceum-imports/<work-model>.json, which imports them.
	Task("lyceum-import-config", [Use("dev"), Run(["roc", "scripts/lyceum-import-config.roc"])]),

	Task("check-lyceum-import-config-tool", [Use("dev"), Run(["roc", "check", "scripts/lyceum-import-config.roc"])]),

	Task("check-lyceum-website-tool", [Use("dev"), Run(["roc", "check", "scripts/lyceum-website.roc"])]),

	# Lyceum is a separate Go reader; scripts/lyceum-website.roc runs these in its pinned development
	# environment, at LYCEUM_WEBSITE_DIR (see .env.example), substituting {website} in each command.
	Task("check-lyceum-reader", [Use("dev"), Run(["roc", "scripts/lyceum-website.roc", "go", "-C", "{website}", "test", "./cmd/...", "./internal/..."])]),

	Task("audit-lyceum-reader", [Use("dev"), Run(["roc", "scripts/lyceum-website.roc", "go", "-C", "{website}", "test", "-tags", "slow", "./cmd/server", "-run", "TestFeaturedInterlinearAudit|TestAesopPerry1", "-v"])]),

	Task("format-lyceum-reader", [Use("dev"), Run(["roc", "scripts/lyceum-website.roc", "gofmt", "-w", "{website}/internal/models/word.go", "{website}/internal/db/texts.go", "{website}/internal/db/sentences.go", "{website}/cmd/server/main.go", "{website}/cmd/server/interlinear_audit_test.go"])]),

	Task("refresh-lyceum-reader-support", [Use("dev"), Run(["roc", "scripts/lyceum-website.roc", "go", "-C", "{website}", "run", "./scripts/generate_reader_support_matrix"])]),

	Task("serve-lyceum-reader", [Use("dev"), Run(["roc", "scripts/lyceum-website.roc", "go", "-C", "{website}", "run", "./cmd/server"])]),

	Task("build-lyceum-reader", [Use("dev"), Run(["roc", "scripts/lyceum-website.roc", "go", "-C", "{website}", "build", "-o", ".tmp/sentence-reader", "./cmd/server"])]),

	Task("check-lyceum-reader-browser", [Use("dev"), Run(["roc", "scripts/lyceum-website.roc", "env", "TEST_LOCAL=1", "npm", "--prefix", "{website}", "test", "--", "--workers=2", "--reporter=line", "--retries=0"])]),

	Task("refresh-lyceum-reader-screenshots", [Use("dev"), Run(["roc", "scripts/lyceum-website.roc", "env", "TEST_LOCAL=1", "npm", "--prefix", "{website}", "test", "--", "screenshots.spec.ts", "--update-snapshots", "--workers=2", "--reporter=line", "--retries=0"])]),

	# Reader-only override and rollback; no NixOS switch or changes to other services.
	Task("deploy-lyceum-reader-staging", [Use("dev"), Run(["roc", "scripts/deploy-lyceum-reader.roc", "staging"])]),

	Task("check-lyceum-reader-deploy", [Use("dev"), Run(["roc", "check", "scripts/deploy-lyceum-reader.roc"])]),

	Task("format-lyceum-reader-deploy", [Use("dev"), Run(["roc", "fmt", "scripts/deploy-lyceum-reader.roc"])]),

	Task("check-loop", [Use("dev"), Run(["roc", "check", "scripts/generate/loop.roc"])]),

	Task("check-translate", [Use("dev"), Run(["roc", "check", "scripts/generate/translate.roc"])]),

	Task("check-gloss", [Use("dev"), Run(["roc", "check", "scripts/generate/gloss.roc"])]),

	Task("lint", [Use("dev"), Run(["roc", "scripts/lint.roc"])]),

	Task("check-lint-tool", [Use("dev"), Run(["roc", "check", "scripts/lint.roc"])]),

	# kai run vendor-oga-refs -- <opera_graeca_adnotata_v0.2.0.zip> <cts-id>...
	# Vendors OGA's canonical citation layer into data/oga/refs/<cts-id>.tsv, which
	# scripts/Passages.roc uses to group each work into verses or sections.
	Task("vendor-oga-refs", [Use("dev"), Run(["roc", "devtools/vendor-oga-refs.roc"])]),

	Task("check-passages-tool", [Use("dev"), Run(["roc", "check", "scripts/passages.roc"])]),

	# Embeds tests/fixtures/fsrs/*.json in the generated tests/FsrsFixtures.elm.
	Task("generate-fsrs-fixtures", [Use("dev"), Run(["roc", "devtools/generate-fsrs-fixtures.roc"])]),

	Task("check-fsrs-fixtures-tool", [Use("dev"), Run(["roc", "check", "devtools/generate-fsrs-fixtures.roc"])]),

	# Runs the Elm tests (the FSRS port against ts-fsrs and fsrs-rs fixtures).
	Task("test-elm", [Use("dev"), Run(["elm-test"])]),

	Workflow(
		"test-fsrs",
		[
			RunTask("generate-fsrs-fixtures", []),
			RunTask("test-elm", []),
		],
	),

	# Bundles every conllu/generated/<work>-<model>/ folder with output.conllu and
	# config.json as corpus <work>, including partially generated works.
	Task("preload", [Use("dev"), Run(["roc", "scripts/build-corpus-preload.roc", "preload", "conllu/generated"])]),

	Task("check-preload-tool", [Use("dev"), Run(["roc", "check", "scripts/build-corpus-preload.roc"])]),

	# kai run cite -- <oga-input.conllu> <model>
	# Prints the citation preload derives from data/oga/urn_cts.xml; fails if it would be incomplete.
	Task("cite", [Use("dev"), Run(["roc", "scripts/cite.roc"])]),

	Task("check-cite-tool", [Use("dev"), Run(["roc", "check", "scripts/cite.roc"])]),

	Task("check-release-tool", [Use("dev"), Run(["roc", "check", "scripts/build-release.roc"])]),

	Task("check-browser-boundary-tool", [Use("dev"), Run(["roc", "check", "scripts/check-browser-boundary.roc"])]),

	Task("check-deploy-tool", [Use("dev"), Run(["roc", "check", "scripts/deploy.roc"])]),

	Task("check-browser-boundary", [Use("dev"), Run(["roc", "scripts/check-browser-boundary.roc"])]),

	Task("bundle", [Use("dev"), Run(["roc", "scripts/build-release.roc"])]),

	Task("provision", [Use("dev"), Run(["roc", "scripts/deploy.roc", "infrastructure"])]),

	Workflow(
		"release",
		[
			RunTask("check-preload-tool", []),
			RunTask("check-cite-tool", []),
			RunTask("check-release-tool", []),
			RunTask("check-browser-boundary-tool", []),
			RunTask("check-deploy-tool", []),
			RunTask("check-lint-tool", []),
			RunTask("preload", []),
			RunTask("check-browser-boundary", []),
			RunTask("bundle", []),
		],
	),
])
