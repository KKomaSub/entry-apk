#!/usr/bin/env bash
set -u

# ===============================
# Fetch Entry assets (offline vendoring)
# - parallel downloads (MAX_JOBS=5)
# - downloads core libs + entry assets
# - scans CSS url(...) and fetches referenced files (images/fonts)
# - optional files don't fail build
# ===============================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-5}"

ENTRY_ORIGIN="https://playentry.org"
ENTRY_CDN="https://entry-cdn.pstatic.net"
CDNJS="https://cdnjs.cloudflare.com/ajax/libs"
CREATEJS="https://code.createjs.com"

mkdir -p "${WWW}"
mkdir -p "${WWW}/lib" "${WWW}/js"

LOG() { echo "[$(date +%H:%M:%S)] $*"; }
BANNER() {
  echo
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $*"
  echo "████████████████████████████████████████████████████████████"
}
ERR_BIG() { BANNER "$*"; }

# ---- curl helper ----
curl_dl() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  # -f fail on 4xx/5xx, -L follow
  curl -fL --retry 3 --retry-delay 1 --connect-timeout 15 --max-time 180 \
    -H "Cache-Control: no-cache" \
    -o "$out" "$url"
}

# ---- job queue file ----
QUEUE_FILE="$(mktemp)"
trap 'rm -f "$QUEUE_FILE"' EXIT

# line format: URL<TAB>DEST<TAB>OPTIONAL(0/1)
add_job() {
  local url="$1" dest="$2" opt="${3:-0}"
  printf "%s\t%s\t%s\n" "$url" "$dest" "$opt" >> "$QUEUE_FILE"
}

# ---- run jobs in parallel (xargs -P) ----
run_jobs() {
  local missing=0
  local total
  total="$(wc -l < "$QUEUE_FILE" | tr -d ' ')"
  LOG "Queued ${total} download(s), MAX_JOBS=${MAX_JOBS}"

  # process
  cat "$QUEUE_FILE" | xargs -P "$MAX_JOBS" -n 1 -I {} bash -lc '
    line="{}"
    url="$(printf "%s" "$line" | cut -f1)"
    out="$(printf "%s" "$line" | cut -f2)"
    opt="$(printf "%s" "$line" | cut -f3)"
    mkdir -p "$(dirname "$out")"
    echo "[DL] $url -> $out"
    if curl -fL --retry 3 --retry-delay 1 --connect-timeout 15 --max-time 180 \
        -H "Cache-Control: no-cache" \
        -o "$out" "$url" >/dev/null 2>&1; then
      echo "[OK] $out"
      exit 0
    else
      if [ "$opt" = "1" ]; then
        echo "[MISS(opt)] $url"
        exit 0
      fi
      echo "[MISS] $url"
      exit 9
    fi
  ' || missing=1

  rm -f "$QUEUE_FILE"
  touch "$QUEUE_FILE"

  if [ "$missing" = "1" ]; then
    ERR_BIG "Some required download(s) failed"
    return 1
  fi
  return 0
}

# ---- CSS url(...) scanner ----
# Fetch relative assets referenced by CSS (images/fonts). Works for:
#   url(../images/a.png)  url(/lib/entryjs/images/a.png)  url(images/a.png)
scan_css_urls_and_fetch() {
  local css_path="$1"
  [ -f "$css_path" ] || return 0

  LOG "Scan CSS url(...): ${css_path}"

  # Extract url(...) values, remove quotes, ignore data:
  local urls
  urls="$(perl -ne '
    while (m/url\(([^)]+)\)/g) {
      my $u=$1;
      $u =~ s/^\s+|\s+$//g;
      $u =~ s/^["'\'']|["'\'']$//g;
      next if $u =~ /^data:/;
      print "$u\n";
    }
  ' "$css_path" | sort -u)"

  [ -n "$urls" ] || return 0

  local css_dir rel out url
  css_dir="$(dirname "$css_path")"

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue

    # absolute path starting with /
    if [[ "$rel" == /* ]]; then
      url="${ENTRY_ORIGIN}${rel}"
      out="${WWW}${rel}"
    elif [[ "$rel" =~ ^https?:// ]]; then
      url="$rel"
      # map to www/lib/external_http/... (avoid weird path)
      out="${WWW}/lib/_ext/$(echo "$rel" | sed -E 's#^https?://##' | tr "?&=" "___")"
    else
      # relative to css file directory
      url="${ENTRY_ORIGIN}/$(realpath -m --relative-to="${WWW}" "${css_dir}/${rel}" | sed 's#^\.\./##')"
      # but better: output to same relative dir under www
      out="$(realpath -m "${css_dir}/${rel}")"
      # If out escapes WWW, clamp it under WWW/lib/_cssrel/
      if [[ "$out" != "$WWW"* ]]; then
        out="${WWW}/lib/_cssrel/${rel}"
      fi
    fi

    # queue as optional (some urls may be dead)
    add_job "$url" "$out" 1
  done <<< "$urls"
}

# ---- create required dirs ----
mkdir -p \
  "${WWW}/lib/lodash/dist" \
  "${WWW}/lib/jquery" \
  "${WWW}/lib/jquery-ui/ui/minified" \
  "${WWW}/lib/PreloadJS/lib" \
  "${WWW}/lib/EaselJS/lib" \
  "${WWW}/lib/SoundJS/lib" \
  "${WWW}/lib/velocity" \
  "${WWW}/lib/codemirror" \
  "${WWW}/lib/entry-tool/dist" \
  "${WWW}/lib/entryjs/dist" \
  "${WWW}/lib/entryjs/extern/lang" \
  "${WWW}/lib/entryjs/extern/util" \
  "${WWW}/lib/module/legacy-video" \
  "${WWW}/lib/entry-paint/dist/static/js" \
  "${WWW}/lib/external/sound" \
  "${WWW}/js/ws"

LOG "=== Fetch Entry assets (offline vendoring) ==="
LOG "ROOT=${ROOT}"
LOG "WWW =${WWW}"
LOG "MAX_JOBS=${MAX_JOBS}"

# ===============================
# 1) Core libs (cdnjs/createjs)
# ===============================
add_job "${CDNJS}/lodash.js/4.17.10/lodash.min.js" \
  "${WWW}/lib/lodash/dist/lodash.min.js" 0

add_job "${CDNJS}/jquery/1.9.1/jquery.min.js" \
  "${WWW}/lib/jquery/jquery.min.js" 0

add_job "${CDNJS}/jqueryui/1.10.4/jquery-ui.min.js" \
  "${WWW}/lib/jquery-ui/ui/minified/jquery-ui.min.js" 0

add_job "${CDNJS}/velocity/1.2.3/velocity.min.js" \
  "${WWW}/lib/velocity/velocity.min.js" 0

add_job "${CDNJS}/codemirror/5.65.16/codemirror.min.css" \
  "${WWW}/lib/codemirror/codemirror.css" 0
add_job "${CDNJS}/codemirror/5.65.16/codemirror.min.js" \
  "${WWW}/lib/codemirror/codemirror.js" 0
add_job "${CDNJS}/codemirror/5.65.16/keymap/vim.min.js" \
  "${WWW}/lib/codemirror/vim.js" 1

add_job "${CREATEJS}/preloadjs-0.6.0.min.js" \
  "${WWW}/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" 0
add_job "${CREATEJS}/easeljs-0.8.0.min.js" \
  "${WWW}/lib/EaselJS/lib/easeljs-0.8.0.min.js" 0
add_job "${CREATEJS}/soundjs-0.6.0.min.js" \
  "${WWW}/lib/SoundJS/lib/soundjs-0.6.0.min.js" 0
# flashaudioplugin은 종종 404임 (optional)
add_job "${CREATEJS}/flashaudioplugin-0.6.0.min.js" \
  "${WWW}/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" 1

# ===============================
# 2) Entry assets (playentry)
# ===============================
# entryjs dist + extern
add_job "${ENTRY_ORIGIN}/lib/entry-js/dist/entry.min.js" \
  "${WWW}/lib/entryjs/dist/entry.min.js" 0
add_job "${ENTRY_ORIGIN}/lib/entry-js/dist/entry.css" \
  "${WWW}/lib/entryjs/dist/entry.css" 0
add_job "${ENTRY_ORIGIN}/lib/entry-js/extern/lang/ko.js" \
  "${WWW}/lib/entryjs/extern/lang/ko.js" 0
add_job "${ENTRY_ORIGIN}/lib/entry-js/extern/util/static.js" \
  "${WWW}/lib/entryjs/extern/util/static.js" 0
add_job "${ENTRY_ORIGIN}/lib/entry-js/extern/util/handle.js" \
  "${WWW}/lib/entryjs/extern/util/handle.js" 0
add_job "${ENTRY_ORIGIN}/lib/entry-js/extern/util/bignumber.min.js" \
  "${WWW}/lib/entryjs/extern/util/bignumber.min.js" 0

# entry-tool
add_job "${ENTRY_ORIGIN}/lib/entry-tool/dist/entry-tool.js" \
  "${WWW}/lib/entry-tool/dist/entry-tool.js" 0
add_job "${ENTRY_ORIGIN}/lib/entry-tool/dist/entry-tool.css" \
  "${WWW}/lib/entry-tool/dist/entry-tool.css" 0

# entry-paint
add_job "${ENTRY_ORIGIN}/lib/entry-paint/dist/static/js/entry-paint.js" \
  "${WWW}/lib/entry-paint/dist/static/js/entry-paint.js" 0

# legacy video module (cdn)
add_job "${ENTRY_CDN}/module/legacy-video/index.js" \
  "${WWW}/lib/module/legacy-video/index.js" 0

# locales
add_job "${ENTRY_ORIGIN}/js/ws/locales.js" \
  "${WWW}/js/ws/locales.js" 1

# sound editor (여러 후보)
add_job "${ENTRY_ORIGIN}/lib/external/sound/sound-editor.js" \
  "${WWW}/lib/external/sound/sound-editor.js" 1
add_job "${ENTRY_CDN}/external/sound/sound-editor.js" \
  "${WWW}/lib/external/sound/sound-editor.js" 1

# ===============================
# 3) Download phase 1
# ===============================
run_jobs || exit 1

# ===============================
# 4) If sound-editor missing, create minimal stub (keeps Entry alive)
# ===============================
if [ ! -f "${WWW}/lib/external/sound/sound-editor.js" ]; then
  ERR_BIG "sound-editor.js missing -> generating safe stub (sound editor disabled)"
  mkdir -p "${WWW}/lib/external/sound"
  cat > "${WWW}/lib/external/sound/sound-editor.js" <<'JS'
/**
 * EntrySoundEditor stub
 * - keep Entry from crashing
 * - provide required exports used by EntryJS bundles:
 *   - renderSoundEditor
 *   - registExportFunction
 */
(function (g) {
  g.EntrySoundEditor = g.EntrySoundEditor || {};
  g.EntrySoundEditor.renderSoundEditor = function () { /* disabled */ };
  g.EntrySoundEditor.registExportFunction = function () { /* noop */ };
})(typeof window !== "undefined" ? window : globalThis);
JS
fi

# ===============================
# 5) CSS url(...) scan & fetch referenced assets
# ===============================
BANNER "CSS url(...) asset scan (download missing relative files)"
scan_css_urls_and_fetch "${WWW}/lib/entryjs/dist/entry.css"
scan_css_urls_and_fetch "${WWW}/lib/entry-tool/dist/entry-tool.css"
scan_css_urls_and_fetch "${WWW}/lib/codemirror/codemirror.css"

# Download referenced assets (optional-only queue)
run_jobs || true

# ===============================
# 6) Ensure alias folder exists (some builds refer /lib/entry-js/)
# ===============================
if [ ! -d "${WWW}/lib/entry-js" ]; then
  cp -R "${WWW}/lib/entryjs" "${WWW}/lib/entry-js" 2>/dev/null || true
fi

# ===============================
# 7) Summary
# ===============================
LOG "✅ FETCH SUMMARY: completed"
LOG "WWW=${WWW}"
exit 0
