#!/usr/bin/env bash
# Entry Offline assets vendoring script (robust)
# - Parallel downloads
# - Never hard-fail on missing files (prints BIG warnings)
# - Ensures images/media for Entry/Tool/Paint via NPM fallback extract
# - Scans CSS url(...) for missing relative assets and fetches them
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"
LIB="$WWW/lib"
JS="$WWW/js"

mkdir -p "$WWW" "$LIB" "$JS"

MAX_JOBS="${MAX_JOBS:-6}"
FAIL_LOG="$WWW/.fetch_failed.txt"
: > "$FAIL_LOG"

# ─────────────────────────────────────────────────────────────
# Logging helpers
# ─────────────────────────────────────────────────────────────
big() {
  echo ""
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $1"
  echo "████████████████████████████████████████████████████████████"
  echo ""
}
log() { echo "[$(date +%H:%M:%S)] $*"; }

# ─────────────────────────────────────────────────────────────
# Download helpers
# ─────────────────────────────────────────────────────────────
curl_get() {
  local url="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  # --fail makes curl exit non-zero on 4xx/5xx
  curl -L --compressed --retry 3 --retry-delay 1 --fail -o "$out" "$url"
}

fetch_one() {
  # fetch_one OUT URL1 URL2 ...
  local out="$1"; shift
  mkdir -p "$(dirname "$out")"

  local url
  for url in "$@"; do
    log "GET  $url"
    if curl_get "$url" "$out" >/dev/null 2>&1; then
      log "OK   -> $out"
      return 0
    fi
    log "MISS $url"
  done

  echo "$out" >> "$FAIL_LOG"
  big "FAIL all candidates -> $out"
  echo "Tried:"
  for url in "$@"; do echo " - $url"; done
  echo ""
  return 0  # IMPORTANT: never fail the script
}

fetch_optional() {
  # same as fetch_one but never counts as missing
  local out="$1"; shift
  fetch_one "$out" "$@" || true
  # remove from fail log if present
  if [ -f "$FAIL_LOG" ]; then
    grep -vxF "$out" "$FAIL_LOG" > "$FAIL_LOG.tmp" 2>/dev/null || true
    mv -f "$FAIL_LOG.tmp" "$FAIL_LOG" 2>/dev/null || true
  fi
  return 0
}

run_bg() {
  # run_bg OUT URL...
  fetch_one "$@" &
  while true; do
    local n
    n="$(jobs -rp | wc -l | tr -d ' ')"
    [ "$n" -lt "$MAX_JOBS" ] && break
    sleep 0.1
  done
}

wait_all() {
  while true; do
    local pids
    pids="$(jobs -pr)"
    [ -z "$pids" ] && break
    wait $pids 2>/dev/null || true
    sleep 0.05
  done
}

# ─────────────────────────────────────────────────────────────
# NPM fallback extract helpers (for images/media completeness)
# ─────────────────────────────────────────────────────────────
npm_extract_to() {
  # npm_extract_to PKG OUTDIR
  local pkg="$1"
  local outDir="$2"
  mkdir -p "$outDir"
  log "NPM EXTRACT: $pkg -> $outDir"

  local tgz
  tgz="$(npm pack "$pkg" 2>/dev/null | tail -n 1)" || true
  if [ -z "${tgz:-}" ] || [ ! -f "$tgz" ]; then
    big "npm pack failed: $pkg"
    return 0
  fi

  rm -rf "$outDir/.tmp_pkg" >/dev/null 2>&1 || true
  mkdir -p "$outDir/.tmp_pkg"
  tar -xzf "$tgz" -C "$outDir/.tmp_pkg" >/dev/null 2>&1 || true
  rm -f "$tgz" >/dev/null 2>&1 || true

  if [ -d "$outDir/.tmp_pkg/package" ]; then
    cp -R "$outDir/.tmp_pkg/package/"* "$outDir/" 2>/dev/null || true
  fi
  rm -rf "$outDir/.tmp_pkg" >/dev/null 2>&1 || true
  return 0
}

copy_if_exists() {
  local src="$1"
  local dst="$2"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst" >/dev/null 2>&1 || true
    cp -R "$src" "$dst" 2>/dev/null || true
    log "COPY OK: $src -> $dst"
  fi
}

# ─────────────────────────────────────────────────────────────
# CSS url(...) scan & download missing relative assets
# ─────────────────────────────────────────────────────────────
extract_css_urls() {
  local css="$1"
  # url("...") / url('...') / url(...)
  sed -nE 's/.*url\(([^)]+)\).*/\1/p' "$css" 2>/dev/null \
    | sed -E 's/^["'\'']|["'\'']$//g' \
    | grep -vE '^(data:|https?:|//)' \
    | sed -E 's/#.*$//g' \
    | sed -E 's/\?.*$//g' \
    | awk 'NF' \
    | sort -u
}

normpath_py() {
  python3 - <<'PY' 2>/dev/null || true
import os,sys
p=sys.stdin.read().strip()
print(os.path.normpath(p))
PY
}

download_relative_to_css() {
  local css="$1"
  local baseDir
  baseDir="$(cd "$(dirname "$css")" && pwd)"

  while read -r rel; do
    [ -z "$rel" ] && continue
    local target="$baseDir/$rel"

    # already exists
    [ -f "$target" ] && continue

    # convert to web path (relative to WWW)
    local webPath="${target#$WWW/}"
    webPath="$(printf "%s" "$webPath" | normpath_py)"
    # if still empty, skip
    [ -z "${webPath:-}" ] && continue

    # download candidates
    run_bg "$target" \
      "https://playentry.org/$webPath" \
      "https://entry-cdn.pstatic.net/$webPath"
  done < <(extract_css_urls "$css")
}

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────
log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"
echo ""

# (A) Core JS libraries expected by Entry ecosystem
mkdir -p "$LIB/underscore" "$LIB/lodash/dist" "$LIB/codemirror" "$LIB/jquery" "$LIB/jquery-ui/ui/minified"

run_bg "$LIB/underscore/underscore-min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/underscore.js/1.8.3/underscore-min.js"

run_bg "$LIB/lodash/dist/lodash.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.21/lodash.min.js"

run_bg "$LIB/codemirror/codemirror.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js"
run_bg "$LIB/codemirror/codemirror.css" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css"
run_bg "$LIB/codemirror/vim.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js"

run_bg "$LIB/jquery/jquery.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js"

run_bg "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js"

# (B) CreateJS (Entry Stage depends on createjs globals)
mkdir -p "$LIB/PreloadJS/lib" "$LIB/EaselJS/lib" "$LIB/SoundJS/lib"

run_bg "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "https://code.createjs.com/preloadjs-0.6.0.min.js"

run_bg "$LIB/EaselJS/lib/easeljs-0.8.0.min.js" \
  "https://code.createjs.com/easeljs-0.8.0.min.js"

run_bg "$LIB/SoundJS/lib/soundjs-0.6.0.min.js" \
  "https://code.createjs.com/soundjs-0.6.0.min.js"

# FlashAudioPlugin is optional (HTML5 audio works without it)
fetch_optional "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" &

# (C) EntryJS / entry-tool / entry-paint from playentry
mkdir -p "$LIB/entryjs/dist" "$LIB/entryjs/extern/lang" "$LIB/entryjs/extern/util"
mkdir -p "$LIB/entry-tool/dist" "$LIB/entry-paint/dist/static/js"

# IMPORTANT: keep both candidate paths (some environments use entry-js, some entryjs)
run_bg "$LIB/entryjs/dist/entry.min.js" \
  "https://playentry.org/lib/entry-js/dist/entry.min.js" \
  "https://playentry.org/lib/entryjs/dist/entry.min.js"

run_bg "$LIB/entryjs/dist/entry.css" \
  "https://playentry.org/lib/entry-js/dist/entry.css" \
  "https://playentry.org/lib/entryjs/dist/entry.css"

run_bg "$LIB/entryjs/extern/lang/ko.js" \
  "https://playentry.org/lib/entry-js/extern/lang/ko.js" \
  "https://playentry.org/lib/entryjs/extern/lang/ko.js"

run_bg "$LIB/entryjs/extern/util/static.js" \
  "https://playentry.org/lib/entry-js/extern/util/static.js" \
  "https://playentry.org/lib/entryjs/extern/util/static.js"

run_bg "$LIB/entryjs/extern/util/handle.js" \
  "https://playentry.org/lib/entry-js/extern/util/handle.js" \
  "https://playentry.org/lib/entryjs/extern/util/handle.js"

run_bg "$LIB/entryjs/extern/util/bignumber.min.js" \
  "https://playentry.org/lib/entry-js/extern/util/bignumber.min.js" \
  "https://playentry.org/lib/entryjs/extern/util/bignumber.min.js"

run_bg "$LIB/entry-tool/dist/entry-tool.js"  "https://playentry.org/lib/entry-tool/dist/entry-tool.js"
run_bg "$LIB/entry-tool/dist/entry-tool.css" "https://playentry.org/lib/entry-tool/dist/entry-tool.css"

run_bg "$LIB/entry-paint/dist/static/js/entry-paint.js" "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js"

wait_all

# (D) Optional ws locales file (not required to run)
mkdir -p "$JS/ws"
fetch_optional "$JS/ws/locales.js" \
  "https://playentry.org/js/ws/locales.js" \
  "https://entry-cdn.pstatic.net/js/ws/locales.js"

# ─────────────────────────────────────────────────────────────
# [IMG FIX] Ensure images/media are present for UI (blocks/icons/object add)
# - safest: extract npm packages and copy resource folders into www/lib/*
# - also parse css files for url(...) and download missing relative files
# ─────────────────────────────────────────────────────────────
big "NPM FALLBACK: extracting packages to ensure images/media exist"

npm_extract_to "@entrylabs/entry"      "$WWW/.npm_entry_pkg"
npm_extract_to "@entrylabs/entry-tool" "$WWW/.npm_entry_tool_pkg"
npm_extract_to "@entrylabs/entry-paint" "$WWW/.npm_entry_paint_pkg"

# Make sure lib/entryjs contains resource folders
mkdir -p "$LIB/entryjs"

# Copy candidate resource folders if found
for cand in \
  "$WWW/.npm_entry_pkg/images" \
  "$WWW/.npm_entry_pkg/media" \
  "$WWW/.npm_entry_pkg/static" \
  "$WWW/.npm_entry_pkg/dist/images" \
  "$WWW/.npm_entry_pkg/dist/media" \
  "$WWW/.npm_entry_pkg/dist/static" \
  "$WWW/.npm_entry_pkg/lib/images" \
  "$WWW/.npm_entry_pkg/lib/media" \
  "$WWW/.npm_entry_pkg/lib/static" \
  "$WWW/.npm_entry_pkg/entryjs/images" \
  "$WWW/.npm_entry_pkg/entryjs/media" \
  "$WWW/.npm_entry_pkg/entryjs/static" \
  "$WWW/.npm_entry_pkg/extern" \
  "$WWW/.npm_entry_pkg/extern/images" \
  "$WWW/.npm_entry_pkg/extern/media"
do
  if [ -d "$cand" ]; then
    base="$(basename "$cand")"
    # If cand is ".../extern", keep name extern
    copy_if_exists "$cand" "$LIB/entryjs/$base"
  fi
done

# Ensure entry-tool and entry-paint dist folders include their assets too
if [ -d "$WWW/.npm_entry_tool_pkg/dist" ]; then
  mkdir -p "$LIB/entry-tool"
  copy_if_exists "$WWW/.npm_entry_tool_pkg/dist" "$LIB/entry-tool/dist"
fi

if [ -d "$WWW/.npm_entry_paint_pkg/dist" ]; then
  mkdir -p "$LIB/entry-paint"
  copy_if_exists "$WWW/.npm_entry_paint_pkg/dist" "$LIB/entry-paint/dist"
fi

# Cleanup temp extracted packages
rm -rf "$WWW/.npm_entry_pkg" "$WWW/.npm_entry_tool_pkg" "$WWW/.npm_entry_paint_pkg" >/dev/null 2>&1 || true

# (E) CSS url(...) scan – download missing relative assets referenced by css
big "CSS url(...) asset scan (download missing relative files)"
for css in \
  "$LIB/entryjs/dist/entry.css" \
  "$LIB/entry-tool/dist/entry-tool.css" \
  "$LIB/codemirror/codemirror.css"
do
  if [ -f "$css" ]; then
    download_relative_to_css "$css"
  fi
done
wait_all

# (F) Alias directories (some code expects entry-js path)
# Your index.html uses ./lib/entryjs; some third-party expects entry-js.
# Create aliases both ways if needed.
if [ -d "$LIB/entryjs" ] && [ ! -d "$LIB/entry-js" ]; then
  copy_if_exists "$LIB/entryjs" "$LIB/entry-js"
fi
if [ -d "$LIB/entry-js" ] && [ ! -d "$LIB/entryjs" ]; then
  copy_if_exists "$LIB/entry-js" "$LIB/entryjs"
fi

# ─────────────────────────────────────────────────────────────
# SUMMARY (never exit non-zero)
# ─────────────────────────────────────────────────────────────
if [ -s "$FAIL_LOG" ]; then
  COUNT="$(sort -u "$FAIL_LOG" | wc -l | tr -d ' ')"
  big "FETCH SUMMARY: $COUNT file(s) may be missing (script continued)"
  sort -u "$FAIL_LOG" | sed 's/^/ - /'
else
  log "✅ FETCH SUMMARY: all downloads OK"
fi

exit 0
