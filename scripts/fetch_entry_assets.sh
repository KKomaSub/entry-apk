#!/usr/bin/env bash
# scripts/fetch_entry_assets.sh
# ✅ 안정판 (CreateJS는 code.createjs.com에서 받음 / playentry /lib 경로 404 회피)
# - 병렬 다운로드 (MAX_JOBS)
# - playentry/entry-cdn 경로 변형(/lib/js->/js, /lib/module->/module, entryjs<->entry-js)
# - 404여도 중단 안 함(크게 로그 + 계속)
# - npm fallback: @entrylabs/entry 통째로 받아서 www/lib/entry-js, www/lib/entryjs에 채움

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"
LIB="$WWW/lib"
JS="$WWW/js"

mkdir -p "$WWW" "$LIB" "$JS"

MAX_JOBS="${MAX_JOBS:-6}"

P1="https://playentry.org"
P2="https://entry-cdn.pstatic.net"

GH_RAW="https://raw.githubusercontent.com"
ENTRYJS_REF="${ENTRYJS_REF:-develop}"

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

# 후보 URL들을 순서대로 시도
# - http(s)면 그대로
# - /path 형태면 자동으로 P2/P1 붙인 후보 + /lib/js -> /js 등 변형 후보 추가
# 전부 실패해도 스크립트는 계속 진행(0 리턴)
fetch_one() {
  local out="$1"; shift
  mkdir -p "$(dirname "$out")"

  local cands=()

  add_cand() { [ -n "${1:-}" ] && cands+=("$1"); }

  add_path_variants() {
    local p="$1"

    # 기본: CDN 우선
    add_cand "$P2$p"
    add_cand "$P1$p"

    # /lib/js/...  -> /js/...
    if [[ "$p" == /lib/js/* ]]; then
      local p2="${p#/lib}"
      add_cand "$P2$p2"
      add_cand "$P1$p2"
    fi

    # /lib/module/... -> /module/...
    if [[ "$p" == /lib/module/* ]]; then
      local p2="${p#/lib}"
      add_cand "$P2$p2"
      add_cand "$P1$p2"
    fi

    # /lib/entryjs/... -> /lib/entry-js/... (반대도)
    if [[ "$p" == /lib/entryjs/* ]]; then
      local p2="${p/\/lib\/entryjs\//\/lib\/entry-js\/}"
      add_cand "$P2$p2"
      add_cand "$P1$p2"
    fi
    if [[ "$p" == /lib/entry-js/* ]]; then
      local p2="${p/\/lib\/entry-js\//\/lib\/entryjs\/}"
      add_cand "$P2$p2"
      add_cand "$P1$p2"
    fi
  }

  while [ $# -gt 0 ]; do
    local x="$1"; shift
    if [[ "$x" == http* ]]; then
      add_cand "$x"
    elif [[ "$x" == /* ]]; then
      add_path_variants "$x"
    else
      add_cand "$x"
    fi
  done

  # 중복 제거
  local uniq=()
  local seen=""
  local u
  for u in "${cands[@]}"; do
    if [[ "$seen" != *"|$u|"* ]]; then
      uniq+=("$u")
      seen+="|$u|"
    fi
  done

  local url
  for url in "${uniq[@]}"; do
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
  for url in "${uniq[@]}"; do echo " - $url"; done
  echo ""
  return 0
}

# 병렬 실행 + 동시 작업 제한
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

# npm pack으로 @entrylabs/entry를 통째로 추출해 lib/entry-js에 채우는 fallback
npm_fallback_entry() {
  command -v npm >/dev/null 2>&1 || { big "npm not found -> skip npm fallback"; return 0; }
  command -v tar >/dev/null 2>&1 || { big "tar not found -> skip npm fallback"; return 0; }

  local NEED=0

  # images/media 없으면 거의 필수
  [ -d "$WWW/lib/entry-js/images/media" ] || NEED=1

  # 실패 로그에 이미지류가 있으면 강제
  if [ -s "$FAIL_LOG" ] && grep -qE '/images/|/media/|/img/|/icon|\.svg|\.png|\.jpg' "$FAIL_LOG"; then
    NEED=1
  fi

  [ "$NEED" -eq 0 ] && { log "NPM fallback not needed"; return 0; }

  big "NPM FALLBACK: extracting FULL @entrylabs/entry into www/lib/entry-js"

  local TMP="$WWW/.tmp_entry_pkg"
  rm -rf "$TMP"
  mkdir -p "$TMP"
  pushd "$TMP" >/dev/null || return 0

  if ! npm pack @entrylabs/entry >/dev/null 2>&1; then
    big "npm pack failed (network/auth). skip."
    popd >/dev/null
    return 0
  fi

  local TGZ
  TGZ="$(ls -1 *.tgz 2>/dev/null | head -n 1)"
  [ -z "$TGZ" ] && { big "npm pack produced no tgz. skip."; popd >/dev/null; return 0; }

  tar -xzf "$TGZ" >/dev/null 2>&1 || true
  [ ! -d "package" ] && { big "tar ok but package/ missing. skip."; popd >/dev/null; return 0; }

  mkdir -p "$WWW/lib/entry-js"
  (
    shopt -s dotglob nullglob
    cp -R "package/"* "$WWW/lib/entry-js/" 2>/dev/null || true
  )

  # alias: /lib/entryjs도 같은 내용으로 맞춤
  mkdir -p "$WWW/lib/entryjs"
  (
    shopt -s dotglob nullglob
    cp -R "$WWW/lib/entry-js/"* "$WWW/lib/entryjs/" 2>/dev/null || true
  )

  popd >/dev/null
  rm -rf "$TMP"

  if [ -d "$WWW/lib/entry-js/images/media" ]; then
    log "NPM FALLBACK OK: images/media exists"
  else
    big "NPM FALLBACK WARNING: images/media still missing (package may differ)"
  fi
  return 0
}

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"
log "ENTRYJS_REF=$ENTRYJS_REF"
echo ""

# ─────────────────────────────────────────────────────────────
# 0) 필수 라이브러리 (Entry가 기대하는 전역)
# ─────────────────────────────────────────────────────────────

# underscore(Entry가 _ 로 기대)
run_bg "$LIB/underscore/underscore-min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/underscore.js/1.8.3/underscore-min.js"

# lodash (있으면 좋음)
run_bg "$LIB/lodash/dist/lodash.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.21/lodash.min.js"

# jQuery
run_bg "$LIB/jquery/jquery.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" \
  "/lib/jquery/jquery.min.js"

# jQuery UI
run_bg "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" \
  "/lib/jquery-ui/ui/minified/jquery-ui.min.js"

# ✅ CreateJS는 playentry CDN이 아니라 "공식 createjs CDN"이 정답
mkdir -p "$LIB/EaselJS/lib" "$LIB/PreloadJS/lib" "$LIB/SoundJS/lib"
run_bg "$LIB/EaselJS/lib/easeljs-0.8.2.min.js" \
  "https://code.createjs.com/easeljs-0.8.2.min.js"
run_bg "$LIB/PreloadJS/lib/preloadjs-0.6.2.min.js" \
  "https://code.createjs.com/preloadjs-0.6.2.min.js"
run_bg "$LIB/SoundJS/lib/soundjs-0.6.2.min.js" \
  "https://code.createjs.com/soundjs-0.6.2.min.js"
run_bg "$LIB/SoundJS/lib/flashaudioplugin-0.6.2.min.js" \
  "https://code.createjs.com/flashaudioplugin-0.6.2.min.js"

# React18 (있으면)
mkdir -p "$JS/react18"
run_bg "$JS/react18/react.production.min.js" \
  "/js/react18/react.production.min.js" \
  "https://unpkg.com/react@18/umd/react.production.min.js"
run_bg "$JS/react18/react-dom.production.min.js" \
  "/js/react18/react-dom.production.min.js" \
  "https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"

# legacy-video
mkdir -p "$JS/module/legacy-video"
run_bg "$JS/module/legacy-video/index.js" \
  "/module/legacy-video/index.js"

# ─────────────────────────────────────────────────────────────
# 1) EntryJS / Tool / Paint
# ─────────────────────────────────────────────────────────────
run_bg "$LIB/entryjs/dist/entry.min.js" \
  "/lib/entryjs/dist/entry.min.js" \
  "/lib/entry-js/dist/entry.min.js"
run_bg "$LIB/entryjs/dist/entry.css" \
  "/lib/entryjs/dist/entry.css" \
  "/lib/entry-js/dist/entry.css"

run_bg "$LIB/entryjs/extern/lang/ko.js" \
  "/lib/entryjs/extern/lang/ko.js" \
  "/lib/entry-js/extern/lang/ko.js"
run_bg "$LIB/entryjs/extern/util/static.js" \
  "/lib/entryjs/extern/util/static.js" \
  "/lib/entry-js/extern/util/static.js"
run_bg "$LIB/entryjs/extern/util/handle.js" \
  "/lib/entryjs/extern/util/handle.js" \
  "/lib/entry-js/extern/util/handle.js"
run_bg "$LIB/entryjs/extern/util/bignumber.min.js" \
  "/lib/entryjs/extern/util/bignumber.min.js" \
  "/lib/entry-js/extern/util/bignumber.min.js"

run_bg "$LIB/entryjs/extern/util/CanvasInput.js" \
  "/lib/entryjs/extern/util/CanvasInput.js" \
  "/lib/entry-js/extern/util/CanvasInput.js"
run_bg "$LIB/entryjs/extern/util/ndgmr.Collision.js" \
  "/lib/entryjs/extern/util/ndgmr.Collision.js" \
  "/lib/entry-js/extern/util/ndgmr.Collision.js"
run_bg "$LIB/entryjs/extern/util/filbert.js" \
  "/lib/entryjs/extern/util/filbert.js" \
  "/lib/entry-js/extern/util/filbert.js"

run_bg "$LIB/entry-tool/dist/entry-tool.js" \
  "/lib/entry-tool/dist/entry-tool.js"
run_bg "$LIB/entry-tool/dist/entry-tool.css" \
  "/lib/entry-tool/dist/entry-tool.css"

run_bg "$LIB/entry-paint/dist/static/js/entry-paint.js" \
  "/lib/entry-paint/dist/static/js/entry-paint.js"

# ─────────────────────────────────────────────────────────────
# 2) ws (힌트/텍스트모드)
# ─────────────────────────────────────────────────────────────
mkdir -p "$JS/ws"

# locales.js는 환경마다 다를 수 있어 "없어도 통과"
run_bg "$JS/ws/locales.js" \
  "$GH_RAW/entrylabs/entryjs/$ENTRYJS_REF/example/js/ws/locales.js" \
  "$GH_RAW/entrylabs/entryjs/master/example/js/ws/locales.js" \
  "/js/ws/locales.js" \
  "/lib/js/ws/locales.js"

# jshint
run_bg "$JS/ws/jshint.js" \
  "/js/jshint.js" \
  "/js/ws/jshint.js" \
  "/lib/js/ws/jshint.js"

# python.js : playentry.org 경로가 자주 바뀌어 entry-cdn 우선
run_bg "$JS/ws/python.js" \
  "https://entry-cdn.pstatic.net/js/ws/python.js" \
  "/js/ws/python.js" \
  "/lib/js/ws/python.js"

# ─────────────────────────────────────────────────────────────
# 3) 기타(있으면 좋음)
# ─────────────────────────────────────────────────────────────
run_bg "$LIB/velocity/velocity.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" \
  "/lib/velocity/velocity.min.js"

run_bg "$LIB/socket.io-client/socket.io.js" \
  "/lib/socket.io-client/socket.io.js"

run_bg "$LIB/codemirror/lib/codemirror.js" \
  "/lib/codemirror/lib/codemirror.js"

run_bg "$LIB/fuzzy/lib/fuzzy.js" \
  "/lib/fuzzy/lib/fuzzy.js"

# 1차 다운로드 완료 대기
wait_all

# ─────────────────────────────────────────────────────────────
# 4) npm fallback (이미지/아이콘/리소스 부족하면 채움)
# ─────────────────────────────────────────────────────────────
npm_fallback_entry

# ─────────────────────────────────────────────────────────────
# 5) alias 호환 (/lib/entryjs <-> /lib/entry-js)
# ─────────────────────────────────────────────────────────────
log "=== Alias copy: /lib/entryjs <-> /lib/entry-js ==="
mkdir -p "$WWW/lib/entry-js" "$WWW/lib/entryjs"
cp -R "$WWW/lib/entryjs/"* "$WWW/lib/entry-js/" 2>/dev/null || true
cp -R "$WWW/lib/entry-js/"* "$WWW/lib/entryjs/" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# 6) Summary
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

