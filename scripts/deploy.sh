#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET_HOST=${TARGET_HOST:-lyceum-staging}
REMOTE_DIR=${REMOTE_DIR:-/var/www/aristos}
DEPLOY_STATE=${DEPLOY_STATE:-/var/lib/aristos-deploy}
LYCEUM_SOURCE=${LYCEUM_SOURCE:-/home/blu/src/greek/lyceum/website}

cd "$ROOT"
nix develop --command ./scripts/build-release.sh

# Preserve the existing sites as a deployment guard before changing services.
curl --fail --silent --show-error --head https://conllu.lyceum.quest/ >/dev/null
curl --fail --silent --show-error --head https://demo.lyceum.quest/ >/dev/null

ssh "$TARGET_HOST" "mkdir -p '$REMOTE_DIR' '$DEPLOY_STATE/lyceum-website'"
rsync -az --delete "$ROOT/dist/" "$TARGET_HOST:$REMOTE_DIR/"
rsync -az --delete \
  "$LYCEUM_SOURCE/flake.nix" \
  "$LYCEUM_SOURCE/flake.lock" \
  "$TARGET_HOST:$DEPLOY_STATE/lyceum-website/"
rsync -az "$ROOT/deploy/flake.nix" "$TARGET_HOST:$DEPLOY_STATE/flake.nix"
ssh "$TARGET_HOST" "
  set -e
  chown -R root:root '$REMOTE_DIR' '$DEPLOY_STATE'
  find '$REMOTE_DIR' -type d -exec chmod 755 {} +
  find '$REMOTE_DIR' -type f -exec chmod 644 {} +
  cd '$DEPLOY_STATE'
  nix flake lock
  nixos-rebuild switch --impure --flake 'path:$DEPLOY_STATE#staging'
  systemctl is-active --quiet lyceum lyceum-admin caddy aristos-caddy
  curl --fail --silent --show-error --head http://127.0.0.1:8092/ >/dev/null
"

for attempt in {1..12}; do
  if curl --fail --silent --show-error --head https://aristos.lyceum.quest/ >/dev/null 2>&1; then
    break
  fi
  if [[ "$attempt" == 12 ]]; then
    echo "Aristos HTTPS verification failed" >&2
    exit 1
  fi
  sleep 5
done
curl --fail --silent --show-error --head https://conllu.lyceum.quest/ >/dev/null
curl --fail --silent --show-error --head https://demo.lyceum.quest/ >/dev/null
printf 'Deployed Aristos to https://aristos.lyceum.quest/ via %s:%s\n' "$TARGET_HOST" "$REMOTE_DIR"
