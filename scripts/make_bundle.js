"use strict";

const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const www = path.join(root, "www");

/**
 * ✅ index.html에서 순서 고정으로 로드하는 파일(번들 제외)
 * - js/ws/locales.js (Lang 전역 생성)
 * - lib/entry-js/extern/lang/ko.js
 * - lib/entry-js/extern/util/static.js
 * - lib/entry-js/dist/entry.min.js
 */
const files = [
  "lib/lodash/dist/lodash.min.js",

  "js/react18/react.production.min.js",
  "js/react18/react-dom.production.min.js",

  "lib/PreloadJS/lib/preloadjs-0.6.0.min.js",
  "lib/EaselJS/lib/easeljs-0.8.0.min.js",
  "lib/SoundJS/lib/soundjs-0.6.0.min.js",
  "lib/SoundJS/lib/flashaudioplugin-0.6.0.min.js",

  "lib/jquery/jquery.min.js",
  "lib/jquery-ui/ui/minified/jquery-ui.min.js",
  "lib/velocity/velocity.min.js",

  "lib/codemirror/lib/codemirror.js",
  "lib/fuzzy/lib/fuzzy.js",

  "js/ws/jshint.js",
  "js/ws/python.js",

  "lib/socket.io-client/socket.io.js",

  "lib/entry-tool/dist/entry-tool.js",
  "lib/entry-paint/dist/static/js/entry-paint.js"
];

let out = "";
const missing = [];

for (const f of files) {
  const p = path.join(www, f);

  if (!fs.existsSync(p)) {
    missing.push(f);
    out += `\n/* MISSING: ${f} */\n`;
    continue;
  }

  out += `\n/* ===== ${f} ===== */\n`;
  out += fs.readFileSync(p, "utf8") + "\n";
}

const bundleDir = path.join(www, "bundle");
fs.mkdirSync(bundleDir, { recursive: true });

const bundlePath = path.join(bundleDir, "vendor.bundle.js");
fs.writeFileSync(bundlePath, out, "utf8");

console.log("OK -> " + bundlePath);

if (missing.length) {
  console.log("WARNING: missing files (bundle still generated):");
  for (const m of missing) console.log(" - " + m);
}
