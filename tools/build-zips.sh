#!/usr/bin/env bash
# Build the distributable zips from this repository.
#
#   bash tools/build-zips.sh            # all of them
#   bash tools/build-zips.sh all        # just ascend-all
#   bash tools/build-zips.sh hazel      # just ascend-hazel
#
# Output lands in dist/ (git-ignored). These zips are only for people who
# cannot use git; a clone plus ./install.sh is the supported path.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"; mkdir -p "$OUT"

EXCL=(--exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store'
      --exclude '*.bak' --exclude '*.orig' --exclude 'dist' --exclude '.git')

leak_check(){
  local hits
  hits="$(grep -rIl 'pliu1\|jpliu\|152\.7\.179\|10\.68\.40' "$1" 2>/dev/null \
          | grep -vE 'README|INSTALL|AGENTS|LICENSE|bin/ascend-' || true)"
  if [ -n "$hits" ]; then echo "WARNING: personal identifier in:" >&2; echo "$hits" >&2; fi
  return 0
}

build_all(){
  local TMP STAGE; TMP="$(mktemp -d)"; STAGE="$TMP/ascend-all"
  mkdir -p "$STAGE"
  for d in common hazel ncshare hurricane; do
    rsync -a "${EXCL[@]}" "$ROOT/$d/" "$STAGE/$d/"
  done
  cp "$ROOT/setup.sh" "$ROOT/install.sh" "$ROOT/README.md" "$ROOT/LICENSE" "$STAGE/"
  cp "$ROOT/docs/INSTALL-ascend-all.txt" "$STAGE/INSTALL-GUIDE.txt"
  mkdir -p "$STAGE/docs"; cp -R "$ROOT/docs/images" "$STAGE/docs/images"
  leak_check "$STAGE"
  ( cd "$TMP" && zip -qr ascend-all.zip ascend-all )
  cp "$TMP/ascend-all.zip" "$OUT/"; echo "built: $OUT/ascend-all.zip"
  rm -rf "$TMP"
}

build_site(){
  local site="$1" TMP STAGE; TMP="$(mktemp -d)"; STAGE="$TMP/ascend-$site"
  mkdir -p "$STAGE"
  rsync -a "${EXCL[@]}" "$ROOT/common/" "$STAGE/common/"
  rsync -a "${EXCL[@]}" "$ROOT/$site/" "$STAGE/$site/"
  cp "$ROOT/install.sh" "$ROOT/setup.sh" "$ROOT/README.md" "$ROOT/LICENSE" "$STAGE/"
  if [ -f "$ROOT/docs/INSTALL-ascend-$site.txt" ]; then
    cp "$ROOT/docs/INSTALL-ascend-$site.txt" "$STAGE/INSTALL-GUIDE.txt"
  fi
  mkdir -p "$STAGE/docs"; cp -R "$ROOT/docs/images" "$STAGE/docs/images"
  leak_check "$STAGE"
  ( cd "$TMP" && zip -qr "ascend-$site.zip" "ascend-$site" )
  cp "$TMP/ascend-$site.zip" "$OUT/"; echo "built: $OUT/ascend-$site.zip"
  rm -rf "$TMP"
}

case "${1:-everything}" in
  all)                      build_all ;;
  hazel|ncshare|hurricane)  build_site "$1" ;;
  everything)               build_all; for s in hazel ncshare hurricane; do build_site "$s"; done ;;
  *) echo "usage: $0 [all|hazel|ncshare|hurricane]" >&2; exit 1 ;;
esac
du -h "$OUT"/*.zip 2>/dev/null || true
