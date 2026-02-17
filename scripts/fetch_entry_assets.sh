#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="$ROOT/www"
MAX_JOBS=5

FAILED=0
log(){ echo "[$(date +'%H:%M:%S')] $*"; }

mkdir -p "$WWW" "$WWW/lib" "$WWW/js/ws"

# -----------------------
# 병렬 제한
# -----------------------
wait_jobs() {
  while [ "$(jobs -r | wc -l | tr -d ' ')" -ge "$MAX_JOBS" ]; do
    sleep 0.15
  done
}

# -----------------------
# 병렬 fetch (실패해도 계속)
# -----------------------
fetch() {
  local url="$1"
  local out="$2"
  (
    mkdir -p "$(dirname "$out")"
    if curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$out"; then
      log "OK   -> $out"
    else
      echo "████████████████████████████████████████████████████████████"
      echo "🚨🚨🚨 MISS $url"
      echo "████████████████████████████████████████████████████████████"
      FAILED=$((FAILED+1))
    fi
  ) &
  wait_jobs
}

# -----------------------
# www 기본 파일 보장
# -----------------------
mkdir -p "$WWW"
if [ ! -f "$WWW/overrides.css" ]; then
  cat > "$WWW/overrides.css" <<'CSS'
/* 화면 깨짐/크기 보정용 */
html, body { height:100%; }
#entryContainer { width:100%; height:100%; }
CSS
  log "WROTE $WWW/overrides.css"
fi

# index.html은 이미 갖고 계시면 그대로 두고, 없을 때만 생성
if [ ! -f "$WWW/index.html" ]; then
  cat > "$WWW/index.html" <<'HTML'
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Entry Offline Editor</title>
  <link rel="stylesheet" href="./lib/entry-tool/dist/entry-tool.css" />
  <link rel="stylesheet" href="./lib/entryjs/dist/entry.css" />
  <link rel="stylesheet" href="./lib/codemirror/codemirror.css" />
  <link rel="stylesheet" href="./overrides.css" />
</head>
<body style="margin:0; height:100%; overflow:hidden;">
  <div id="entryContainer" style="height:100%"></div>
  <script src="./js/ws/locales.js"></script>

  <script src="./lib/lodash/dist/lodash.min.js"></script>
  <script src="./lib/jquery/jquery.min.js"></script>
  <script src="./lib/jquery-ui/ui/minified/jquery-ui.min.js"></script>

  <script src="./lib/PreloadJS/lib/preloadjs-0.6.0.min.js"></script>
  <script src="./lib/EaselJS/lib/easeljs-0.8.0.min.js"></script>
  <script src="./lib/SoundJS/lib/soundjs-0.6.0.min.js"></script>

  <script src="./lib/velocity/velocity.min.js"></script>

  <script src="./lib/codemirror/codemirror.js"></script>
  <script src="./lib/codemirror/vim.js"></script>

  <script src="./lib/entry-tool/dist/entry-tool.js"></script>

  <script src="./lib/entryjs/extern/lang/ko.js"></script>
  <script src="./lib/entryjs/extern/util/static.js"></script>
  <script src="./lib/entryjs/extern/util/handle.js"></script>
  <script src="./lib/entryjs/extern/util/bignumber.min.js"></script>

  <script src="./lib/module/legacy-video/index.js"></script>
  <script src="./lib/external/sound/sound-editor.js"></script>

  <script src="./lib/entryjs/dist/entry.min.js"></script>
  <script src="./lib/entry-paint/dist/static/js/entry-paint.js"></script>

  <script>
    Entry.init(document.getElementById("entryContainer"), {
      type: "workspace",
      libDir: "./lib",
      textCodingEnable: true
    });
    Entry.loadProject();
  </script>
</body>
</html>
HTML
  log "WROTE $WWW/index.html"
fi

log "=== Fetch Entry assets (parallel x$MAX_JOBS) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"

# -----------------------
# 1) entryjs 전체 통째 복사 (@entrylabs/entry)
# -----------------------
rm -rf "$WWW/lib/entryjs" "$WWW/.entry_pkg"
mkdir -p "$WWW/.entry_pkg"

log "NPM pack @entrylabs/entry (full copy)"
PKG_TGZ="$(npm pack @entrylabs/entry | tail -n1)"
tar -xzf "$PKG_TGZ" -C "$WWW/.entry_pkg"
rm -f "$PKG_TGZ"

# package/* -> lib/entryjs
cp -r "$WWW/.entry_pkg/package" "$WWW/lib/entryjs"
rm -rf "$WWW/.entry_pkg"

# -----------------------
# 2) 나머지 필수 파일들 다운로드 (MISS 나면 화면 깨짐/EntryTool undefined)
# -----------------------

# entry-tool / entry-paint (playentry에서 직접)
fetch "https://playentry.org/lib/entry-tool/dist/entry-tool.js"  "$WWW/lib/entry-tool/dist/entry-tool.js"
fetch "https://playentry.org/lib/entry-tool/dist/entry-tool.css" "$WWW/lib/entry-tool/dist/entry-tool.css"
fetch "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" "$WWW/lib/entry-paint/dist/static/js/entry-paint.js"

# locales (없으면 일부 UI/문구 깨질 수 있음)
fetch "https://playentry.org/js/ws/locales.js" "$WWW/js/ws/locales.js"

# legacy-video (EntryVideoLegacy 필요)
fetch "https://entry-cdn.pstatic.net/module/legacy-video/index.js" "$WWW/lib/module/legacy-video/index.js"

# lodash/jquery 등 (entryjs가 기대하는 것들)
fetch "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" "$WWW/lib/lodash/dist/lodash.min.js"
fetch "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" "$WWW/lib/jquery/jquery.min.js"
fetch "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" "$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js"

# CreateJS
fetch "https://code.createjs.com/preloadjs-0.6.0.min.js" "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
fetch "https://code.createjs.com/easeljs-0.8.0.min.js" "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js"
fetch "https://code.createjs.com/soundjs-0.6.0.min.js" "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js"

# flashaudioplugin은 없어도 동작 가능(옵션)
fetch "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" "$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" || true

# velocity
fetch "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" "$WWW/lib/velocity/velocity.min.js"

# CodeMirror (textCodingEnable 켜면 필수)
fetch "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css" "$WWW/lib/codemirror/codemirror.css"
fetch "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js" "$WWW/lib/codemirror/codemirror.js"
fetch "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js" "$WWW/lib/codemirror/vim.js" || true

# -----------------------
# 3) sound-editor.js (없으면 EntrySoundEditor 관련 크래시)
# - 일단은 "stub(비활성)"로라도 만들어두면 Entry가 죽진 않음
# -----------------------
mkdir -p "$WWW/lib/external/sound"
if [ ! -f "$WWW/lib/external/sound/sound-editor.js" ]; then
  cat > "$WWW/lib/external/sound/sound-editor.js" <<'JS'
window.EntrySoundEditor = window.EntrySoundEditor || {};
// Entry가 내부에서 호출하는 인터페이스만 최소로 제공 (죽지 않게)
window.EntrySoundEditor.renderSoundEditor = function(){ return null; };
JS
  log "WROTE $WWW/lib/external/sound/sound-editor.js (stub)"
fi

# -----------------------
# 병렬 다운로드 끝까지 대기
# -----------------------
wait

if [ "$FAILED" -gt 0 ]; then
  echo "████████████████████████████████████████████████████"
  echo "🚨 FETCH SUMMARY: $FAILED file(s) missing (script continued)"
  echo "████████████████████████████████████████████████████"
else
  log "✅ FETCH SUMMARY: all downloads OK"
fi

# 마지막: www가 비었다고 느껴지면 여기서 확인 가능
log "WWW listing (top):"
ls -al "$WWW" | sed -n '1,120p' || true
