const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const www = path.join(root, "www");

// ✅ entry.min.js는 여기서 제외합니다.
//    (index.html에서 별도 로드하므로 중복/꼬임 방지)
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

  "js/ws/locales.js",
  "js/ws/jshint.js",
  "js/ws/python.js",

  "lib/socket.io-client/socket.io.js",

  "lib/entry-js/extern/util/filbert.js",
  "lib/entry-js/extern/util/CanvasInput.js",
  "lib/entry-js/extern/util/ndgmr.Collision.js",
  "lib/entry-js/extern/util/handle.js",
  "lib/entry-js/extern/util/bignumber.min.js",

  "lib/entry-js/extern/util/static.js",
  "lib/entry-tool/dist/entry-tool.js",
  "lib/entry-paint/dist/static/js/entry-paint.js"
];

let out = "";
let missing = [];

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

fs.mkdirSync(path.join(www, "bundle"), { recursive: true });
fs.writeFileSync(path.join(www, "bundle", "vendor.bundle.js"), out, "utf8");

console.log("OK -> www/bundle/vendor.bundle.js");
if (missing.length) {
  console.log("WARNING missing files:");
  for (const m of missing) console.log(" - " + m);
}  "lib/entry-js/extern/util/static.js",
  "lib/entry-tool/dist/entry-tool.js",
  "lib/entry-paint/dist/static/js/entry-paint.js",

  "lib/entry-js/dist/entry.min.js"
];

let out = "";
let missing = [];

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

fs.mkdirSync(path.join(www, "bundle"), { recursive: true });
fs.writeFileSync(path.join(www, "bundle", "vendor.bundle.js"), out, "utf8");

console.log("OK -> www/bundle/vendor.bundle.js");
if (missing.length) {
  console.log("WARNING missing files:");
  for (const m of missing) console.log(" - " + m);
}
