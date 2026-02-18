#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# Entry Offline vendoring fetcher
# - robust: never mkdir /lib... due to WWW bug
# - parallel downloads (MAX_JOBS default 5)
# - continues on 404; prints BIG warnings
# - attempts to pull "as much as possible" of entryjs
############################################

# ----------------------------
# CONFIG (override via env)
# ----------------------------
ROOT="${ROOT:-$(pwd)}"
WWW="${WWW:-$ROOT/www}"
MAX_JOBS="${MAX_JOBS:-5}"          # <= 요구: 병렬 5개
CURL_UA="${CURL_UA:-Mozilla/5.0 (X11; Linux x86_64) entry-apk-fetch/1.0}"
CURL_OPTS=(
  -L --fail --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 120
  -H "User-Agent: $CURL_UA"
)

# Guard: never write to "/" or empty
if [[ -z "$WWW" || "$WWW" == "/" ]]; then
  echo "FATAL: WWW is empty or '/', refusing. (WWW='$WWW')"
  exit 2
fi

# Normalize paths
ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$WWW"

# ----------------------------
# Logging helpers
# ----------------------------
ts() { date +"%H:%M:%S"; }
log() { echo "[$(ts)] $*"; }

bigwarn() {
  echo
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $*"
  echo "████████████████████████████████████████████████████████████"
  echo
}

# ----------------------------
# Job queue (parallel downloads)
# ----------------------------
_jobs=()
job_add() { _jobs+=("$*"); }

job_wait_all() {
  local pids=()
  local cmd
  local running=0

  for cmd in "${_jobs[@]}"; do
    # shellcheck disable=SC2086
    bash -c "$cmd" &
    pids+=("$!")
    running=$((running+1))

    if (( running >= MAX_JOBS )); then
      # wait one
      wait "${pids[0]}" || true
      pids=("${pids[@]:1}")
      running=$((running-1))
    fi
  done

  # wait remain
  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done

  _jobs=()
}

# ----------------------------
# File helpers
# ----------------------------
ensure_dir() { mkdir -p "$(dirname "$1")"; }

# safe write: download to temp then move
curl_to_file() {
  local url="$1"
  local out="$2"
  ensure_dir "$out"
  local tmp="$out.tmp.$$"
  if curl "${CURL_OPTS[@]}" "$url" -o "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$out"
    return 0
  else
    rm -f "$tmp" >/dev/null 2>&1 || true
    return 1
  fi
}

# try multiple URLs (candidates) to one dest
fetch_any() {
  local out="$1"; shift
  local ok=0
  local tried=()
  local url
  for url in "$@"; do
    tried+=("$url")
    if curl_to_file "$url" "$out"; then
      log "OK   -> $out"
      ok=1
      break
    else
      log "MISS $url"
    fi
  done
  if [[ "$ok" -eq 0 ]]; then
    bigwarn "FAIL all candidates -> $out"
    echo "Tried:"
    for url in "${tried[@]}"; do echo " - $url"; done
    echo
    return 1
  fi
  return 0
}

# like fetch_any but never fails build (optional)
fetch_optional() {
  local out="$1"; shift
  if fetch_any "$out" "$@"; then
    return 0
  fi
  bigwarn "OPTIONAL missing: $(basename "$out") (continuing)"
  return 0
}

# ----------------------------
# URL join & extraction helpers
# ----------------------------
# Convert "/path/..." or "./path" or "path" into normalized relative path
norm_rel_path() {
  local p="$1"
  p="${p#\"}"; p="${p%\"}"
  p="${p#\'}"; p="${p%\'}"
  p="${p#./}"
  p="${p#/}"
  # remove query/hash
  p="${p%%\?*}"
  p="${p%%\#*}"
  echo "$p"
}

# Grep candidate asset paths from a file (JS/CSS)
# - extracts: /images/... /media/... /extern/... /module/... /lib/... etc
extract_paths() {
  local file="$1"
  if [[ ! -f "$file" ]]; then return 0; fi

  # CSS url(...)
  grep -Eo 'url\(([^)]+)\)' "$file" 2>/dev/null \
    | sed -E 's/^url\((.*)\)$/\1/' \
    | tr -d '"' | tr -d "'" \
    | sed -E 's/[?#].*$//' \
    | grep -vE '^(data:|https?:|//)' \
    || true

  # JS string literals containing common asset dirs
  grep -Eo '["'\''](/(images|media|extern|module|lib)/[^"'\'']+)["'\'']' "$file" 2>/dev/null \
    | sed -E 's/^["'\''](.*)["'\'']$/\1/' \
    | sed -E 's/[?#].*$//' \
    || true

  # Also catch "./images/.." "./media/.."
  grep -Eo '["'\''](\.?/(images|media|extern|module|lib)/[^"'\'']+)["'\'']' "$file" 2>/dev/null \
    | sed -E 's/^["'\''](.*)["'\'']$/\1/' \
    | sed -E 's/^\.\///' \
    | sed -E 's/[?#].*$//' \
    || true
}

# Download an asset by relative path, trying known base hosts
fetch_rel_asset() {
  local rel="$1"
  local out="$WWW/$rel"

  # Skip dangerous
  [[ -z "$rel" ]] && return 0
  [[ "$rel" == *".."* ]] && return 0

  # already exists
  if [[ -f "$out" ]]; then return 0; fi

  # candidate bases
  # (playentry + pstatic cdn + createjs/cdnjs handled separately above)
  local bases=(
    "https://playentry.org/"
    "https://entry-cdn.pstatic.net/"
  )

  local urls=()
  local b
  for b in "${bases[@]}"; do urls+=("${b}${rel}"); done

  # never fail hard for extracted assets; just warn
  fetch_optional "$out" "${urls[@]}"
}

# parallel fetch many rel assets
fetch_rel_assets_parallel() {
  local list_file="$1"
  [[ ! -f "$list_file" ]] && return 0
  local rel
  while IFS= read -r rel; do
    rel="$(norm_rel_path "$rel")"
    [[ -z "$rel" ]] && continue
    job_add "bash -c 'fetch_rel_asset \"$rel\"'"
  done < "$list_file"
  job_wait_all
}

# Export functions for subshell jobs
export -f ts log bigwarn ensure_dir curl_to_file fetch_any fetch_optional norm_rel_path fetch_rel_asset

# ----------------------------
# Main
# ----------------------------
log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"

# Ensure base dirs
mkdir -p \
  "$WWW/lib" \
  "$WWW/js" \
  "$WWW/bundle" \
  "$WWW/lib/entryjs" \
  "$WWW/lib/entry-tool" \
  "$WWW/lib/entry-paint" \
  "$WWW/lib/module" \
  "$WWW/lib/external" \
  "$WWW/lib/external/sound" \
  "$WWW/lib/react" \
  "$WWW/lib/codemirror" \
  "$WWW/lib/jquery" \
  "$WWW/lib/jquery-ui/ui/minified" \
  "$WWW/lib/lodash/dist" \
  "$WWW/lib/underscore" \
  "$WWW/lib/velocity" \
  "$WWW/lib/PreloadJS/lib" \
  "$WWW/lib/EaselJS/lib" \
  "$WWW/lib/SoundJS/lib"

# ----------------------------
# 1) Core third-party libs
# ----------------------------
log "Downloading 3rd-party libs…"

# lodash 4.17.10
job_add "bash -c 'fetch_any \"$WWW/lib/lodash/dist/lodash.min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js\" \
  \"https://cdn.jsdelivr.net/npm/lodash@4.17.10/lodash.min.js\"'"

# underscore 1.8.3 (sometimes Entry expects underscore semantics; keep both)
job_add "bash -c 'fetch_any \"$WWW/lib/underscore/underscore-min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/underscore.js/1.8.3/underscore-min.js\" \
  \"https://cdn.jsdelivr.net/npm/underscore@1.8.3/underscore-min.js\"'"

# jQuery 1.9.1
job_add "bash -c 'fetch_any \"$WWW/lib/jquery/jquery.min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js\" \
  \"https://cdn.jsdelivr.net/npm/jquery@1.9.1/dist/jquery.min.js\"'"

# jQuery UI 1.10.4 (minified)
job_add "bash -c 'fetch_any \"$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js\" \
  \"https://cdn.jsdelivr.net/npm/jquery-ui@1.10.4/jquery-ui.min.js\"'"

# velocity 1.2.3
job_add "bash -c 'fetch_any \"$WWW/lib/velocity/velocity.min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js\" \
  \"https://cdn.jsdelivr.net/npm/velocity-animate@1.2.3/velocity.min.js\"'"

# CodeMirror (for text coding)
job_add "bash -c 'fetch_any \"$WWW/lib/codemirror/codemirror.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js\" \
  \"https://cdn.jsdelivr.net/npm/codemirror@5.65.16/lib/codemirror.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/codemirror/codemirror.css\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css\" \
  \"https://cdn.jsdelivr.net/npm/codemirror@5.65.16/lib/codemirror.css\"'"

job_add "bash -c 'fetch_optional \"$WWW/lib/codemirror/vim.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js\" \
  \"https://cdn.jsdelivr.net/npm/codemirror@5.65.16/keymap/vim.js\"'"

# React/ReactDOM (sound-editor needs it)
job_add "bash -c 'fetch_any \"$WWW/lib/react/react.production.min.js\" \
  \"https://unpkg.com/react@16.14.0/umd/react.production.min.js\" \
  \"https://cdn.jsdelivr.net/npm/react@16.14.0/umd/react.production.min.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/react/react-dom.production.min.js\" \
  \"https://unpkg.com/react-dom@16.14.0/umd/react-dom.production.min.js\" \
  \"https://cdn.jsdelivr.net/npm/react-dom@16.14.0/umd/react-dom.production.min.js\"'"

# CreateJS (Entry Stage uses createjs)
job_add "bash -c 'fetch_any \"$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js\" \
  \"https://code.createjs.com/preloadjs-0.6.0.min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/PreloadJS/0.6.0/preloadjs-0.6.0.min.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js\" \
  \"https://code.createjs.com/easeljs-0.8.0.min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/EaselJS/0.8.0/easeljs-0.8.0.min.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js\" \
  \"https://code.createjs.com/soundjs-0.6.0.min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/SoundJS/0.6.0/soundjs-0.6.0.min.js\"'"

# flashaudioplugin often removed; keep optional
job_add "bash -c 'fetch_optional \"$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js\" \
  \"https://code.createjs.com/flashaudioplugin-0.6.0.min.js\" \
  \"https://cdnjs.cloudflare.com/ajax/libs/SoundJS/0.6.0/flashaudioplugin-0.6.0.min.js\"'"

job_wait_all

# ----------------------------
# 2) Entry libs from playentry/cdn
# ----------------------------
log "Downloading Entry core libs…"

# EntryJS core (dist + extern)
job_add "bash -c 'fetch_any \"$WWW/lib/entryjs/dist/entry.min.js\" \
  \"https://playentry.org/lib/entry-js/dist/entry.min.js\" \
  \"https://entry-cdn.pstatic.net/lib/entry-js/dist/entry.min.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/entryjs/dist/entry.css\" \
  \"https://playentry.org/lib/entry-js/dist/entry.css\" \
  \"https://entry-cdn.pstatic.net/lib/entry-js/dist/entry.css\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/entryjs/extern/lang/ko.js\" \
  \"https://playentry.org/lib/entry-js/extern/lang/ko.js\" \
  \"https://entry-cdn.pstatic.net/lib/entry-js/extern/lang/ko.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/entryjs/extern/util/static.js\" \
  \"https://playentry.org/lib/entry-js/extern/util/static.js\" \
  \"https://entry-cdn.pstatic.net/lib/entry-js/extern/util/static.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/entryjs/extern/util/handle.js\" \
  \"https://playentry.org/lib/entry-js/extern/util/handle.js\" \
  \"https://entry-cdn.pstatic.net/lib/entry-js/extern/util/handle.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/entryjs/extern/util/bignumber.min.js\" \
  \"https://playentry.org/lib/entry-js/extern/util/bignumber.min.js\" \
  \"https://entry-cdn.pstatic.net/lib/entry-js/extern/util/bignumber.min.js\"'"

# Entry Tool
job_add "bash -c 'fetch_any \"$WWW/lib/entry-tool/dist/entry-tool.js\" \
  \"https://playentry.org/lib/entry-tool/dist/entry-tool.js\" \
  \"https://entry-cdn.pstatic.net/lib/entry-tool/dist/entry-tool.js\"'"

job_add "bash -c 'fetch_any \"$WWW/lib/entry-tool/dist/entry-tool.css\" \
  \"https://playentry.org/lib/entry-tool/dist/entry-tool.css\" \
  \"https://entry-cdn.pstatic.net/lib/entry-tool/dist/entry-tool.css\"'"

# Entry Paint
job_add "bash -c 'fetch_any \"$WWW/lib/entry-paint/dist/static/js/entry-paint.js\" \
  \"https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js\" \
  \"https://entry-cdn.pstatic.net/lib/entry-paint/dist/static/js/entry-paint.js\"'"

# WS locales
job_add "bash -c 'fetch_any \"$WWW/js/ws/locales.js\" \
  \"https://playentry.org/js/ws/locales.js\" \
  \"https://entry-cdn.pstatic.net/js/ws/locales.js\"'"

# legacy-video module (required by some entry builds)
job_add "bash -c 'fetch_any \"$WWW/lib/module/legacy-video/index.js\" \
  \"https://entry-cdn.pstatic.net/module/legacy-video/index.js\" \
  \"https://playentry.org/module/legacy-video/index.js\"'"

# sound-editor (optional but entry may reference)
job_add "bash -c 'fetch_optional \"$WWW/lib/external/sound/sound-editor.js\" \
  \"https://playentry.org/lib/external/sound/sound-editor.js\" \
  \"https://entry-cdn.pstatic.net/lib/external/sound/sound-editor.js\" \
  \"https://entry-cdn.pstatic.net/external/sound/sound-editor.js\"'"

job_wait_all

# Convenience alias dir: /lib/entry-js <-> /lib/entryjs (some builds differ)
rm -rf "$WWW/lib/entry-js" >/dev/null 2>&1 || true
cp -R "$WWW/lib/entryjs" "$WWW/lib/entry-js" >/dev/null 2>&1 || true

# ----------------------------
# 3) Extract & fetch referenced assets (images/audio/etc)
# ----------------------------
log "Scanning JS/CSS for additional assets…"

TMPDIR="$ROOT/.fetch_tmp"
mkdir -p "$TMPDIR"

assets_list="$TMPDIR/assets.txt"
: > "$assets_list"

# Add paths found in these key files
for f in \
  "$WWW/lib/entryjs/dist/entry.css" \
  "$WWW/lib/entry-tool/dist/entry-tool.css" \
  "$WWW/lib/entryjs/dist/entry.min.js" \
  "$WWW/lib/entry-paint/dist/static/js/entry-paint.js" \
  "$WWW/lib/entryjs/extern/util/static.js" \
  "$WWW/lib/external/sound/sound-editor.js"
do
  extract_paths "$f" >> "$assets_list" || true
done

# Normalize, unique
sort -u "$assets_list" | sed '/^\s*$/d' > "$assets_list.uniq"
mv -f "$assets_list.uniq" "$assets_list"

# Filter only relative-ish resources (we will fetch from playentry/cdn)
# Convert to rel
rel_list="$TMPDIR/rel_assets.txt"
: > "$rel_list"
while IFS= read -r p; do
  p="$(norm_rel_path "$p")"
  [[ -z "$p" ]] && continue
  # skip js/css already fetched (ok to keep but reduces noise)
  echo "$p" >> "$rel_list"
done < "$assets_list"
sort -u "$rel_list" -o "$rel_list"

log "Found $(wc -l < "$rel_list" | tr -d ' ') asset path(s) from static scan."

# Fetch in parallel (optional style; never fails build)
fetch_rel_assets_parallel "$rel_list"

# ----------------------------
# 4) Aggressive: also fetch whole entryjs images/media/extern if referenced
# ----------------------------
# We ensure common directories exist even if empty.
mkdir -p \
  "$WWW/lib/entryjs/images" \
  "$WWW/lib/entryjs/media" \
  "$WWW/lib/entryjs/extern" \
  "$WWW/lib/entryjs/dist" \
  "$WWW/lib/entryjs/assets" \
  "$WWW/lib/entryjs/src" \
  "$WWW/lib/entryjs/sounds" \
  "$WWW/lib/entryjs/audio"

# Try a few known common entry asset roots (best-effort)
# NOTE: these may 404 depending on current Entry CDN layout; optional only.
known_roots=(
  "lib/entry-js/images"
  "lib/entry-js/media"
  "lib/entry-js/extern/images"
  "lib/entry-js/extern/media"
  "lib/entry-js/dist/images"
  "lib/entry-js/dist/media"
  "lib/entry-tool/dist/images"
  "lib/entry-tool/dist/media"
  "lib/entry-paint/dist/static/media"
  "lib/entry-paint/dist/static/img"
)

# We cannot list directories; but we can try common filenames from CSS scan.
# Additionally, if the app still shows missing images, those paths will appear in DevTools
# and you can add them into a text file to fetch here later.

# ----------------------------
# 5) Summary (never hard fail)
# ----------------------------
missing=0

# Critical checks
crit_files=(
  "$WWW/lib/lodash/dist/lodash.min.js"
  "$WWW/lib/jquery/jquery.min.js"
  "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js"
  "$WWW/lib/entryjs/dist/entry.min.js"
  "$WWW/lib/entryjs/dist/entry.css"
  "$WWW/lib/entry-tool/dist/entry-tool.js"
  "$WWW/lib/entry-tool/dist/entry-tool.css"
)

for f in "${crit_files[@]}"; do
  if [[ ! -s "$f" ]]; then
    bigwarn "CRITICAL missing: $f"
    missing=$((missing+1))
  fi
done

if (( missing > 0 )); then
  bigwarn "FETCH SUMMARY: $missing critical file(s) missing (but script will exit 0 to continue workflow)"
else
  log "✅ FETCH SUMMARY: critical files OK"
fi

log "fetch exit=0"
exit 0
