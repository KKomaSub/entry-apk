#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-5}"

# repos
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

# ---- build helper (npm) ----
npm_build_repo(){
  local repo_dir="$1"
  local build_cmd="${2:-build}"
  (
    cd "$repo_dir"
    # package-lock 없을 수도 있으니 ci 대신 install
    npm install --no-audit --no-fund >/dev/null 2>&1 || npm install --no-audit --no-fund
    # build script가 없으면 실패할 수 있으므로 조건 처리
    if npm run | grep -qE " ${build_cmd}\b"; then
      npm run "$build_cmd"
    else
      bigwarn "No npm script '${build_cmd}' in $repo_dir (skipping build)"
      return 2
    fi
  )
}

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"

# ------------------------------------------------------------
# 1) CDN/공개 URL: 필수 libs
# ------------------------------------------------------------
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" "/lib/lodash/dist/lodash.min.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" "/lib/jquery/jquery.min.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" "/lib/jquery-ui/ui/minified/jquery-ui.min.js"

job_spawn fetch_one "https://code.createjs.com/preloadjs-0.6.0.min.js" "/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
job_spawn fetch_one "https://code.createjs.com/easeljs-0.8.0.min.js" "/lib/EaselJS/lib/easeljs-0.8.0.min.js"
job_spawn fetch_one "https://code.createjs.com/soundjs-0.6.0.min.js" "/lib/SoundJS/lib/soundjs-0.6.0.min.js"
( job_spawn fetch_one "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" "/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" ) || true

job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" "/lib/velocity/velocity.min.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js" "/lib/codemirror/codemirror.js"
job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css" "/lib/codemirror/codemirror.css"
( job_spawn fetch_one "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js" "/lib/codemirror/vim.js" ) || true

# locales(opt)
( job_spawn fetch_one "https://playentry.org/js/ws/locales.js" "/js/ws/locales.js" ) || true

# legacy video (필수)
job_spawn fetch_one "https://entry-cdn.pstatic.net/module/legacy-video/index.js" "/lib/module/legacy-video/index.js"

job_wait_all || true

# ------------------------------------------------------------
# 2) entryjs FULL COPY (images 하위 폴더 포함)
# ------------------------------------------------------------
log "=== CLONE entryjs (FULL static) ==="
command -v git >/dev/null 2>&1 || { bigwarn "git not found"; exit 1; }

TMP_ENTRYJS="${WWW}/.tmp_entryjs_clone"
if ! clone_shallow "$ENTRYJS_REPO" "$ENTRYJS_BRANCH" "$TMP_ENTRYJS"; then
  bigwarn "entryjs clone failed: $ENTRYJS_REPO ($ENTRYJS_BRANCH)"
  exit 1
fi

DEST_ENTRYJS="${WWW}/lib/entryjs"
DEST_ENTRYJS_ALIAS="${WWW}/lib/entry-js"
mkdir -p "$DEST_ENTRYJS" "$DEST_ENTRYJS_ALIAS"

for d in dist images media extern src res resources static public uploads; do
  if [ -d "${TMP_ENTRYJS}/${d}" ]; then
    log "COPY entryjs ${d}/ -> ${DEST_ENTRYJS}/${d}/"
    copy_tree "${TMP_ENTRYJS}/${d}" "${DEST_ENTRYJS}/${d}" || true
  fi
done

# dist가 없으면 CDN fallback (최소)
[ -f "${DEST_ENTRYJS}/dist/entry.min.js" ] || fetch_one "https://playentry.org/lib/entry-js/dist/entry.min.js" "/lib/entryjs/dist/entry.min.js" || true
[ -f "${DEST_ENTRYJS}/dist/entry.css" ]    || fetch_one "https://playentry.org/lib/entry-js/dist/entry.css" "/lib/entryjs/dist/entry.css" || true
[ -f "${DEST_ENTRYJS}/extern/lang/ko.js" ] || fetch_one "https://playentry.org/lib/entry-js/extern/lang/ko.js" "/lib/entryjs/extern/lang/ko.js" || true
[ -f "${DEST_ENTRYJS}/extern/util/static.js" ] || fetch_one "https://playentry.org/lib/entry-js/extern/util/static.js" "/lib/entryjs/extern/util/static.js" || true
[ -f "${DEST_ENTRYJS}/extern/util/handle.js" ] || fetch_one "https://playentry.org/lib/entry-js/extern/util/handle.js" "/lib/entryjs/extern/util/handle.js" || true
[ -f "${DEST_ENTRYJS}/extern/util/bignumber.min.js" ] || fetch_one "https://playentry.org/lib/entry-js/extern/util/bignumber.min.js" "/lib/entryjs/extern/util/bignumber.min.js" || true

log "=== ALIAS copy: lib/entryjs -> lib/entry-js ==="
copy_tree "$DEST_ENTRYJS" "$DEST_ENTRYJS_ALIAS" || true

# ------------------------------------------------------------
# 3) entry-tool: dist가 없으면 "빌드해서 dist 생성" 후 복사
# ------------------------------------------------------------
log "=== RESTORE entry-tool (must provide lib/entry-tool/dist/entry-tool.{js,css}) ==="
TMP_TOOL="${WWW}/.tmp_entry_tool_clone"
rm -rf "${WWW}/lib/entry-tool/dist"
mkdir -p "${WWW}/lib/entry-tool/dist"

if clone_shallow "$ENTRY_TOOL_REPO" "$ENTRY_TOOL_BRANCH" "$TMP_TOOL"; then
  if [ -d "${TMP_TOOL}/dist" ] && (ls -1 "${TMP_TOOL}/dist" | grep -q "entry-tool"); then
    log "COPY entry-tool dist/ -> www/lib/entry-tool/dist/"
    copy_tree "${TMP_TOOL}/dist" "${WWW}/lib/entry-tool/dist" || true
  else
    bigwarn "entry-tool dist missing in repo -> building..."
    if npm_build_repo "$TMP_TOOL" "build"; then
      # 빌드 결과 후보 디렉토리들 중 dist 찾기
      if [ -d "${TMP_TOOL}/dist" ]; then
        copy_tree "${TMP_TOOL}/dist" "${WWW}/lib/entry-tool/dist" || true
      elif [ -d "${TMP_TOOL}/build" ]; then
        copy_tree "${TMP_TOOL}/build" "${WWW}/lib/entry-tool/dist" || true
      else
        bigwarn "entry-tool build done but no dist/build directory found"
      fi
    else
      bigwarn "entry-tool build failed (EntryTool will be missing)"
    fi
  fi
else
  bigwarn "entry-tool clone failed (EntryTool will be missing)"
fi

# ------------------------------------------------------------
# 4) entry-paint: dist가 없으면 "빌드해서 dist 생성" 후 복사
# ------------------------------------------------------------
log "=== RESTORE entry-paint (must provide lib/entry-paint/dist/static/js/entry-paint.js) ==="
TMP_PAINT="${WWW}/.tmp_entry_paint_clone"
rm -rf "${WWW}/lib/entry-paint/dist"
mkdir -p "${WWW}/lib/entry-paint/dist"

if clone_shallow "$ENTRY_PAINT_REPO" "$ENTRY_PAINT_BRANCH" "$TMP_PAINT"; then
  if [ -d "${TMP_PAINT}/dist" ]; then
    copy_tree "${TMP_PAINT}/dist" "${WWW}/lib/entry-paint/dist" || true
  else
    bigwarn "entry-paint dist missing in repo -> building..."
    if npm_build_repo "$TMP_PAINT" "build"; then
      if [ -d "${TMP_PAINT}/dist" ]; then
        copy_tree "${TMP_PAINT}/dist" "${WWW}/lib/entry-paint/dist" || true
      elif [ -d "${TMP_PAINT}/build" ]; then
        copy_tree "${TMP_PAINT}/build" "${WWW}/lib/entry-paint/dist" || true
      else
        bigwarn "entry-paint build done but no dist/build directory found"
      fi
    else
      bigwarn "entry-paint build failed"
    fi
  fi
else
  bigwarn "entry-paint clone failed"
fi

# ------------------------------------------------------------
# 5) 절대경로(/images /media /uploads) 미러링: 실제 파일 복사
# ------------------------------------------------------------
log "=== ABSOLUTE PATH mirrors: www/images,www/media,www/uploads ==="
mkdir -p "$WWW/images" "$WWW/media" "$WWW/uploads"

[ -d "${DEST_ENTRYJS}/images" ] && copy_tree "${DEST_ENTRYJS}/images" "$WWW/images" || true
[ -d "${DEST_ENTRYJS}/media" ]  && copy_tree "${DEST_ENTRYJS}/media"  "$WWW/media"  || true
[ -d "${TMP_ENTRYJS}/uploads" ] && copy_tree "${TMP_ENTRYJS}/uploads" "$WWW/uploads" || true

# ------------------------------------------------------------
# 6) Verify: entry-tool/entry-paint 실제로 생겼는지 (지금 문제 핵심)
# ------------------------------------------------------------
log "=== VERIFY must-have files ==="
if [ -f "$WWW/lib/entry-tool/dist/entry-tool.js" ]; then
  log "OK  entry-tool.js exists"
else
  bigwarn "MISSING: www/lib/entry-tool/dist/entry-tool.js"
  ls -la "$WWW/lib/entry-tool/dist" || true
fi
if [ -f "$WWW/lib/entry-tool/dist/entry-tool.css" ]; then
  log "OK  entry-tool.css exists"
else
  bigwarn "MISSING: www/lib/entry-tool/dist/entry-tool.css"
  ls -la "$WWW/lib/entry-tool/dist" || true
fi
if [ -f "$WWW/lib/entry-paint/dist/static/js/entry-paint.js" ]; then
  log "OK  entry-paint.js exists"
else
  bigwarn "MISSING: www/lib/entry-paint/dist/static/js/entry-paint.js"
  find "$WWW/lib/entry-paint/dist" -maxdepth 4 -type f | head -n 50 || true
fi

log "=== SIZE CHECK ==="
du -sh "$WWW" || true
du -sh "$WWW/images" || true
du -sh "$WWW/lib/entryjs" || true
du -sh "$WWW/lib/entry-tool" || true
du -sh "$WWW/lib/entry-paint" || true

log "✅ FETCH DONE"
