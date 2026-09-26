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

Run the Kai workflow:

```sh
kai workflow deploy
```

Defaults:

```text
TARGET_HOST=lyceum-staging
REMOTE_DIR=/var/www/aristos
```

The workflow builds an optimized Elm release, synchronizes the static bundle,
and verifies Aristos plus the existing Conllu and Lyceum endpoints. Pushes no
longer trigger it: the CI workflow was removed while that host is down.

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
routes. Override `LYCEUM_SOURCE` if that checkout moves.
