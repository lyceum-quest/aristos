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
(defaults `TARGET_HOST=lyceum-staging`, `REMOTE_DIR=/var/www/aristos`) and
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

# Write an import config for a generated work, citing each sentence by its
# first token in data/oga/refs; levels is the reader's citation depth.
kai run lyceum-import-config -- conllu/generated/romans-claude-sonnet-5 2

# Write the SQL only, then apply it (backs up both databases first).
LYCEUM_IMPORT_CONFIG=scripts/lyceum-imports/romans-claude-sonnet-5.json kai run import-lyceum
LYCEUM_IMPORT_CONFIG=scripts/lyceum-imports/romans-claude-sonnet-5.json LYCEUM_IMPORT_APPLY=1 kai run import-lyceum

kai run check-lyceum-reader     # the website's Go tests, in its dev shell
kai run deploy-lyceum-data      # lyceum-staging (demo.lyceum.quest)
LYCEUM_DEPLOY_PRODUCTION=1 kai run deploy-lyceum-data-prod
```

Applying needs the website's full `data/texts.db`, which is not in its Git
repository, and the work and its author must already be in its catalog.
Configs in `scripts/lyceum-imports/` add an `aristos-<model>` edition;
`scripts/lyceum-replace.example.json` instead replaces two existing editions
wholesale. A re-import replaces the passages it names and keeps the rest.
Deploying uses the `lyceum-staging` and `lyceum-prod` SSH hosts.
