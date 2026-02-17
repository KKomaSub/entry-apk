#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="$ROOT/www"

log(){ echo "[$(date +'%H:%M:%S')] $*"; }

log "=== FULL ENTRYJS COPY MODE ==="
log "ROOT=$ROOT"
log "WWW =$WWW"

mkdir -p "$WWW/lib"

# ---------------------------------
# 1️⃣ 기존 entryjs 제거
# ---------------------------------
rm -rf "$WWW/lib/entryjs"
rm -rf "$WWW/.entry_pkg"

# ---------------------------------
# 2️⃣ entryjs npm 패키지 전체 다운로드
# ---------------------------------
log "Downloading @entrylabs/entry..."

PKG_TGZ=$(npm pack @entrylabs/entry | tail -n1)

mkdir -p "$WWW/.entry_pkg"
tar -xzf "$PKG_TGZ" -C "$WWW/.entry_pkg"
rm "$PKG_TGZ"

# ---------------------------------
# 3️⃣ entryjs 전체 복사
# ---------------------------------
log "Copying FULL entry package..."
cp -r "$WWW/.entry_pkg/package" "$WWW/lib/entryjs"

# ---------------------------------
# 4️⃣ 정리
# ---------------------------------
rm -rf "$WWW/.entry_pkg"

log "ENTRYJS FULL COPY DONE"

# ---------------------------------
# 5️⃣ 기타 필수 라이브러리 (CDN)
# ---------------------------------

mkdir -p "$WWW/lib/lodash/dist"
mkdir -p "$WWW/lib/jquery"
mkdir -p "$WWW/lib/jquery-ui/ui/minified"
mkdir -p "$WWW/lib/PreloadJS/lib"
mkdir -p "$WWW/lib/EaselJS/lib"
mkdir -p "$WWW/lib/SoundJS/lib"
mkdir -p "$WWW/lib/velocity"

curl -fsSL https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js \
  -o "$WWW/lib/lodash/dist/lodash.min.js"

curl -fsSL https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js \
  -o "$WWW/lib/jquery/jquery.min.js"

curl -fsSL https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js \
  -o "$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js"

curl -fsSL https://code.createjs.com/preloadjs-0.6.0.min.js \
  -o "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"

curl -fsSL https://code.createjs.com/easeljs-0.8.0.min.js \
  -o "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js"

curl -fsSL https://code.createjs.com/soundjs-0.6.0.min.js \
  -o "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js" || true

curl -fsSL https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js \
  -o "$WWW/lib/velocity/velocity.min.js"

log "Other dependencies downloaded"

echo "████████████████████████████████████"
echo "✅ ENTRYJS FULL COPY COMPLETE"
echo "████████████████████████████████████"
