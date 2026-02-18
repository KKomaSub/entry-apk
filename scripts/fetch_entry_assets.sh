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
  local tarball
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

# ============================================================
# ✅✅✅ ONLY ADD: make sure subfolder images/media are REAL FILES
# (fix symlink directories like images/icon/* not being packaged)
# ============================================================
bigwarn "RESTORE: ensure images/media/uploads are copied WITH symlinks resolved (subfolder assets)"

copy_follow_links () {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"

  if command -v rsync >/dev/null 2>&1; then
    # --copy-links : follow symlinks and copy the REAL files
    # trailing slash 중요: 내용만 복사
    rsync -a --copy-links "$src/" "$dst/"
  else
    # cp -aL : follow symlinks
    cp -aL "$src/." "$dst/"
  fi
}

# 1) lib/entryjs 내부의 images/media/uploads가 symlink일 수 있음 → 실파일로 펼쳐 복사
copy_follow_links "$WWW/lib/entryjs/images"  "$WWW/lib/entryjs/images"
copy_follow_links "$WWW/lib/entryjs/media"   "$WWW/lib/entryjs/media"
copy_follow_links "$WWW/lib/entryjs/uploads" "$WWW/lib/entryjs/uploads"

# 2) 절대경로(/images, /media, /uploads)로도 요청될 수 있으니 www 루트에도 보강
mkdir -p "$WWW/images" "$WWW/media" "$WWW/uploads"
copy_follow_links "$WWW/lib/entryjs/images"  "$WWW/images"
copy_follow_links "$WWW/lib/entryjs/media"   "$WWW/media"
copy_follow_links "$WWW/lib/entryjs/uploads" "$WWW/uploads"

# 3) entry-js alias에도 동일 반영
if [ -d "$WWW/lib/entry-js" ]; then
  mkdir -p "$WWW/lib/entry-js/images" "$WWW/lib/entry-js/media" "$WWW/lib/entry-js/uploads"
  copy_follow_links "$WWW/lib/entryjs/images"  "$WWW/lib/entry-js/images"
  copy_follow_links "$WWW/lib/entryjs/media"   "$WWW/lib/entry-js/media"
  copy_follow_links "$WWW/lib/entryjs/uploads" "$WWW/lib/entry-js/uploads"
fi

# 4) 검증 로그 (용량/파일수 확인)
log "VERIFY images/icon/block_icon.png?"
if [ -f "$WWW/images/icon/block_icon.png" ]; then
  log "OK  $WWW/images/icon/block_icon.png"
else
  bigwarn "STILL MISSING: $WWW/images/icon/block_icon.png  (means source package doesn't contain it or path differs)"
fi
log "SIZE www/images = $(du -sh "$WWW/images" 2>/dev/null | awk '{print $1}')"
log "COUNT www/images files = $(find "$WWW/images" -type f 2>/dev/null | wc -l | tr -d ' ')"

# ============================================================

if [ "$MISSING_COUNT" -gt 0 ]; then
  bigwarn "FETCH SUMMARY: $MISSING_COUNT file(s) may be missing (script continued)"
else
  log "✅ FETCH SUMMARY: all downloads OK"
fi
# ============================================================
# ✅ ONLY ADD: scan JS/CSS for /images/, /media/, /uploads/ and fetch all (subfolders 포함)
# ============================================================
bigwarn "RESTORE: scan bundles/css for /images|/media|/uploads paths and fetch missing (subfolder assets)"

ASSET_SCAN_FILES=(
  "$WWW/lib/entryjs/dist/entry.min.js"
  "$WWW/lib/entryjs/dist/entry.css"
  "$WWW/lib/entry-tool/dist/entry-tool.css"
  "$WWW/lib/entry-paint/dist/static/js/entry-paint.js"
  "$WWW/lib/entryjs/extern/util/static.js"
)

ASSET_HOSTS=(
  "https://playentry.org"
  "https://entry-cdn.pstatic.net"
)

# rel like /images/icon/a.png -> save to $WWW/images/icon/a.png
asset_out_path() {
  local rel="$1"
  rel="${rel#./}"
  rel="${rel#/}"
  echo "$WWW/$rel"
}

fetch_candidates() {
  local rel="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  # 이미 있으면 스킵
  if [ -s "$out" ]; then
    return 0
  fi

  local h url
  for h in "${ASSET_HOSTS[@]}"; do
    url="${h}${rel}"
    if curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 -o "$out" "$url"; then
      log "OK   ASSET -> $rel"
      return 0
    fi
  done

  # 못 찾으면 실패(계속 진행)
  bigwarn "ASSET MISS (continued): $rel"
  return 1
}

# JS/CSS에서 /images/... /media/... /uploads/... 경로 추출
extract_asset_paths() {
  local f="$1"
  [ -f "$f" ] || return 0

  # 1) url(/images/...), url('/images/...'), "/images/..", '/images/..' 등 모두 잡기
  # 2) 쿼리스트링 제거 (?v=xxx)
  # 3) 공백/괄호/따옴표에서 끊기
  grep -aoE '(/(images|media|uploads)/[^"'\''\)\s?#]+)' "$f" \
    | sed -E 's/[?].*$//' \
    | sort -u
}

# 병렬 다운로드에 기존 job_add/job_wait_all 사용 (수정 금지라 재사용)
ASSET_TMP="$WWW/.asset_paths.txt"
: > "$ASSET_TMP"

for f in "${ASSET_SCAN_FILES[@]}"; do
  if [ -f "$f" ]; then
    log "SCAN $f"
    extract_asset_paths "$f" >> "$ASSET_TMP" || true
  else
    log "SCAN SKIP (missing): $f"
  fi
done

# 중복 제거
sort -u "$ASSET_TMP" -o "$ASSET_TMP" || true

ASSET_TOTAL="$(wc -l < "$ASSET_TMP" | tr -d ' ')"
log "ASSET PATHS FOUND = $ASSET_TOTAL"

# 다운로드 큐 추가 (MAX_JOBS 병렬)
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  out="$(asset_out_path "$rel")"
  # job_add(url,out,desc) 형태라서, 여기서는 "호스트별로 순회"가 필요 -> fetch_candidates를 job으로 돌림
  (
    fetch_candidates "$rel" "$out" || true
  ) &
  JOB_PIDS+=("$!")
  JOB_DESC+=("asset $rel")
  while [ "${#JOB_PIDS[@]}" -ge "$MAX_JOBS" ]; do
    job_wait_one
  done
done < "$ASSET_TMP"

job_wait_all

# 최종 검증(예시 파일)
log "VERIFY: $WWW/images/block_icon/ai_hand_icon.svg ?"
if [ -f "$WWW/images/block_icon/ai_hand_icon.svg" ]; then
  log "OK  images/block_icon/ai_hand_icon.svg exists"
else
  bigwarn "STILL MISSING: images/block_icon/ai_hand_icon.svg  (path may differ in this Entry build; check network request path)"
fi

log "SIZE www/images = $(du -sh "$WWW/images" 2>/dev/null | awk '{print $1}')"
log "COUNT www/images files = $(find "$WWW/images" -type f 2>/dev/null | wc -l | tr -d ' ')"
# ============================================================
# ============================================================
# ✅ ONLY ADD: Mirror EntryJS images/** (including subfolders) into www/images/**
#   - fixes: /images/icon/... 404
#   - do NOT symlink (APK/webview can break); copy with -L to resolve links
# ============================================================
bigwarn "MIRROR: lib/entryjs/images/** -> www/images/** (subfolder assets fix)"

# ensure targets exist
mkdir -p "$WWW/images" "$WWW/media" "$WWW/uploads" || true

# source candidates (some builds may use entry-js)
IMG_SRC1="$WWW/lib/entryjs/images"
IMG_SRC2="$WWW/lib/entry-js/images"

mirror_tree () {
  local src="$1" dst="$2"
  if [ -d "$src" ]; then
    # copy contents, keep subdirs, overwrite/merge, dereference symlinks
    cp -aL "$src/." "$dst/" 2>/dev/null || true
    log "MIRROR OK: $src -> $dst"
  else
    log "MIRROR SKIP (missing): $src"
  fi
}

mirror_tree "$IMG_SRC1" "$WWW/images"
mirror_tree "$IMG_SRC2" "$WWW/images"

# also mirror media if present (sometimes audio/cursor assets live there)
MEDIA_SRC1="$WWW/lib/entryjs/media"
MEDIA_SRC2="$WWW/lib/entry-js/media"
mirror_tree "$MEDIA_SRC1" "$WWW/media"
mirror_tree "$MEDIA_SRC2" "$WWW/media"

# verify a known subfolder case (requested)
VERIFY_FILE="$WWW/images/block_icon/ai_hand_icon.svg"
log "VERIFY: $VERIFY_FILE ?"

if [ -f "$VERIFY_FILE" ]; then
  log "OK  FIXED: images/block_icon/ai_hand_icon.svg exists"
  # show size for sanity
  log "SIZE: $(stat -c%s "$VERIFY_FILE" 2>/dev/null || wc -c < "$VERIFY_FILE") bytes"
else
  bigwarn "STILL MISSING: images/block_icon/ai_hand_icon.svg"
  # help: show what we actually have under block_icon
  if [ -d "$WWW/images/block_icon" ]; then
    log "LIST www/images/block_icon (top 80):"
    ls -1 "$WWW/images/block_icon" | head -n 80 || true
  else
    bigwarn "DIR MISSING: $WWW/images/block_icon"
  fi

  # help: show if it exists inside entryjs package but not mirrored
  if [ -f "$WWW/lib/entryjs/images/block_icon/ai_hand_icon.svg" ]; then
    bigwarn "FOUND IN lib/entryjs/images BUT NOT IN www/images (mirror step failed?)"
  fi
  if [ -f "$WWW/lib/entry-js/images/block_icon/ai_hand_icon.svg" ]; then
    bigwarn "FOUND IN lib/entry-js/images BUT NOT IN www/images (mirror step failed?)"
  fi
fi

log "SIZE www/images = $(du -sh "$WWW/images" 2>/dev/null | awk '{print $1}')"
log "COUNT www/images files = $(find "$WWW/images" -type f 2>/dev/null | wc -l | tr -d ' ')"
# ============================================================
exit 0
