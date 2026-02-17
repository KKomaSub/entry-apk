// scripts/fetch_css_deps.js
"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const root = path.join(__dirname, "..");
const www = path.join(root, "www");

function walk(dir, out = []) {
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

function relFromCss(cssFile, targetFile) {
  const cssDir = path.dirname(cssFile);
  return path.relative(cssDir, targetFile).replace(/\\/g, "/");
}

const cssFiles = walk(www).filter((p) => p.endsWith(".css"));

let downloaded = 0;
let rewritten = 0;

for (const cssFile of cssFiles) {
  let css = fs.readFileSync(cssFile, "utf8");

  // url(...) 추출
  const urls = [];
  css.replace(/url\(([^)]+)\)/g, (_, g1) => {
    const u = normalizeUrl(g1);
    if (u) urls.push(u);
    return _;
  });

  if (!urls.length) continue;

  let changed = false;

  for (const u0 of urls) {
    const u = u0;

    // 1) 원격 URL -> www 아래에 mirror로 저장 후 css rewrite
    if (isHttp(u)) {
      const clean = stripQuery(u);
      const urlObj = new URL(clean);
      // mirror/<host>/<path>
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
      } catch (e) {
        console.error("CSS dep download failed:", u0);
      }
      continue;
    }

    // 2) 절대경로 (/lib/...) -> 로컬 절대는 그대로 두되 파일 존재 확인만
    if (u.startsWith("/")) {
      const localPath = path.join(www, u.replace(/^\//, ""));
      if (!fs.existsSync(localPath)) {
        console.error("MISSING local asset referenced by CSS:", u, "from", cssFile);
      }
      continue;
    }

    // 3) 상대경로 (../images/...) -> 파일 존재 확인
    const localRel = path.join(path.dirname(cssFile), u);
    if (!fs.existsSync(localRel)) {
      // 혹시 CSS가 원래 원격 기준 상대경로였던 경우를 대비해 경고만
      console.error("MISSING relative asset referenced by CSS:", u, "from", cssFile);
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
