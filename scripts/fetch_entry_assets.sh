#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="$ROOT/www"
MAX_JOBS="${MAX_JOBS:-6}"

log() { echo "[$(date +'%H:%M:%S')] $*"; }
bigerr() {
  echo
  echo "████████████████████████████████████████████████████████████"
  echo "🚨🚨🚨 $*"
  echo "████████████████████████████████████████████████████████████"
  echo
}
mkdirp() { mkdir -p "$1"; }

# 병렬 제한
throttle() {
  while [ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$MAX_JOBS" ]; do
    wait -n || true
  done
}

curl_get() {
  local url="$1" out="$2"
  mkdirp "$(dirname "$out")"
  # -f: 404면 실패코드, 우리는 실패를 캐치해서 "계속" 진행
  if curl -fsSL --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 120 "$url" -o "$out"; then
    log "OK   -> $out"
    return 0
  else
    return 1
  fi
}

# 여러 후보 URL 중 하나라도 성공하면 OK
get_any() {
  local out="$1"; shift
  local ok=1
  for url in "$@"; do
    log "GET  $url"
    if curl_get "$url" "$out"; then ok=0; break; fi
    bigerr "MISS $url"
  done
  if [ "$ok" -ne 0 ]; then
    bigerr "FAIL all candidates -> $out"
    echo "Tried:"
    for url in "$@"; do echo " - $url"; done
    return 1
  fi
  return 0
}

# npm pack extract helper
npm_extract() {
  local pkg="$1" outdir="$2"
  mkdirp "$outdir"
  ( cd "$outdir" && npm pack "$pkg" >/dev/null 2>&1 ) || return 1
  local tgz
  tgz="$(ls -1t "$outdir"/*.tgz 2>/dev/null | head -n1 || true)"
  [ -n "$tgz" ] || return 1
  tar -xzf "$tgz" -C "$outdir"
  rm -f "$tgz"
  return 0
}

copy_if_exists() {
  local src="$1" dst="$2"
  if [ -e "$src" ]; then
    mkdirp "$(dirname "$dst")"
    rm -rf "$dst"
    cp -R "$src" "$dst"
    log "COPY OK: $src -> $dst"
    return 0
  fi
  return 1
}

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"
log "MAX_JOBS=$MAX_JOBS"

mkdirp "$WWW/lib"
mkdirp "$WWW/js/ws"

missing_count=0

# ---------------------------
# A) CDN/외부 라이브러리
# ---------------------------
declare -a TASKS=(
  # lodash (Entry가 _로 기대)
  "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js|$WWW/lib/lodash/dist/lodash.min.js"

  # jQuery/jQuery UI
  "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js|$WWW/lib/jquery/jquery.min.js"
  "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js|$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js"

  # Velocity
  "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js|$WWW/lib/velocity/velocity.min.js"

  # CodeMirror (최소 구성)
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css|$WWW/lib/codemirror/codemirror.css"
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js|$WWW/lib/codemirror/codemirror.js"
  "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js|$WWW/lib/codemirror/vim.js"

  # CreateJS (Entry README 기준 버전)
  "https://code.createjs.com/preloadjs-0.6.0.min.js|$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
  "https://code.createjs.com/easeljs-0.8.0.min.js|$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js"
  "https://code.createjs.com/soundjs-0.6.0.min.js|$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js"
)

for item in "${TASKS[@]}"; do
  throttle
  (
    IFS="|" read -r url out <<< "$item"
    log "GET  $url"
    if ! curl_get "$url" "$out"; then
      bigerr "MISSING: $url"
      missing_count=$((missing_count+1)) || true
    fi
  ) &
done
wait || true

# flashaudioplugin은 없어도 되지만, 있으면 받아둠(없어도 계속)
if ! get_any "$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js" \
  "https://code.createjs.com/flashaudioplugin-0.6.0.min.js"; then
  bigerr "MISS flashaudioplugin(optional) (continue)"
fi

# locales.js (playentry에서)
if ! get_any "$WWW/js/ws/locales.js" "https://playentry.org/js/ws/locales.js"; then
  bigerr "MISS ws/locales.js (continue)"
fi

# ---------------------------
# B) Entry 배포물: @entrylabs/entry에서 dist/extern/images를 “통째로” 복사 (핵심)
# ---------------------------
bigerr "NPM EXTRACT: @entrylabs/entry (dist/extern/images)"
TMP_ENTRY="$WWW/.npm_entry_pkg"
rm -rf "$TMP_ENTRY"
if npm_extract "@entrylabs/entry" "$TMP_ENTRY"; then
  # npm pack은 package/ 아래로 풀림
  PKGDIR="$TMP_ENTRY/package"
  # dist/extern/images는 Entry 구동 필수
  copy_if_exists "$PKGDIR/dist"   "$WWW/lib/entryjs/dist"   || true
  copy_if_exists "$PKGDIR/extern" "$WWW/lib/entryjs/extern" || true
  copy_if_exists "$PKGDIR/images" "$WWW/lib/entryjs/images" || true

  # Entry가 /lib/entry-js 를 참조하는 케이스도 있어서 alias 생성
  rm -rf "$WWW/lib/entry-js"
  cp -R "$WWW/lib/entryjs" "$WWW/lib/entry-js"
  log "ALIAS OK: /lib/entry-js created"
else
  bigerr "npm pack failed: @entrylabs/entry (FATAL)"
  exit 2
fi

# ---------------------------
# C) entry-tool / entry-paint / legacy-video는 playentry/entry-cdn에서
# ---------------------------
log "GET  https://playentry.org/lib/entry-tool/dist/entry-tool.js"
curl_get "https://playentry.org/lib/entry-tool/dist/entry-tool.js"  "$WWW/lib/entry-tool/dist/entry-tool.js" || missing_count=$((missing_count+1)) || true
log "GET  https://playentry.org/lib/entry-tool/dist/entry-tool.css"
curl_get "https://playentry.org/lib/entry-tool/dist/entry-tool.css" "$WWW/lib/entry-tool/dist/entry-tool.css" || missing_count=$((missing_count+1)) || true

log "GET  https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js"
curl_get "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" "$WWW/lib/entry-paint/dist/static/js/entry-paint.js" || missing_count=$((missing_count+1)) || true

# legacy-video (Entry가 기대하는 전역)
log "GET  https://entry-cdn.pstatic.net/module/legacy-video/index.js"
curl_get "https://entry-cdn.pstatic.net/module/legacy-video/index.js" "$WWW/lib/module/legacy-video/index.js" || missing_count=$((missing_count+1)) || true

# ---------------------------
# D) EntrySoundEditor 후보 경로로 시도 (없어도 index.html이 스텁으로 버팀)
#    - “정답 경로”는 Entry 배포/버전에 따라 달라질 수 있어 후보를 넓게 둠
# ---------------------------
bigerr "Try fetch EntrySoundEditor candidates (continue on fail)"
get_any "$WWW/lib/external/sound/sound-editor.js" \
  "https://playentry.org/external/sound/sound-editor.js" \
  "https://playentry.org/lib/external/sound/sound-editor.js" \
  "https://entry-cdn.pstatic.net/external/sound/sound-editor.js" \
  "https://entry-cdn.pstatic.net/lib/external/sound/sound-editor.js" \
  "https://playentry.org/sound/sound-editor.js" \
  "https://entry-cdn.pstatic.net/sound/sound-editor.js" \
  || bigerr "MISS EntrySoundEditor (stub will be used) (continue)"

# ---------------------------
# E) 요약 (절대 멈추지 않게, missing 있어도 계속)
# ---------------------------
if [ "$missing_count" -gt 0 ]; then
  bigerr "FETCH SUMMARY: $missing_count file(s) failed (script continued)"
else
  log "✅ FETCH SUMMARY: all downloads OK"
fi

exit 0
