#!/usr/bin/env bash
# scripts/fetch_entry_assets.sh
# ✅ 404를 없애는 정석: CDN의 /lib/...를 긁지 말고 npm(pack) 기반으로 vendor 구성
# - @entrylabs/entry (entryDir 기본 /@entrylabs/entry) => www/@entrylabs/entry 로 배치
# - entryjs / entry-tool / entry-paint 등은 www/lib/... 로 배치
# - third-party deps는 npm에서 정확한 버전으로 받아 www/lib/... 로 배치
# - playentry 서버에 포함된 일부 파일(jshint, python)은 playentry.org에서 직접 받되,
#   경로는 문서/예시대로 /js/... 를 사용 (404 적음)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"
LIB="$WWW/lib"
NODE_BIN="${NODE_BIN:-node}"
NPM_BIN="${NPM_BIN:-npm}"

mkdir -p "$WWW" "$LIB"
FAIL_LOG="$WWW/.fetch_failed.txt"
: > "$FAIL_LOG"

log(){ echo "[$(date +%H:%M:%S)] $*"; }
big(){
  echo ""
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $1"
  echo "████████████████████████████████████████████████████████████"
  echo ""
}

curl_get() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  if ! curl -L --compressed --retry 3 --retry-delay 1 --fail -o "$out" "$url" ; then
    echo "$out" >> "$FAIL_LOG"
    big "MISS $url"
    return 1
  fi
  return 0
}

# npm pack으로 tgz 받아서 풀고, package/ 내용을 원하는 곳에 복사
npm_pack_copy_all() {
  local spec="$1" dest="$2"
  local tmp="$WWW/.tmp_pack_$(echo "$spec" | tr '/@:' '___')"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  pushd "$tmp" >/dev/null

  log "npm pack $spec"
  if ! "$NPM_BIN" pack "$spec" >/dev/null 2>&1; then
    big "npm pack failed: $spec"
    popd >/dev/null
    rm -rf "$tmp"
    return 1
  fi

  local tgz
  tgz="$(ls -1 *.tgz | head -n 1)"
  tar -xzf "$tgz" >/dev/null 2>&1 || true
  if [ ! -d package ]; then
    big "npm pack extract failed (no package/): $spec"
    popd >/dev/null
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$dest"
  (
    shopt -s dotglob nullglob
    cp -R package/* "$dest/" 2>/dev/null || true
  )

  popd >/dev/null
  rm -rf "$tmp"
  return 0
}

# 특정 파일만 복사(패키지 구조가 달라도 robust하게)
copy_if_exists() {
  local from="$1" to="$2"
  if [ -f "$from" ]; then
    mkdir -p "$(dirname "$to")"
    cp -f "$from" "$to"
    return 0
  fi
  return 1
}

# npm pack 후 풀린 package/에서 특정 파일을 찾아 복사하는 helper
npm_pack_pick() {
  local spec="$1" rel_from="$2" to="$3"
  local tmp="$WWW/.tmp_pick_$(echo "$spec" | tr '/@:' '___')"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  pushd "$tmp" >/dev/null

  log "npm pack $spec"
  if ! "$NPM_BIN" pack "$spec" >/dev/null 2>&1; then
    big "npm pack failed: $spec"
    popd >/dev/null
    rm -rf "$tmp"
    return 1
  fi

  local tgz
  tgz="$(ls -1 *.tgz | head -n 1)"
  tar -xzf "$tgz" >/dev/null 2>&1 || true

  if [ ! -f "package/$rel_from" ]; then
    big "missing in $spec: package/$rel_from"
    echo "$to" >> "$FAIL_LOG"
    popd >/dev/null
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$(dirname "$to")"
  cp -f "package/$rel_from" "$to"

  popd >/dev/null
  rm -rf "$tmp"
  return 0
}

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW=$WWW"
echo ""

# ─────────────────────────────────────────────────────────────
# 1) Entry assets (entryDir 기본값: /@entrylabs/entry)
#    => www/@entrylabs/entry 로 통째로 배치
# ─────────────────────────────────────────────────────────────
mkdir -p "$WWW/@entrylabs"
npm_pack_copy_all "@entrylabs/entry" "$WWW/@entrylabs/entry" || true

# ─────────────────────────────────────────────────────────────
# 2) EntryJS / entry-tool / entry-paint 는 www/lib/... 로 배치
#    (npm에 있으면 npm이 최우선)
# ─────────────────────────────────────────────────────────────
# entryjs (패키지명이 @entrylabs/entry 안에 이미 포함될 수도 있지만, lib 경로를 맞추기 위해 별도 배치)
#   - npm에 entryjs가 없거나 구조가 다르면 아래 curl 후보를 쓰게 할 수도 있지만,
#     원칙적으로 @entrylabs/entry 안에 entryjs가 포함되어 있는 경우가 많습니다. 2
mkdir -p "$LIB/entryjs"
# @entrylabs/entry 안에 entryjs 구조가 있으면 그것을 lib로 복사
if [ -d "$WWW/@entrylabs/entry/entryjs" ]; then
  ( shopt -s dotglob nullglob; cp -R "$WWW/@entrylabs/entry/entryjs/"* "$LIB/entryjs/" 2>/dev/null || true )
fi
# entry-js alias도 맞춤
mkdir -p "$LIB/entry-js"
( shopt -s dotglob nullglob; cp -R "$LIB/entryjs/"* "$LIB/entry-js/" 2>/dev/null || true )

# entry-tool / entry-paint도 @entrylabs/entry 내부에 있으면 그대로 복사
mkdir -p "$LIB/entry-tool" "$LIB/entry-paint"
if [ -d "$WWW/@entrylabs/entry/entry-tool" ]; then
  ( shopt -s dotglob nullglob; cp -R "$WWW/@entrylabs/entry/entry-tool/"* "$LIB/entry-tool/" 2>/dev/null || true )
fi
if [ -d "$WWW/@entrylabs/entry/entry-paint" ]; then
  ( shopt -s dotglob nullglob; cp -R "$WWW/@entrylabs/entry/entry-paint/"* "$LIB/entry-paint/" 2>/dev/null || true )
fi

# 만약 위 복사로 dist가 비어 있으면, 공개 배포된 경로를 curl로 최소만 받음(여기서는 실패해도 계속)
# (Docs는 entry-cdn.pstatic.net에서 받을 수 있다고만 되어 있고 /lib 경로 보장은 약함) 3
mkdir -p "$LIB/entryjs/dist" "$LIB/entryjs/extern/lang" "$LIB/entryjs/extern/util"
[ -f "$LIB/entryjs/dist/entry.min.js" ] || curl_get "https://playentry.org/lib/entry-js/dist/entry.min.js" "$LIB/entryjs/dist/entry.min.js" || true
[ -f "$LIB/entryjs/dist/entry.css" ]    || curl_get "https://playentry.org/lib/entry-js/dist/entry.css"    "$LIB/entryjs/dist/entry.css"    || true
[ -f "$LIB/entryjs/extern/lang/ko.js" ] || curl_get "https://playentry.org/lib/entry-js/extern/lang/ko.js" "$LIB/entryjs/extern/lang/ko.js" || true
[ -f "$LIB/entryjs/extern/util/static.js" ] || curl_get "https://playentry.org/lib/entry-js/extern/util/static.js" "$LIB/entryjs/extern/util/static.js" || true

# alias 동기화
mkdir -p "$LIB/entry-js"
( shopt -s dotglob nullglob; cp -R "$LIB/entryjs/"* "$LIB/entry-js/" 2>/dev/null || true )

# ─────────────────────────────────────────────────────────────
# 3) Third-party deps: npm으로 정확한 버전 받아서 www/lib 경로에 배치
#    (Entry가 기대하는 구버전 계열을 맞추는 게 중요) 4
# ─────────────────────────────────────────────────────────────
# underscore 1.8.3
npm_pack_pick "underscore@1.8.3" "underscore-min.js" "$LIB/underscore/underscore-min.js" || true

# jquery 1.9.1
npm_pack_pick "jquery@1.9.1" "dist/jquery.min.js" "$LIB/jquery/jquery.min.js" || true

# jquery-ui 1.10.4 (파일 위치가 버전마다 달라서 통째로 두고, 우리가 쓰는 경로로 링크)
# npm pack 전체를 lib/jquery-ui 로 풀어놓고, 기대 경로에 복사 시도
mkdir -p "$LIB/jquery-ui"
npm_pack_copy_all "jquery-ui@1.10.4" "$LIB/jquery-ui" || true
# 흔한 위치 후보들
copy_if_exists "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" || true
copy_if_exists "$LIB/jquery-ui/jquery-ui.min.js" "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" || true

# lodash 4.17.10(문서에 4.17.10 언급) 5
npm_pack_pick "lodash@4.17.10" "lodash.min.js" "$LIB/lodash/dist/lodash.min.js" || true

# velocity 1.2.3 (패키지명 velocity-animate)
npm_pack_pick "velocity-animate@1.2.3" "velocity.min.js" "$LIB/velocity/velocity.min.js" || true

# CreateJS 계열(구버전): easeljs/preloadjs/soundjs
npm_pack_pick "easeljs@0.8.0" "lib/easeljs-0.8.0.min.js" "$LIB/EaselJS/lib/easeljs-0.8.0.min.js" || true
npm_pack_pick "preloadjs@0.6.0" "lib/preloadjs-0.6.0.min.js" "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js" || true
npm_pack_pick "soundjs@0.6.0" "lib/soundjs-0.6.0.min.js" "$LIB/SoundJS/lib/soundjs-0.6.0.min.js" || true
# flashaudioplugin은 soundjs 패키지에 없을 수 있어, 있으면 복사(없으면 무시)
npm_pack_pick "soundjs@0.6.0" "lib/flashaudioplugin-0.6.0.min.js" "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js" || true

# ─────────────────────────────────────────────────────────────
# 4) playentry 서버 포함 스크립트(문서/예시대로 /js 경로)
#    (기존 /lib/js/... 는 404가 많음) 6
# ─────────────────────────────────────────────────────────────
mkdir -p "$WWW/js/ws" "$WWW/js/textmode/python"
curl_get "https://playentry.org/js/jshint.js" "$WWW/js/ws/jshint.js" || true
curl_get "https://playentry.org/js/textmode/python/python.js" "$WWW/js/textmode/python/python.js" || true

# (locales.js는 환경마다 다를 수 있으니 "없어도 통과")
mkdir -p "$WWW/js/ws"
curl_get "https://playentry.org/js/ws/locales.js" "$WWW/js/ws/locales.js" || true

# ─────────────────────────────────────────────────────────────
# 5) entryjs <-> entry-js alias
# ─────────────────────────────────────────────────────────────
mkdir -p "$LIB/entryjs" "$LIB/entry-js"
( shopt -s dotglob nullglob; cp -R "$LIB/entryjs/"* "$LIB/entry-js/" 2>/dev/null || true )
( shopt -s dotglob nullglob; cp -R "$LIB/entry-js/"* "$LIB/entryjs/" 2>/dev/null || true )

# ─────────────────────────────────────────────────────────────
# 6) Summary
# ─────────────────────────────────────────────────────────────
if [ -s "$FAIL_LOG" ]; then
  COUNT="$(sort -u "$FAIL_LOG" | wc -l | tr -d ' ')"
  big "FETCH SUMMARY: $COUNT file(s) may be missing (script continued)"
  sort -u "$FAIL_LOG" | sed 's/^/ - /'
else
  log "✅ FETCH SUMMARY: OK (no missing logs)"
fi

exit 0
