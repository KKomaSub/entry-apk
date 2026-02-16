#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"

mkdir -p "$WWW/lib" "$WWW/js"

# ---- helpers ----
fetch_try() {
  local out="$1"; shift
  mkdir -p "$(dirname "$out")"

  for url in "$@"; do
    echo "GET $url"
    if curl -L --retry 5 --retry-delay 2 --fail -o "$out" "$url"; then
      echo "OK -> $out"
      return 0
    fi
    echo "MISS: $url"
  done

  echo "❌ Failed all URLs for $out"
  return 1
}

# CDN base 후보들 (playentry 경로가 바뀌면 pstatic이 살아있는 경우가 많음)
P1="https://playentry.org"
P2="https://entry-cdn.pstatic.net"

echo "=== Fetch EntryJS (workspace) full deps ==="

# ---------------------------
# Entry core / css
# ---------------------------
fetch_try "$WWW/lib/entry-js/dist/entry.min.js" \
  "$P1/lib/entry-js/dist/entry.min.js" \
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

# locales는 경로가 자주 바뀜 → 2곳 시도
fetch "https://playentry.org/lib/js/ws/locales.js" \
      "$WWW/lib/js/ws/locales.js"

fetch "https://entry-cdn.pstatic.net/js/ws/locales.js" \
      "$WWW/lib/js/ws/locales.js"

# React 18
fetch "https://playentry.org/lib/js/react18/react.production.min.js" \
      "$WWW/lib/js/react18/react.production.min.js"

fetch "https://playentry.org/lib/js/react18/react-dom.production.min.js" \
      "$WWW/lib/js/react18/react-dom.production.min.js"

echo "=== Fetch Completed ==="
