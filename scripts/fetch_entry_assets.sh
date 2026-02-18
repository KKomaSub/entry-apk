#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# Config
# =========================
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

# =========================
# Parallel fetch (5개씩)
# =========================
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

# job queue (bash 병렬)
declare -a JOB_PIDS=()
declare -a JOB_DESC=()
job_add(){
  local url="$1" out="$2" desc="${3:-$out}"
  (
    _fetch_one "$url" "$out"
  ) &
  JOB_PIDS+=("$!")
  JOB_DESC+=("$desc")
  # MAX_JOBS 넘으면 하나 기다림
  while [ "${#JOB_PIDS[@]}" -ge "$MAX_JOBS" ]; do
    job_wait_one
  done
}
job_wait_one(){
  local pid="${JOB_PIDS[0]}"
  local desc="${JOB_DESC[0]}"
  if wait "$pid"; then
    :
  else
    bigwarn "FAILED: $desc (continued)"
    MISSING_COUNT=$((MISSING_COUNT+1))
  fi
  JOB_PIDS=("${JOB_PIDS[@]:1}")
  JOB_DESC=("${JOB_DESC[@]:1}")
}
job_wait_all(){
  while [ "${#JOB_PIDS[@]}" -gt 0 ]; do
    job_wait_one
  done
}

MISSING_COUNT=0

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"

# =========================
# 0) Base dirs
# =========================
mkdir -p \
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

# =========================
# 1) CDN libs (필수)
# =========================
job_add "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" \
        "$WWW/lib/lodash/dist/lodash.min.js" \
        "lodash 4.17.10"

job_add "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" \
        "$WWW/lib/jquery/jquery.min.js" \
        "jquery 1.9.1"

job_add "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" \
        "$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js" \
        "jquery-ui 1.10.4"

job_add "https://cdnjs.cloudflare.com/ajax/libs/underscore.js/1.8.3/underscore-min.js" \
        "$WWW/lib/underscore/underscore-min.js" \
        "underscore 1.8.3 (optional)"

job_add "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" \
        "$WWW/lib/velocity/velocity.min.js" \
        "velocity 1.2.3"

job_add "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css" \
        "$WWW/lib/codemirror/codemirror.css" \
        "codemirror css"

job_add "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js" \
        "$WWW/lib/codemirror/codemirror.js" \
        "codemirror js"

job_add "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js" \
        "$WWW/lib/codemirror/vim.js" \
        "codemirror vim (optional)"

# createjs
job_add "https://code.createjs.com/preloadjs-0.6.0.min.js" \
        "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" \
        "preloadjs 0.6.0"

job_add "https://code.createjs.com/easeljs-0.8.0.min.js" \
        "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js" \
        "easeljs 0.8.0"

job_add "https://code.createjs.com/soundjs-0.6.0.min.js" \
        "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js" \
        "soundjs 0.6.0"

# flash plugin은 요즘 CDN에서 404가 자주 나서 "옵션" 취급
job_add "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" \
        "$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
        "flashaudioplugin 0.6.0 (optional)"

# ws locales (있으면 좋음)
job_add "https://playentry.org/js/ws/locales.js" \
        "$WWW/js/ws/locales.js" \
        "ws/locales.js (optional but recommended)"

# =========================
# 2) playentry에서 정적파일 (필수)
# =========================
job_add "https://playentry.org/lib/entry-js/dist/entry.min.js" \
        "$WWW/lib/entryjs/dist/entry.min.js" \
        "entry.min.js"

job_add "https://playentry.org/lib/entry-js/dist/entry.css" \
        "$WWW/lib/entryjs/dist/entry.css" \
        "entry.css"

job_add "https://playentry.org/lib/entry-js/extern/lang/ko.js" \
        "$WWW/lib/entryjs/extern/lang/ko.js" \
        "ko.js"

job_add "https://playentry.org/lib/entry-js/extern/util/static.js" \
        "$WWW/lib/entryjs/extern/util/static.js" \
        "static.js"

job_add "https://playentry.org/lib/entry-js/extern/util/handle.js" \
        "$WWW/lib/entryjs/extern/util/handle.js" \
        "handle.js"

job_add "https://playentry.org/lib/entry-js/extern/util/bignumber.min.js" \
        "$WWW/lib/entryjs/extern/util/bignumber.min.js" \
        "bignumber.min.js"

job_add "https://playentry.org/lib/entry-tool/dist/entry-tool.js" \
        "$WWW/lib/entry-tool/dist/entry-tool.js" \
        "entry-tool.js"

job_add "https://playentry.org/lib/entry-tool/dist/entry-tool.css" \
        "$WWW/lib/entry-tool/dist/entry-tool.css" \
        "entry-tool.css"

job_add "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" \
        "$WWW/lib/entry-paint/dist/static/js/entry-paint.js" \
        "entry-paint.js"

# legacy video module
job_add "https://entry-cdn.pstatic.net/module/legacy-video/index.js" \
        "$WWW/lib/module/legacy-video/index.js" \
        "legacy-video/index.js"

job_wait_all

# =========================
# 3) NPM FULL EXTRACT (이미지/extern “완전복사”용)
#    - @entrylabs/entry 는 npm에 존재
#    - @entrylabs/tool 로 tool 이미지/리소스 확보 시도 (없어도 playentry CDN이 이미 있음)
# =========================
bigwarn "NPM FALLBACK: extracting packages to ensure images/media exist"

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

# 3-1) @entrylabs/entry FULL extract (핵심: images/media/extern)
ENTRY_PKG="$WWW/.npm_entry_pkg"
if npm_extract_pkg "@entrylabs/entry" "$ENTRY_PKG"; then
  # npm pack 결과는 $outdir/package/ 아래에 들어감
  if [ -d "$ENTRY_PKG/package" ]; then
    # entryjs 폴더로 "그대로 복사"
    # (dist/extern/images/media 등 전체)
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

# 3-2) tool package: @entrylabs/tool (정답)
TOOL_PKG="$WWW/.npm_tool_pkg"
if npm_extract_pkg "@entrylabs/tool" "$TOOL_PKG"; then
  # 필요하면 dist/resources 등을 여기서 추가 복사 가능
  log "NPM EXTRACT OK: @entrylabs/tool"
else
  # 여기서 실패해도 이미 playentry에서 entry-tool.js/css 받아왔으므로 중단 금지
  bigwarn "Skip @entrylabs/tool extract (CDN already fetched) (continued)"
fi

# 3-3) sound editor는 레포/버전에 따라 경로가 달라서
#      최소한 '폴더'는 보장(없으면 index.html에서 stub로 처리)
mkdir -p "$WWW/lib/external/sound"
if [ -f "$WWW/lib/external/sound/sound-editor.js" ]; then
  :
else
  # 없으면 그냥 둠 (index.html이 stub fallback)
  log "sound-editor.js not present (will be stubbed)"
fi

# alias copy: /lib/entry-js 와 /lib/entryjs 둘 다 맞춰줌
if [ -d "$WWW/lib/entryjs" ]; then
  rm -rf "$WWW/lib/entry-js"
  cp -a "$WWW/lib/entryjs" "$WWW/lib/entry-js"
  log "COPY OK: $WWW/lib/entryjs -> $WWW/lib/entry-js"
fi

# =========================
# Summary
# =========================
if [ "$MISSING_COUNT" -gt 0 ]; then
  bigwarn "FETCH SUMMARY: $MISSING_COUNT file(s) may be missing (script continued)"
else
  log "✅ FETCH SUMMARY: all downloads OK"
fi

exit 0
