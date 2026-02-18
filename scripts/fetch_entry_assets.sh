#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Fetch Entry assets (offline vendoring)
# - Parallel downloads (default 5)
# - Copy FULL entryjs extern/images/media from GitHub zip (raw)
# - Ensure dist/entry.min.js + dist/entry.css exist (CDN fallback)
# - NEVER write to absolute filesystem paths like /uploads (fix)
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-5}"

mkdir -p "${WWW}"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

bigwarn() {
  echo
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $*"
  echo "████████████████████████████████████████████████████████████"
  echo
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { bigwarn "Missing command: $1"; exit 1; }
}
need_cmd curl
need_cmd unzip
need_cmd rsync

# --- job pool ------------------------------------------------
pids=()
job_spawn() { ("$@") & pids+=("$!"); job_throttle; }
job_throttle() {
  while [ "${#pids[@]}" -ge "${MAX_JOBS}" ]; do
    for i in "${!pids[@]}"; do
      if ! kill -0 "${pids[$i]}" 2>/dev/null; then
        wait "${pids[$i]}" || true
        unset 'pids[i]'
        pids=("${pids[@]}")
        break
      fi
    done
    sleep 0.05
  done
}
job_wait_all() {
  local rc=0
  for pid in "${pids[@]}"; do
    wait "$pid" || rc=1
  done
  pids=()
  return $rc
}

# --- path normalize ------------------------------------------
# Convert "/uploads/font/a.woff" -> "uploads/font/a.woff"
# Convert "./x" -> "x"
relpath() {
  local p="$1"
  p="${p#./}"
  p="${p#/}"   # CRITICAL: never allow absolute paths like /uploads
  echo "$p"
}

ensure_parent() { mkdir -p "$(dirname "$1")"; }

curl_get() {
  local url="$1" dest="$2"
  ensure_parent "$dest"
  if curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 "$url" -o "${dest}.tmp"; then
    mv -f "${dest}.tmp" "$dest"
    log "OK   -> $dest"
    return 0
  else
    rm -f "${dest}.tmp" || true
    log "MISS $url"
    return 1
  fi
}

fetch_with_candidates() {
  local dest_rel="$1"; shift
  local dest="${WWW}/$(relpath "$dest_rel")"
  local ok=1
  for url in "$@"; do
    log "GET  $url"
    if curl_get "$url" "$dest"; then ok=0; break; fi
  done
  if [ $ok -ne 0 ]; then
    bigwarn "FAIL all candidates -> ${dest_rel}"
    echo "Tried:"
    for url in "$@"; do echo " - $url"; done
    return 1
  fi
  return 0
}

fetch_optional() {
  local dest_rel="$1"; shift
  if ! fetch_with_candidates "$dest_rel" "$@"; then
    bigwarn "OPTIONAL missing: $(basename "$dest_rel") (continuing)"
    return 0
  fi
  return 0
}

extract_zip_url() {
  local url="$1" outdir="$2"
  rm -rf "$outdir"
  mkdir -p "$outdir"
  local zip="${outdir}.zip"
  log "DOWNLOAD ZIP $url"
  curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$zip"
  unzip -q "$zip" -d "$outdir"
  rm -f "$zip"
}

# ============================================================
# 0) Start
# ============================================================
log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=${ROOT}"
log "WWW =${WWW}"
log "MAX_JOBS=${MAX_JOBS}"

# ============================================================
# 1) entryjs: extern/images/media 는 GitHub ZIP에서 '그대로 복사'
#    dist는 repo에 없거나(빌드 산출물) 비어있을 수 있어 CDN로 보강
# ============================================================
ENTRYJS_REF="${ENTRYJS_REF:-develop}"
ENTRYJS_ZIP="https://codeload.github.com/entrylabs/entryjs/zip/refs/heads/${ENTRYJS_REF}"
TMP_ENTRYJS="${WWW}/.tmp_entryjs"

bigwarn "FULL COPY entryjs extern/images/media from GitHub (${ENTRYJS_REF})"
extract_zip_url "$ENTRYJS_ZIP" "$TMP_ENTRYJS"
ENTRYJS_ROOT_DIR="$(find "$TMP_ENTRYJS" -maxdepth 1 -type d -name "entryjs-*" | head -n 1)"
if [ -z "${ENTRYJS_ROOT_DIR}" ] || [ ! -d "${ENTRYJS_ROOT_DIR}" ]; then
  bigwarn "entryjs zip layout unexpected"
  exit 1
fi

mkdir -p "${WWW}/lib/entryjs"
mkdir -p "${WWW}/lib/entryjs/dist"   # dist는 나중에 CDN로 반드시 채움

# extern/images/media는 "그대로 복사"
if [ -d "${ENTRYJS_ROOT_DIR}/extern" ]; then
  rsync -a --delete "${ENTRYJS_ROOT_DIR}/extern/" "${WWW}/lib/entryjs/extern/" || true
fi
if [ -d "${ENTRYJS_ROOT_DIR}/images" ]; then
  rsync -a --delete "${ENTRYJS_ROOT_DIR}/images/" "${WWW}/lib/entryjs/images/" || true
fi
if [ -d "${ENTRYJS_ROOT_DIR}/media" ]; then
  rsync -a --delete "${ENTRYJS_ROOT_DIR}/media/" "${WWW}/lib/entryjs/media/" || true
else
  mkdir -p "${WWW}/lib/entryjs/media"
fi

# dist는 repo에 있을 수도 있으니 "있으면" 복사 (하지만 없으면 아래 CDN에서 채움)
if [ -d "${ENTRYJS_ROOT_DIR}/dist" ]; then
  rsync -a "${ENTRYJS_ROOT_DIR}/dist/" "${WWW}/lib/entryjs/dist/" || true
fi

rm -rf "$TMP_ENTRYJS" || true
log "OK   entryjs extern/images/media copied (raw)"

# ============================================================
# 1-2) dist 보강: entry.min.js, entry.css는 CDN에서 "확실히" 받기
# ============================================================
bigwarn "ENSURE entryjs dist (entry.min.js + entry.css) from CDN if missing"

# entry.min.js
if [ ! -f "${WWW}/lib/entryjs/dist/entry.min.js" ]; then
  fetch_with_candidates "lib/entryjs/dist/entry.min.js" \
    "https://playentry.org/lib/entry-js/dist/entry.min.js" \
    "https://entry-cdn.pstatic.net/lib/entry-js/dist/entry.min.js"
fi

# entry.css (경로/파일명은 entry.css)
if [ ! -f "${WWW}/lib/entryjs/dist/entry.css" ]; then
  fetch_with_candidates "lib/entryjs/dist/entry.css" \
    "https://playentry.org/lib/entry-js/dist/entry.css" \
    "https://entry-cdn.pstatic.net/lib/entry-js/dist/entry.css"
fi

# entryjs 별칭 폴더 유지 (entry-js <-> entryjs)
mkdir -p "${WWW}/lib/entry-js"
rsync -a --delete "${WWW}/lib/entryjs/" "${WWW}/lib/entry-js/" || true

# ============================================================
# 2) 3rd-party libs (병렬 5개)
# ============================================================
job_spawn fetch_with_candidates "lib/lodash/dist/lodash.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js"

job_spawn fetch_with_candidates "lib/jquery/jquery.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js"

job_spawn fetch_with_candidates "lib/jquery-ui/ui/minified/jquery-ui.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js"

job_spawn fetch_with_candidates "lib/PreloadJS/lib/preloadjs-0.6.0.min.js" \
  "https://code.createjs.com/preloadjs-0.6.0.min.js"

job_spawn fetch_with_candidates "lib/EaselJS/lib/easeljs-0.8.0.min.js" \
  "https://code.createjs.com/easeljs-0.8.0.min.js"

job_spawn fetch_with_candidates "lib/SoundJS/lib/soundjs-0.6.0.min.js" \
  "https://code.createjs.com/soundjs-0.6.0.min.js"

job_spawn fetch_optional "lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "https://code.createjs.com/flashaudioplugin-0.6.0.min.js"

job_spawn fetch_with_candidates "lib/velocity/velocity.min.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js"

job_spawn fetch_with_candidates "lib/codemirror/codemirror.css" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css"

job_spawn fetch_with_candidates "lib/codemirror/codemirror.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js"

job_spawn fetch_optional "lib/codemirror/vim.js" \
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js"

job_spawn fetch_optional "js/ws/locales.js" \
  "https://playentry.org/js/ws/locales.js"

job_spawn fetch_with_candidates "lib/module/legacy-video/index.js" \
  "https://entry-cdn.pstatic.net/module/legacy-video/index.js" \
  "https://playentry.org/module/legacy-video/index.js"

job_wait_all || true

# ============================================================
# 3) entry-tool / entry-paint (CDN)
# ============================================================
job_spawn fetch_with_candidates "lib/entry-tool/dist/entry-tool.js" \
  "https://playentry.org/lib/entry-tool/dist/entry-tool.js" \
  "https://entry-cdn.pstatic.net/lib/entry-tool/dist/entry-tool.js"

job_spawn fetch_with_candidates "lib/entry-tool/dist/entry-tool.css" \
  "https://playentry.org/lib/entry-tool/dist/entry-tool.css" \
  "https://entry-cdn.pstatic.net/lib/entry-tool/dist/entry-tool.css"

job_spawn fetch_with_candidates "lib/entry-paint/dist/static/js/entry-paint.js" \
  "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" \
  "https://entry-cdn.pstatic.net/lib/entry-paint/dist/static/js/entry-paint.js"

job_wait_all || true

# ============================================================
# 4) /uploads/* (폰트 등) -> www/uploads/*
# ============================================================
fetch_optional "uploads/font/NanumSquare_acB.ttf" \
  "https://playentry.org/uploads/font/NanumSquare_acB.ttf" \
  "https://entry-cdn.pstatic.net/uploads/font/NanumSquare_acB.ttf"

fetch_optional "uploads/font/NanumSquare_acB.woff" \
  "https://playentry.org/uploads/font/NanumSquare_acB.woff" \
  "https://entry-cdn.pstatic.net/uploads/font/NanumSquare_acB.woff"

fetch_optional "uploads/font/NanumSquare_acR.ttf" \
  "https://playentry.org/uploads/font/NanumSquare_acR.ttf" \
  "https://entry-cdn.pstatic.net/uploads/font/NanumSquare_acR.ttf"

fetch_optional "uploads/font/NanumSquare_acR.woff" \
  "https://playentry.org/uploads/font/NanumSquare_acR.woff" \
  "https://entry-cdn.pstatic.net/uploads/font/NanumSquare_acR.woff"

# ============================================================
# 5) sanity check
# ============================================================
missing=0
if [ ! -f "${WWW}/lib/entryjs/dist/entry.min.js" ]; then
  bigwarn "CRITICAL missing: www/lib/entryjs/dist/entry.min.js"
  missing=1
fi
if [ ! -f "${WWW}/lib/entryjs/dist/entry.css" ]; then
  bigwarn "CRITICAL missing: www/lib/entryjs/dist/entry.css"
  missing=1
fi
if [ ! -d "${WWW}/lib/entryjs/images" ] || [ -z "$(ls -A "${WWW}/lib/entryjs/images" 2>/dev/null || true)" ]; then
  bigwarn "CRITICAL missing/empty: www/lib/entryjs/images (icons will not show)"
  missing=1
fi

if [ "$missing" -eq 0 ]; then
  log "✅ FETCH SUMMARY: dist+extern+images+media OK"
else
  bigwarn "FETCH SUMMARY: missing critical assets (see warnings above)"
fi

exit 0
