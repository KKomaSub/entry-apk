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
# 병렬 수 (원하는 값으로)
P="${P:-5}"

# 1) js/html/css만 파일 리스트 생성 (한 번만)
find www -type f \( -name '*.js' -o -name '*.html' -o -name '*.css' \) -print0 \
  > www/.web_files.bin

# 2) 파일별 병렬 검색 (예: /images|/media|/uploads 경로 뽑기)
xargs -0 -P "$P" -n 1 bash -lc '
  f="$1"
  # 파일마다 결과를 임시로 따로 저장(충돌 방지)
  out="www/.scan.$(echo "$f" | tr "/ " "__").txt"
  grep -aoE "(/(images|media|uploads)/[^\"'\''\)\s?#]+)" "$f" \
    | sed -E "s/[?].*$//" \
    | sort -u > "$out" || true
' _ < www/.web_files.bin

# 3) 결과 합치기(중복 제거)
cat www/.scan.*.txt 2>/dev/null | sort -u > www/.asset_paths.txt
echo "ASSET PATHS FOUND = $(wc -l < www/.asset_paths.txt | tr -d ' ')"

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
# -----------------------------------------------------------------------------
# FIX: subfolder images 404 (alias paths)
# - Example: images/btn.png works but images/icon/* or other nested paths 404
# - We keep original assets, and ALSO create alias folders that Entry may request.
# -----------------------------------------------------------------------------
bigwarn "FIX: alias-copy subfolder images to match legacy request paths (no other changes)"

# 1) ensure target dirs exist
mkdir -p "$WWW/images/icon" "$WWW/lib/entryjs/images/icon" "$WWW/lib/entry-js/images/icon" || true

# 2) If block_icon exists but icon/block_icon is requested, mirror it
if [ -d "$WWW/images/block_icon" ] && [ ! -d "$WWW/images/icon/block_icon" ]; then
  mkdir -p "$WWW/images/icon/block_icon"
  cp -a "$WWW/images/block_icon/." "$WWW/images/icon/block_icon/" 2>/dev/null || true
  log "ALIAS COPY OK: www/images/block_icon -> www/images/icon/block_icon"
fi

if [ -d "$WWW/lib/entryjs/images/block_icon" ] && [ ! -d "$WWW/lib/entryjs/images/icon/block_icon" ]; then
  mkdir -p "$WWW/lib/entryjs/images/icon/block_icon"
  cp -a "$WWW/lib/entryjs/images/block_icon/." "$WWW/lib/entryjs/images/icon/block_icon/" 2>/dev/null || true
  log "ALIAS COPY OK: lib/entryjs/images/block_icon -> lib/entryjs/images/icon/block_icon"
fi

if [ -d "$WWW/lib/entry-js/images/block_icon" ] && [ ! -d "$WWW/lib/entry-js/images/icon/block_icon" ]; then
  mkdir -p "$WWW/lib/entry-js/images/icon/block_icon"
  cp -a "$WWW/lib/entry-js/images/block_icon/." "$WWW/lib/entry-js/images/icon/block_icon/" 2>/dev/null || true
  log "ALIAS COPY OK: lib/entry-js/images/block_icon -> lib/entry-js/images/icon/block_icon"
fi

# 3) Verify your exact example after aliasing
VERIFY_FILE="$WWW/images/icon/block_icon/ai_hand_icon.svg"
log "VERIFY (alias path): $VERIFY_FILE ?"
if [ -f "$VERIFY_FILE" ]; then
  log "OK  alias exists: images/icon/block_icon/ai_hand_icon.svg"
else
  bigwarn "STILL MISSING alias: images/icon/block_icon/ai_hand_icon.svg (check which path Entry requests in Network tab)"
fi
# ============================================================
# ✅ FINAL FIX: ensure /images/icon/** exists (Entry legacy path)
# ============================================================
bigwarn "FINAL FIX: ensure www/images/icon/** alias exists (legacy requests)"

mkdir -p "$WWW/images/icon" || true

# 1) if we have block_icon, mirror into icon/block_icon
if [ -d "$WWW/images/block_icon" ]; then
  mkdir -p "$WWW/images/icon/block_icon"
  cp -aL "$WWW/images/block_icon/." "$WWW/images/icon/block_icon/" 2>/dev/null || true
  log "ALIAS OK: images/block_icon -> images/icon/block_icon"
fi

# 2) if we have icon folder inside lib/entryjs, mirror it too
if [ -d "$WWW/lib/entryjs/images/icon" ]; then
  mkdir -p "$WWW/images/icon"
  cp -aL "$WWW/lib/entryjs/images/icon/." "$WWW/images/icon/" 2>/dev/null || true
  log "ALIAS OK: lib/entryjs/images/icon -> images/icon"
fi

# 3) verify the exact file you asked
VERIFY1="$WWW/images/block_icon/ai_hand_icon.svg"
VERIFY2="$WWW/images/icon/block_icon/ai_hand_icon.svg"
log "VERIFY: $VERIFY1 ?"; [ -f "$VERIFY1" ] && log "OK  $VERIFY1" || bigwarn "MISS $VERIFY1"
log "VERIFY: $VERIFY2 ?"; [ -f "$VERIFY2" ] && log "OK  $VERIFY2" || bigwarn "MISS $VERIFY2"
# ============================================================
# ============================================================
# ✅ FINAL: copy ALL images into www/images and rewrite refs
# ============================================================
bigwarn "FINAL: COPY ALL images -> www/images (recursive, resolve symlinks)"

mkdir -p "$WWW/images" "$WWW/media" "$WWW/uploads" || true

copy_tree_resolve_links () {
  local src="$1" dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --copy-links "$src/" "$dst/"
  else
    cp -aL "$src/." "$dst/"
  fi
  log "COPY OK: $src -> $dst"
}

# 1) Entry 패키지 내부의 images/media/uploads를 루트(www)로 풀카피
copy_tree_resolve_links "$WWW/lib/entryjs/images"  "$WWW/images"
copy_tree_resolve_links "$WWW/lib/entryjs/media"   "$WWW/media"
copy_tree_resolve_links "$WWW/lib/entryjs/uploads" "$WWW/uploads"

# 2) alias 라이브러리(entry-js)에도 있으면 추가로 병합
copy_tree_resolve_links "$WWW/lib/entry-js/images"  "$WWW/images"
copy_tree_resolve_links "$WWW/lib/entry-js/media"   "$WWW/media"
copy_tree_resolve_links "$WWW/lib/entry-js/uploads" "$WWW/uploads"

# 3) (선택) 혹시 다른 위치에 images가 더 있으면 전부 루트로 병합
# - 예: www/lib/**/images
while IFS= read -r d; do
  copy_tree_resolve_links "$d" "$WWW/images"
done < <(find "$WWW/lib" -type d -name images 2>/dev/null | sort -u)

log "SIZE www/images = $(du -sh "$WWW/images" 2>/dev/null | awk '{print $1}')"
log "COUNT www/images files = $(find "$WWW/images" -type f 2>/dev/null | wc -l | tr -d ' ')"

# ------------------------------------------------------------
# ✅ FINAL: rewrite ALL refs in html/js/css to /images/..., /media/..., /uploads/...
#   - 목표: 어떤 파일 위치에서 로드하든 항상 동일한 절대 경로로 접근
# ------------------------------------------------------------
bigwarn "FINAL: REWRITE asset refs in *.html/*.js/*.css to /images|/media|/uploads"

rewrite_file () {
  local f="$1"
  # perl로 안전하게 다중 패턴 치환 (JS/CSS/HTML 공통)
  perl -0777 -i -pe '
    # ---- images ----
    s#https?://(?:playentry\.org|entry-cdn\.pstatic\.net)(/images/)#\1#g;
    s#\./lib/entryjs/images/#/images/#g;
    s#/lib/entryjs/images/#/images/#g;
    s#\./lib/entry-js/images/#/images/#g;
    s#/lib/entry-js/images/#/images/#g;
    s#\./images/#/images/#g;

    # ---- media ----
    s#https?://(?:playentry\.org|entry-cdn\.pstatic\.net)(/media/)#\1#g;
    s#\./lib/entryjs/media/#/media/#g;
    s#/lib/entryjs/media/#/media/#g;
    s#\./lib/entry-js/media/#/media/#g;
    s#/lib/entry-js/media/#/media/#g;
    s#\./media/#/media/#g;

    # ---- uploads ----
    s#https?://(?:playentry\.org|entry-cdn\.pstatic\.net)(/uploads/)#\1#g;
    s#\./lib/entryjs/uploads/#/uploads/#g;
    s#/lib/entryjs/uploads/#/uploads/#g;
    s#\./lib/entry-js/uploads/#/uploads/#g;
    s#/lib/entry-js/uploads/#/uploads/#g;
    s#\./uploads/#/uploads/#g;

    # ---- CSS url("...") 형태의 상대경로를 강제로 /images 로 통일하고 싶은 경우 (보수적으로만)
    # url(images/xxx) -> url(/images/xxx)
    s#url\(\s*([\"\047]?)images/#url(\1/images/#g;
    s#url\(\s*([\"\047]?)/?lib/entryjs/images/#url(\1/images/#g;
    s#url\(\s*([\"\047]?)/?lib/entry-js/images/#url(\1/images/#g;

  ' "$f" || true
}

# 대상: www 아래 모든 html/js/css
while IFS= read -r f; do
  rewrite_file "$f"
done < <(find "$WWW" -type f \( -name '*.html' -o -name '*.js' -o -name '*.css' \) 2>/dev/null)

log "REWRITE DONE: unified refs -> /images /media /uploads"

# (검증 예시)
if [ -f "$WWW/images/block_icon/ai_hand_icon.svg" ]; then
  log "OK  /images/block_icon/ai_hand_icon.svg exists"
else
  bigwarn "MISS: /images/block_icon/ai_hand_icon.svg (check actual requested path)"
fi
# ============================================================
# ============================================================
# FIX: Capacitor/WebView often fails to serve paths that end with dot (e.g. /images/ai_on.)
# Strategy:
#  1) Duplicate "name." -> "name.png" (or svg/jpg/gif based on magic bytes)
#  2) Patch JS/CSS references "/images/name." -> "/images/name.png"
#  3) Same for /media if needed
# ============================================================
bigwarn "FIX: dot-ending asset filenames (name.) -> (name.png) + patch references"

detect_ext_by_magic() {
  local f="$1"
  # PNG
  if head -c 8 "$f" | od -An -t x1 | tr -d ' \n' | grep -qi '^89504e470d0a1a0a$'; then
    echo "png"; return 0
  fi
  # JPG
  if head -c 2 "$f" | od -An -t x1 | tr -d ' \n' | grep -qi '^ffd8$'; then
    echo "jpg"; return 0
  fi
  # GIF
  if head -c 3 "$f" | od -An -t x1 | tr -d ' \n' | grep -qi '^474946$'; then
    echo "gif"; return 0
  fi
  # SVG (text)
  if head -c 200 "$f" | tr -d '\r' | grep -qi '<svg'; then
    echo "svg"; return 0
  fi
  # default: png (Entry assets are overwhelmingly png)
  echo "png"
}
# (A) 먼저 이미 망가진 pngpng/jpgjpg 등을 되돌리는 1회 복구
fix_double_ext() {
  local f="$1"
  [ -f "$f" ] || return 0
  sed -i -E \
    's@\.pngpng([^A-Za-z0-9]|$)@.png\1@g;
     s@\.jpgjpg([^A-Za-z0-9]|$)@.jpg\1@g;
     s@\.jpegjpeg([^A-Za-z0-9]|$)@.jpeg\1@g;
     s@\.gifgif([^A-Za-z0-9]|$)@.gif\1@g;
     s@\.svgsvg([^A-Za-z0-9]|$)@.svg\1@g;
     s@\.webpwebp([^A-Za-z0-9]|$)@.webp\1@g' "$f" || true
}

# (B) "끝이 점(.)인 경로"만 -> .png 로 치환 (중간 dot는 절대 건드리지 않음)
patch_dot_refs() {
  local f="$1"
  [ -f "$f" ] || return 0

  # 1) 먼저 pngpng 같은 손상 복구
  fix_double_ext "$f"

  # 2) dot-ending only:
  #    /images/abc.  + (따옴표/괄호/공백/?/#/끝) => /images/abc.png + 그 구분자
  sed -i -E \
    's@(/images/[^"'\''\)\s?#]+)\.([\"'\''\)\s?#]|$)@\1.png\2@g;
     s@(/media/[^"'\''\)\s?#]+)\.([\"'\''\)\s?#]|$)@\1.png\2@g' "$f" || true
}

# ============================================================
# ✅ FIX: filenames ending with "." break in Android/Capacitor (URL normalization + MIME)
# - If we have files like images/ai_on. then runtime may request ai_on (dot stripped)
# - Also no extension -> wrong MIME -> image/audio won't render
# So: create REAL copies with proper extension (png/svg/jpg/gif/webp) + also dotless alias
# ============================================================
bigwarn "FIX: dot-ending assets -> create .png/.svg/... copies + dotless alias (Android safe)"

guess_ext_by_magic() {
  local f="$1"
  # read first 16 bytes as hex
  local hx
  hx="$(xxd -p -l 16 "$f" 2>/dev/null | tr -d '\n' || true)"

  # PNG: 89504e470d0a1a0a
  if [[ "$hx" == 89504e470d0a1a0a* ]]; then echo "png"; return; fi
  # JPG: ffd8ff
  if [[ "$hx" == ffd8ff* ]]; then echo "jpg"; return; fi
  # GIF: 474946383761 or 474946383961
  if [[ "$hx" == 4749463837* || "$hx" == 4749463839* ]]; then echo "gif"; return; fi
  # WEBP: "RIFF"...."WEBP" (52494646....57454250)
  if [[ "$hx" == 52494646* ]]; then
    if grep -aq "WEBP" "$f" 2>/dev/null; then echo "webp"; return; fi
  fi
  # SVG: starts with <svg or <?xml ... <svg
  if head -c 512 "$f" 2>/dev/null | grep -aq "<svg"; then echo "svg"; return; fi

  # default
  echo "png"
}

make_aliases_for_dot_files() {
  local base="$1"   # e.g. $WWW/images or $WWW/media
  [ -d "$base" ] || return 0

  # find files whose name ends with a dot.
  # -print0 safe
  while IFS= read -r -d '' f; do
    # original: .../name.
    local dir bn stem ext dst1 dst2
    dir="$(dirname "$f")"
    bn="$(basename "$f")"       # name.
    stem="${bn%.}"              # name

    # 1) dotless alias: name  (for servers that strip trailing dot)
    dst1="$dir/$stem"
    if [ ! -s "$dst1" ]; then
      cp -a "$f" "$dst1" 2>/dev/null || true
    fi

    # 2) extension alias: name.png / name.svg / name.jpg ... (for correct MIME)
    ext="$(guess_ext_by_magic "$f")"
    dst2="$dir/$stem.$ext"
    if [ ! -s "$dst2" ]; then
      cp -a "$f" "$dst2" 2>/dev/null || true
    fi
  done < <(find "$base" -type f -name '*.' -print0 2>/dev/null)
}

# run for all relevant roots
make_aliases_for_dot_files "$WWW/images"
make_aliases_for_dot_files "$WWW/media"
make_aliases_for_dot_files "$WWW/uploads"
make_aliases_for_dot_files "$WWW/lib/entryjs/images"
make_aliases_for_dot_files "$WWW/lib/entryjs/media"
make_aliases_for_dot_files "$WWW/lib/entry-js/images"
make_aliases_for_dot_files "$WWW/lib/entry-js/media"

# quick verify: dot-ending examples should now have .png too
log "VERIFY dot-ending -> png alias sample (ai_on)"
ls -la "$WWW/images/ai_on." 2>/dev/null || true
ls -la "$WWW/images/ai_on.png" 2>/dev/null || true
# ============================================================
# ============================================================
# ============================================================
# ✅ ONLY ADD: POST-PATCH absolute asset paths in css/js/html
#  - fixes CSS background url(/images/...) not being rewritten by JS patch
#  - rewrite only when clearly absolute-root paths are used
# ============================================================
bigwarn "POST-PATCH: rewrite /images|/media|/uploads => ./images|./media|./uploads in css/js/html"

rewrite_paths_in_file() {
  local f="$1"
  [ -f "$f" ] || return 0

  # GNU sed (ubuntu-latest) OK
  # 1) url(/images/..) or url('/images/..') or url("/images/..")
  sed -i -E \
    -e 's#url\((["'"'"']?)\/(images|media|uploads)/#url(\1./\2/#g' \
    -e 's#url\((["'"'"']?)\.\./(images|media|uploads)/#url(\1./\2/#g' \
    -e 's#(["'"'"']?)\/(images|media|uploads)/#\1./\2/#g' \
    "$f" || true
}

# patch targets (최소 핵심만)
PATCH_FILES=(
  "$WWW/index.html"
  "$WWW/overrides.css"
  "$WWW/lib/entryjs/dist/entry.css"
  "$WWW/lib/entry-tool/dist/entry-tool.css"
  "$WWW/lib/entryjs/dist/entry.min.js"
  "$WWW/lib/entry-paint/dist/static/js/entry-paint.js"
  "$WWW/lib/entryjs/extern/util/static.js"
)

for f in "${PATCH_FILES[@]}"; do
  if [ -f "$f" ]; then
    log "PATCH $f"
    rewrite_paths_in_file "$f"
  fi
done

# quick verify in css/js (원하면 유지)
log "VERIFY PATCH: find remaining 'url(/images' patterns (should be 0)"
grep -RIn "url\(/images" "$WWW" | head -n 20 || true
log "VERIFY PATCH: find remaining '\"/images/' patterns (should be near 0)"
grep -RIn "\"/images/" "$WWW" | head -n 20 || true
# ============================================================
# ============================================================
# FIX: Android is case-sensitive. Create lowercase alias copies
#      and common legacy alias folders for subfolder images.
# ============================================================
bigwarn "FIX: case-sensitive subfolder asset aliases (Android-safe)"

IMGROOT="$WWW/images"
[ -d "$IMGROOT" ] || exit 0

# 1) lower-case directory aliases (e.g. aiUtilize -> aiutilize)
#    and lower-case file aliases inside those directories.
while IFS= read -r -d '' path; do
  rel="${path#$IMGROOT/}"
  lower_rel="$(echo "$rel" | tr 'A-Z' 'a-z')"

  # if same already, skip
  [ "$rel" = "$lower_rel" ] && continue

  src="$IMGROOT/$rel"
  dst="$IMGROOT/$lower_rel"

  if [ -d "$src" ]; then
    mkdir -p "$dst"
    # copy contents, resolve symlinks
    cp -aL "$src/." "$dst/" 2>/dev/null || true
    log "ALIAS DIR: images/$rel -> images/$lower_rel"
  fi
done < <(find "$IMGROOT" -type d -print0 2>/dev/null)

# 2) file aliases (exact lowercase path)
while IFS= read -r -d '' f; do
  rel="${f#$IMGROOT/}"
  lower_rel="$(echo "$rel" | tr 'A-Z' 'a-z')"
  [ "$rel" = "$lower_rel" ] && continue
  dst="$IMGROOT/$lower_rel"
  mkdir -p "$(dirname "$dst")"
  if [ ! -f "$dst" ]; then
    cp -aL "$f" "$dst" 2>/dev/null || true
    log "ALIAS FILE: images/$rel -> images/$lower_rel"
  fi
done < <(find "$IMGROOT" -type f -print0 2>/dev/null)

# 3) common legacy alias folders (몇몇 빌드가 이렇게 요청함)
#    block_icon <-> blockIcon, icon/block_icon 등
if [ -d "$IMGROOT/block_icon" ]; then
  mkdir -p "$IMGROOT/icon/block_icon" "$IMGROOT/blockIcon" "$IMGROOT/icon/blockIcon"
  cp -aL "$IMGROOT/block_icon/." "$IMGROOT/icon/block_icon/" 2>/dev/null || true
  cp -aL "$IMGROOT/block_icon/." "$IMGROOT/blockIcon/" 2>/dev/null || true
  cp -aL "$IMGROOT/block_icon/." "$IMGROOT/icon/blockIcon/" 2>/dev/null || true
  log "ALIAS OK: block_icon -> icon/block_icon, blockIcon, icon/blockIcon"
fi

log "VERIFY (alias): $IMGROOT/icon/block_icon/ai_hand_icon.svg ?"
ls -la "$IMGROOT/icon/block_icon/ai_hand_icon.svg" 2>/dev/null || true

log "COUNT www/images files = $(find "$IMGROOT" -type f 2>/dev/null | wc -l | tr -d ' ')"
# ============================================================
exit 0
