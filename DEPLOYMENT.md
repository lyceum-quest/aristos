# Aristos deployment

Live preview: <https://aristos.blu.cx>, served from the development machine by
`aristos-preview.service` (`elm-live` on `127.0.0.1:8092` in the repository
root) behind the machine's system Caddy. It needs no deployment: source edits
recompile automatically and `kai run preload` refreshes its data.

The remainder of this document describes the earlier static deployment to
`aristos.lyceum.quest`, which is currently down.

Aristos was deployed to the same NixOS host as `conllu.lyceum.quest`, but its
static files and serving process are isolated:

- `/var/www/aristos` contains the release bundle;
- `aristos-caddy.service` serves it on `127.0.0.1:8092`;
- the host's public Caddy service terminates TLS and reverse-proxies only the
  `aristos.lyceum.quest` virtual host to that internal service; and
- `conllu.lyceum.quest` continues to serve `/var/www/conllu-viz` directly.

This two-Caddy layout gives Aristos a separate service and configuration while
allowing the existing public Caddy instance to remain the sole owner of ports
80 and 443.

## Deploy

The `deploy` workflow, `publish` task, and CI workflow were removed while
that host is down. `roc scripts/deploy.roc` still publishes `dist/` to it
(defaults `TARGET_HOST` to `LYCEUM_STAGING_HOST`, `REMOTE_DIR=/var/www/aristos`) and
verifies Aristos plus the existing Conllu and Lyceum endpoints, should the
host return.

## Provision infrastructure

The static service and public route normally do not need to be rebuilt during
an application deploy. To apply the declarative NixOS module explicitly:

```sh
kai workflow release
kai run provision
```

The Roc deployment CLI assembles the host configuration in
`/var/lib/aristos-deploy` from `deploy/flake.nix` and the local Lyceum checkout.
This host-extension flake remains handwritten because the current Kai machine
model cannot preserve and extend undeclared sibling services. It explicitly
preserves the deployed Lyceum reader/admin packages and all existing Caddy
routes. The checkout is `LYCEUM_WEBSITE_DIR` (see `.env.example`).

## Lyceum reader data

Generated works are imported into the Lyceum website's `data/texts.db` and
`data/editions.db` and deployed to its hosts. Every task that touches the
website finds its checkout through `LYCEUM_WEBSITE_DIR`, set in the
environment or in a git-ignored `.env` (copy `.env.example`); nothing falls
back to a guessed path.

```sh
cp .env.example .env            # then set LYCEUM_WEBSITE_DIR

# Write a generated work's passages (units.jsonl, one Lyceum passage per Aristos
# verse or section) to /tmp and its import config to scripts/lyceum-imports/.
kai run lyceum-import-config -- conllu/generated/romans-claude-sonnet-5
# A work whose Lyceum editions predate Aristos is replaced in place instead:
kai run lyceum-import-config -- conllu/generated/meditations-claude-sonnet-5 \
  --replace urn:cts:greekLit:tlg0562.tlg001.workspace-grc1 urn:cts:greekLit:tlg0562.tlg001.workspace-grc1-gen-eng1

# Write the SQL only, then apply it (backs up both databases first).
LYCEUM_IMPORT_CONFIG=scripts/lyceum-imports/romans-claude-sonnet-5.json kai run import-lyceum
LYCEUM_IMPORT_CONFIG=scripts/lyceum-imports/romans-claude-sonnet-5.json LYCEUM_IMPORT_APPLY=1 kai run import-lyceum

kai run check-lyceum-reader     # the website's Go tests, in its dev shell
kai run deploy-lyceum-data      # staging, over the tailnet
LYCEUM_DEPLOY_PRODUCTION=1 kai run deploy-lyceum-data-prod
```

Applying needs the website's full `data/texts.db`, which is not in its Git
repository, and the work and its author must already be in its catalog.
Configs in `scripts/lyceum-imports/` add an `aristos-<model>` edition;
`scripts/lyceum-replace.example.json` instead replaces two existing editions
wholesale. A re-import replaces the passages it names and keeps the rest.
Deploying connects with SSH (as root: it stops and starts the `lyceum` service, and
`lyceum-admin` where installed (production only) and installs the databases into `/var/lib/lyceum/data`
owned by `lyceum`) to `LYCEUM_STAGING_HOST` (default `lyceum-staging`, the
tailnet name) or `LYCEUM_PROD_HOST` (default `lyceum-prod`), then checks
`<url>/health` with `LYCEUM_STAGING_URL` (default `http://<staging host>`) or
`LYCEUM_PROD_URL` (default `https://lyceum.quest`). Staging needs no public
domain. Set `LYCEUM_STAGING_HOST=root@lyceum-staging` unless SSH config already
logs in as root.

## Archeion releases

[Archeion](https://github.com/lyceum-quest/archeion) publishes what Lyceum serves.
`publish-archeion` checks that production serves exactly the website's local
`texts.db`, `editions.db`, `morph.db`, and `lsj.db` (by SHA-256 over SSH),
copies every work with a config in `scripts/lyceum-imports/` into
`ARCHEION_DIR/conllu/lyceum/<work>-<model>/` (`output.conllu`, `units.jsonl`,
`config.json`), and commits and tags `vYYYY.MM.DD` there with a manifest in
`releases/`. A partly imported work is cut to the passages the served
`editions.db` holds; a work whose imported passages are not a prefix of its
`units.jsonl` stops the release until it is re-imported. The zstd-compressed
databases, `SHA256SUMS.txt`, `manifest.json`, `NOTES.md`, and the website's
`DATA_PROVENANCE.md` are staged in `ARCHEION_RELEASE_DIR/<version>/` (default
`/var/tmp/archeion-releases`). `users.db` is never read.

```sh
kai run publish-archeion                 # production; nothing leaves this machine
ARCHEION_PUSH=1 kai run push-archeion    # master + tag to ARCHEION_REMOTES (default rad)
ARCHEION_GITHUB_RELEASE=1 kai run release-archeion-github   # needs the tag on GitHub

# All of it, after deploying the data to production:
LYCEUM_DEPLOY_PRODUCTION=1 ARCHEION_PUSH=1 ARCHEION_REMOTES="rad origin" \
  ARCHEION_GITHUB_RELEASE=1 kai workflow release-lyceum
```

`publish-archeion-staging` rehearses against staging and tags
`vYYYY.MM.DD-staging`; `release-archeion-github` refuses anything not verified
against production. Set `ARCHEION_VERSION=vYYYY.MM.DD.2` for a second release
on the same day.
