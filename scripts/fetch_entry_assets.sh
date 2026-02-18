#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="$ROOT/www"
MAX_JOBS="${MAX_JOBS:-5}"

mkdir -p "$WWW"

log(){ echo "[$(date +'%H:%M:%S')] $*"; }
bigwarn(){
  echo
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $*"
  echo "████████████████████████████████████████████████████████████"
  echo
}

_fetch_one() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  if curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 -o "$out" "$url"; then
    log "OK   -> $out"
    return 0
  else
    log "MISS $url"
    return 1
  fi
}

declare -a JOB_PIDS=()
declare -a JOB_DESC=()
MISSING_COUNT=0

job_wait_one(){
  local pid="${JOB_PIDS[0]}"
  local desc="${JOB_DESC[0]}"
  if wait "$pid"; then :; else
    bigwarn "FAILED: $desc (continued)"
    MISSING_COUNT=$((MISSING_COUNT+1))
  fi
  JOB_PIDS=("${JOB_PIDS[@]:1}")
  JOB_DESC=("${JOB_DESC[@]:1}")
}

job_add(){
  local url="$1" out="$2" desc="${3:-$out}"
  (
    _fetch_one "$url" "$out"
  ) &
  JOB_PIDS+=("$!")
  JOB_DESC+=("$desc")
  while [ "${#JOB_PIDS[@]}" -ge "$MAX_JOBS" ]; do
    job_wait_one
  done
}

job_wait_all(){
  while [ "${#JOB_PIDS[@]}" -gt 0 ]; do
    job_wait_one
  done
}

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"

mkdir -p \
  "$WWW/lib/react" \
  "$WWW/lib" \
  "$WWW/js/ws" \
  "$WWW/lib/jquery" \
  "$WWW/lib/jquery-ui/ui/minified" \
  "$WWW/lib/lodash/dist" \
  "$WWW/lib/underscore" \
  "$WWW/lib/codemirror" \
  "$WWW/lib/PreloadJS/lib" \
  "$WWW/lib/EaselJS/lib" \
  "$WWW/lib/SoundJS/lib" \
  "$WWW/lib/velocity" \
  "$WWW/lib/entry-tool/dist" \
  "$WWW/lib/entry-paint/dist/static/js" \
  "$WWW/lib/module/legacy-video" \
  "$WWW/lib/external/sound" \
  "$WWW/lib/entryjs" \
  "$WWW/lib/entryjs/dist" \
  "$WWW/lib/entryjs/extern/lang" \
  "$WWW/lib/entryjs/extern/util"

# ---------- React (필수) ----------
# entry.min.js 내부에서 SoundEditor(React 기반)를 기대하는 버전이 많아서 반드시 포함
job_add "https://unpkg.com/react@16.14.0/umd/react.production.min.js" \
        "$WWW/lib/react/react.production.min.js" \
        "react 16.14.0"

job_add "https://unpkg.com/react-dom@16.14.0/umd/react-dom.production.min.js" \
        "$WWW/lib/react/react-dom.production.min.js" \
        "react-dom 16.14.0"

# ---------- CDN libs ----------
job_add "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" \
        "$WWW/lib/lodash/dist/lodash.min.js" "lodash 4.17.10"

job_add "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" \
        "$WWW/lib/jquery/jquery.min.js" "jquery 1.9.1"

job_add "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" \
        "$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js" "jquery-ui 1.10.4"

job_add "https://cdnjs.cloudflare.com/ajax/libs/underscore.js/1.8.3/underscore-min.js" \
        "$WWW/lib/underscore/underscore-min.js" "underscore 1.8.3 (optional)"

job_add "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" \
        "$WWW/lib/velocity/velocity.min.js" "velocity 1.2.3"

job_add "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css" \
        "$WWW/lib/codemirror/codemirror.css" "codemirror css"

job_add "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js" \
        "$WWW/lib/codemirror/codemirror.js" "codemirror js"

job_add "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js" \
        "$WWW/lib/codemirror/vim.js" "codemirror vim (optional)"

job_add "https://code.createjs.com/preloadjs-0.6.0.min.js" \
        "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" "preloadjs 0.6.0"

job_add "https://code.createjs.com/easeljs-0.8.0.min.js" \
        "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js" "easeljs 0.8.0"

job_add "https://code.createjs.com/soundjs-0.6.0.min.js" \
        "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js" "soundjs 0.6.0"

job_add "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" \
        "$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" "flashaudioplugin 0.6.0 (optional)"

job_add "https://playentry.org/js/ws/locales.js" \
        "$WWW/js/ws/locales.js" "ws/locales.js (optional)"

# ---------- playentry static ----------
job_add "https://playentry.org/lib/entry-js/dist/entry.min.js" \
        "$WWW/lib/entryjs/dist/entry.min.js" "entry.min.js"
job_add "https://playentry.org/lib/entry-js/dist/entry.css" \
        "$WWW/lib/entryjs/dist/entry.css" "entry.css"
job_add "https://playentry.org/lib/entry-js/extern/lang/ko.js" \
        "$WWW/lib/entryjs/extern/lang/ko.js" "ko.js"
job_add "https://playentry.org/lib/entry-js/extern/util/static.js" \
        "$WWW/lib/entryjs/extern/util/static.js" "static.js"
job_add "https://playentry.org/lib/entry-js/extern/util/handle.js" \
        "$WWW/lib/entryjs/extern/util/handle.js" "handle.js"
job_add "https://playentry.org/lib/entry-js/extern/util/bignumber.min.js" \
        "$WWW/lib/entryjs/extern/util/bignumber.min.js" "bignumber.min.js"

job_add "https://playentry.org/lib/entry-tool/dist/entry-tool.js" \
        "$WWW/lib/entry-tool/dist/entry-tool.js" "entry-tool.js"
job_add "https://playentry.org/lib/entry-tool/dist/entry-tool.css" \
        "$WWW/lib/entry-tool/dist/entry-tool.css" "entry-tool.css"

job_add "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" \
        "$WWW/lib/entry-paint/dist/static/js/entry-paint.js" "entry-paint.js"

job_add "https://entry-cdn.pstatic.net/module/legacy-video/index.js" \
        "$WWW/lib/module/legacy-video/index.js" "legacy-video/index.js"

# ---------- sound-editor.js (가능하면 로컬화) ----------
# 경로/버전이 바뀔 수 있어서 "시도만" 하고 실패해도 계속
job_add "https://playentry.org/lib/external/sound/sound-editor.js" \
        "$WWW/lib/external/sound/sound-editor.js" "sound-editor.js (try 1, optional)"
job_add "https://entry-cdn.pstatic.net/lib/external/sound/sound-editor.js" \
        "$WWW/lib/external/sound/sound-editor.js" "sound-editor.js (try 2, optional)"

job_wait_all

# ---------- FULL extract: @entrylabs/entry ----------
bigwarn "NPM FALLBACK: extracting @entrylabs/entry (images/media/extern full copy)"

export NPM_CONFIG_USERCONFIG=/dev/null
export NPM_CONFIG_FUND=false
export NPM_CONFIG_AUDIT=false
export NPM_CONFIG_PROGRESS=false
export NPM_CONFIG_LOGLEVEL=error
unset NODE_AUTH_TOKEN || true
unset NPM_TOKEN || true

npm_extract_pkg () {
  local spec="$1" outdir="$2"
  mkdir -p "$outdir"
  log "NPM EXTRACT: $spec -> $outdir"
  if ! tarball="$(npm pack "$spec" 2>/dev/null | tail -n 1)"; then
    bigwarn "npm pack failed: $spec (continued)"
    return 1
  fi
  tar -xf "$tarball" -C "$outdir"
  rm -f "$tarball"
  return 0
}

ENTRY_PKG="$WWW/.npm_entry_pkg"
if npm_extract_pkg "@entrylabs/entry" "$ENTRY_PKG"; then
  if [ -d "$ENTRY_PKG/package" ]; then
    rm -rf "$WWW/lib/entryjs"
    mkdir -p "$WWW/lib/entryjs"
    cp -a "$ENTRY_PKG/package/." "$WWW/lib/entryjs/"
    log "COPY OK: FULL @entrylabs/entry -> $WWW/lib/entryjs"
  else
    bigwarn "unexpected npm pack layout for @entrylabs/entry (continued)"
  fi
else
  bigwarn "cannot extract @entrylabs/entry (images may break) (continued)"
fi

# alias: entry-js도 맞춰줌
if [ -d "$WWW/lib/entryjs" ]; then
  rm -rf "$WWW/lib/entry-js"
  cp -a "$WWW/lib/entryjs" "$WWW/lib/entry-js"
  log "COPY OK: $WWW/lib/entryjs -> $WWW/lib/entry-js"
fi

if [ "$MISSING_COUNT" -gt 0 ]; then
  bigwarn "FETCH SUMMARY: $MISSING_COUNT file(s) may be missing (script continued)"
else
  log "✅ FETCH SUMMARY: all downloads OK"
fi
# ---------- EXTRA: mirror ALL nested assets to absolute paths (/images, /media, /uploads) ----------
# (다른 부분 수정 금지 요청에 따라, 여기만 "추가"합니다)

bigwarn "ASSET MIRROR: entryjs/images/** -> www/images/** (recursive), media/uploads too"

mkdir -p "$WWW/images" "$WWW/media" "$WWW/uploads" || true

# 1) lib/entryjs/images/**  -> www/images/**
if [ -d "$WWW/lib/entryjs/images" ]; then
  cp -a "$WWW/lib/entryjs/images/." "$WWW/images/" || true
  log "MIRROR OK: $WWW/lib/entryjs/images/** -> $WWW/images/**"
fi

# 2) lib/entryjs/media/** -> www/media/**
if [ -d "$WWW/lib/entryjs/media" ]; then
  cp -a "$WWW/lib/entryjs/media/." "$WWW/media/" || true
  log "MIRROR OK: $WWW/lib/entryjs/media/** -> $WWW/media/**"
fi

# 3) lib/entryjs/uploads/** -> www/uploads/** (있으면)
if [ -d "$WWW/lib/entryjs/uploads" ]; then
  cp -a "$WWW/lib/entryjs/uploads/." "$WWW/uploads/" || true
  log "MIRROR OK: $WWW/lib/entryjs/uploads/** -> $WWW/uploads/**"
fi

# 4) 혹시 images가 다른 위치에 있을 경우(패키지 구조 차이 대비)
#    - src/images, res/images 등이 있으면 전부 합쳐 넣기
for cand in \
  "$WWW/lib/entryjs/src/images" \
  "$WWW/lib/entryjs/res/images" \
  "$WWW/lib/entryjs/resources/images" \
  "$WWW/lib/entryjs/static/images" \
  "$WWW/lib/entryjs/public/images"
do
  if [ -d "$cand" ]; then
    cp -a "$cand/." "$WWW/images/" || true
    log "MIRROR OK: $cand/** -> $WWW/images/**"
  fi
done

# 5) 검증 로그(하위폴더 대표 파일)
if [ -f "$WWW/images/icon/block_icon.png" ]; then
  log "VERIFY OK: images/icon/block_icon.png exists"
else
  bigwarn "VERIFY FAIL: images/icon/block_icon.png still missing"
  # 디버깅용: 실제 lib/entryjs/images 하위에 무엇이 있는지 출력
  if [ -d "$WWW/lib/entryjs/images" ]; then
    log "DEBUG: listing lib/entryjs/images/icon (if exists)"
    ls -la "$WWW/lib/entryjs/images/icon" 2>/dev/null || true
  fi
fi
exit 0
