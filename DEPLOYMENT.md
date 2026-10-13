# Aristos deployment

Live preview: <https://aristos.internal.blu.cx> (tailnet only), served from the
development machine by `aristos-preview.service` (`elm-live` on
`127.0.0.1:8092` in the repository root). It needs no deployment: source edits
recompile automatically and `kai run preload` refreshes its data. The committed
`config.json` points the preview's "Sign in to sync" at the staging account API,
`https://lyceum.internal.blu.cx`; while that is unreachable Aristos only notes it
on the Progress page.

## study.lyceum.quest

Aristos is published as a static site on the Lyceum production host, whose
Caddy serves `ARISTOS_DEPLOY_DIR/current` (default `/var/www/aristos/current`)
at `study.lyceum.quest`. The vhost is declared in the Lyceum website's
`flake.nix` (`services.lyceum.staticSites`); deploying Aristos never rebuilds
the host.

### Release

```sh
kai workflow release            # production: account API https://lyceum.quest
kai workflow release-staging    # staging: https://lyceum.internal.blu.cx
kai run bundle -- local         # no account API: no sign-in UI
```

The workflows check the tools, rebuild `preload/`, check the browser boundary,
and run `scripts/build-release.roc <target>`, which writes a self-contained
site to `dist/aristos/<target>/<version>/` (version
`<UTC time>-<commit>[-dirty]`) and its name to `dist/aristos/<target>/latest`:

- `index.html`, rewritten to load the assets below;
- `assets/elm.<hash>.js` (`elm make --optimize`, not minified),
  `assets/browser-bridge.<hash>.js`, `assets/styles.<hash>.css`, named by the
  first 16 hex digits of their SHA-256;
- `config.json`: `{"accountApi": "<origin>"}`, or `{}` for `local`;
- `preload/`, copied as built.

Caching: files under `assets/` never change under a name, so Caddy serves them
`Cache-Control: public, max-age=31536000, immutable`. Everything else
(`index.html`, `config.json`, `preload/`) keeps a fixed name and is served
`no-cache`, so browsers revalidate it (ETag/Last-Modified) on every load.

### Deploy

Settings come from the environment or `.env` (see `.env.example`):
`ARISTOS_DEPLOY_HOST` (SSH destination, required; root, like the Lyceum data
deploy), `ARISTOS_DEPLOY_DIR` (default `/var/www/aristos`), and
`ARISTOS_SITE_URL` (checked after the swap; default
`https://study.lyceum.quest` for production and
`https://study.internal.blu.cx` for staging). Production also needs
`ARISTOS_DEPLOY_PRODUCTION=1`, read only from the environment.

```sh
ARISTOS_DEPLOY_PRODUCTION=1 kai run deploy-site -- production             # newest production bundle
ARISTOS_DEPLOY_PRODUCTION=1 kai run deploy-site -- production <version>   # a specific one
```

Staging is the Lyceum staging microVM on blu-tower, at
`https://study.internal.blu.cx` (tailnet only; signs in through
`https://lyceum.internal.blu.cx`):

```sh
kai workflow release-staging
ARISTOS_DEPLOY_HOST=root@lyceum-staging.tail42aee1.ts.net kai run deploy-site -- staging
```

`scripts/deploy-site.roc` checks the local release (complete, and its
`config.json` matches the target), uploads it with rsync to
`releases/.<version>.partial` (owned by the SSH user, world-readable), compares
it with the local copy by checksum, renames it to `releases/<version>`, and
points `current` at it by renaming a new symlink over the old one, so visitors
get either the whole old site or the whole new one. It then requires
`ARISTOS_SITE_URL` to serve the new `index.html` and `config.json`; if it does
not, `current` is put back. On success `previous` points at the release it
replaced and every other release is removed. Deploys take no lock: run one at a
time.

### Roll back

```sh
ARISTOS_DEPLOY_PRODUCTION=1 kai run rollback-site -- production
ARISTOS_DEPLOY_HOST=root@lyceum-staging.tail42aee1.ts.net kai run rollback-site -- staging
```

Swaps `current` and `previous` (so running it again rolls forward) and checks
the site. Releases already on the host are never overwritten, so to
return to the release you rolled back from, roll back again rather than
redeploying it.

## Earlier deployment: aristos.lyceum.quest (down)

Aristos was once deployed to the same NixOS host as `conllu.lyceum.quest`, with
`/var/www/aristos` served by a separate `aristos-caddy.service` on
`127.0.0.1:8092` behind the host's public Caddy. `roc scripts/deploy.roc` and
`kai run provision` (which assembles that host's configuration in
`/var/lib/aristos-deploy` from `deploy/flake.nix` and `LYCEUM_WEBSITE_DIR`)
remain for it, but they publish a `dist/` bundle that the release workflow no
longer builds; they need updating to `dist/aristos/<target>/<version>/` should
that host return.

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
Deploying connects with SSH (as root: it stops and starts the `lyceum` service, and any
leftover `lyceum-admin` unit (the admin panel has been removed), and installs the databases into `/var/lib/lyceum/data`
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
