#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"

mkdir -p "$WWW/lib"

fetch() {
  local url="$1"
  local out="$2"

  mkdir -p "$(dirname "$out")"

  echo "Downloading $url"

  if curl -L --retry 3 --retry-delay 2 -f -o "$out" "$url"; then
    echo "OK"
  else
    echo "⚠ Failed: $url"
  fi
}

echo "=== Fetch Entry Web Assets ==="

# ==========================
# EntryJS Core
# ==========================
fetch "https://playentry.org/lib/entry-js/dist/entry.min.js" \
      "$WWW/lib/entry-js/dist/entry.min.js"

fetch "https://playentry.org/lib/entry-js/dist/entry.css" \
      "$WWW/lib/entry-js/dist/entry.css"

# ==========================
# Extern
# ==========================
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
