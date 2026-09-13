#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET_HOST=${TARGET_HOST:-lyceum-staging}
REMOTE_DIR=${REMOTE_DIR:-/var/www/aristos}

cd "$ROOT"
nix develop --command ./scripts/build-release.sh

ssh "$TARGET_HOST" "mkdir -p '$REMOTE_DIR'"
rsync -az --delete "$ROOT/dist/" "$TARGET_HOST:$REMOTE_DIR/"
ssh "$TARGET_HOST" "chown -R root:root '$REMOTE_DIR' && find '$REMOTE_DIR' -type d -exec chmod 755 {} + && find '$REMOTE_DIR' -type f -exec chmod 644 {} +"

nixos-rebuild switch --flake "$ROOT#staging" --target-host "$TARGET_HOST"

curl --fail --silent --show-error --head https://aristos.lyceum.quest/ >/dev/null
printf 'Deployed Aristos to https://aristos.lyceum.quest/ via %s:%s\n' "$TARGET_HOST" "$REMOTE_DIR"
