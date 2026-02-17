// scripts/fetch_css_deps.js
"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const root = path.join(__dirname, "..");
const www = path.join(root, "www");

const P1 = "https://playentry.org";
const P2 = "https://entry-cdn.pstatic.net";

// ✅ 로컬 CSS 파일 -> 원격 CSS URL 매핑(기준점)
const CSS_REMOTE_MAP = {
  "lib/entryjs/dist/entry.css": [
    `${P1}/lib/entryjs/dist/entry.css`,
    `${P2}/lib/entryjs/dist/entry.css`,
  ],
  "lib/entry-tool/dist/entry-tool.css": [
    `${P1}/lib/entry-tool/dist/entry-tool.css`,
    `${P2}/lib/entry-tool/dist/entry-tool.css`,
  ],
  // entry-paint는 경우에 따라 css가 있을 수 있어 대비
  "lib/entry-paint/dist/static/css/entry-paint.css": [
    `${P1}/lib/entry-paint/dist/static/css/entry-paint.css`,
    `${P2}/lib/entry-paint/dist/static/css/entry-paint.css`,
  ],
};

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

function runCurl(url, outPath) {
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  execFileSync("curl", ["-L", "--retry", "3", "--retry-delay", "1", "--fail", "-o", outPath, url], {
    stdio: "inherit",
  });
}

function normalizeUrl(raw) {
  let u = raw.trim().replace(/^['"]|['"]$/g, "");
  if (!u || u.startsWith("data:")) return null;
  return u;
}

function isHttp(u) {
  return /^https?:\/\//i.test(u);
}

function stripQuery(u) {
  return u.split("?")[0].split("#")[0];
}

function toPosix(p) {
  return p.replace(/\\/g, "/");
}

function relFromCss(cssFile, targetFile) {
  const cssDir = path.dirname(cssFile);
  return path.relative(cssDir, targetFile).replace(/\\/g, "/");
}

function tryDownloadCandidates(outPath, candidates) {
  for (const url of candidates) {
    try {
      console.log(`[CSS-DEP] GET ${url}`);
      runCurl(url, outPath);
      return true;
    } catch (e) {
      console.log(`[CSS-DEP] MISS ${url}`);
    }
  }
  return false;
}

// 로컬 cssFile에 대해 가능한 원격 base URL을 반환
function getRemoteBasesForCss(cssFileAbs) {
  const rel = toPosix(path.relative(www, cssFileAbs));
  const urls = CSS_REMOTE_MAP[rel];
  if (!urls) return [];
  // base dir (…/dist/)
  return urls.map((u) => u.replace(/\/[^/]+\.css$/, "/"));
}

const cssFiles = walk(www).filter((p) => p.endsWith(".css"));

let downloaded = 0;
let rewritten = 0;

for (const cssFile of cssFiles) {
  let css = fs.readFileSync(cssFile, "utf8");

  const urls = [];
  css.replace(/url\(([^)]+)\)/g, (_, g1) => {
    const u = normalizeUrl(g1);
    if (u) urls.push(u);
    return _;
  });

  if (!urls.length) continue;

  const remoteBases = getRemoteBasesForCss(cssFile);
  let changed = false;

  for (const u0 of urls) {
    const u = u0;

    // 1) http(s)면 mirror로 받고 CSS rewrite (기존 동작)
    if (isHttp(u)) {
      const clean = stripQuery(u);
      const urlObj = new URL(clean);
      const outPath = path.join(www, "mirror", urlObj.host, urlObj.pathname.replace(/^\//, ""));
      try {
        if (!fs.existsSync(outPath)) {
          runCurl(clean, outPath);
          downloaded++;
        }
        const newRel = relFromCss(cssFile, outPath);
        const re = new RegExp(`url\\((\\s*['"]?)${escapeRegExp(u0)}(['"]?\\s*)\\)`, "g");
        css = css.replace(re, `url($1${newRel}$2)`);
        changed = true;
      } catch {
        console.error("[CSS-DEP] FAILED http asset:", u0);
      }
      continue;
    }

    // 2) 절대경로(/lib/...)면 로컬 존재 체크 + 없으면 원격에서 받아서 같은 경로에 저장
    if (u.startsWith("/")) {
      const localPath = path.join(www, u.replace(/^\//, ""));
      if (!fs.existsSync(localPath)) {
        // 원격 후보 = P1/P2 + 동일 절대 경로
        const candidates = [`${P1}${u}`, `${P2}${u}`];
        if (tryDownloadCandidates(localPath, candidates)) downloaded++;
        else console.error("[CSS-DEP] MISSING absolute asset:", u, "from", cssFile);
      }
      continue;
    }

    // 3) 상대경로(../images/...)면 로컬 파일 없을 때 원격 base로 계산해서 다운로드
    const localRel = path.join(path.dirname(cssFile), u);
    if (!fs.existsSync(localRel)) {
      // 원격 base를 알고 있을 때만 시도
      if (remoteBases.length) {
        // cssFile이 …/dist/entry.css 이고 u가 ../images/x.png 라면
        // 원격에서는 …/dist/ + ../images/x.png => …/images/x.png
        const candidates = remoteBases.map((b) => new URL(u, b).toString());
        if (tryDownloadCandidates(localRel, candidates)) {
          downloaded++;
        } else {
          console.error("[CSS-DEP] MISSING relative asset:", u, "from", cssFile);
        }
      } else {
        console.error("[CSS-DEP] (no remote base) missing relative asset:", u, "from", cssFile);
      }
    }
  }

  if (changed) {
    fs.writeFileSync(cssFile, css, "utf8");
    rewritten++;
  }
}

console.log(`CSS deps done. downloaded=${downloaded}, rewritten_css_files=${rewritten}`);

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
