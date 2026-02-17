#!/usr/bin/env bash
# scripts/fetch_entry_assets.sh
# Entry Offline(웹)용 라이브러리/이미지/폰트/리소스를 www/ 아래로 “경로 그대로” 받아오는 스크립트
# - 병렬 다운로드
# - CSS url(...) 의존성 자동 다운로드
# - HTML src/href/poster + JS 문자열 경로 의존성 자동 다운로드
# - static.js / entry.min.js 내부 문자열 경로 의존성 자동 다운로드
# - /lib/entryjs <-> /lib/entry-js 경로 alias 양방향 복사
#
# 주의: 절대 실패로 멈추지 않게(오류는 크게 로그만 남기고 계속) 설계됨

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"
LIB="$WWW/lib"
JS="$WWW/js"

mkdir -p "$LIB" "$JS"

# 병렬 개수(기본 6)
MAX_JOBS="${MAX_JOBS:-6}"

# 원격 후보(둘 다 시도)
P1="https://playentry.org"
P2="https://entry-cdn.pstatic.net"
GH_RAW="https://raw.githubusercontent.com"
ENTRYJS_REF="${ENTRYJS_REF:-develop}"

# 실패 목록
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

# curl로 다운로드 (실패하면 non-zero)
curl_get() {
  local url="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  curl -L --retry 3 --retry-delay 1 --fail -o "$out" "$url"
}

# 후보 URL들을 순서대로 시도, 전부 실패해도 스크립트는 계속 진행(0 리턴)
fetch_one() {
  local out="$1"; shift
  mkdir -p "$(dirname "$out")"

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
  return 0
}

# 병렬 실행 + 동시 작업 제한
run_bg() {
  fetch_one "$@" &
  while [ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$MAX_JOBS" ]; do
    sleep 0.2
  done
}

wait_all() {
  while true; do
    local pids
    pids="$(jobs -pr)"
    [ -z "$pids" ] && break
    wait $pids 2>/dev/null || true
    sleep 0.1
  done
}

log "=== Fetch Entry assets ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"
log "ENTRYJS_REF=$ENTRYJS_REF"
echo ""

# ─────────────────────────────────────────────────────────────
# 0) 필수 라이브러리(EntryJS가 기대)
# ─────────────────────────────────────────────────────────────

# ✅ Underscore: EntryJS가 _ 로 기대하는 쪽(가장 중요)
run_bg "$LIB/underscore/underscore-min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/underscore.js/1.8.3/underscore-min.js"

# ✅ Lodash: 필요할 때만 쓰되, index.html에서 noConflict로 window.lodash로 빼서 _를 건드리지 않게 사용
run_bg "$LIB/lodash/dist/lodash.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.21/lodash.min.js"

# jQuery / jQuery UI (EntryJS 일부 UI에서 필요)
run_bg "$LIB/jquery/jquery.min.js" \
  "$P1/lib/jquery/jquery.min.js" \
  "$P2/lib/jquery/jquery.min.js"

run_bg "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P1/lib/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P2/lib/jquery-ui/ui/minified/jquery-ui.min.js"

# CreateJS(스테이지/사운드 등)
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

# ─────────────────────────────────────────────────────────────
# 1) EntryJS / Tool / Paint 본체
# ─────────────────────────────────────────────────────────────

# EntryJS
run_bg "$LIB/entryjs/dist/entry.min.js" \
  "$P1/lib/entryjs/dist/entry.min.js" \
  "$P2/lib/entryjs/dist/entry.min.js" \
  "$P1/lib/entry-js/dist/entry.min.js" \
  "$P2/lib/entry-js/dist/entry.min.js"

run_bg "$LIB/entryjs/dist/entry.css" \
  "$P1/lib/entryjs/dist/entry.css" \
  "$P2/lib/entryjs/dist/entry.css" \
  "$P1/lib/entry-js/dist/entry.css" \
  "$P2/lib/entry-js/dist/entry.css"

# extern
run_bg "$LIB/entryjs/extern/lang/ko.js" \
  "$P1/lib/entryjs/extern/lang/ko.js" \
  "$P2/lib/entryjs/extern/lang/ko.js" \
  "$P1/lib/entry-js/extern/lang/ko.js" \
  "$P2/lib/entry-js/extern/lang/ko.js"

run_bg "$LIB/entryjs/extern/util/static.js" \
  "$P1/lib/entryjs/extern/util/static.js" \
  "$P2/lib/entryjs/extern/util/static.js" \
  "$P1/lib/entry-js/extern/util/static.js" \
  "$P2/lib/entry-js/extern/util/static.js"

run_bg "$LIB/entryjs/extern/util/handle.js" \
  "$P1/lib/entryjs/extern/util/handle.js" \
  "$P2/lib/entryjs/extern/util/handle.js" \
  "$P1/lib/entry-js/extern/util/handle.js" \
  "$P2/lib/entry-js/extern/util/handle.js"

run_bg "$LIB/entryjs/extern/util/bignumber.min.js" \
  "$P1/lib/entryjs/extern/util/bignumber.min.js" \
  "$P2/lib/entryjs/extern/util/bignumber.min.js" \
  "$P1/lib/entry-js/extern/util/bignumber.min.js" \
  "$P2/lib/entry-js/extern/util/bignumber.min.js"

# (있으면 도움되는 util들)
run_bg "$LIB/entryjs/extern/util/CanvasInput.js" \
  "$P1/lib/entryjs/extern/util/CanvasInput.js" \
  "$P2/lib/entryjs/extern/util/CanvasInput.js" \
  "$P1/lib/entry-js/extern/util/CanvasInput.js" \
  "$P2/lib/entry-js/extern/util/CanvasInput.js"

run_bg "$LIB/entryjs/extern/util/ndgmr.Collision.js" \
  "$P1/lib/entryjs/extern/util/ndgmr.Collision.js" \
  "$P2/lib/entryjs/extern/util/ndgmr.Collision.js" \
  "$P1/lib/entry-js/extern/util/ndgmr.Collision.js" \
  "$P2/lib/entry-js/extern/util/ndgmr.Collision.js"

run_bg "$LIB/entryjs/extern/util/filbert.js" \
  "$P1/lib/entryjs/extern/util/filbert.js" \
  "$P2/lib/entryjs/extern/util/filbert.js" \
  "$P1/lib/entry-js/extern/util/filbert.js" \
  "$P2/lib/entry-js/extern/util/filbert.js"

# Entry Tool
run_bg "$LIB/entry-tool/dist/entry-tool.js" \
  "$P1/lib/entry-tool/dist/entry-tool.js" \
  "$P2/lib/entry-tool/dist/entry-tool.js"

run_bg "$LIB/entry-tool/dist/entry-tool.css" \
  "$P1/lib/entry-tool/dist/entry-tool.css" \
  "$P2/lib/entry-tool/dist/entry-tool.css"

# Entry Paint
run_bg "$LIB/entry-paint/dist/static/js/entry-paint.js" \
  "$P1/lib/entry-paint/dist/static/js/entry-paint.js" \
  "$P2/lib/entry-paint/dist/static/js/entry-paint.js"

# ─────────────────────────────────────────────────────────────
# 2) ws(번역/힌트 등) – playentry CDN에서 404 날 수 있어 raw 후보 포함
# ─────────────────────────────────────────────────────────────
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
  "$P2/lib/js/ws/python.js"

# ─────────────────────────────────────────────────────────────
# 3) 기타 자주 쓰는 라이브러리(있으면 편함)
# ─────────────────────────────────────────────────────────────
run_bg "$LIB/velocity/velocity.min.js" \
  "$P1/lib/velocity/velocity.min.js" \
  "$P2/lib/velocity/velocity.min.js"

run_bg "$LIB/socket.io-client/socket.io.js" \
  "$P1/lib/socket.io-client/socket.io.js" \
  "$P2/lib/socket.io-client/socket.io.js"

run_bg "$LIB/codemirror/lib/codemirror.js" \
  "$P1/lib/codemirror/lib/codemirror.js" \
  "$P2/lib/codemirror/lib/codemirror.js"

run_bg "$LIB/fuzzy/lib/fuzzy.js" \
  "$P1/lib/fuzzy/lib/fuzzy.js" \
  "$P2/lib/fuzzy/lib/fuzzy.js"

# 다운로드 완료 대기
wait_all

# ─────────────────────────────────────────────────────────────
# 4) 의존성 자동 보강 스크립트 실행(실패해도 계속)
#    - 이 3개는 "깨지는 이미지/폰트/오브젝트 추가 화면" 해결 핵심
# ─────────────────────────────────────────────────────────────
log "=== Post processing: deps fetch ==="

# (1) CSS url(...) 의존성 다운로드 + (http면 mirror로 rewrite)
if [ -f "$ROOT/scripts/fetch_css_deps.js" ]; then
  node "$ROOT/scripts/fetch_css_deps.js" || true
else
  big "Missing scripts/fetch_css_deps.js (skip)"
fi

# (2) HTML src/href/poster + JS 내 문자열 경로 의존성 다운로드
if [ -f "$ROOT/scripts/fetch_dom_js_deps.js" ]; then
  node "$ROOT/scripts/fetch_dom_js_deps.js" || true
else
  big "Missing scripts/fetch_dom_js_deps.js (skip)"
fi

# (3) static.js / entry.min.js / tool / paint 내부 문자열 경로 의존성 다운로드
if [ -f "$ROOT/scripts/fetch_static_and_bundle_deps.js" ]; then
  node "$ROOT/scripts/fetch_static_and_bundle_deps.js" || true
else
  big "Missing scripts/fetch_static_and_bundle_deps.js (skip)"
fi

# ─────────────────────────────────────────────────────────────
# 5) 경로 alias 호환 (/lib/entryjs <-> /lib/entry-js)
# ─────────────────────────────────────────────────────────────
log "=== Alias copy: /lib/entryjs <-> /lib/entry-js ==="
mkdir -p "$WWW/lib/entry-js" "$WWW/lib/entryjs"
cp -R "$WWW/lib/entryjs/"* "$WWW/lib/entry-js/" 2>/dev/null || true
cp -R "$WWW/lib/entry-js/"* "$WWW/lib/entryjs/" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# 6) 요약(실패해도 종료코드는 0)
# ─────────────────────────────────────────────────────────────
if [ -s "$FAIL_LOG" ]; then
  COUNT="$(sort -u "$FAIL_LOG" | wc -l | tr -d ' ')"
  big "FETCH SUMMARY: $COUNT file(s) missing (script continues)"
  sort -u "$FAIL_LOG" | sed 's/^/ - /'
  echo ""
else
  log "✅ FETCH SUMMARY: all downloads OK"
fi

exit 0
```0
