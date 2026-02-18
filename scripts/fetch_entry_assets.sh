#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-5}"

echo "=== FULL ENTRYJS OFFLINE COPY MODE ==="
echo "ROOT=${ROOT}"
echo "WWW =${WWW}"

mkdir -p "${WWW}/lib"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

########################################
# 1️⃣ entryjs 전체 복사 (npm tarball)
########################################

echo
echo "████████████████████████████████████████████████████████████"
echo "📦 extracting FULL @entrylabs/entry (ALL FILES)"
echo "████████████████████████████████████████████████████████████"
echo

cd "$TMP_DIR"

# 최신 버전 tarball 다운로드
npm pack @entrylabs/entry >/dev/null

TAR_FILE=$(ls *.tgz)

mkdir entry_pkg
tar -xzf "$TAR_FILE" -C entry_pkg

# 기존 entryjs 제거 후 전체 복사
rm -rf "${WWW}/lib/entryjs"
mkdir -p "${WWW}/lib/entryjs"

cp -R entry_pkg/package/* "${WWW}/lib/entryjs/"

echo "✅ entryjs FULL COPY COMPLETE"

########################################
# 2️⃣ entry-tool 전체 복사
########################################

echo
echo "📦 extracting FULL @entrylabs/entry-tool"
echo

rm -f *.tgz
npm pack @entrylabs/entry-tool >/dev/null
TAR_FILE=$(ls *.tgz)

mkdir entry_tool_pkg
tar -xzf "$TAR_FILE" -C entry_tool_pkg

rm -rf "${WWW}/lib/entry-tool"
mkdir -p "${WWW}/lib/entry-tool"
cp -R entry_tool_pkg/package/* "${WWW}/lib/entry-tool/"

echo "✅ entry-tool FULL COPY COMPLETE"

########################################
# 3️⃣ entry-paint 전체 복사
########################################

echo
echo "📦 extracting FULL @entrylabs/entry-paint"
echo

rm -f *.tgz
npm pack @entrylabs/entry-paint >/dev/null
TAR_FILE=$(ls *.tgz)

mkdir entry_paint_pkg
tar -xzf "$TAR_FILE" -C entry_paint_pkg

rm -rf "${WWW}/lib/entry-paint"
mkdir -p "${WWW}/lib/entry-paint"
cp -R entry_paint_pkg/package/* "${WWW}/lib/entry-paint/"

echo "✅ entry-paint FULL COPY COMPLETE"

########################################
# 4️⃣ React / ReactDOM (sound-editor용)
########################################

echo
echo "📦 fetching React (for sound-editor)"
echo

mkdir -p "${WWW}/lib/react"

curl -L --fail -o "${WWW}/lib/react/react.production.min.js" \
  https://unpkg.com/react@16.14.0/umd/react.production.min.js

curl -L --fail -o "${WWW}/lib/react/react-dom.production.min.js" \
  https://unpkg.com/react-dom@16.14.0/umd/react-dom.production.min.js

echo "✅ React downloaded"

########################################
# 5️⃣ 기타 외부 라이브러리
########################################

echo
echo "📦 fetching external libs"
echo

mkdir -p "${WWW}/lib/lodash/dist"
mkdir -p "${WWW}/lib/jquery"
mkdir -p "${WWW}/lib/jquery-ui/ui/minified"
mkdir -p "${WWW}/lib/PreloadJS/lib"
mkdir -p "${WWW}/lib/EaselJS/lib"
mkdir -p "${WWW}/lib/SoundJS/lib"
mkdir -p "${WWW}/lib/velocity"
mkdir -p "${WWW}/lib/codemirror"

curl -L -o "${WWW}/lib/lodash/dist/lodash.min.js" \
  https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js

curl -L -o "${WWW}/lib/jquery/jquery.min.js" \
  https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js

curl -L -o "${WWW}/lib/jquery-ui/ui/minified/jquery-ui.min.js" \
  https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js

curl -L -o "${WWW}/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  https://code.createjs.com/preloadjs-0.6.0.min.js

curl -L -o "${WWW}/lib/EaselJS/lib/easeljs-0.8.0.min.js" \
  https://code.createjs.com/easeljs-0.8.0.min.js

curl -L -o "${WWW}/lib/SoundJS/lib/soundjs-0.6.0.min.js" \
  https://code.createjs.com/soundjs-0.6.0.min.js || true

curl -L -o "${WWW}/lib/velocity/velocity.min.js" \
  https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js

curl -L -o "${WWW}/lib/codemirror/codemirror.js" \
  https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js

curl -L -o "${WWW}/lib/codemirror/codemirror.css" \
  https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css

echo "✅ external libs fetched"

########################################
# 6️⃣ ws/locales
########################################

mkdir -p "${WWW}/js/ws"

curl -L -o "${WWW}/js/ws/locales.js" \
  https://playentry.org/js/ws/locales.js || true

echo
echo "████████████████████████████████████████████████████████████"
echo "🎉 FULL OFFLINE ENTRY BUILD READY"
echo "████████████████████████████████████████████████████████████"
echo
