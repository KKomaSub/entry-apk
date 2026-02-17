#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"
LIB="$WWW/lib"
JS="$WWW/js"

mkdir -p "$WWW" "$LIB" "$JS"

MAX_JOBS="${MAX_JOBS:-6}"

FAIL_LOG="$WWW/.fetch_failed.txt"
: > "$FAIL_LOG"

big() {
  echo ""
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $1"
  echo "████████████████████████████████████████████████████████████"
  echo ""
}
log() { echo "[$(date +%H:%M:%S)] $*"; }

curl_get() {
  local url="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  curl -L --compressed --retry 3 --retry-delay 1 --fail -o "$out" "$url"
}

fetch_one() {
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
  big "FAIL -> $out"
  echo "Tried:"; for url in "$@"; do echo " - $url"; done
  echo ""
  return 0
}

fetch_optional() {
  local out="$1"; shift
  fetch_one "$out" "$@" || true
  # optional은 fail 목록에서 제거
  if [ -f "$FAIL_LOG" ]; then
    grep -vxF "$out" "$FAIL_LOG" > "$FAIL_LOG.tmp" 2>/dev/null || true
    mv -f "$FAIL_LOG.tmp" "$FAIL_LOG" 2>/dev/null || true
  fi
  return 0
}

run_bg() {
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
log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"
echo ""

# 0) underscore (Entry에서 _ 로 필수)
mkdir -p "$LIB/underscore"
run_bg "$LIB/underscore/underscore-min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/underscore.js/1.8.3/underscore-min.js"

# 1) lodash (entry-tool/paint쪽에서 많이 씀)
mkdir -p "$LIB/lodash/dist"
run_bg "$LIB/lodash/dist/lodash.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.21/lodash.min.js"

# 2) CodeMirror
mkdir -p "$LIB/codemirror"
run_bg "$LIB/codemirror/codemirror.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js"
run_bg "$LIB/codemirror/codemirror.css" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css"
run_bg "$LIB/codemirror/vim.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js"

# 3) jQuery / jQuery UI
mkdir -p "$LIB/jquery" "$LIB/jquery-ui/ui/minified"
run_bg "$LIB/jquery/jquery.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js"
run_bg "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js"

# 4) CreateJS (Entry가 기대하는 구버전 라인)
mkdir -p "$LIB/PreloadJS/lib" "$LIB/EaselJS/lib" "$LIB/SoundJS/lib"
run_bg "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "https://code.createjs.com/preloadjs-0.6.0.min.js"
run_bg "$LIB/EaselJS/lib/easeljs-0.8.0.min.js" \
  "https://code.createjs.com/easeljs-0.8.0.min.js"
run_bg "$LIB/SoundJS/lib/soundjs-0.6.0.min.js" \
  "https://code.createjs.com/soundjs-0.6.0.min.js"
fetch_optional "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" &

# 5) EntryJS / Tool / Paint (playentry에서 가져오기)
mkdir -p "$LIB/entryjs/dist" "$LIB/entryjs/extern/lang" "$LIB/entryjs/extern/util"
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

mkdir -p "$LIB/entry-tool/dist" "$LIB/entry-paint/dist/static/js"
run_bg "$LIB/entry-tool/dist/entry-tool.js"  "https://playentry.org/lib/entry-tool/dist/entry-tool.js"
run_bg "$LIB/entry-tool/dist/entry-tool.css" "https://playentry.org/lib/entry-tool/dist/entry-tool.css"
run_bg "$LIB/entry-paint/dist/static/js/entry-paint.js" "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js"

wait_all

# summary
if [ -s "$FAIL_LOG" ]; then
  COUNT="$(sort -u "$FAIL_LOG" | wc -l | tr -d ' ')"
  big "FETCH SUMMARY: $COUNT file(s) missing (script continued)"
  sort -u "$FAIL_LOG" | sed 's/^/ - /'
else
  log "✅ FETCH SUMMARY: all downloads OK"
fi

exit 0
