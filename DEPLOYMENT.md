# Aristos deployment

Production preview: <https://aristos.lyceum.quest>

Aristos is deployed to the same NixOS host as `conllu.lyceum.quest`, but its
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

```sh
./scripts/deploy.sh
```

Defaults:

```text
TARGET_HOST=lyceum-staging
REMOTE_DIR=/var/www/aristos
```

The script builds an optimized Elm release, synchronizes the static bundle,
applies the declarative NixOS module, and verifies Aristos plus the existing
Conllu and Lyceum endpoints.

The host configuration is assembled in `/var/lib/aristos-deploy` from
`deploy/flake.nix` and the local Lyceum checkout. It explicitly preserves the
currently deployed Lyceum reader/admin packages and all existing Caddy routes;
this is necessary because the sibling open-source checkout no longer declares
the private admin service or the independently deployed Conllu route. Override
`LYCEUM_SOURCE` if that checkout moves.
