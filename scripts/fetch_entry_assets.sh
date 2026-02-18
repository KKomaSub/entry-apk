#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-5}"

# ✅ 레포에서 직접 복사(= npm 404 회피)
ENTRYJS_REPO="${ENTRYJS_REPO:-https://github.com/entrylabs/entryjs.git}"
ENTRYJS_BRANCH="${ENTRYJS_BRANCH:-master}"

ENTRY_TOOL_REPO="${ENTRY_TOOL_REPO:-https://github.com/entrylabs/entry-tool.git}"
ENTRY_TOOL_BRANCH="${ENTRY_TOOL_BRANCH:-master}"

ENTRY_PAINT_REPO="${ENTRY_PAINT_REPO:-https://github.com/entrylabs/entry-paint.git}"
ENTRY_PAINT_BRANCH="${ENTRY_PAINT_BRANCH:-master}"

mkdir -p "$WWW"

log(){ echo "[$(date +'%H:%M:%S')] $*"; }
bigwarn(){
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $*"
  echo "████████████████████████████████████████████████████████████"
}

# ---- safe path: ALWAYS under $WWW ----
to_www_path(){
  local p="$1"
  p="${p#./}"
  p="${p#/}"         # drop leading slash to avoid /uploads permission
  echo "${WWW}/${p}"
}
ensure_dir(){ mkdir -p "$(dirname "$1")"; }

# ---- parallel ----
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

# ---- fetch ----
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

# ---- copy dir recursively (real files) ----
copy_tree(){
  local src="$1"
  local dst="$2"
  [ -d "$src" ] || return 1
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src"/ "$dst"/
  else
    rm -rf "$dst"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
  fi
}

clone_shallow(){
  local repo="$1" branch="$2" dst="$3"
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  git clone --depth 1 --branch "$branch" "$repo" "$dst" >/dev/null 2>&1
}

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"

# ------------------------------------------------------------
# 1) CDN/공개 URL로 받을 수 있는 것들(누락 난 것 포함)
# ------------------------------------------------------------
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" "/lib/lodash/dist/lodash.min.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" "/lib/jquery/jquery.min.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" "/lib/jquery-ui/ui/minified/jquery-ui.min.js"

job_spawn fetch_one "https://code.createjs.com/preloadjs-0.6.0.min.js" "/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
job_spawn fetch_one "https://code.createjs.com/easeljs-0.8.0.min.js" "/lib/EaselJS/lib/easeljs-0.8.0.min.js"
job_spawn fetch_one "https://code.createjs.com/soundjs-0.6.0.min.js" "/lib/SoundJS/lib/soundjs-0.6.0.min.js"
( job_spawn fetch_one "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" "/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" ) || true

# ✅ velocity / codemirror (지금 로그에서 MISS 난 것들)
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" "/lib/velocity/velocity.min.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js" "/lib/codemirror/codemirror.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css" "/lib/codemirror/codemirror.css"
( job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js" "/lib/codemirror/vim.js" ) || true

# locales (optional)
( job_spawn fetch_one "https://playentry.org/js/ws/locales.js" "/js/ws/locales.js" ) || true

# legacy video (지금 로그에서 MISS)
job_spawn fetch_one "https://entry-cdn.pstatic.net/module/legacy-video/index.js" "/lib/module/legacy-video/index.js"

job_wait_all || true

# ------------------------------------------------------------
# 2) entryjs FULL COPY (images 하위폴더까지 포함)
# ------------------------------------------------------------
log "=== CLONE entryjs (FULL static) ==="
if ! command -v git >/dev/null 2>&1; then
  bigwarn "git not found. Cannot clone repos."
  exit 1
fi

TMP_ENTRYJS="${WWW}/.tmp_entryjs_clone"
if ! clone_shallow "$ENTRYJS_REPO" "$ENTRYJS_BRANCH" "$TMP_ENTRYJS"; then
  bigwarn "entryjs clone failed: $ENTRYJS_REPO ($ENTRYJS_BRANCH)"
  exit 1
fi

DEST_ENTRYJS="${WWW}/lib/entryjs"
DEST_ENTRYJS_ALIAS="${WWW}/lib/entry-js"
mkdir -p "$DEST_ENTRYJS" "$DEST_ENTRYJS_ALIAS"

# entryjs repo에서 존재하는 폴더만 전부 복사
for d in dist images media extern src res resources static public uploads; do
  if [ -d "${TMP_ENTRYJS}/${d}" ]; then
    log "COPY entryjs ${d}/ -> ${DEST_ENTRYJS}/${d}/"
    copy_tree "${TMP_ENTRYJS}/${d}" "${DEST_ENTRYJS}/${d}" || true
  fi
done

# dist가 없으면 CDN fallback (최소)
if [ ! -f "${DEST_ENTRYJS}/dist/entry.min.js" ]; then
  bigwarn "entryjs dist/entry.min.js missing in repo copy -> CDN fallback"
  fetch_one "https://playentry.org/lib/entry-js/dist/entry.min.js" "/lib/entryjs/dist/entry.min.js" || true
fi
if [ ! -f "${DEST_ENTRYJS}/dist/entry.css" ]; then
  fetch_one "https://playentry.org/lib/entry-js/dist/entry.css" "/lib/entryjs/dist/entry.css" || true
fi
if [ ! -f "${DEST_ENTRYJS}/extern/lang/ko.js" ]; then
  fetch_one "https://playentry.org/lib/entry-js/extern/lang/ko.js" "/lib/entryjs/extern/lang/ko.js" || true
fi
if [ ! -f "${DEST_ENTRYJS}/extern/util/static.js" ]; then
  fetch_one "https://playentry.org/lib/entry-js/extern/util/static.js" "/lib/entryjs/extern/util/static.js" || true
fi
if [ ! -f "${DEST_ENTRYJS}/extern/util/handle.js" ]; then
  fetch_one "https://playentry.org/lib/entry-js/extern/util/handle.js" "/lib/entryjs/extern/util/handle.js" || true
fi
if [ ! -f "${DEST_ENTRYJS}/extern/util/bignumber.min.js" ]; then
  fetch_one "https://playentry.org/lib/entry-js/extern/util/bignumber.min.js" "/lib/entryjs/extern/util/bignumber.min.js" || true
fi

# alias mirror
log "=== ALIAS copy: lib/entryjs -> lib/entry-js ==="
copy_tree "$DEST_ENTRYJS" "$DEST_ENTRYJS_ALIAS" || true

# ------------------------------------------------------------
# 3) entry-tool / entry-paint: npm 404라서 GitHub clone로 “dist만” 복사
#    (index.html이 ./lib/entry-tool/dist/... , ./lib/entry-paint/dist/... 를 요구)
# ------------------------------------------------------------
log "=== CLONE entry-tool (dist) ==="
TMP_TOOL="${WWW}/.tmp_entry_tool_clone"
if clone_shallow "$ENTRY_TOOL_REPO" "$ENTRY_TOOL_BRANCH" "$TMP_TOOL"; then
  if [ -d "${TMP_TOOL}/dist" ]; then
    copy_tree "${TMP_TOOL}/dist" "${WWW}/lib/entry-tool/dist" || true
  fi
else
  bigwarn "entry-tool clone failed (continuing). You will MISS EntryTool."
fi

log "=== CLONE entry-paint (dist) ==="
TMP_PAINT="${WWW}/.tmp_entry_paint_clone"
if clone_shallow "$ENTRY_PAINT_REPO" "$ENTRY_PAINT_BRANCH" "$TMP_PAINT"; then
  if [ -d "${TMP_PAINT}/dist" ]; then
    copy_tree "${TMP_PAINT}/dist" "${WWW}/lib/entry-paint/dist" || true
  fi
else
  bigwarn "entry-paint clone failed (continuing)."
fi

# ------------------------------------------------------------
# 4) 절대경로(/images /media /uploads) 미러링: “실제 복사본” 생성
# ------------------------------------------------------------
log "=== ABSOLUTE PATH mirrors: www/images,www/media,www/uploads ==="
mkdir -p "$WWW/images" "$WWW/media" "$WWW/uploads"

if [ -d "${DEST_ENTRYJS}/images" ]; then
  copy_tree "${DEST_ENTRYJS}/images" "$WWW/images" || true
fi
if [ -d "${DEST_ENTRYJS}/media" ]; then
  copy_tree "${DEST_ENTRYJS}/media" "$WWW/media" || true
fi
# entryjs repo에 uploads가 있으면 미러
if [ -d "${TMP_ENTRYJS}/uploads" ]; then
  copy_tree "${TMP_ENTRYJS}/uploads" "$WWW/uploads" || true
fi

# ------------------------------------------------------------
# 5) 빠른 검증 (당신 케이스: images/icon/block_icon.png)
# ------------------------------------------------------------
log "=== VERIFY nested images ==="
if [ -f "$WWW/images/icon/block_icon.png" ] || [ -f "$WWW/lib/entryjs/images/icon/block_icon.png" ]; then
  log "OK  nested image exists: images/icon/block_icon.png"
else
  bigwarn "MISSING nested image: images/icon/block_icon.png"
  log "List $WWW/images/icon:"
  ls -la "$WWW/images/icon" || true
  log "List $WWW/lib/entryjs/images/icon:"
  ls -la "$WWW/lib/entryjs/images/icon" || true
fi

log "=== SIZE CHECK ==="
du -sh "$WWW" || true
du -sh "$WWW/images" || true
du -sh "$WWW/lib/entryjs" || true
du -sh "$WWW/lib/entry-tool/dist" || true
du -sh "$WWW/lib/entry-paint/dist" || true

log "✅ FETCH DONE"
