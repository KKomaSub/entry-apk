#!/usr/bin/env bash
# scripts/fetch_entry_assets.sh
# Entry Offline(웹)용 라이브러리/이미지/폰트/리소스를 www/ 아래로 “경로 그대로” 받아오는 스크립트
# - 병렬 다운로드 (run_bg + MAX_JOBS)
# - URL 후보 자동 변형(/lib/js -> /js, /lib/module -> /module, entryjs <-> entry-js)
# - CSS url(...) 의존성 자동 다운로드
# - HTML src/href/poster + JS 문자열 경로 의존성 자동 다운로드
# - static.js / entry.min.js 내부 문자열 경로 의존성 자동 다운로드
# - (핵심) CDN 404/경로변경을 회피하기 위해 @entrylabs/entry NPM 패키지에서 assets를 "통째로" 추출해 채우는 fallback
# - /lib/entryjs <-> /lib/entry-js 경로 alias 양방향 복사
#
# 목표: 404가 나와도 "중단하지 않고", 가능한 후보를 끝까지 시도하고, 실패는 크게 로그만 남기기

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"
LIB="$WWW/lib"
JS="$WWW/js"

mkdir -p "$LIB" "$JS"

# 병렬 개수(기본 6) - 필요시: MAX_JOBS=3 bash scripts/fetch_entry_assets.sh
MAX_JOBS="${MAX_JOBS:-6}"

# 원격 후보(둘 다 시도) - CDN을 P2로 우선
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

  add_cand() {
    local u="$1"
    [ -z "$u" ] && return 0
    cands+=("$u")
    return 0
  }

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
      # 상대경로/기타는 그대로 한 번만
      add_cand "$x"
    fi
  done

  # 중복 제거(간단)
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

  # 현재 실행 중인 background job 수가 MAX_JOBS 미만이 될 때까지 대기
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

log "=== Fetch Entry assets ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"
log "ENTRYJS_REF=$ENTRYJS_REF"
echo ""

# ─────────────────────────────────────────────────────────────
# 0) 필수 라이브러리(EntryJS가 기대)
# ─────────────────────────────────────────────────────────────

# ✅ Underscore: EntryJS가 _ 로 기대
run_bg "$LIB/underscore/underscore-min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/underscore.js/1.8.3/underscore-min.js"

# ✅ Lodash: 필요하면 index.html에서 noConflict로 window.lodash로 사용
run_bg "$LIB/lodash/dist/lodash.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.21/lodash.min.js"

# jQuery / jQuery UI
run_bg "$LIB/jquery/jquery.min.js" \
  "/lib/jquery/jquery.min.js"

run_bg "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" \
  "/lib/jquery-ui/ui/minified/jquery-ui.min.js"

# CreateJS
run_bg "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"

run_bg "$LIB/EaselJS/lib/easeljs-0.8.0.min.js" \
  "/lib/EaselJS/lib/easeljs-0.8.0.min.js"

run_bg "$LIB/SoundJS/lib/soundjs-0.6.0.min.js" \
  "/lib/SoundJS/lib/soundjs-0.6.0.min.js"

run_bg "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js"

# ✅ React18 (일부 UI에서 참조될 수 있음)
mkdir -p "$JS/react18"
run_bg "$JS/react18/react.production.min.js" \
  "/js/react18/react.production.min.js"

run_bg "$JS/react18/react-dom.production.min.js" \
  "/js/react18/react-dom.production.min.js"

# ✅ legacy-video (EntryVideoLegacy 관련)
mkdir -p "$JS/module/legacy-video"
run_bg "$JS/module/legacy-video/index.js" \
  "/module/legacy-video/index.js"

# ─────────────────────────────────────────────────────────────
# 1) EntryJS / Tool / Paint 본체
# ─────────────────────────────────────────────────────────────

# EntryJS
run_bg "$LIB/entryjs/dist/entry.min.js" \
  "/lib/entryjs/dist/entry.min.js" \
  "/lib/entry-js/dist/entry.min.js"

run_bg "$LIB/entryjs/dist/entry.css" \
  "/lib/entryjs/dist/entry.css" \
  "/lib/entry-js/dist/entry.css"

# extern
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

# util(필요한 경우 많음)
run_bg "$LIB/entryjs/extern/util/CanvasInput.js" \
  "/lib/entryjs/extern/util/CanvasInput.js" \
  "/lib/entry-js/extern/util/CanvasInput.js"

run_bg "$LIB/entryjs/extern/util/ndgmr.Collision.js" \
  "/lib/entryjs/extern/util/ndgmr.Collision.js" \
  "/lib/entry-js/extern/util/ndgmr.Collision.js"

run_bg "$LIB/entryjs/extern/util/filbert.js" \
  "/lib/entryjs/extern/util/filbert.js" \
  "/lib/entry-js/extern/util/filbert.js"

# Entry Tool
run_bg "$LIB/entry-tool/dist/entry-tool.js" \
  "/lib/entry-tool/dist/entry-tool.js"

run_bg "$LIB/entry-tool/dist/entry-tool.css" \
  "/lib/entry-tool/dist/entry-tool.css"

# Entry Paint
run_bg "$LIB/entry-paint/dist/static/js/entry-paint.js" \
  "/lib/entry-paint/dist/static/js/entry-paint.js"

# ─────────────────────────────────────────────────────────────
# 2) ws(번역/힌트 등) – playentry CDN에서 404 날 수 있어 raw 후보 포함
# ─────────────────────────────────────────────────────────────
mkdir -p "$JS/ws"

run_bg "$JS/ws/locales.js" \
  "$GH_RAW/entrylabs/entryjs/$ENTRYJS_REF/example/js/ws/locales.js" \
  "$GH_RAW/entrylabs/entryjs/master/example/js/ws/locales.js" \
  "/js/ws/locales.js" \
  "/lib/js/ws/locales.js"

run_bg "$JS/ws/jshint.js" \
  "/js/ws/jshint.js" \
  "/lib/js/ws/jshint.js"

run_bg "$JS/ws/python.js" \
  "/js/ws/python.js" \
  "/lib/js/ws/python.js"

# ─────────────────────────────────────────────────────────────
# 3) 기타 자주 쓰는 라이브러리(있으면 편함)
# ─────────────────────────────────────────────────────────────
run_bg "$LIB/velocity/velocity.min.js" \
  "/lib/velocity/velocity.min.js"

run_bg "$LIB/socket.io-client/socket.io.js" \
  "/lib/socket.io-client/socket.io.js"

run_bg "$LIB/codemirror/lib/codemirror.js" \
  "/lib/codemirror/lib/codemirror.js"

run_bg "$LIB/fuzzy/lib/fuzzy.js" \
  "/lib/fuzzy/lib/fuzzy.js"

# 다운로드 완료 대기
wait_all

# ─────────────────────────────────────────────────────────────
# 4) 의존성 자동 보강 스크립트 실행(실패해도 계속)
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
# 5) NPM FALLBACK (가장 확실한 방식)
#  - CDN에서 이미지/아이콘이 404 나면 @entrylabs/entry 패키지에서 "통째로" 꺼내서 채움
# ─────────────────────────────────────────────────────────────
npm_fallback_entry() {
  command -v npm >/dev/null 2>&1 || { big "npm not found -> skip npm fallback"; return 0; }
  command -v tar >/dev/null 2>&1 || { big "tar not found -> skip npm fallback"; return 0; }

  local NEED=0

  # images/media가 없으면 거의 100% 404가 뜸
  [ -d "$WWW/lib/entry-js/images/media" ] || NEED=1

  # 실패 로그에 이미지류가 있으면 강제 실행
  if [ -s "$FAIL_LOG" ] && grep -qE '/images/|/media/|/img/|/icon|\.svg|\.png|\.jpg' "$FAIL_LOG"; then
    NEED=1
  fi

  [ "$NEED" -eq 0 ] && { log "NPM fallback not needed"; return 0; }

  big "NPM FALLBACK: extracting FULL @entrylabs/entry into www/lib/entry-js"

  local TMP="$WWW/.tmp_entry_pkg"
  rm -rf "$TMP"
  mkdir -p "$TMP"
  pushd "$TMP" >/dev/null || return 0

  # 원하는 버전 고정 가능: npm pack @entrylabs/entry@x.y.z
  if ! npm pack @entrylabs/entry >/dev/null 2>&1; then
    big "npm pack failed (network/auth). skip."
    popd >/dev/null
    return 0
  fi

  local TGZ
  TGZ="$(ls -1 *.tgz 2>/dev/null | head -n 1)"
  if [ -z "$TGZ" ]; then
    big "npm pack produced no tgz. skip."
    popd >/dev/null
    return 0
  fi

  tar -xzf "$TGZ" >/dev/null 2>&1 || true

  if [ ! -d "package" ]; then
    big "tar extract ok but package/ missing. skip."
    popd >/dev/null
    return 0
  fi

  mkdir -p "$WWW/lib/entry-js"

  # ✅ 핵심: package/ 전체를 통째로 www/lib/entry-js 로 복사(구조 유지)
  (
    shopt -s dotglob nullglob
    cp -R "package/"* "$WWW/lib/entry-js/" 2>/dev/null || true
  )

  # ✅ alias 유지: /lib/entryjs 도 같은 내용으로 맞춤
  mkdir -p "$WWW/lib/entryjs"
  (
    shopt -s dotglob nullglob
    cp -R "$WWW/lib/entry-js/"* "$WWW/lib/entryjs/" 2>/dev/null || true
  )

  popd >/dev/null
  rm -rf "$TMP"

  # 간단 검증 로그(없어도 계속)
  if [ -d "$WWW/lib/entry-js/images/media" ]; then
    log "NPM FALLBACK OK: images/media exists"
  else
    big "NPM FALLBACK WARNING: images/media still missing (package may differ)"
  fi

  return 0
}
npm_fallback_entry

# ─────────────────────────────────────────────────────────────
# 6) 경로 alias 호환 (/lib/entryjs <-> /lib/entry-js)
# ─────────────────────────────────────────────────────────────
log "=== Alias copy: /lib/entryjs <-> /lib/entry-js ==="
mkdir -p "$WWW/lib/entry-js" "$WWW/lib/entryjs"
cp -R "$WWW/lib/entryjs/"* "$WWW/lib/entry-js/" 2>/dev/null || true
cp -R "$WWW/lib/entry-js/"* "$WWW/lib/entryjs/" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# 7) 요약(실패해도 종료코드는 0)
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

