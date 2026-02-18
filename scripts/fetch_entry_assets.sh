# =============================================================================
# EXTRA: fetch ALL referenced assets (images/fonts/audio) from CSS + JS strings
# - keep everything else unchanged
# - do NOT fail the workflow on missing assets
# =============================================================================
bigwarn "EXTRA ASSET PASS: scan CSS url(...) + JS string paths (images/audio/fonts)"

ASSET_FAILS=0

# URL -> local path helper
# - supports:
#   /lib/...  -> $WWW/lib/...
#   ./lib/... -> $WWW/lib/...
#   lib/...   -> $WWW/lib/...
#   /js/...   -> $WWW/js/...
#   /overrides.css -> $WWW/overrides.css
to_local_path() {
  local p="$1"
  p="${p%%\?*}"        # strip query
  p="${p%%\#*}"        # strip hash
  p="${p#./}"          # remove leading ./
  p="${p#/}"           # remove leading /
  echo "$WWW/$p"
}

# download with multiple candidate origins
# (1) playentry (2) entry-cdn
fetch_asset_candidates() {
  local rel="$1" out="$2"

  # normalize rel
  rel="${rel%%\?*}"; rel="${rel%%\#*}"
  rel="${rel#./}"
  rel="/${rel#/}"

  mkdir -p "$(dirname "$out")"

  # candidates (add more if you already have other CDN roots)
  local c1="https://playentry.org${rel}"
  local c2="https://entry-cdn.pstatic.net${rel}"

  # try each; never hard-fail
  if curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 10 -o "$out" "$c1" 2>/dev/null; then
    log "ASSET OK  $rel  (playentry)"
    return 0
  fi
  if curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 10 -o "$out" "$c2" 2>/dev/null; then
    log "ASSET OK  $rel  (entry-cdn)"
    return 0
  fi

  ASSET_FAILS=$((ASSET_FAILS+1))
  echo
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 ASSET MISS $rel"
  echo "████████████████████████████████████████████████████████████"
  echo
  return 1
}

# enqueue asset fetch (uses existing parallel job_add if available)
asset_add() {
  local rel="$1"
  local out
  out="$(to_local_path "$rel")"

  # skip data: / blob: / http(s):
  if [[ "$rel" =~ ^data: ]] || [[ "$rel" =~ ^blob: ]] || [[ "$rel" =~ ^https?:// ]]; then
    return 0
  fi

  # ignore obvious non-assets
  if [[ "$rel" =~ ^javascript: ]] || [[ "$rel" == "" ]]; then
    return 0
  fi

  # Only fetch typical asset extensions (images/fonts/audio/video)
  if [[ ! "$rel" =~ \.(png|jpg|jpeg|gif|webp|svg|ico|cur|woff2|woff|ttf|otf|eot|mp3|wav|ogg|m4a|mp4|webm)$ ]]; then
    return 0
  fi

  # if already exists, skip
  if [ -f "$out" ] && [ -s "$out" ]; then
    return 0
  fi

  # Use your existing job_add queue (parallel)
  job_add "ASSET::${rel}" "$out" "asset $rel"
}

# Adapt job_add to support ASSET:: pseudo urls without breaking your old behavior
# If your script already has job_add, DO NOT replace it.
# Instead, we override the internal fetch behavior only for ASSET:: entries.
_original_fetch_one_declared=0
if declare -F _fetch_one >/dev/null 2>&1; then
  _original_fetch_one_declared=1
  eval "$(declare -f _fetch_one | sed 's/^_fetch_one/_fetch_one__orig/')"
fi

_fetch_one() {
  local url="$1" out="$2"

  if [[ "$url" == ASSET::* ]]; then
    local rel="${url#ASSET::}"
    fetch_asset_candidates "$rel" "$out" && return 0 || return 1
  fi

  # fallback to original if existed
  if [ "$_original_fetch_one_declared" -eq 1 ]; then
    _fetch_one__orig "$url" "$out"
    return $?
  fi

  # minimal default (should not happen in your script)
  mkdir -p "$(dirname "$out")"
  curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 10 -o "$out" "$url"
}

# ----------------------------
# 1) Scan CSS url(...)
# ----------------------------
scan_css_urls() {
  local css="$1"
  [ -f "$css" ] || return 0

  # extract url(...) tokens
  # supports: url(x) url('x') url("x")
  grep -Eo 'url\(([^)]+)\)' "$css" \
    | sed -E 's/^url\((.*)\)$/\1/' \
    | sed -E 's/^["'\'']|["'\'']$//g' \
    | while read -r u; do
        # ignore data uris
        [[ "$u" =~ ^data: ]] && continue
        # normalize relative -> rooted at css directory
        # if starts with / -> use as-is
        # else make relative to css location
        if [[ "$u" =~ ^/ ]]; then
          asset_add "$u"
        else
          local base_dir rel
          base_dir="$(dirname "${css#$WWW/}")"
          rel="/${base_dir}/${u}"
          # cleanup /./ and // etc
          rel="$(echo "$rel" | sed -E 's#/\.?/#/#g; s#//#/#g')"
          asset_add "$rel"
        fi
      done
}

# Scan key CSS files you already download
scan_css_urls "$WWW/lib/entryjs/dist/entry.css"
scan_css_urls "$WWW/lib/entry-tool/dist/entry-tool.css"
scan_css_urls "$WWW/lib/codemirror/codemirror.css"
scan_css_urls "$WWW/overrides.css"  # if exists

# ----------------------------
# 2) Scan JS for common asset string paths
#    (best-effort; won't be perfect, but catches most)
# ----------------------------
scan_js_strings() {
  local js="$1"
  [ -f "$js" ] || return 0

  # pull strings that look like /lib/...something.(png|svg|mp3|woff2...)
  # keep it simple and robust
  grep -Eo '(/[^"'"'"' ]+\.(png|jpg|jpeg|gif|webp|svg|ico|cur|woff2|woff|ttf|otf|eot|mp3|wav|ogg|m4a|mp4|webm))' "$js" \
    | sort -u \
    | while read -r p; do
        asset_add "$p"
      done
}

scan_js_strings "$WWW/lib/entryjs/dist/entry.min.js"
scan_js_strings "$WWW/lib/entry-tool/dist/entry-tool.js"
scan_js_strings "$WWW/lib/entry-paint/dist/static/js/entry-paint.js"
scan_js_strings "$WWW/lib/module/legacy-video/index.js"
scan_js_strings "$WWW/lib/external/sound/sound-editor.js"  # if present

# ----------------------------
# 3) Also ensure “known” asset folders exist (best effort)
#    If you already copied FULL @entrylabs/entry -> lib/entryjs,
#    this will already be there. If not, at least create dirs.
# ----------------------------
mkdir -p \
  "$WWW/lib/entryjs/images" \
  "$WWW/lib/entryjs/media" \
  "$WWW/lib/entryjs/sounds" \
  "$WWW/lib/entryjs/fonts" \
  "$WWW/lib/entryjs/extern" \
  "$WWW/lib/entryjs/dist"

# Kick parallel downloads
job_wait_all || true

if [ "$ASSET_FAILS" -gt 0 ]; then
  bigwarn "EXTRA ASSET PASS done: $ASSET_FAILS miss(es) (script continued)"
else
  log "✅ EXTRA ASSET PASS done: all extra assets fetched (best-effort)"
fi
