#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"

mkdir -p "$WWW/lib"

fetch () {
  local url="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  echo "GET $url"
  curl -L --retry 5 --retry-delay 2 --fail -o "$out" "$url"
}

# =========================
# EntryJS core + css
# =========================
fetch "https://playentry.org/lib/entry-js/dist/entry.min.js" "$WWW/lib/entry-js/dist/entry.min.js"
fetch "https://playentry.org/lib/entry-js/dist/entry.css"    "$WWW/lib/entry-js/dist/entry.css"

# extern (최소 필수)
fetch "https://playentry.org/lib/entry-js/extern/lang/ko.js"     "$WWW/lib/entry-js/extern/lang/ko.js"
fetch "https://playentry.org/lib/entry-js/extern/util/static.js" "$WWW/lib/entry-js/extern/util/static.js"

# =========================
# Entry Tool / Paint
# =========================
fetch "https://playentry.org/lib/entry-tool/dist/entry-tool.js"  "$WWW/lib/entry-tool/dist/entry-tool.js"
fetch "https://playentry.org/lib/entry-tool/dist/entry-tool.css" "$WWW/lib/entry-tool/dist/entry-tool.css"

fetch "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" "$WWW/lib/entry-paint/dist/static/js/entry-paint.js"

# =========================
# Workspace 필수 의존성 (문서 예시 기반)
# - lodash
# - locales
# - react18 / react-dom18
# =========================
fetch "https://playentry.org/lib/lodash/dist/lodash.min.js" "$WWW/lib/lodash/dist/lodash.min.js"
fetch "https://playentry.org/lib/js/ws/locales.js"         "$WWW/lib/js/ws/locales.js"
fetch "https://playentry.org/lib/js/react18/react.production.min.js"     "$WWW/lib/js/react18/react.production.min.js"
fetch "https://playentry.org/lib/js/react18/react-dom.production.min.js" "$WWW/lib/js/react18/react-dom.production.min.js"

echo "✅ fetch complete: $WWW/lib"# ==========================================
# 문서에서 이 라이브러리들이 CDN으로 배포된다고 안내함 2
# 우선 playentry.org/lib 경로로 받고, 실패하면 entry-cdn.pstatic.net에서 받도록 fallback.

# lodash
if curl -L --fail -o /dev/null -sI "https://playentry.org/lib/lodash/dist/lodash.min.js"; then
  fetch "https://playentry.org/lib/lodash/dist/lodash.min.js" "$WWW/lib/lodash/dist/lodash.min.js"
else
  fetch "https://entry-cdn.pstatic.net/lodash/dist/lodash.min.js" "$WWW/lib/lodash/dist/lodash.min.js"
fi

# locales.js
if curl -L --fail -o /dev/null -sI "https://playentry.org/lib/js/ws/locales.js"; then
  fetch "https://playentry.org/lib/js/ws/locales.js" "$WWW/lib/js/ws/locales.js"
else
  fetch "https://entry-cdn.pstatic.net/js/ws/locales.js" "$WWW/lib/js/ws/locales.js"
fi

# react18
if curl -L --fail -o /dev/null -sI "https://playentry.org/lib/js/react18/react.production.min.js"; then
  fetch "https://playentry.org/lib/js/react18/react.production.min.js" "$WWW/lib/js/react18/react.production.min.js"
  fetch "https://playentry.org/lib/js/react18/react-dom.production.min.js" "$WWW/lib/js/react18/react-dom.production.min.js"
else
  fetch "https://entry-cdn.pstatic.net/js/react18/react.production.min.js" "$WWW/lib/js/react18/react.production.min.js"
  fetch "https://entry-cdn.pstatic.net/js/react18/react-dom.production.min.js" "$WWW/lib/js/react18/react-dom.production.min.js"
fi

echo "✅ fetch complete. Files under: $WWW/lib"
