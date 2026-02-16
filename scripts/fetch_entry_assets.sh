#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WWW="$ROOT/www"

mkdir -p "$WWW/lib/entry-js/dist" "$WWW/lib/entry-js/extern/lang" "$WWW/lib/entry-js/extern/util"
mkdir -p "$WWW/lib/entry-tool/dist"
mkdir -p "$WWW/lib/entry-paint/dist/static/js"

# 1) EntryJS/EntryTool/EntryPaint는 playentry CDN에도 배포됨(문서에 언급) 5
#    가장 단순하게는 playentry의 lib 경로에서 가져오면 됨.
curl -L --retry 5 -o "$WWW/lib/entry-js/dist/entry.min.js" "https://playentry.org/lib/entry-js/dist/entry.min.js"
curl -L --retry 5 -o "$WWW/lib/entry-js/dist/entry.css" "https://playentry.org/lib/entry-js/dist/entry.css"

curl -L --retry 5 -o "$WWW/lib/entry-js/extern/lang/ko.js" "https://playentry.org/lib/entry-js/extern/lang/ko.js"
curl -L --retry 5 -o "$WWW/lib/entry-js/extern/util/static.js" "https://playentry.org/lib/entry-js/extern/util/static.js"

curl -L --retry 5 -o "$WWW/lib/entry-tool/dist/entry-tool.js" "https://playentry.org/lib/entry-tool/dist/entry-tool.js"
curl -L --retry 5 -o "$WWW/lib/entry-tool/dist/entry-tool.css" "https://playentry.org/lib/entry-tool/dist/entry-tool.css"

curl -L --retry 5 -o "$WWW/lib/entry-paint/dist/static/js/entry-paint.js" "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js"

echo "✅ entry assets fetched into www/lib"
