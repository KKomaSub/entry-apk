#!/usr/bin/env bash
# scripts/fetch_entry_assets.sh
# Extended offline vendoring + auto patch sound-editor.js

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-6}"

ts(){ date +"[%H:%M:%S]"; }
log(){ echo "$(ts) $*"; }
BANNER(){ echo; echo "████████████████████████████████████████████████████████████"; echo "🚨🚨🚨 $*"; echo "████████████████████████████████████████████████████████████"; }

mkdir -p "$WWW/lib" "$WWW/js" "$WWW/lib/external/sound"

MISSING_REQUIRED=()
MISSING_OPTIONAL=()

dl_one() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  if [[ -s "$out" ]]; then
    echo "OK   (cached) -> $out"
    return 0
  fi
  if curl -L --fail --retry 2 --retry-delay 1 --connect-timeout 8 --max-time 180 \
      -H "User-Agent: entry-apk-fetch/3.1" \
      -o "$out" "$url" >/dev/null 2>&1; then
    echo "OK   -> $out"
    return 0
  fi
  rm -f "$out" >/dev/null 2>&1 || true
  echo "MISS $url"
  return 1
}

get_any() {
  local out="$1"; shift
  local required="$1"; shift
  local name="$1"; shift

  local ok=0
  local tried=()
  for url in "$@"; do
    tried+=("$url")
    log "GET  $url"
    if dl_one "$url" "$out"; then ok=1; break; fi
  done

  if [[ "$ok" -eq 0 ]]; then
    BANNER "FAIL all candidates -> $out"
    echo "Tried:"; for t in "${tried[@]}"; do echo " - $t"; done
    if [[ "$required" -eq 1 ]]; then
      MISSING_REQUIRED+=("$name :: $out")
    else
      MISSING_OPTIONAL+=("$name :: $out")
    fi
  fi
}

QUEUE="${ROOT}/.fetch_queue.tmp"
: > "$QUEUE"
q(){ echo "$*" >> "$QUEUE"; }
runq(){
  [[ -s "$QUEUE" ]] || return 0
  cat "$QUEUE" | xargs -I{} -P "$MAX_JOBS" bash -lc '{}' || true
  : > "$QUEUE"
}

npm_extract() {
  local spec="$1" dest="$2"
  local tmp="${WWW}/.npm_tmp"
  rm -rf "$tmp" "$dest" >/dev/null 2>&1 || true
  mkdir -p "$tmp" "$dest"
  log "NPM EXTRACT: $spec -> $dest"
  (cd "$tmp" && npm pack "$spec" >/dev/null 2>&1) || { BANNER "npm pack failed: $spec"; return 1; }
  local tgz
  tgz="$(ls -1 "$tmp"/*.tgz 2>/dev/null | head -n 1 || true)"
  [[ -n "$tgz" ]] || { BANNER "npm pack produced no tgz: $spec"; return 1; }
  tar -xzf "$tgz" -C "$tmp" >/dev/null 2>&1 || { BANNER "tar extract failed: $spec"; return 1; }
  [[ -d "$tmp/package" ]] || { BANNER "npm extract missing ./package: $spec"; return 1; }
  cp -R "$tmp/package/." "$dest" >/dev/null 2>&1 || true
  log "NPM EXTRACT OK: $spec"
  return 0
}

copy_if_dir(){
  local src="$1" dst="$2"
  if [[ -d "$src" ]]; then
    rm -rf "$dst" >/dev/null 2>&1 || true
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst" >/dev/null 2>&1 || true
    log "COPY OK: $src -> $dst"
  fi
}

log "=== Fetch Entry assets (offline vendoring + sound-editor patch) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"

# Core libs
q "get_any '$WWW/lib/lodash/dist/lodash.min.js' 1 'lodash' \
  'https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js'"

q "get_any '$WWW/lib/jquery/jquery.min.js' 1 'jquery' \
  'https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js' \
  'https://code.jquery.com/jquery-1.9.1.min.js'"

q "get_any '$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js' 1 'jquery-ui' \
  'https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js'"

q "get_any '$WWW/lib/velocity/velocity.min.js' 1 'velocity' \
  'https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js'"

q "get_any '$WWW/lib/codemirror/codemirror.js' 1 'codemirror-js' \
  'https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js'"

q "get_any '$WWW/lib/codemirror/codemirror.css' 1 'codemirror-css' \
  'https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css'"

q "get_any '$WWW/lib/codemirror/vim.js' 0 'codemirror-vim(optional)' \
  'https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js'"

q "get_any '$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js' 1 'preloadjs' \
  'https://code.createjs.com/preloadjs-0.6.0.min.js'"

q "get_any '$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js' 1 'easeljs' \
  'https://code.createjs.com/easeljs-0.8.0.min.js'"

q "get_any '$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js' 1 'soundjs' \
  'https://code.createjs.com/soundjs-0.6.0.min.js'"

q "get_any '$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js' 0 'flashaudioplugin(optional)' \
  'https://code.createjs.com/flashaudioplugin-0.6.0.min.js'"

runq

# Entry / tool / paint / legacy-video / locales
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

q "get_any '$WWW/lib/entry-tool/dist/entry-tool.js' 1 'entry-tool.js' \
  'https://playentry.org/lib/entry-tool/dist/entry-tool.js' \
  'https://entry-cdn.pstatic.net/lib/entry-tool/dist/entry-tool.js'"

q "get_any '$WWW/lib/entry-tool/dist/entry-tool.css' 1 'entry-tool.css' \
  'https://playentry.org/lib/entry-tool/dist/entry-tool.css' \
  'https://entry-cdn.pstatic.net/lib/entry-tool/dist/entry-tool.css'"

q "get_any '$WWW/lib/entry-paint/dist/static/js/entry-paint.js' 1 'entry-paint.js' \
  'https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js' \
  'https://entry-cdn.pstatic.net/lib/entry-paint/dist/static/js/entry-paint.js'"

q "get_any '$WWW/lib/module/legacy-video/index.js' 1 'legacy-video(EntryVideoLegacy)' \
  'https://entry-cdn.pstatic.net/module/legacy-video/index.js' \
  'https://playentry.org/module/legacy-video/index.js'"

q "get_any '$WWW/js/ws/locales.js' 0 'ws/locales.js(optional)' \
  'https://playentry.org/js/ws/locales.js' \
  'https://entry-cdn.pstatic.net/js/ws/locales.js'"

runq

BANNER "NPM FALLBACK: extracting packages to ensure images/media exist (best-effort)"
npm_extract "@entrylabs/entry" "${WWW}/.npm_entry_pkg" || true
copy_if_dir "${WWW}/.npm_entry_pkg/images" "${WWW}/lib/entryjs/images"
copy_if_dir "${WWW}/.npm_entry_pkg/media"  "${WWW}/lib/entryjs/media"
copy_if_dir "${WWW}/.npm_entry_pkg/extern" "${WWW}/lib/entryjs/extern"

log "=== Alias copy: /lib/entryjs <-> /lib/entry-js ==="
rm -rf "${WWW}/lib/entry-js" >/dev/null 2>&1 || true
cp -R "${WWW}/lib/entryjs" "${WWW}/lib/entry-js" >/dev/null 2>&1 || true

# ✅ Auto patch sound-editor.js (create/overwrite as needed)
log "=== Auto patch sound-editor.js ==="
node "${ROOT}/scripts/patch_sound_editor.js" || true

# Final summary
required=(
  "$WWW/lib/lodash/dist/lodash.min.js"
  "$WWW/lib/jquery/jquery.min.js"
  "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
  "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js"
  "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js"
  "$WWW/lib/entry-tool/dist/entry-tool.js"
  "$WWW/lib/entryjs/extern/util/static.js"
  "$WWW/lib/entryjs/dist/entry.min.js"
  "$WWW/lib/module/legacy-video/index.js"
  "$WWW/lib/external/sound/sound-editor.js"
)

for p in "${required[@]}"; do
  [[ -s "$p" ]] || MISSING_REQUIRED+=("required_path :: $p")
done

if [[ "${#MISSING_REQUIRED[@]}" -gt 0 ]]; then
  BANNER "FETCH SUMMARY: REQUIRED missing = ${#MISSING_REQUIRED[@]}"
  for x in "${MISSING_REQUIRED[@]}"; do echo " - $x"; done
else
  BANNER "FETCH SUMMARY: all REQUIRED downloads OK"
fi

if [[ "${#MISSING_OPTIONAL[@]}" -gt 0 ]]; then
  BANNER "Optional missing = ${#MISSING_OPTIONAL[@]} (script continued)"
  for x in "${MISSING_OPTIONAL[@]}"; do echo " - $x"; done
fi

log "fetch exit=0"
exit 0
