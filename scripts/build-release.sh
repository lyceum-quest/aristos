#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ELM=${ELM:-$(command -v elm || true)}
DIST="$ROOT/dist"

if [[ -z "$ELM" || ! -x "$ELM" ]]; then
  echo "Elm is not available; run through 'nix develop --command' or set ELM" >&2
  exit 1
fi
if [[ "$($ELM --version)" != "0.19.2" ]]; then
  echo "Aristos requires Elm 0.19.2; found $($ELM --version)" >&2
  exit 1
fi

cd "$ROOT"
rm -rf "$DIST"
mkdir -p "$DIST/conllu/xenophon/anabasis"

roc "$ROOT/scripts/import-lyceum-anabasis.roc"
"$ELM" make "$ROOT/src/Main.elm" --optimize --output="$DIST/elm.js"
cp "$ROOT/index.html" "$ROOT/styles.css" "$ROOT/anabasis-data.js" "$DIST/"
cp "$ROOT/conllu/xenophon/anabasis/book-01-first-sentence.tb.conllu" "$DIST/conllu/xenophon/anabasis/"

printf 'Built %s (%s)\n' "$DIST" "$(du -sh "$DIST" | cut -f1)"
