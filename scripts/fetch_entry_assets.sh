#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WWW="$ROOT/www"

log(){ echo "[$(date +'%H:%M:%S')] $*"; }

mkdir -p "$WWW" "$WWW/lib" "$WWW/js/ws"

# --- downloader ---
get() {
  local url="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  if curl -fsSL --retry 3 --retry-delay 1 -o "$out" "$url"; then
    log "OK   $out"
    return 0
  else
    log "MISS $url"
    return 1
  fi
}

log "=== Fetch Entry assets (offline vendoring) ==="
log "ROOT=$ROOT"
log "WWW =$WWW"

# --- index.html / overrides.css 존재 강제 (없으면 최소 파일 생성) ---
if [ ! -f "$WWW/index.html" ]; then
  cat > "$WWW/index.html" <<'HTML'
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Entry Offline Editor</title>

  <link rel="stylesheet" href="./lib/entry-tool/dist/entry-tool.css" />
  <link rel="stylesheet" href="./lib/entryjs/dist/entry.css" />
  <link rel="stylesheet" href="./lib/codemirror/codemirror.css" />
  <link rel="stylesheet" href="./overrides.css" />
  <style>
    html,body{margin:0;height:100%;overflow:hidden;background:#111}
    #entryContainer{width:100%;height:100%;background:#f5f5f5}
    #boot{
      position:fixed;inset:0;background:#000;color:#0f0;
      font:12px/1.45 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
      padding:12px;white-space:pre-wrap;overflow:auto;z-index:9999
    }
    .bad{color:#ff5c5c}
    .dim{opacity:.8}
    .ok{color:#66ff66}
  </style>
</head>
<body>
  <div id="entryContainer"></div>
  <div id="boot">Entry Offline Editor\nLoading…</div>

  <script>
    const bootEl = () => document.getElementById("boot");
    function line(t, cls="") {
      const el = bootEl();
      const d = document.createElement("div");
      if (cls) d.className = cls;
      d.textContent = t;
      el.appendChild(d);
      el.scrollTop = el.scrollHeight;
    }
    window.onerror = function (m, s, l, c, e) {
      line("JS ERROR:", "bad");
      line(String(e && e.stack ? e.stack : m), "bad");
    };

    async function probeBase() {
      // capacitor(안드로이드): 보통 "./" 로 접근 가능
      // 개발 서버/특수 상황 대비로 몇 개 후보를 점검
      const candidates = ["./", "/", "/public/", "/www/"];
      for (const b of candidates) {
        line("PROBE BASE: " + b, "dim");
        try {
          const r = await fetch(b + "lib/lodash/dist/lodash.min.js", { cache: "no-store" });
          if (r.ok) return b;
        } catch {}
      }
      return "./";
    }

    async function loadJS(src) {
      return new Promise((resolve) => {
        const s = document.createElement("script");
        s.src = src;
        s.onload = () => resolve({ ok: true, src });
        s.onerror = () => resolve({ ok: false, src });
        document.head.appendChild(s);
      });
    }

    async function loadCSS(href) {
      return new Promise((resolve) => {
        const l = document.createElement("link");
        l.rel = "stylesheet";
        l.href = href;
        l.onload = () => resolve({ ok: true, href });
        l.onerror = () => resolve({ ok: false, href });
        document.head.appendChild(l);
      });
    }

    function must(name, cond) {
      if (!cond) throw new Error(name);
      line("OK   " + name, "ok");
    }

    document.addEventListener("DOMContentLoaded", async () => {
      const BASE = await probeBase();
      line("BASE = " + BASE);

      // CSS 먼저
      for (const href of [
        BASE + "lib/entry-tool/dist/entry-tool.css",
        BASE + "lib/entryjs/dist/entry.css",
        BASE + "lib/codemirror/codemirror.css",
        BASE + "overrides.css"
      ]) {
        const r = await loadCSS(href);
        line((r.ok ? "OK   CSS " : "MISS CSS ") + href, r.ok ? "ok" : "bad");
      }

      // locales는 optional
      {
        const r = await loadJS(BASE + "js/ws/locales.js");
        line((r.ok ? "OK   JS  " : "MISS(opt) ") + " " + r.src, r.ok ? "ok" : "dim");
      }

      // JS 로딩 순서(중요)
      const jsList = [
        BASE + "lib/lodash/dist/lodash.min.js",
        BASE + "lib/jquery/jquery.min.js",
        BASE + "lib/jquery-ui/ui/minified/jquery-ui.min.js",

        BASE + "lib/PreloadJS/lib/preloadjs-0.6.0.min.js",
        BASE + "lib/EaselJS/lib/easeljs-0.8.0.min.js",
        BASE + "lib/SoundJS/lib/soundjs-0.6.0.min.js",
        // flashaudioplugin은 optional
        BASE + "lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js",

        BASE + "lib/velocity/velocity.min.js",

        BASE + "lib/codemirror/codemirror.js",
        BASE + "lib/codemirror/vim.js",

        BASE + "lib/entry-tool/dist/entry-tool.js",

        BASE + "lib/entryjs/extern/lang/ko.js",
        BASE + "lib/entryjs/extern/util/static.js",
        BASE + "lib/entryjs/extern/util/handle.js",
        BASE + "lib/entryjs/extern/util/bignumber.min.js",

        BASE + "lib/module/legacy-video/index.js",

        // sound-editor는 프로젝트에서 제공(없어도 stub로 대체 가능)
        BASE + "lib/external/sound/sound-editor.js",

        BASE + "lib/entryjs/dist/entry.min.js",
        BASE + "lib/entry-paint/dist/static/js/entry-paint.js"
      ];

      for (const src of jsList) {
        const optional =
          src.includes("flashaudioplugin") ||
          src.endsWith("/vim.js");

        const r = await loadJS(src);
        if (!r.ok && optional) {
          line("MISS(opt) " + src, "dim");
          continue;
        }
        line((r.ok ? "OK   JS  " : "MISS     ") + src, r.ok ? "ok" : "bad");
      }

      try {
        line("_.memoize = " + (window._ ? typeof _.memoize : "N/A"));
        line("$.fn.jquery = " + (window.$ ? $.fn.jquery : "N/A"));
        line("createjs = " + (typeof window.createjs));
        line("Lang = " + (typeof window.Lang));
        line("EntryTool = " + (typeof window.EntryTool));
        line("EntryVideoLegacy = " + (typeof window.EntryVideoLegacy));
        line("EntryStatic = " + (typeof window.EntryStatic));
        line("EntrySoundEditor.renderSoundEditor = " + (window.EntrySoundEditor ? typeof window.EntrySoundEditor.renderSoundEditor : "N/A"));
        line("Entry.init = " + (window.Entry ? typeof window.Entry.init : "N/A"));

        must("lodash(_)", !!window._);
        must("jQuery($)", !!window.$);
        must("createjs", !!window.createjs);
        must("Lang", !!window.Lang);
        must("EntryTool", !!window.EntryTool);
        must("EntryVideoLegacy", !!window.EntryVideoLegacy);
        must("EntryStatic", !!window.EntryStatic);
        must("Entry.init", !!(window.Entry && typeof window.Entry.init === "function"));

        line("Starting Entry.init …", "dim");
        Entry.init(document.getElementById("entryContainer"), {
          type: "workspace",
          libDir: BASE + "lib",
          textCodingEnable: true
        });
        Entry.loadProject();
        bootEl().remove();
      } catch (e) {
        line("Boot Error", "bad");
        line(String(e && e.stack ? e.stack : e), "bad");
      }
    });
  </script>
</body>
</html>
HTML
  log "WROTE $WWW/index.html"
fi

if [ ! -f "$WWW/overrides.css" ]; then
  cat > "$WWW/overrides.css" <<'CSS'
/* 필요한 경우 여기서 UI 깨짐/크기 문제를 보정 */
CSS
  log "WROTE $WWW/overrides.css"
fi

# --- Download core libs ---
get "https://cdnjs.cloudflare.com/ajax/libs/lodash.js/4.17.10/lodash.min.js" \
    "$WWW/lib/lodash/dist/lodash.min.js"

get "https://cdnjs.cloudflare.com/ajax/libs/jquery/1.9.1/jquery.min.js" \
    "$WWW/lib/jquery/jquery.min.js"

get "https://cdnjs.cloudflare.com/ajax/libs/jqueryui/1.10.4/jquery-ui.min.js" \
    "$WWW/lib/jquery-ui/ui/minified/jquery-ui.min.js"

get "https://code.createjs.com/preloadjs-0.6.0.min.js" \
    "$WWW/lib/PreloadJS/lib/preloadjs-0.6.0.min.js"
get "https://code.createjs.com/easeljs-0.8.0.min.js" \
    "$WWW/lib/EaselJS/lib/easeljs-0.8.0.min.js"
get "https://code.createjs.com/soundjs-0.6.0.min.js" \
    "$WWW/lib/SoundJS/lib/soundjs-0.6.0.min.js"
if ! get "https://code.createjs.com/flashaudioplugin-0.6.0.min.js" \
         "$WWW/lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js"; then
  log "MISS flashaudioplugin(optional)"
fi

get "https://cdnjs.cloudflare.com/ajax/libs/velocity/1.2.3/velocity.min.js" \
    "$WWW/lib/velocity/velocity.min.js"

get "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css" \
    "$WWW/lib/codemirror/codemirror.css"
get "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js" \
    "$WWW/lib/codemirror/codemirror.js"
get "https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/keymap/vim.min.js" \
    "$WWW/lib/codemirror/vim.js" || true

# --- Entry assets from playentry ---
get "https://playentry.org/lib/entry-js/dist/entry.min.js" \
    "$WWW/lib/entryjs/dist/entry.min.js"
get "https://playentry.org/lib/entry-js/dist/entry.css" \
    "$WWW/lib/entryjs/dist/entry.css"

get "https://playentry.org/lib/entry-js/extern/lang/ko.js" \
    "$WWW/lib/entryjs/extern/lang/ko.js"
get "https://playentry.org/lib/entry-js/extern/util/static.js" \
    "$WWW/lib/entryjs/extern/util/static.js"
get "https://playentry.org/lib/entry-js/extern/util/handle.js" \
    "$WWW/lib/entryjs/extern/util/handle.js"
get "https://playentry.org/lib/entry-js/extern/util/bignumber.min.js" \
    "$WWW/lib/entryjs/extern/util/bignumber.min.js"

get "https://playentry.org/lib/entry-tool/dist/entry-tool.js" \
    "$WWW/lib/entry-tool/dist/entry-tool.js"
get "https://playentry.org/lib/entry-tool/dist/entry-tool.css" \
    "$WWW/lib/entry-tool/dist/entry-tool.css"

get "https://playentry.org/lib/entry-paint/dist/static/js/entry-paint.js" \
    "$WWW/lib/entry-paint/dist/static/js/entry-paint.js"

get "https://entry-cdn.pstatic.net/module/legacy-video/index.js" \
    "$WWW/lib/module/legacy-video/index.js"

# ws locales (optional)
get "https://playentry.org/js/ws/locales.js" "$WWW/js/ws/locales.js" || true

# sound-editor (기본 stub)
if [ ! -f "$WWW/lib/external/sound/sound-editor.js" ]; then
  cat > "$WWW/lib/external/sound/sound-editor.js" <<'JS'
window.EntrySoundEditor = window.EntrySoundEditor || {};
// 최소 호환: Entry가 호출하는 함수만 제공
window.EntrySoundEditor.renderSoundEditor = function(){ return null; };
JS
  log "WROTE stub sound-editor.js"
fi

log "✅ FETCH DONE"
