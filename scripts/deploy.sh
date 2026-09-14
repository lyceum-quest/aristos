#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET_HOST=${TARGET_HOST:-lyceum-staging}
REMOTE_DIR=${REMOTE_DIR:-/var/www/aristos}

cd "$ROOT"
test -f "$ROOT/dist/preload/corpora.json"

# Do not update Aristos if either neighboring site is already unhealthy.
curl --fail --silent --show-error --head https://conllu.lyceum.quest/ >/dev/null
curl --fail --silent --show-error --head https://demo.lyceum.quest/ >/dev/null

ssh "$TARGET_HOST" "mkdir -p '$REMOTE_DIR'"
rsync -az --delete "$ROOT/dist/" "$TARGET_HOST:$REMOTE_DIR/"
ssh "$TARGET_HOST" "
  set -e
  chown -R root:root '$REMOTE_DIR'
  find '$REMOTE_DIR' -type d -exec chmod 755 {} +
  find '$REMOTE_DIR' -type f -exec chmod 644 {} +
  curl --fail --silent --show-error http://127.0.0.1:8092/ | grep -q 'corpus-preload.js'
  curl --fail --silent --show-error http://127.0.0.1:8092/elm.js | grep -c 'Elm.Main' >/dev/null
  curl --fail --silent --show-error http://127.0.0.1:8092/corpus-preload.js | grep -c 'AristosPreload' >/dev/null
  curl --fail --silent --show-error http://127.0.0.1:8092/preload/corpora.json | grep -q 'anabasis'
  curl --fail --silent --show-error http://127.0.0.1:8092/preload/corpora/anabasis.conllu | grep -q 'sentence_id'
"

for attempt in {1..12}; do
  if curl --fail --silent --show-error https://aristos.lyceum.quest/preload/corpora.json 2>/dev/null | grep -q 'anabasis'; then
    break
  fi
  if [[ "$attempt" == 12 ]]; then
    echo "Aristos HTTPS verification failed" >&2
    exit 1
  fi
  sleep 5
done
curl --fail --silent --show-error https://aristos.lyceum.quest/ | grep -q 'corpus-preload.js'
curl --fail --silent --show-error https://aristos.lyceum.quest/elm.js | grep -c 'Elm.Main' >/dev/null
curl --fail --silent --show-error https://aristos.lyceum.quest/corpus-preload.js | grep -c 'AristosPreload' >/dev/null
curl --fail --silent --show-error --head https://conllu.lyceum.quest/ >/dev/null
curl --fail --silent --show-error --head https://demo.lyceum.quest/ >/dev/null
printf 'Deployed Aristos to https://aristos.lyceum.quest/ via %s:%s\n' "$TARGET_HOST" "$REMOTE_DIR"
