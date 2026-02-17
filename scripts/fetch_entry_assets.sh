#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="$ROOT/www"
MAX_JOBS="${MAX_JOBS:-6}"

log(){ echo "[$(date +'%H:%M:%S')] $*"; }
mkdir -p "$WWW/lib" "$WWW/js/ws" "$WWW/bundle" "$WWW/lib/module" "$WWW/lib/external/sound"

# ---------- helpers ----------
curl_get() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  if curl -fsSL --retry 3 --retry-delay 1 -o "$out" "$url"; then
    log "OK   -> $out"
    return 0
  fi
  log "MISS $url"
  return 1
}

# npm tarball extract (no npm install needed)
npm_extract_pkg() {
  local spec="$1" outdir="$2"
  mkdir -p "$outdir"
  log "NPM TARBALL: $spec -> $outdir"
  # fetch tarball url then download+extract
  local tarurl
  tarurl="$(node -e "require('https').get('https://registry.npmjs.org/${spec//@/}%2f${spec#*@}', r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>{let j=JSON.parse(d);let v='${spec#*@}'; if(v==='$spec') v=j['dist-tags'].latest; console.log(j.versions[v].dist.tarball);});}).on('error',e=>{console.error(e);process.exit(1);})" 2>/dev/null || true)"

  # 위 한줄이 spec 형태에 따라 안맞을 수 있어 fallback:
  if [[ -z "$tarurl" ]]; then
    tarurl="$(npm view "$spec" dist.tarball)"
  fi

  curl -fsSL --retry 3 --retry-delay 1 "$tarurl" -o "$outdir/pkg.tgz"
  tar -xzf "$outdir/pkg.tgz" -C "$outdir"
}

copy_if_exists() {
  local src="$1" dst="$2"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
    log "COPY OK: $src -> $dst"
  fi
}

log "=== Fetch Entry assets (hard vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"

# ---------- 1) 반드시 필요한 패키지들: entry / entry-tool / entry-paint ----------
TMP="$WWW/.pkgs"
rm -rf "$TMP"
mkdir -p "$TMP"

# @entrylabs/entry 에는 images/extern 등이 들어있고, dist는 최신이 아닐 수 있어도 extern/이미지용으로 강제 사용
npm_extract_pkg "@entrylabs/entry@latest" "$TMP/entry"
npm_extract_pkg "@entrylabs/entry-tool@latest" "$TMP/entry-tool" || true
npm_extract_pkg "@entrylabs/entry-paint@latest" "$TMP/entry-paint" || true

# package/ 아래가 실제 내용
ENTRY_P="$TMP/entry/package"
ETOOL_P="$TMP/entry-tool/package"
EPAINT_P="$TMP/entry-paint/package"

# ---------- 2) entryjs extern/images는 npm에서 복사 ----------
copy_if_exists "$ENTRY_P/images" "$WWW/lib/entryjs/images"
copy_if_exists "$ENTRY_P/extern" "$WWW/lib/entryjs/extern"

# ---------- 3) dist(entry.min.js/entry.css)는 playentry의 최신 배포를 우선으로 강제 다운로드 ----------
mkdir -p "$WWW/lib/entryjs/dist"
curl_get "https://playentry.org/lib/entry-js/dist/entry.min.js" "$WWW/lib/entryjs/dist/entry.min.js"
curl_get "https://playentry.org/lib/entry-js/dist/entry.css"    "$WWW/lib/entryjs/dist/entry.css"

# ---------- 4) entry-tool / entry-paint는 배포본 다운로드(우선) ----------
mkdir -p "$WWW/lib/entry-tool/dist"
curl_get "https://playentry.org/lib/entry-tool/dist/entry-tool.js"  "$WWW/lib/entry-tool/dist/entry-tool.js"
curl_get "https://playentry.org/lib/entry-tool/dist/entry-tool.css" "$WWW/lib/entry-tool/dist/entry-tool.css"

mkdir -p "$WWW/lib/entry-paint/dist/static/js"
curl_get "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" \
         "$WWW/lib/entry-paint/dist/static/js/entry-paint.js"

# ---------- 5) legacy video ----------
mkdir -p "$WWW/lib/module/legacy-video"
curl_get "https://entry-cdn.pstatic.net/module/legacy-video/index.js" \
         "$WWW/lib/module/legacy-video/index.js"

# ---------- 6) ws locales ----------
mkdir -p "$WWW/js/ws"
curl_get "https://playentry.org/js/ws/locales.js" "$WWW/js/ws/locales.js" || true

# ---------- 7) 외부 라이브러리(확실한 CDN) ----------
curl_get "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" \
         "$WWW/lib/lodash/dist/lodash.min.js"

curl_get "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" \
         "$WWW/lib/jquery/jquery.min.js"

curl_get "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" \
         "$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js"

curl_get "https://code.createjs.com/preloadjs-0.6.0.min.js" \
         "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
curl_get "https://code.createjs.com/easeljs-0.8.0.min.js" \
         "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js"
curl_get "https://code.createjs.com/soundjs-0.6.0.min.js" \
         "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js"

# flashaudioplugin은 없어도 되게(그냥 자리만)
mkdir -p "$WWW/lib/SoundJS/lib"
if ! curl_get "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" \
              "$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js"; then
  log "MISS flashaudioplugin(optional)"
fi

curl_get "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" \
         "$WWW/lib/velocity/velocity.min.js"

# CodeMirror
curl_get "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css" \
         "$WWW/lib/codemirror/codemirror.css"
curl_get "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js" \
         "$WWW/lib/codemirror/codemirror.js"
curl_get "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js" \
         "$WWW/lib/codemirror/vim.js" || true

# sound-editor.js 는 현재 프로젝트에서 관리(있으면 유지). 없으면 stub 생성
if [[ ! -f "$WWW/lib/external/sound/sound-editor.js" ]]; then
  cat > "$WWW/lib/external/sound/sound-editor.js" <<'JS'
window.EntrySoundEditor = window.EntrySoundEditor || {};
window.EntrySoundEditor.renderSoundEditor = function(){ return null; };
JS
  log "WROTE stub sound-editor.js"
fi

log "=== DONE ==="
log "Check: ls -al $WWW/lib/lodash/dist/lodash.min.js"
