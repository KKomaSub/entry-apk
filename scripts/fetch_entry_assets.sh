#!/usr/bin/env bash
set -u  # -e 제거(중간 실패로 전체 중단 방지)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"
LIB="$WWW/lib"
JS="$WWW/js"

mkdir -p "$LIB" "$JS"

MAX_JOBS="${MAX_JOBS:-8}"

P1="https://playentry.org"
P2="https://entry-cdn.pstatic.net"
GH_RAW="https://raw.githubusercontent.com"
ENTRYJS_REF="${ENTRYJS_REF:-develop}"

FAIL_LOG="$WWW/.fetch_failed.txt"
: > "$FAIL_LOG"

log_big() {
  echo ""
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $1"
  echo "████████████████████████████████████████████████████████████"
  echo ""
}

fetch_one() {
  local out="$1"; shift
  mkdir -p "$(dirname "$out")"

  for url in "$@"; do
    echo "[FETCH] $url"
    if curl -L --retry 3 --retry-delay 1 --fail -o "$out" "$url"; then
      echo "[OK]   -> $out"
      return 0
    fi
    echo "[MISS] $url"
  done

  echo "$out" >> "$FAIL_LOG"
  log_big "FETCH FAILED: $out"
  echo "Tried:"
  for url in "$@"; do echo " - $url"; done
  echo ""
  return 0
}

# 병렬 실행 (MAX_JOBS 제한)
run_bg() {
  fetch_one "$@" &
  while [ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$MAX_JOBS" ]; do
    sleep 0.2
  done
}

wait_all() {
  # wait -n 없이 “모든 job이 끝날 때까지” 대기
  local pids
  while true; do
    pids="$(jobs -pr)"
    [ -z "$pids" ] && break
    # 하나라도 끝나면 다음 루프로
    wait $pids 2>/dev/null || true
    sleep 0.1
  done
}

echo "=== Fetch Entry assets (offline vendoring, parallel) ==="
echo "ROOT=$ROOT"
echo "WWW=$WWW"
echo "MAX_JOBS=$MAX_JOBS"
echo "ENTRYJS_REF=$ENTRYJS_REF"
echo ""

# --- Entry core/tool/paint ---
run_bg "$LIB/entry-js/dist/entry.min.js" \
  "$P1/lib/entry-js/dist/entry.min.js" \
  "$P2/lib/entry-js/dist/entry.min.js"

run_bg "$LIB/entry-js/dist/entry.css" \
  "$P1/lib/entry-js/dist/entry.css" \
  "$P2/lib/entry-js/dist/entry.css"

run_bg "$LIB/entry-js/extern/lang/ko.js" \
  "$P1/lib/entry-js/extern/lang/ko.js" \
  "$P2/lib/entry-js/extern/lang/ko.js"

run_bg "$LIB/entry-js/extern/util/static.js" \
  "$P1/lib/entry-js/extern/util/static.js" \
  "$P2/lib/entry-js/extern/util/static.js"

run_bg "$LIB/entry-tool/dist/entry-tool.js" \
  "$P1/lib/entry-tool/dist/entry-tool.js" \
  "$P2/lib/entry-tool/dist/entry-tool.js"

run_bg "$LIB/entry-tool/dist/entry-tool.css" \
  "$P1/lib/entry-tool/dist/entry-tool.css" \
  "$P2/lib/entry-tool/dist/entry-tool.css"

run_bg "$LIB/entry-paint/dist/static/js/entry-paint.js" \
  "$P1/lib/entry-paint/dist/static/js/entry-paint.js" \
  "$P2/lib/entry-paint/dist/static/js/entry-paint.js"

# --- Common libs ---
run_bg "$LIB/lodash/dist/lodash.min.js" \
  "$P1/lib/lodash/dist/lodash.min.js" \
  "$P2/lib/lodash/dist/lodash.min.js"

run_bg "$LIB/jquery/jquery.min.js" \
  "$P1/lib/jquery/jquery.min.js" \
  "$P2/lib/jquery/jquery.min.js"

run_bg "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P1/lib/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P2/lib/jquery-ui/ui/minified/jquery-ui.min.js"

run_bg "$LIB/velocity/velocity.min.js" \
  "$P1/lib/velocity/velocity.min.js" \
  "$P2/lib/velocity/velocity.min.js"

# CreateJS
run_bg "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "$P1/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "$P2/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"

run_bg "$LIB/EaselJS/lib/easeljs-0.8.0.min.js" \
  "$P1/lib/EaselJS/lib/easeljs-0.8.0.min.js" \
  "$P2/lib/EaselJS/lib/easeljs-0.8.0.min.js"

run_bg "$LIB/SoundJS/lib/soundjs-0.6.0.min.js" \
  "$P1/lib/SoundJS/lib/soundjs-0.6.0.min.js" \
  "$P2/lib/SoundJS/lib/soundjs-0.6.0.min.js"

run_bg "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "$P1/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "$P2/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js"

# CodeMirror minimal
run_bg "$LIB/codemirror/lib/codemirror.js" \
  "$P1/lib/codemirror/lib/codemirror.js" \
  "$P2/lib/codemirror/lib/codemirror.js"

# fuzzy
run_bg "$LIB/fuzzy/lib/fuzzy.js" \
  "$P1/lib/fuzzy/lib/fuzzy.js" \
  "$P2/lib/fuzzy/lib/fuzzy.js"

# socket.io-client (있으면)
run_bg "$LIB/socket.io-client/socket.io.js" \
  "$P1/lib/socket.io-client/socket.io.js" \
  "$P2/lib/socket.io-client/socket.io.js"

# --- ws files ---
mkdir -p "$JS/ws"

run_bg "$JS/ws/locales.js" \
  "$GH_RAW/entrylabs/entryjs/$ENTRYJS_REF/example/js/ws/locales.js" \
  "$GH_RAW/entrylabs/entryjs/master/example/js/ws/locales.js" \
  "$P1/js/ws/locales.js" \
  "$P2/js/ws/locales.js" \
  "$P1/lib/js/ws/locales.js" \
  "$P2/lib/js/ws/locales.js"

run_bg "$JS/ws/jshint.js" \
  "$P1/js/ws/jshint.js" \
  "$P2/js/ws/jshint.js" \
  "$P1/lib/js/ws/jshint.js" \
  "$P2/lib/js/ws/jshint.js"

run_bg "$JS/ws/python.js" \
  "$P1/js/ws/python.js" \
  "$P2/js/ws/python.js" \
  "$P1/lib/js/ws/python.js" \
  "$P2/lib/js/ws/python.js" \
  "$P1/js/textmode/python/python.js"

# Entry extern utils
run_bg "$LIB/entry-js/extern/util/filbert.js" \
  "$P1/lib/entry-js/extern/util/filbert.js" \
  "$P2/lib/entry-js/extern/util/filbert.js"

run_bg "$LIB/entry-js/extern/util/CanvasInput.js" \
  "$P1/lib/entry-js/extern/util/CanvasInput.js" \
  "$P2/lib/entry-js/extern/util/CanvasInput.js"

run_bg "$LIB/entry-js/extern/util/ndgmr.Collision.js" \
  "$P1/lib/entry-js/extern/util/ndgmr.Collision.js" \
  "$P2/lib/entry-js/extern/util/ndgmr.Collision.js"

run_bg "$LIB/entry-js/extern/util/handle.js" \
  "$P1/lib/entry-js/extern/util/handle.js" \
  "$P2/lib/entry-js/extern/util/handle.js"

run_bg "$LIB/entry-js/extern/util/bignumber.min.js" \
  "$P1/lib/entry-js/extern/util/bignumber.min.js" \
  "$P2/lib/entry-js/extern/util/bignumber.min.js"

# ✅ 여기까지 병렬 다운로드 대기
wait_all

# --- React 18: npm vendoring (마지막에 안전하게) ---
echo "=== Vendor React 18 from npm (stable) ==="
npm install --no-audit --no-fund --silent react@18.2.0 react-dom@18.2.0 || true

mkdir -p "$JS/react18"
if [ -f "$ROOT/node_modules/react/umd/react.production.min.js" ]; then
  cp -f "$ROOT/node_modules/react/umd/react.production.min.js" "$JS/react18/react.production.min.js"
else
  echo "$JS/react18/react.production.min.js" >> "$FAIL_LOG"
fi

if [ -f "$ROOT/node_modules/react-dom/umd/react-dom.production.min.js" ]; then
  cp -f "$ROOT/node_modules/react-dom/umd/react-dom.production.min.js" "$JS/react18/react-dom.production.min.js"
else
  echo "$JS/react18/react-dom.production.min.js" >> "$FAIL_LOG"
fi

# summary (항상 성공 종료)
if [ -s "$FAIL_LOG" ]; then
  COUNT="$(sort -u "$FAIL_LOG" | wc -l | tr -d ' ')"
  log_big "FETCH SUMMARY: $COUNT file(s) missing"
  sort -u "$FAIL_LOG" | sed 's/^/ - /'
  echo ""
  echo "⚠ 일부 파일이 빠져도 fetch는 계속됩니다."
else
  echo "✅ FETCH SUMMARY: all downloads OK"
fi

exit 0
