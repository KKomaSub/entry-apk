#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Fetch Entry assets (offline vendoring)
# - Parallel downloads (default 5)
# - FULL copy of entryjs (dist/extern/images/media) from GitHub zip
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

# --- job pool ------------------------------------------------
pids=()
job_spawn() {
  ("$@") &
  pids+=("$!")
  job_throttle
}
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
# Convert "lib/entryjs/..." stays as-is
relpath() {
  local p="$1"
  p="${p#./}"
  p="${p#/}"          # <-- CRITICAL: strip leading slash to avoid /uploads mkdir
  echo "$p"
}

ensure_parent() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
}

curl_get() {
  local url="$1" dest="$2"
  ensure_parent "$dest"
  # --fail to treat 404 as error; retry a bit
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
  # usage: fetch_with_candidates "dest_rel" "url1" "url2" ...
  local dest_rel="$1"; shift
  local dest="${WWW}/$(relpath "$dest_rel")"

  local ok=1
  for url in "$@"; do
    log "GET  $url"
    if curl_get "$url" "$dest"; then ok=0; break; fi
  done

  if [ $ok -ne 0 ]; then
    bigwarn "FAIL all candidates -> $dest_rel"
    echo "Tried:"
    for url in "$@"; do echo " - $url"; done
    return 1
  fi
  return 0
}

# optional fetch: never fails pipeline
fetch_optional() {
  local dest_rel="$1"; shift
  if ! fetch_with_candidates "$dest_rel" "$@"; then
    bigwarn "OPTIONAL missing: $(basename "$dest_rel") (continuing)"
    return 0
  fi
  return 0
}

# --- extract zip ----------------------------------------------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { bigwarn "Missing command: $1"; exit 1; }
}
need_cmd curl
need_cmd unzip
need_cmd rsync

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
# 1) FULL COPY entryjs (dist/extern/images/media) - 그대로 복사
# ============================================================
# 최신은 보통 develop에 있고, entry-offline은 master라는 맥락이지만
# entryjs는 공식 repo 기본 브랜치가 develop임. (필요 시 ENTRYJS_REF로 변경)
ENTRYJS_REF="${ENTRYJS_REF:-develop}"
ENTRYJS_ZIP="https://codeload.github.com/entrylabs/entryjs/zip/refs/heads/${ENTRYJS_REF}"
TMP_ENTRYJS="${WWW}/.tmp_entryjs"

bigwarn "FULL COPY entryjs from GitHub (${ENTRYJS_REF}) -> www/lib/entryjs (dist/extern/images/media)"
extract_zip_url "$ENTRYJS_ZIP" "$TMP_ENTRYJS"

# zip 최상단 폴더 찾기
ENTRYJS_ROOT_DIR="$(find "$TMP_ENTRYJS" -maxdepth 1 -type d -name "entryjs-*" | head -n 1)"
if [ -z "${ENTRYJS_ROOT_DIR}" ] || [ ! -d "${ENTRYJS_ROOT_DIR}" ]; then
  bigwarn "entryjs zip layout unexpected"
  exit 1
fi

mkdir -p "${WWW}/lib/entryjs"
rsync -a --delete "${ENTRYJS_ROOT_DIR}/dist/"  "${WWW}/lib/entryjs/dist/"  || true
rsync -a --delete "${ENTRYJS_ROOT_DIR}/extern/" "${WWW}/lib/entryjs/extern/" || true
rsync -a --delete "${ENTRYJS_ROOT_DIR}/images/" "${WWW}/lib/entryjs/images/" || true
# media 폴더가 없을 수도 있으니 optional
if [ -d "${ENTRYJS_ROOT_DIR}/media" ]; then
  rsync -a --delete "${ENTRYJS_ROOT_DIR}/media/" "${WWW}/lib/entryjs/media/" || true
else
  mkdir -p "${WWW}/lib/entryjs/media"
fi

# entryjs 경로 별칭도 유지(기존 스크립트들 호환)
mkdir -p "${WWW}/lib/entry-js"
rsync -a --delete "${WWW}/lib/entryjs/" "${WWW}/lib/entry-js/" || true

rm -rf "$TMP_ENTRYJS" || true
log "OK   entryjs FULL copy complete"

# ============================================================
# 2) 필수 3rd-party libs (entryjs README 기준)  (병렬 5개)
# ============================================================
# lodash/jq/ui/createjs/velocity/codemirror
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

# flashaudioplugin은 종종 404 → optional
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

# locales (optional but nice)
job_spawn fetch_optional "js/ws/locales.js" \
  "https://playentry.org/js/ws/locales.js"

# legacy-video module
job_spawn fetch_with_candidates "lib/module/legacy-video/index.js" \
  "https://entry-cdn.pstatic.net/module/legacy-video/index.js" \
  "https://playentry.org/module/legacy-video/index.js"

job_wait_all || true

# ============================================================
# 3) entry-tool / entry-paint (CDN에서 가져오되, 이미지/정적리소스는 폴더째 가져오기)
#    - npm registry에서 @entrylabs/* 는 404가 날 수 있어 CDN 우선
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
# 4) /uploads/* (폰트 등) - "절대경로 mkdir" 금지: www/uploads 로 저장
#    - entryjs initOptions fonts에서 /uploads/font/... 를 쓰는 케이스가 많아서
# ============================================================
# (필수는 아니지만, 있으면 깨지는 UI가 줄어듬. 전부 optional 처리)
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
# 5) 결과 체크 (이미지/미디어가 실제로 존재하는지)
# ============================================================
missing=0
if [ ! -d "${WWW}/lib/entryjs/images" ] || [ -z "$(ls -A "${WWW}/lib/entryjs/images" 2>/dev/null || true)" ]; then
  bigwarn "entryjs images directory is empty -> images will not show"
  missing=1
fi
if [ ! -d "${WWW}/lib/entryjs/dist" ] || [ ! -f "${WWW}/lib/entryjs/dist/entry.min.js" ]; then
  bigwarn "entryjs dist missing -> entry cannot boot"
  missing=1
fi

if [ "$missing" -eq 0 ]; then
  log "✅ FETCH SUMMARY: entryjs FULL + libs OK (images/media included)"
else
  bigwarn "FETCH SUMMARY: some critical folders missing (check logs above)"
fi

exit 0
