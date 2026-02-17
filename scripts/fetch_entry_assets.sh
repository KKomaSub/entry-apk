#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="${ROOT}/www"
MAX_JOBS="${MAX_JOBS:-6}"

ts(){ date +"[%H:%M:%S]"; }
log(){ echo "$(ts) $*"; }
BANNER(){ echo; echo "████████████████████████████████████████████████████████████"; echo "🚨🚨🚨 $*"; echo "████████████████████████████████████████████████████████████"; }

mkdir -p "$WWW/lib" "$WWW/js"

# --- curl helper (never stop on 404; return nonzero only for required handling in caller) ---
dl() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  if curl -L --fail --retry 2 --retry-delay 1 --connect-timeout 8 --max-time 120 \
    -H "User-Agent: entry-apk-fetch/2.0" \
    -o "$out" "$url" >/dev/null 2>&1; then
    log "OK   -> $out"
    return 0
  else
    rm -f "$out" >/dev/null 2>&1 || true
    log "MISS $url"
    return 1
  fi
}

# --- REQUIRED fetch from playentry ---
log "=== Fetch core CDN assets ==="
dl "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" "$WWW/lib/lodash/dist/lodash.min.js" || true
dl "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" "$WWW/lib/jquery/jquery.min.js" || true
dl "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" "$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js" || true
dl "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" "$WWW/lib/velocity/velocity.min.js" || true

dl "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js" "$WWW/lib/codemirror/codemirror.js" || true
dl "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css" "$WWW/lib/codemirror/codemirror.css" || true
dl "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js" "$WWW/lib/codemirror/vim.js" || true

dl "https://code.createjs.com/preloadjs-0.6.0.min.js" "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js" || true
dl "https://code.createjs.com/easeljs-0.8.0.min.js" "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js" || true
dl "https://code.createjs.com/soundjs-0.6.0.min.js" "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js" || true
# optional
dl "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" "$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" || true

# entry libs
log "=== Fetch playentry libs ==="
dl "https://playentry.org/lib/entry-js/dist/entry.min.js" "$WWW/lib/entryjs/dist/entry.min.js" || true
dl "https://playentry.org/lib/entry-js/dist/entry.css" "$WWW/lib/entryjs/dist/entry.css" || true
dl "https://playentry.org/lib/entry-js/extern/lang/ko.js" "$WWW/lib/entryjs/extern/lang/ko.js" || true
dl "https://playentry.org/lib/entry-js/extern/util/static.js" "$WWW/lib/entryjs/extern/util/static.js" || true
dl "https://playentry.org/lib/entry-js/extern/util/handle.js" "$WWW/lib/entryjs/extern/util/handle.js" || true
dl "https://playentry.org/lib/entry-js/extern/util/bignumber.min.js" "$WWW/lib/entryjs/extern/util/bignumber.min.js" || true

dl "https://playentry.org/lib/entry-tool/dist/entry-tool.js" "$WWW/lib/entry-tool/dist/entry-tool.js" || true
dl "https://playentry.org/lib/entry-tool/dist/entry-tool.css" "$WWW/lib/entry-tool/dist/entry-tool.css" || true
dl "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" "$WWW/lib/entry-paint/dist/static/js/entry-paint.js" || true

dl "https://entry-cdn.pstatic.net/module/legacy-video/index.js" "$WWW/lib/module/legacy-video/index.js" || true
dl "https://playentry.org/js/ws/locales.js" "$WWW/js/ws/locales.js" || true

# --- THE KEY: copy ALL entry assets via npm pack (images/media/extern/dist 등) ---
BANNER "NPM FALLBACK: copy ALL @entrylabs/entry into www/lib/entryjs (best-effort)"
TMP="$WWW/.npm_tmp"
rm -rf "$TMP" "$WWW/.npm_entry_pkg" >/dev/null 2>&1 || true
mkdir -p "$TMP"

if (cd "$TMP" && npm pack "@entrylabs/entry" >/dev/null 2>&1); then
  TGZ="$(ls -1 "$TMP"/*.tgz | head -n 1)"
  tar -xzf "$TGZ" -C "$TMP"
  if [[ -d "$TMP/package" ]]; then
    rm -rf "$WWW/.npm_entry_pkg"
    cp -R "$TMP/package" "$WWW/.npm_entry_pkg"

    # dist/extern/images/media 를 www/lib/entryjs 로 통째로 덮어씀
    mkdir -p "$WWW/lib/entryjs"
    for d in dist extern images media; do
      if [[ -d "$WWW/.npm_entry_pkg/$d" ]]; then
        rm -rf "$WWW/lib/entryjs/$d" >/dev/null 2>&1 || true
        cp -R "$WWW/.npm_entry_pkg/$d" "$WWW/lib/entryjs/$d"
        log "COPY OK: @entrylabs/entry/$d -> lib/entryjs/$d"
      fi
    done
  fi
else
  BANNER "npm pack @entrylabs/entry failed (continue)"
fi

# alias copy (/lib/entry-js 도 같은 내용으로)
rm -rf "$WWW/lib/entry-js" >/dev/null 2>&1 || true
cp -R "$WWW/lib/entryjs" "$WWW/lib/entry-js" >/dev/null 2>&1 || true
log "Alias OK: lib/entryjs -> lib/entry-js"

# disable sound editor file (keep placeholder)
mkdir -p "$WWW/lib/external/sound"
cat > "$WWW/lib/external/sound/sound-editor.js" <<'EOF'
/* EntrySoundEditor disabled placeholder (avoid React mismatch crash) */
EOF

# --- Make CSS url(...) absolute (images/media 깨짐 방지) ---
# entry.css 안의 url(../images/...) 같은 상대 경로를 /lib/entryjs/... 로 보정
if [[ -f "$WWW/lib/entryjs/dist/entry.css" ]]; then
  log "Patch entry.css url(...) to absolute paths"
  # 보정 규칙:
  # url(../images/...) 또는 url(images/...) 등을 url(/lib/entryjs/images/...)로
  sed -i \
    -e 's|url(\.\./images/|url(/lib/entryjs/images/|g' \
    -e 's|url(\.\./media/|url(/lib/entryjs/media/|g' \
    -e 's|url(images/|url(/lib/entryjs/images/|g' \
    -e 's|url(media/|url(/lib/entryjs/media/|g' \
    "$WWW/lib/entryjs/dist/entry.css" || true
fi

BANNER "FETCH DONE (script always exits 0)"
exit 0
