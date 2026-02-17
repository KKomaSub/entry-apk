#!/usr/bin/env bash
# Fetch Entry assets for offline vendoring (APK webview)
# - Parallel downloads
# - Never hard-fail on 404; keep going
# - Summarize missing at end
# - Provide npm-pack fallback for images/media (best-effort)

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-6}"

# ------------ pretty logs ------------
ts() { date +"[%H:%M:%S]"; }
log() { echo "$(ts) $*"; }

BANNER() {
  echo
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $*"
  echo "████████████████████████████████████████████████████████████"
}

# ------------ state ------------
MISSING_REQUIRED=()
MISSING_OPTIONAL=()
FAIL_COUNT=0

# ------------ utils ------------
ensure_dir() { mkdir -p "$1"; }

# safe rm
rmrf() { rm -rf "$1" 2>/dev/null || true; }

# curl download helper
# args: url out
dl_one() {
  local url="$1"
  local out="$2"

  ensure_dir "$(dirname "$out")"

  # If already exists and non-empty, keep
  if [[ -s "$out" ]]; then
    echo "OK   (cached) -> $out"
    return 0
  fi

  # -L follow redirect, --fail for status>=400, but we handle exit codes
  # timeouts to avoid long hang
  if curl -L --fail --retry 2 --retry-delay 1 \
      --connect-timeout 8 --max-time 120 \
      -H "User-Agent: entry-apk-fetch/1.0" \
      -o "$out" "$url" >/dev/null 2>&1; then
    echo "OK   -> $out"
    return 0
  else
    rm -f "$out" >/dev/null 2>&1 || true
    echo "MISS $url"
    return 1
  fi
}

# Try multiple candidate URLs for one output path
# args: out required(0/1) name url1 url2 ...
get_any() {
  local out="$1"; shift
  local required="$1"; shift
  local name="$1"; shift

  local ok=0
  local tried=()
  for url in "$@"; do
    tried+=("$url")
    log "GET  $url"
    if dl_one "$url" "$out"; then
      ok=1
      break
    fi
  done

  if [[ "$ok" -eq 0 ]]; then
    BANNER "FAIL all candidates -> $out"
    echo "Tried:"
    for t in "${tried[@]}"; do echo " - $t"; done

    if [[ "$required" -eq 1 ]]; then
      MISSING_REQUIRED+=("$name :: $out")
      FAIL_COUNT=$((FAIL_COUNT+1))
    else
      MISSING_OPTIONAL+=("$name :: $out")
    fi
  fi
}

# Parallel job runner for get_any calls
# we queue commands as strings, run with xargs -P
queue_file="${ROOT}/.fetch_queue.tmp"
rm -f "$queue_file" >/dev/null 2>&1 || true
touch "$queue_file"

q() {
  # append a command line that will be executed in bash -lc
  echo "$*" >> "$queue_file"
}

run_queue() {
  # run queued commands in parallel, keep going even if some fail
  if [[ ! -s "$queue_file" ]]; then
    return 0
  fi
  # shellcheck disable=SC2016
  cat "$queue_file" | xargs -I{} -P "$MAX_JOBS" bash -lc '{}' || true
  rm -f "$queue_file" >/dev/null 2>&1 || true
  touch "$queue_file"
}

# npm pack extract helper (best effort)
# args: package@version dest_dir
npm_extract() {
  local spec="$1"
  local dest="$2"

  ensure_dir "$dest"
  local tmp="${WWW}/.npm_tmp"
  rmrf "$tmp"; ensure_dir "$tmp"

  log "NPM EXTRACT: $spec -> $dest"
  (cd "$tmp" && npm pack "$spec" >/dev/null 2>&1) || {
    BANNER "npm pack failed: $spec"
    return 1
  }

  local tgz
  tgz="$(ls -1 "$tmp"/*.tgz 2>/dev/null | head -n 1 || true)"
  if [[ -z "$tgz" ]]; then
    BANNER "npm pack produced no tgz: $spec"
    return 1
  fi

  tar -xzf "$tgz" -C "$tmp" >/dev/null 2>&1 || {
    BANNER "tar extract failed: $spec"
    return 1
  }

  # npm pack creates ./package/*
  if [[ -d "$tmp/package" ]]; then
    rmrf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -R "$tmp/package" "$dest" >/dev/null 2>&1 || true
    log "NPM EXTRACT OK: $spec"
    return 0
  fi

  BANNER "npm extract missing ./package: $spec"
  return 1
}

# Copy if exists
copy_if_dir() {
  local src="$1"
  local dst="$2"
  if [[ -d "$src" ]]; then
    rmrf "$dst"
    ensure_dir "$(dirname "$dst")"
    cp -R "$src" "$dst" >/dev/null 2>&1 || true
    log "COPY OK: $src -> $dst"
    return 0
  fi
  return 1
}

# ------------ main ------------
log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"

ensure_dir "$WWW/lib"
ensure_dir "$WWW/js"

# ------------------------------
# 1) CDN libs (lodash/jQuery/CodeMirror/etc)
# ------------------------------
q "get_any '$WWW/lib/lodash/dist/lodash.min.js' 1 'lodash' \
  'https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js'"

q "get_any '$WWW/lib/jquery/jquery.min.js' 1 'jquery' \
  'https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js' \
  'https://code.jquery.com/jquery-1.9.1.min.js'"

q "get_any '$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js' 1 'jquery-ui' \
  'https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js'"

# Velocity (Entry legacy UI sometimes expects it)
q "get_any '$WWW/lib/velocity/velocity.min.js' 1 'velocity' \
  'https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js'"

# CodeMirror (text coding)
q "get_any '$WWW/lib/codemirror/codemirror.js' 1 'codemirror-js' \
  'https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js'"

q "get_any '$WWW/lib/codemirror/codemirror.css' 1 'codemirror-css' \
  'https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css'"

q "get_any '$WWW/lib/codemirror/vim.js' 0 'codemirror-vim(optional)' \
  'https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js'"

# CreateJS (use code.createjs.com; flash plugin optional may 404)
q "get_any '$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js' 1 'preloadjs' \
  'https://code.createjs.com/preloadjs-0.6.0.min.js'"

q "get_any '$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js' 1 'easeljs' \
  'https://code.createjs.com/easeljs-0.8.0.min.js'"

q "get_any '$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js' 1 'soundjs' \
  'https://code.createjs.com/soundjs-0.6.0.min.js'"

q "get_any '$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js' 0 'flashaudioplugin(optional)' \
  'https://code.createjs.com/flashaudioplugin-0.6.0.min.js'"

run_queue

# ------------------------------
# 2) Entry core libs from playentry
# ------------------------------
# NOTE: place into www/lib/entryjs/...
q "get_any '$WWW/lib/entryjs/dist/entry.min.js' 1 'entry.min.js' \
  'https://playentry.org/lib/entry-js/dist/entry.min.js' \
  'https://entry-cdn.pstatic.net/lib/entry-js/dist/entry.min.js'"

q "get_any '$WWW/lib/entryjs/dist/entry.css' 1 'entry.css' \
  'https://playentry.org/lib/entry-js/dist/entry.css' \
  'https://entry-cdn.pstatic.net/lib/entry-js/dist/entry.css'"

q "get_any '$WWW/lib/entryjs/extern/lang/ko.js' 1 'ko.js' \
  'https://playentry.org/lib/entry-js/extern/lang/ko.js' \
  'https://entry-cdn.pstatic.net/lib/entry-js/extern/lang/ko.js'"

q "get_any '$WWW/lib/entryjs/extern/util/static.js' 1 'static.js(EntryStatic)' \
  'https://playentry.org/lib/entry-js/extern/util/static.js' \
  'https://entry-cdn.pstatic.net/lib/entry-js/extern/util/static.js'"

q "get_any '$WWW/lib/entryjs/extern/util/handle.js' 1 'handle.js(EaselHandle)' \
  'https://playentry.org/lib/entry-js/extern/util/handle.js' \
  'https://entry-cdn.pstatic.net/lib/entry-js/extern/util/handle.js'"

q "get_any '$WWW/lib/entryjs/extern/util/bignumber.min.js' 1 'bignumber' \
  'https://playentry.org/lib/entry-js/extern/util/bignumber.min.js' \
  'https://entry-cdn.pstatic.net/lib/entry-js/extern/util/bignumber.min.js'"

# entry-tool
q "get_any '$WWW/lib/entry-tool/dist/entry-tool.js' 1 'entry-tool.js' \
  'https://playentry.org/lib/entry-tool/dist/entry-tool.js' \
  'https://entry-cdn.pstatic.net/lib/entry-tool/dist/entry-tool.js'"

q "get_any '$WWW/lib/entry-tool/dist/entry-tool.css' 1 'entry-tool.css' \
  'https://playentry.org/lib/entry-tool/dist/entry-tool.css' \
  'https://entry-cdn.pstatic.net/lib/entry-tool/dist/entry-tool.css'"

# entry-paint
q "get_any '$WWW/lib/entry-paint/dist/static/js/entry-paint.js' 1 'entry-paint.js' \
  'https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js' \
  'https://entry-cdn.pstatic.net/lib/entry-paint/dist/static/js/entry-paint.js'"

# legacy video module (EntryVideoLegacy)
q "get_any '$WWW/lib/module/legacy-video/index.js' 1 'legacy-video(EntryVideoLegacy)' \
  'https://entry-cdn.pstatic.net/module/legacy-video/index.js' \
  'https://playentry.org/module/legacy-video/index.js'"

# ws locales (필수는 아님, 하지만 있으면 좋음)
q "get_any '$WWW/js/ws/locales.js' 0 'ws/locales.js(optional)' \
  'https://playentry.org/js/ws/locales.js' \
  'https://entry-cdn.pstatic.net/js/ws/locales.js'"

run_queue

# ------------------------------
# 3) NPM fallback: ensure images/media exist (best effort)
#    - 이건 “소스 이미지/extern 폴더”를 채우는 용도
# ------------------------------
BANNER "NPM FALLBACK: extracting packages to ensure images/media exist"

# NOTE: 최신 버전/태그가 바뀔 수 있어서 실패해도 진행
# 가장 중요한 건 entry 패키지에서 images/media/extern가 나오는지
npm_extract "@entrylabs/entry" "${WWW}/.npm_entry_pkg" || true
npm_extract "@entrylabs/entry-tool" "${WWW}/.npm_entry_tool_pkg" || true
npm_extract "@entrylabs/entry-paint" "${WWW}/.npm_entry_paint_pkg" || true

# copy likely folders into expected locations (if exist)
copy_if_dir "${WWW}/.npm_entry_pkg/images" "${WWW}/lib/entryjs/images" || true
copy_if_dir "${WWW}/.npm_entry_pkg/media"  "${WWW}/lib/entryjs/media"  || true
copy_if_dir "${WWW}/.npm_entry_pkg/extern" "${WWW}/lib/entryjs/extern" || true

# some packages place static assets under dist/static etc; best-effort copies
copy_if_dir "${WWW}/.npm_entry_tool_pkg/images" "${WWW}/lib/entry-tool/images" || true
copy_if_dir "${WWW}/.npm_entry_paint_pkg/images" "${WWW}/lib/entry-paint/images" || true

# ------------------------------
# 4) Alias copy: /lib/entry-js path also present (some HTMLs reference it)
# ------------------------------
log "=== Alias copy: /lib/entryjs <-> /lib/entry-js ==="
copy_if_dir "${WWW}/lib/entryjs" "${WWW}/lib/entry-js" || true

# ------------------------------
# 5) Disable sound editor file (prevents React crash / mismatch)
#    (index.html에서 스텁을 쓰는 방식)
# ------------------------------
ensure_dir "${WWW}/lib/external/sound"
if [[ ! -s "${WWW}/lib/external/sound/sound-editor.js" ]]; then
  cat > "${WWW}/lib/external/sound/sound-editor.js" <<'EOF'
/* EntrySoundEditor disabled in this offline build.
 * A mismatched sound editor (React-based) will crash EntryJS.
 * Keep this file as a harmless placeholder.
 */
EOF
  log "WROTE placeholder: /lib/external/sound/sound-editor.js (disabled)"
fi

# ------------------------------
# 6) Basic sanity checks (required files exist)
# ------------------------------
# required minimal set to avoid "Entry.init missing" due to missing files
required_paths=(
  "${WWW}/lib/lodash/dist/lodash.min.js"
  "${WWW}/lib/jquery/jquery.min.js"
  "${WWW}/lib/jquery-ui/ui/minified/jquery-ui.min.js"
  "${WWW}/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
  "${WWW}/lib/EaselJS/lib/easeljs-0.8.0.min.js"
  "${WWW}/lib/SoundJS/lib/soundjs-0.6.0.min.js"
  "${WWW}/lib/entry-tool/dist/entry-tool.js"
  "${WWW}/lib/entry-paint/dist/static/js/entry-paint.js"
  "${WWW}/lib/entryjs/extern/lang/ko.js"
  "${WWW}/lib/entryjs/extern/util/static.js"
  "${WWW}/lib/entryjs/extern/util/handle.js"
  "${WWW}/lib/entryjs/extern/util/bignumber.min.js"
  "${WWW}/lib/entryjs/dist/entry.min.js"
  "${WWW}/lib/module/legacy-video/index.js"
)

for p in "${required_paths[@]}"; do
  if [[ ! -s "$p" ]]; then
    MISSING_REQUIRED+=("required_path :: $p")
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
done

# ------------------------------
# 7) Summary
# ------------------------------
if [[ "${#MISSING_REQUIRED[@]}" -gt 0 ]]; then
  BANNER "FETCH SUMMARY: ${#MISSING_REQUIRED[@]} REQUIRED file(s) missing"
  for m in "${MISSING_REQUIRED[@]}"; do echo " - $m"; done
else
  BANNER "FETCH SUMMARY: all REQUIRED downloads OK"
fi

if [[ "${#MISSING_OPTIONAL[@]}" -gt 0 ]]; then
  BANNER "Optional missing (script continued): ${#MISSING_OPTIONAL[@]}"
  for m in "${MISSING_OPTIONAL[@]}"; do echo " - $m"; done
fi

log "fetch exit=0"
exit 0
