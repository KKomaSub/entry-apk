#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-5}"

# entryjs repo (원하면 환경변수로 덮어쓰기 가능)
ENTRYJS_REPO="${ENTRYJS_REPO:-https://github.com/entrylabs/entryjs.git}"
ENTRYJS_BRANCH="${ENTRYJS_BRANCH:-master}"

mkdir -p "$WWW"

log(){ echo "[$(date +'%H:%M:%S')] $*"; }
bigwarn(){
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $*"
  echo "████████████████████████████████████████████████████████████"
}

# ---- safe path: ALWAYS under $WWW ----
# input: /images/a.png  -> $WWW/images/a.png
# input: images/a.png   -> $WWW/images/a.png
to_www_path(){
  local p="$1"
  p="${p#./}"
  p="${p#/}"         # IMPORTANT: drop leading slash to avoid /images /uploads permission
  echo "${WWW}/${p}"
}

ensure_dir(){
  local f="$1"
  mkdir -p "$(dirname "$f")"
}

# ---- parallel downloader ----
pids=()
job_wait_all(){
  local fail=0
  for pid in "${pids[@]:-}"; do
    if ! wait "$pid"; then fail=1; fi
  done
  pids=()
  return $fail
}
job_spawn(){
  while [ "${#pids[@]}" -ge "$MAX_JOBS" ]; do
    if ! wait "${pids[0]}"; then true; fi
    pids=("${pids[@]:1}")
  done
  ( "$@" ) &
  pids+=("$!")
}

# ---- fetch helper ----
# usage: fetch_one "https://..." "/lib/xxx/file.js"
fetch_one(){
  local url="$1"
  local rel="$2"
  local out
  out="$(to_www_path "$rel")"
  ensure_dir "$out"

  log "GET  $url"
  if curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$out"; then
    log "OK   -> $out"
    return 0
  else
    bigwarn "MISS $url"
    return 1
  fi
}

# ---- copy dir recursively (real files, not symlinks) ----
copy_tree(){
  local src="$1"
  local dst="$2"
  if [ ! -d "$src" ]; then
    return 1
  fi
  mkdir -p "$dst"
  # rsync가 있으면 가장 안전 (권한/타임스탬프/하위폴더)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src"/ "$dst"/
  else
    rm -rf "$dst"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
  fi
  return 0
}

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"
log "ENTRYJS_REPO=$ENTRYJS_REPO (branch=$ENTRYJS_BRANCH)"

# --- core libs (필요한 최소) ---
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" "/lib/lodash/dist/lodash.min.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" "/lib/jquery/jquery.min.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" "/lib/jquery-ui/ui/minified/jquery-ui.min.js"
job_spawn fetch_one "https://code.createjs.com/preloadjs-0.6.0.min.js" "/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
job_spawn fetch_one "https://code.createjs.com/easeljs-0.8.0.min.js" "/lib/EaselJS/lib/easeljs-0.8.0.min.js"
job_spawn fetch_one "https://code.createjs.com/soundjs-0.6.0.min.js" "/lib/SoundJS/lib/soundjs-0.6.0.min.js"

# flashaudioplugin optional (실패해도 계속)
( job_spawn fetch_one "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" "/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" ) || true

# locales optional
( job_spawn fetch_one "https://playentry.org/js/ws/locales.js" "/js/ws/locales.js" ) || true

# 기다림
job_wait_all || true

# ------------------------------------------------------------
# ✅ ENTRYJS FULL COPY (핵심)
# ------------------------------------------------------------
TMP="${WWW}/.tmp_entryjs_clone"
rm -rf "$TMP"
mkdir -p "$TMP"

log "=== CLONE entryjs repo for FULL static assets ==="
if command -v git >/dev/null 2>&1; then
  # shallow clone
  git clone --depth 1 --branch "$ENTRYJS_BRANCH" "$ENTRYJS_REPO" "$TMP" >/dev/null 2>&1 || {
    bigwarn "git clone failed: $ENTRYJS_REPO (branch=$ENTRYJS_BRANCH)"
    bigwarn "TIP: set ENTRYJS_REPO env to correct repo URL"
    exit 1
  }
else
  bigwarn "git not found on runner. Cannot full-copy entryjs."
  exit 1
fi

# 복사 대상: www/lib/entryjs (그리고 과거 호환 alias www/lib/entry-js)
DEST_ENTRYJS="${WWW}/lib/entryjs"
DEST_ENTRYJS_ALIAS="${WWW}/lib/entry-js"

mkdir -p "$DEST_ENTRYJS" "$DEST_ENTRYJS_ALIAS"

log "=== COPY entryjs folders (dist/images/media/extern/src 등 존재하는 것 전부) ==="
# 가능한 폴더를 “있는 것만” 전부 복사
for d in dist images media extern src res resources static public; do
  if [ -d "${TMP}/${d}" ]; then
    log "COPY ${d}/ -> ${DEST_ENTRYJS}/${d}/"
    copy_tree "${TMP}/${d}" "${DEST_ENTRYJS}/${d}" || true
  fi
done

# package 내에서 entry.css/entry.min.js가 dist에 없고 다른 경로에 있을 수 있음:
# dist가 비어있으면 playentry CDN을 fallback으로 가져오되, 기존 방식 유지 위해 최소만.
if [ ! -f "${DEST_ENTRYJS}/dist/entry.min.js" ] && [ ! -f "${DEST_ENTRYJS}/dist/entry.js" ]; then
  bigwarn "entryjs dist missing in repo copy. Fallback to playentry CDN for dist files."
  # 필요한 최소 dist 파일만
  fetch_one "https://playentry.org/lib/entry-js/dist/entry.min.js" "/lib/entryjs/dist/entry.min.js" || true
  fetch_one "https://playentry.org/lib/entry-js/dist/entry.css" "/lib/entryjs/dist/entry.css" || true
fi

# alias copy: /lib/entry-js <-> /lib/entryjs (둘 다 동일하게 유지)
log "=== ALIAS copy: lib/entryjs -> lib/entry-js ==="
copy_tree "$DEST_ENTRYJS" "$DEST_ENTRYJS_ALIAS" || true

# ------------------------------------------------------------
# ✅ 절대경로(/images /media /uploads) 대비: www/images 등에 “실제 복사본” 만들기
#   - EntryStatic.imagePath/mediaPath가 /images, /media 쓰는 경우
#   - images/icon/... 같은 하위폴더가 APK에 포함되도록
# ------------------------------------------------------------
log "=== ABSOLUTE PATH mirrors: www/images,www/media,www/uploads ==="
mkdir -p "$WWW/images" "$WWW/media" "$WWW/uploads"

# entryjs/images -> www/images (실제 파일 복사)
if [ -d "${DEST_ENTRYJS}/images" ]; then
  copy_tree "${DEST_ENTRYJS}/images" "$WWW/images" || true
fi
if [ -d "${DEST_ENTRYJS}/media" ]; then
  copy_tree "${DEST_ENTRYJS}/media" "$WWW/media" || true
fi
# uploads는 repo에 없을 수 있음. 있으면 복사.
if [ -d "${TMP}/uploads" ]; then
  copy_tree "${TMP}/uploads" "$WWW/uploads" || true
fi

# ------------------------------------------------------------
# ✅ 검증 (하위폴더 이미지)
# ------------------------------------------------------------
log "=== VERIFY nested images ==="
if [ -f "$WWW/images/btn.png" ]; then
  log "OK  images/btn.png"
else
  bigwarn "MISSING images/btn.png (unexpected)"
fi

if [ -f "$WWW/images/icon/block_icon.png" ]; then
  log "OK  images/icon/block_icon.png"
else
  bigwarn "MISSING images/icon/block_icon.png (this is your issue)"
  log "CHECK: $WWW/images/icon exists?"
  ls -la "$WWW/images/icon" || true
fi

log "=== SIZE CHECK ==="
du -sh "$WWW" || true
du -sh "$WWW/images" || true
du -sh "$WWW/lib/entryjs" || true

log "✅ FETCH DONE"
