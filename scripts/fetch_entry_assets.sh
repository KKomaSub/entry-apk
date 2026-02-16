#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"

LIB="$WWW/lib"
JS="$WWW/js"

mkdir -p "$LIB" "$JS"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

# fetch_try <out> <url1> [url2 ...]
fetch_try() {
  local out="$1"; shift
  mkdir -p "$(dirname "$out")"

  for url in "$@"; do
    log "GET  $url"
    if curl -L --retry 5 --retry-delay 2 --fail -o "$out" "$url"; then
      log "OK   -> $out"
      return 0
    fi
    log "MISS $url"
  done

  log "FAIL all candidates -> $out"
  return 1
}
# --- compatibility wrapper ---
# 파일 안에 fetch "URL" "OUT" 호출이 남아있어도 동작하게
fetch() {
  local url="$1"
  local out="$2"
  fetch_try "$out" "$url"
}
require_file() {
  local f="$1"
  if [ ! -f "$f" ]; then
    log "❌ MISSING: $f"
    return 1
  fi
  return 0
}

# CDN 후보
P1="https://playentry.org"
P2="https://entry-cdn.pstatic.net"
GH_RAW="https://raw.githubusercontent.com"

log "=== Fetch EntryJS workspace deps (Docs checklist enforced) ==="

# ---------------------------
# CSS (필수)  1
# ---------------------------
fetch_try "$LIB/entry-tool/dist/entry-tool.css" \
  "$P1/lib/entry-tool/dist/entry-tool.css" \
  "$P2/lib/entry-tool/dist/entry-tool.css"

fetch_try "$LIB/entry-js/dist/entry.css" \
  "$P1/lib/entry-js/dist/entry.css" \
  "$P2/lib/entry-js/dist/entry.css"

# ---------------------------
# language (필수) 2
# ---------------------------
fetch_try "$LIB/entry-js/extern/lang/ko.js" \
  "$P1/lib/entry-js/extern/lang/ko.js" \
  "$P2/lib/entry-js/extern/lang/ko.js"

# ---------------------------
# lodash (필수)
# ---------------------------
fetch_try "$LIB/lodash/dist/lodash.min.js" \
  "$P1/lib/lodash/dist/lodash.min.js" \
  "$P2/lib/lodash/dist/lodash.min.js"

# ---------------------------
# locales.js (필수) — 저장 경로는 문서대로 www/js/ws/locales.js
fetch_try "$JS/ws/locales.js" \
  "$P1/js/ws/locales.js" \
  "$P2/js/ws/locales.js" \
  "$P1/lib/js/ws/locales.js" \
  "$P2/lib/js/ws/locales.js" \
  "https://raw.githubusercontent.com/entrylabs/entryjs/develop/example/js/ws/locales.js" \
  "https://raw.githubusercontent.com/entrylabs/entryjs/master/example/js/ws/locales.js"

# ---------------------------
# react18 (필수)
# ---------------------------
fetch_try "$JS/react18/react.production.min.js" \
  "$P1/lib/js/react18/react.production.min.js" \
  "$P2/js/react18/react.production.min.js"

fetch_try "$JS/react18/react-dom.production.min.js" \
  "$P1/lib/js/react18/react-dom.production.min.js" \
  "$P2/js/react18/react-dom.production.min.js"

# ---------------------------
# CreateJS (필수)
# ---------------------------
fetch_try "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "$P1/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "$P2/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"

fetch_try "$LIB/EaselJS/lib/easeljs-0.8.0.min.js" \
  "$P1/lib/EaselJS/lib/easeljs-0.8.0.min.js" \
  "$P2/lib/EaselJS/lib/easeljs-0.8.0.min.js"

fetch_try "$LIB/SoundJS/lib/soundjs-0.6.0.min.js" \
  "$P1/lib/SoundJS/lib/soundjs-0.6.0.min.js" \
  "$P2/lib/SoundJS/lib/soundjs-0.6.0.min.js"

fetch_try "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "$P1/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "$P2/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js"

# ---------------------------
# jquery / jquery-ui / velocity (필수)
# ---------------------------
fetch_try "$LIB/jquery/jquery.min.js" \
  "$P1/lib/jquery/jquery.min.js" \
  "$P2/lib/jquery/jquery.min.js"

fetch_try "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P1/lib/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P2/lib/jquery-ui/ui/minified/jquery-ui.min.js"

fetch_try "$LIB/velocity/velocity.min.js" \
  "$P1/lib/velocity/velocity.min.js" \
  "$P2/lib/velocity/velocity.min.js"

# ---------------------------
# CodeMirror (필수)
# ---------------------------
fetch_try "$LIB/codemirror/lib/codemirror.js" \
  "$P1/lib/codemirror/lib/codemirror.js" \
  "$P2/lib/codemirror/lib/codemirror.js"

fetch_try "$LIB/codemirror/addon/hint/show-hint.js" \
  "$P1/lib/codemirror/addon/hint/show-hint.js" \
  "$P2/lib/codemirror/addon/hint/show-hint.js"

fetch_try "$LIB/codemirror/addon/lint/lint.js" \
  "$P1/lib/codemirror/addon/lint/lint.js" \
  "$P2/lib/codemirror/addon/lint/lint.js"

fetch_try "$LIB/codemirror/addon/selection/active-line.js" \
  "$P1/lib/codemirror/addon/selection/active-line.js" \
  "$P2/lib/codemirror/addon/selection/active-line.js"

fetch_try "$LIB/codemirror/mode/javascript/javascript.js" \
  "$P1/lib/codemirror/mode/javascript/javascript.js" \
  "$P2/lib/codemirror/mode/javascript/javascript.js"

fetch_try "$LIB/codemirror/addon/hint/javascript-hint.js" \
  "$P1/lib/codemirror/addon/hint/javascript-hint.js" \
  "$P2/lib/codemirror/addon/hint/javascript-hint.js"

# ---------------------------
# jshint / python (필수)  ※ 문서에 “js/ws/”로 표기 4
# 현실에서는 /js/.. 로 운영되는 경우도 있어 후보 추가
# ---------------------------
fetch_try "$JS/ws/jshint.js" \
  "$P1/js/ws/jshint.js" \
  "$P2/js/ws/jshint.js" \
  "$P1/lib/js/ws/jshint.js" \
  "$P2/lib/js/ws/jshint.js" \
  "$P1/js/jshint.js"

fetch_try "$JS/ws/python.js" \
  "$P1/js/ws/python.js" \
  "$P2/js/ws/python.js" \
  "$P1/lib/js/ws/python.js" \
  "$P2/lib/js/ws/python.js" \
  "$P1/js/textmode/python/python.js"

# ---------------------------
# fuzzy / socket.io-client (필수)
# ---------------------------
fetch_try "$LIB/fuzzy/lib/fuzzy.js" \
  "$P1/lib/fuzzy/lib/fuzzy.js" \
  "$P2/lib/fuzzy/lib/fuzzy.js"

fetch_try "$LIB/socket.io-client/socket.io.js" \
  "$P1/lib/socket.io-client/socket.io.js" \
  "$P2/lib/socket.io-client/socket.io.js"

# ---------------------------
# entry extern utils (필수)
# ---------------------------
fetch_try "$LIB/entry-js/extern/util/filbert.js" \
  "$P1/lib/entry-js/extern/util/filbert.js" \
  "$P2/lib/entry-js/extern/util/filbert.js"

fetch_try "$LIB/entry-js/extern/util/CanvasInput.js" \
  "$P1/lib/entry-js/extern/util/CanvasInput.js" \
  "$P2/lib/entry-js/extern/util/CanvasInput.js"

fetch_try "$LIB/entry-js/extern/util/ndgmr.Collision.js" \
  "$P1/lib/entry-js/extern/util/ndgmr.Collision.js" \
  "$P2/lib/entry-js/extern/util/ndgmr.Collision.js"

fetch_try "$LIB/entry-js/extern/util/handle.js" \
  "$P1/lib/entry-js/extern/util/handle.js" \
  "$P2/lib/entry-js/extern/util/handle.js"

fetch_try "$LIB/entry-js/extern/util/bignumber.min.js" \
  "$P1/lib/entry-js/extern/util/bignumber.min.js" \
  "$P2/lib/entry-js/extern/util/bignumber.min.js"

# webfontloader (필수)
fetch_try "$LIB/components-webfontloader/webfontloader.js" \
  "$P1/lib/components-webfontloader/webfontloader.js" \
  "$P2/lib/components-webfontloader/webfontloader.js"

# entry-lms (문서 예시에 포함: 필수로 체크) 5
fetch_try "$LIB/entry-lms/dist/assets/app.js" \
  "$P1/lib/entry-lms/dist/assets/app.js" \
  "$P2/lib/entry-lms/dist/assets/app.js"

# static.js (필수) 6
fetch_try "$LIB/entry-js/extern/util/static.js" \
  "$P1/lib/entry-js/extern/util/static.js" \
  "$P2/lib/entry-js/extern/util/static.js"

# entry-tool / entry-paint (필수) 7
fetch_try "$LIB/entry-tool/dist/entry-tool.js" \
  "$P1/lib/entry-tool/dist/entry-tool.js" \
  "$P2/lib/entry-tool/dist/entry-tool.js"

fetch_try "$LIB/entry-paint/dist/static/js/entry-paint.js" \
  "$P1/lib/entry-paint/dist/static/js/entry-paint.js" \
  "$P2/lib/entry-paint/dist/static/js/entry-paint.js"

# sound-editor (문서 예시에는 포함) 8
# 없을 수도 있어서 optional
fetch_try "$WWW/external/sound/sound-editor.js" \
  "$P1/external/sound/sound-editor.js" \
  "$P2/external/sound/sound-editor.js" || true

# entry.min.js (필수) 9
fetch_try "$LIB/entry-js/dist/entry.min.js" \
  "$P1/lib/entry-js/dist/entry.min.js" \
  "$P2/lib/entry-js/dist/entry.min.js"

# ---------------------------
# ✅ Docs 필수 항목 검증 (누락 0 강제) 10
# ---------------------------
log "=== Verify required files (Docs checklist) ==="

REQ=(
  "$LIB/entry-tool/dist/entry-tool.css"
  "$LIB/entry-js/dist/entry.css"
  "$LIB/entry-js/extern/lang/ko.js"
  "$LIB/lodash/dist/lodash.min.js"
  "$JS/ws/locales.js"
  "$JS/react18/react.production.min.js"
  "$JS/react18/react-dom.production.min.js"
  "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js"
  "$LIB/EaselJS/lib/easeljs-0.8.0.min.js"
  "$LIB/SoundJS/lib/soundjs-0.6.0.min.js"
  "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js"
  "$LIB/jquery/jquery.min.js"
  "$LIB/jquery-ui/ui/minified/jquery-ui.min.js"
  "$LIB/velocity/velocity.min.js"
  "$LIB/codemirror/lib/codemirror.js"
  "$LIB/codemirror/addon/hint/show-hint.js"
  "$LIB/codemirror/addon/lint/lint.js"
  "$LIB/codemirror/addon/selection/active-line.js"
  "$LIB/codemirror/mode/javascript/javascript.js"
  "$LIB/codemirror/addon/hint/javascript-hint.js"
  "$JS/ws/jshint.js"
  "$LIB/fuzzy/lib/fuzzy.js"
  "$JS/ws/python.js"
  "$LIB/socket.io-client/socket.io.js"
  "$LIB/entry-js/extern/util/filbert.js"
  "$LIB/entry-js/extern/util/CanvasInput.js"
  "$LIB/entry-js/extern/util/ndgmr.Collision.js"
  "$LIB/entry-js/extern/util/handle.js"
  "$LIB/entry-js/extern/util/bignumber.min.js"
  "$LIB/components-webfontloader/webfontloader.js"
  "$LIB/entry-lms/dist/assets/app.js"
  "$LIB/entry-js/extern/util/static.js"
  "$LIB/entry-tool/dist/entry-tool.js"
  "$LIB/entry-paint/dist/static/js/entry-paint.js"
  "$LIB/entry-js/dist/entry.min.js"
)

MISSING=0
for f in "${REQ[@]}"; do
  if ! require_file "$f"; then
    MISSING=$((MISSING+1))
  fi
done

if [ "$MISSING" -ne 0 ]; then
  log "❌ Verification failed. Missing files: $MISSING"
  exit 1
fi

log "✅ All required files present (per Entry Docs run example)."
log "Output root: $WWW"}

# 필수 파일 존재 체크
require_file() {
  local f="$1"
  if [ ! -f "$f" ]; then
    log "❌ MISSING: $f"
    return 1
  fi
  return 0
}

# -------------------------
# CDN 후보 (문서에서 entry-cdn.pstatic.net 사용 가능 명시) 1
# -------------------------
P1="https://playentry.org"
P2="https://entry-cdn.pstatic.net"

# -------------------------
# 출력 경로 규칙
# - 문서 예시의 path/to/lib/... , path/to/js/... 형태를 그대로 맞춤 2
# -------------------------
LIB="$WWW/lib"
JS="$WWW/js"

log "=== Fetch EntryJS workspace dependencies (doc checklist) ==="

# =========================================================
# [A] CSS (필수) 3
# =========================================================
fetch_try "$LIB/entry-tool/dist/entry-tool.css" \
  "$P1/lib/entry-tool/dist/entry-tool.css" \
  "$P2/lib/entry-tool/dist/entry-tool.css"

fetch_try "$LIB/entry-js/dist/entry.css" \
  "$P1/lib/entry-js/dist/entry.css" \
  "$P2/lib/entry-js/dist/entry.css"

# =========================================================
# [B] 언어 (필수) 4
# =========================================================
fetch_try "$LIB/entry-js/extern/lang/ko.js" \
  "$P1/lib/entry-js/extern/lang/ko.js" \
  "$P2/lib/entry-js/extern/lang/ko.js"

# =========================================================
# [C] 문서 기준 의존성 목록 (필수) 5
# =========================================================
# lodash
fetch_try "$LIB/lodash/dist/lodash.min.js" \
  "$P1/lib/lodash/dist/lodash.min.js" \
  "$P2/lib/lodash/dist/lodash.min.js"

# locales.js (404 자주 나서 후보 여러개)
fetch_try "$JS/ws/locales.js" \
  "$P1/lib/js/ws/locales.js" \
  "$P2/js/ws/locales.js" \
  "$P1/lib/js/locales.js" \
  "$P2/js/locales.js"

# react18
fetch_try "$JS/react18/react.production.min.js" \
  "$P1/lib/js/react18/react.production.min.js" \
  "$P2/js/react18/react.production.min.js"

fetch_try "$JS/react18/react-dom.production.min.js" \
  "$P1/lib/js/react18/react-dom.production.min.js" \
  "$P2/js/react18/react-dom.production.min.js"

# PreloadJS / EaselJS / SoundJS
fetch_try "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "$P1/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "$P2/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"

fetch_try "$LIB/EaselJS/lib/easeljs-0.8.0.min.js" \
  "$P1/lib/EaselJS/lib/easeljs-0.8.0.min.js" \
  "$P2/lib/EaselJS/lib/easeljs-0.8.0.min.js"

fetch_try "$LIB/SoundJS/lib/soundjs-0.6.0.min.js" \
  "$P1/lib/SoundJS/lib/soundjs-0.6.0.min.js" \
  "$P2/lib/SoundJS/lib/soundjs-0.6.0.min.js"

fetch_try "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "$P1/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "$P2/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js"

# jquery / jquery-ui / velocity
fetch_try "$LIB/jquery/jquery.min.js" \
  "$P1/lib/jquery/jquery.min.js" \
  "$P2/lib/jquery/jquery.min.js"

fetch_try "$LIB/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P1/lib/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P2/lib/jquery-ui/ui/minified/jquery-ui.min.js"

fetch_try "$LIB/velocity/velocity.min.js" \
  "$P1/lib/velocity/velocity.min.js" \
  "$P2/lib/velocity/velocity.min.js"

# CodeMirror + addons + mode + hints
fetch_try "$LIB/codemirror/lib/codemirror.js" \
  "$P1/lib/codemirror/lib/codemirror.js" \
  "$P2/lib/codemirror/lib/codemirror.js"

fetch_try "$LIB/codemirror/addon/hint/show-hint.js" \
  "$P1/lib/codemirror/addon/hint/show-hint.js" \
  "$P2/lib/codemirror/addon/hint/show-hint.js"

fetch_try "$LIB/codemirror/addon/lint/lint.js" \
  "$P1/lib/codemirror/addon/lint/lint.js" \
  "$P2/lib/codemirror/addon/lint/lint.js"

fetch_try "$LIB/codemirror/addon/selection/active-line.js" \
  "$P1/lib/codemirror/addon/selection/active-line.js" \
  "$P2/lib/codemirror/addon/selection/active-line.js"

fetch_try "$LIB/codemirror/mode/javascript/javascript.js" \
  "$P1/lib/codemirror/mode/javascript/javascript.js" \
  "$P2/lib/codemirror/mode/javascript/javascript.js"

fetch_try "$LIB/codemirror/addon/hint/javascript-hint.js" \
  "$P1/lib/codemirror/addon/hint/javascript-hint.js" \
  "$P2/lib/codemirror/addon/hint/javascript-hint.js"

# jshint / fuzzy / python
fetch_try "$JS/ws/jshint.js" \
  "$P1/lib/js/ws/jshint.js" \
  "$P2/js/ws/jshint.js"

fetch_try "$LIB/fuzzy/lib/fuzzy.js" \
  "$P1/lib/fuzzy/lib/fuzzy.js" \
  "$P2/lib/fuzzy/lib/fuzzy.js"

fetch_try "$JS/ws/python.js" \
  "$P1/lib/js/ws/python.js" \
  "$P2/js/ws/python.js"

# socket.io-client
fetch_try "$LIB/socket.io-client/socket.io.js" \
  "$P1/lib/socket.io-client/socket.io.js" \
  "$P2/lib/socket.io-client/socket.io.js"

# entry extern util들
fetch_try "$LIB/entry-js/extern/util/filbert.js" \
  "$P1/lib/entry-js/extern/util/filbert.js" \
  "$P2/lib/entry-js/extern/util/filbert.js"

fetch_try "$LIB/entry-js/extern/util/CanvasInput.js" \
  "$P1/lib/entry-js/extern/util/CanvasInput.js" \
  "$P2/lib/entry-js/extern/util/CanvasInput.js"

fetch_try "$LIB/entry-js/extern/util/ndgmr.Collision.js" \
  "$P1/lib/entry-js/extern/util/ndgmr.Collision.js" \
  "$P2/lib/entry-js/extern/util/ndgmr.Collision.js"

fetch_try "$LIB/entry-js/extern/util/handle.js" \
  "$P1/lib/entry-js/extern/util/handle.js" \
  "$P2/lib/entry-js/extern/util/handle.js"

fetch_try "$LIB/entry-js/extern/util/bignumber.min.js" \
  "$P1/lib/entry-js/extern/util/bignumber.min.js" \
  "$P2/lib/entry-js/extern/util/bignumber.min.js"

# webfontloader
fetch_try "$LIB/components-webfontloader/webfontloader.js" \
  "$P1/lib/components-webfontloader/webfontloader.js" \
  "$P2/lib/components-webfontloader/webfontloader.js"

# entry-lms (문서 예시에 포함) — 일부 기능에서만 필요할 수 있으나, 문서 예시대로 받음 6
fetch_try "$LIB/entry-lms/dist/assets/app.js" \
  "$P1/lib/entry-lms/dist/assets/app.js" \
  "$P2/lib/entry-lms/dist/assets/app.js"

# static.js (필수) 7
fetch_try "$LIB/entry-js/extern/util/static.js" \
  "$P1/lib/entry-js/extern/util/static.js" \
  "$P2/lib/entry-js/extern/util/static.js"

# entry-tool js (필수)
fetch_try "$LIB/entry-tool/dist/entry-tool.js" \
  "$P1/lib/entry-tool/dist/entry-tool.js" \
  "$P2/lib/entry-tool/dist/entry-tool.js"

# entry-paint (필수)
fetch_try "$LIB/entry-paint/dist/static/js/entry-paint.js" \
  "$P1/lib/entry-paint/dist/static/js/entry-paint.js" \
  "$P2/lib/entry-paint/dist/static/js/entry-paint.js"

# sound-editor (문서 예시에는 external/sound/sound-editor.js 라고만 되어 있음 → 존재하면 받기, 없어도 진행) 8
# (필요해지면 index.html에서 해당 스크립트 태그를 켜면 됩니다)
fetch_try "$WWW/external/sound/sound-editor.js" \
  "$P1/external/sound/sound-editor.js" \
  "$P2/external/sound/sound-editor.js" || true

# 마지막: entry.min.js (필수)
fetch_try "$LIB/entry-js/dist/entry.min.js" \
  "$P1/lib/entry-js/dist/entry.min.js" \
  "$P2/lib/entry-js/dist/entry.min.js"

# =========================================================
# [D] 문서 “필수 항목 리스트” 체크 (누락 0 보장) 9
# =========================================================
log "=== Verify required files (doc checklist) ==="

REQ=(
  "$LIB/entry-tool/dist/entry-tool.css"
  "$LIB/entry-js/dist/entry.css"
  "$LIB/entry-js/extern/lang/ko.js"
  "$LIB/lodash/dist/lodash.min.js"
  "$JS/ws/locales.js"
  "$JS/react18/react.production.min.js"
  "$JS/react18/react-dom.production.min.js"
  "$LIB/PreloadJS/lib/preloadjs-0.6.0.min.js"
  "$LIB/EaselJS/lib/easeljs-0.8.0.min.js"
  "$LIB/SoundJS/lib/soundjs-0.6.0.min.js"
  "$LIB/SoundJS/lib/flashaudioplugin-0.6.0.min.js"
  "$LIB/jquery/jquery.min.js"
  "$LIB/jquery-ui/ui/minified/jquery-ui.min.js"
  "$LIB/velocity/velocity.min.js"
  "$LIB/codemirror/lib/codemirror.js"
  "$LIB/codemirror/addon/hint/show-hint.js"
  "$LIB/codemirror/addon/lint/lint.js"
  "$LIB/codemirror/addon/selection/active-line.js"
  "$LIB/codemirror/mode/javascript/javascript.js"
  "$LIB/codemirror/addon/hint/javascript-hint.js"
  "$JS/ws/jshint.js"
  "$LIB/fuzzy/lib/fuzzy.js"
  "$JS/ws/python.js"
  "$LIB/socket.io-client/socket.io.js"
  "$LIB/entry-js/extern/util/filbert.js"
  "$LIB/entry-js/extern/util/CanvasInput.js"
  "$LIB/entry-js/extern/util/ndgmr.Collision.js"
  "$LIB/entry-js/extern/util/handle.js"
  "$LIB/entry-js/extern/util/bignumber.min.js"
  "$LIB/components-webfontloader/webfontloader.js"
  "$LIB/entry-lms/dist/assets/app.js"
  "$LIB/entry-js/extern/util/static.js"
  "$LIB/entry-tool/dist/entry-tool.js"
  "$LIB/entry-paint/dist/static/js/entry-paint.js"
  "$LIB/entry-js/dist/entry.min.js"
)

MISSING=0
for f in "${REQ[@]}"; do
  if ! require_file "$f"; then
    MISSING=$((MISSING+1))
  fi
done

if [ "$MISSING" -ne 0 ]; then
  log "❌ Verification failed. Missing files: $MISSING"
  exit 1
fi

log "✅ All required files present (per Entry Docs run example)."
log "Output root: $WWW"  "$P1/lib/entry-js/dist/entry.min.js" \
  "$P2/lib/entry-js/dist/entry.min.js"

fetch_try "$WWW/lib/entry-js/dist/entry.css" \
  "$P1/lib/entry-js/dist/entry.css" \
  "$P2/lib/entry-js/dist/entry.css"

# language + static
fetch_try "$WWW/lib/entry-js/extern/lang/ko.js" \
  "$P1/lib/entry-js/extern/lang/ko.js" \
  "$P2/lib/entry-js/extern/lang/ko.js"

fetch_try "$WWW/lib/entry-js/extern/util/static.js" \
  "$P1/lib/entry-js/extern/util/static.js" \
  "$P2/lib/entry-js/extern/util/static.js"

# tool / paint
fetch_try "$WWW/lib/entry-tool/dist/entry-tool.js" \
  "$P1/lib/entry-tool/dist/entry-tool.js" \
  "$P2/lib/entry-tool/dist/entry-tool.js"

fetch_try "$WWW/lib/entry-tool/dist/entry-tool.css" \
  "$P1/lib/entry-tool/dist/entry-tool.css" \
  "$P2/lib/entry-tool/dist/entry-tool.css"

fetch_try "$WWW/lib/entry-paint/dist/static/js/entry-paint.js" \
  "$P1/lib/entry-paint/dist/static/js/entry-paint.js" \
  "$P2/lib/entry-paint/dist/static/js/entry-paint.js"

# ---------------------------
# Dependencies from docs
# (Entry Docs "실행하기" 예시 기준) 1
# ---------------------------

# lodash
fetch_try "$WWW/lib/lodash/dist/lodash.min.js" \
  "$P1/lib/lodash/dist/lodash.min.js" \
  "$P2/lib/lodash/dist/lodash.min.js"

# locales.js (경로 변경 잦음)
fetch_try "$WWW/js/ws/locales.js" \
  "$P1/lib/js/ws/locales.js" \
  "$P2/js/ws/locales.js" \
  "$P1/lib/js/locales.js" \
  "$P2/js/locales.js"

# react18
fetch_try "$WWW/js/react18/react.production.min.js" \
  "$P1/lib/js/react18/react.production.min.js" \
  "$P2/js/react18/react.production.min.js"

fetch_try "$WWW/js/react18/react-dom.production.min.js" \
  "$P1/lib/js/react18/react-dom.production.min.js" \
  "$P2/js/react18/react-dom.production.min.js"

# createjs 계열(PreloadJS/EaselJS/SoundJS)
fetch_try "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "$P1/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "$P2/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"

fetch_try "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js" \
  "$P1/lib/EaselJS/lib/easeljs-0.8.0.min.js" \
  "$P2/lib/EaselJS/lib/easeljs-0.8.0.min.js"

fetch_try "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js" \
  "$P1/lib/SoundJS/lib/soundjs-0.6.0.min.js" \
  "$P2/lib/SoundJS/lib/soundjs-0.6.0.min.js"

fetch_try "$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "$P1/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "$P2/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js"

# jquery + jquery-ui
fetch_try "$WWW/lib/jquery/jquery.min.js" \
  "$P1/lib/jquery/jquery.min.js" \
  "$P2/lib/jquery/jquery.min.js"

fetch_try "$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P1/lib/jquery-ui/ui/minified/jquery-ui.min.js" \
  "$P2/lib/jquery-ui/ui/minified/jquery-ui.min.js"

# velocity
fetch_try "$WWW/lib/velocity/velocity.min.js" \
  "$P1/lib/velocity/velocity.min.js" \
  "$P2/lib/velocity/velocity.min.js"

# codemirror (최소 필수 파일들)
fetch_try "$WWW/lib/codemirror/lib/codemirror.js" \
  "$P1/lib/codemirror/lib/codemirror.js" \
  "$P2/lib/codemirror/lib/codemirror.js"

fetch_try "$WWW/lib/codemirror/addon/hint/show-hint.js" \
  "$P1/lib/codemirror/addon/hint/show-hint.js" \
  "$P2/lib/codemirror/addon/hint/show-hint.js"

fetch_try "$WWW/lib/codemirror/addon/lint/lint.js" \
  "$P1/lib/codemirror/addon/lint/lint.js" \
  "$P2/lib/codemirror/addon/lint/lint.js"

fetch_try "$WWW/lib/codemirror/addon/selection/active-line.js" \
  "$P1/lib/codemirror/addon/selection/active-line.js" \
  "$P2/lib/codemirror/addon/selection/active-line.js"

fetch_try "$WWW/lib/codemirror/mode/javascript/javascript.js" \
  "$P1/lib/codemirror/mode/javascript/javascript.js" \
  "$P2/lib/codemirror/mode/javascript/javascript.js"

fetch_try "$WWW/lib/codemirror/addon/hint/javascript-hint.js" \
  "$P1/lib/codemirror/addon/hint/javascript-hint.js" \
  "$P2/lib/codemirror/addon/hint/javascript-hint.js"

# jshint / fuzzy / python
fetch_try "$WWW/js/ws/jshint.js" \
  "$P1/lib/js/ws/jshint.js" \
  "$P2/js/ws/jshint.js"

fetch_try "$WWW/lib/fuzzy/lib/fuzzy.js" \
  "$P1/lib/fuzzy/lib/fuzzy.js" \
  "$P2/lib/fuzzy/lib/fuzzy.js"

fetch_try "$WWW/js/ws/python.js" \
  "$P1/lib/js/ws/python.js" \
  "$P2/js/ws/python.js"

# socket.io-client
fetch_try "$WWW/lib/socket.io-client/socket.io.js" \
  "$P1/lib/socket.io-client/socket.io.js" \
  "$P2/lib/socket.io-client/socket.io.js"

# entry extern utils
fetch_try "$WWW/lib/entry-js/extern/util/filbert.js" \
  "$P1/lib/entry-js/extern/util/filbert.js" \
  "$P2/lib/entry-js/extern/util/filbert.js"

fetch_try "$WWW/lib/entry-js/extern/util/CanvasInput.js" \
  "$P1/lib/entry-js/extern/util/CanvasInput.js" \
  "$P2/lib/entry-js/extern/util/CanvasInput.js"

fetch_try "$WWW/lib/entry-js/extern/util/ndgmr.Collision.js" \
  "$P1/lib/entry-js/extern/util/ndgmr.Collision.js" \
  "$P2/lib/entry-js/extern/util/ndgmr.Collision.js"

fetch_try "$WWW/lib/entry-js/extern/util/handle.js" \
  "$P1/lib/entry-js/extern/util/handle.js" \
  "$P2/lib/entry-js/extern/util/handle.js"

fetch_try "$WWW/lib/entry-js/extern/util/bignumber.min.js" \
  "$P1/lib/entry-js/extern/util/bignumber.min.js" \
  "$P2/lib/entry-js/extern/util/bignumber.min.js"

# webfontloader
fetch_try "$WWW/lib/components-webfontloader/webfontloader.js" \
  "$P1/lib/components-webfontloader/webfontloader.js" \
  "$P2/lib/components-webfontloader/webfontloader.js"

# entry-lms (있으면 기능 일부에서 요구)
fetch_try "$WWW/lib/entry-lms/dist/assets/app.js" \
  "$P1/lib/entry-lms/dist/assets/app.js" \
  "$P2/lib/entry-lms/dist/assets/app.js" || true

echo "✅ fetch complete: $WWW"# ==========================
fetch "https://playentry.org/lib/entry-js/extern/lang/ko.js" \
      "$WWW/lib/entry-js/extern/lang/ko.js"

fetch "https://playentry.org/lib/entry-js/extern/util/static.js" \
      "$WWW/lib/entry-js/extern/util/static.js"

# ==========================
# Tool / Paint
# ==========================
fetch "https://playentry.org/lib/entry-tool/dist/entry-tool.js" \
      "$WWW/lib/entry-tool/dist/entry-tool.js"

fetch "https://playentry.org/lib/entry-tool/dist/entry-tool.css" \
      "$WWW/lib/entry-tool/dist/entry-tool.css"

fetch "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" \
      "$WWW/lib/entry-paint/dist/static/js/entry-paint.js"

# ==========================
# Workspace 의존성
# ==========================
fetch "https://playentry.org/lib/lodash/dist/lodash.min.js" \
      "$WWW/lib/lodash/dist/lodash.min.js"



fetch "https://entry-cdn.pstatic.net/js/ws/locales.js" \
      "$WWW/lib/js/ws/locales.js"

# React 18
fetch "https://playentry.org/lib/js/react18/react.production.min.js" \
      "$WWW/lib/js/react18/react.production.min.js"

fetch "https://playentry.org/lib/js/react18/react-dom.production.min.js" \
      "$WWW/lib/js/react18/react-dom.production.min.js"

echo "=== Fetch Completed ==="
