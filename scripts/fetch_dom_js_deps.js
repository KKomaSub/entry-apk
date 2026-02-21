//// scripts/fetch_dom_js_deps.js
"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const root = path.join(__dirname, "..");
const www = path.join(root, "www");

const P1 = "https://playentry.org";
const P2 = "https://entry-cdn.pstatic.net";

const exts = new Set([
  "png","jpg","jpeg","gif","webp","svg","ico",
  "mp3","wav","ogg","mp4","webm",
  "ttf","otf","woff","woff2","eot",
  "json","xml","txt","bin","wasm"
]);

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

function stripQuery(u) {
  return u.split("?")[0].split("#")[0];
}

function isHttp(u) {
  return /^https?:\/\//i.test(u);
}

function normalize(s) {
  return (s || "").trim().replace(/^['"]|['"]$/g, "");
}

function toPosix(p) {
  return p.replace(/\\/g, "/");
}

function extOf(u) {
  const clean = stripQuery(u);
  const m = clean.match(/\.([a-z0-9]+)$/i);
  return m ? m[1].toLowerCase() : "";
}

function likelyAsset(u) {
  const e = extOf(u);
  return e && exts.has(e);
}

function writeMaybeUpdated(file, content) {
  fs.writeFileSync(file, content, "utf8");
}

// HTML attribute extractor (간단/안전)
function extractHtmlRefs(html) {
  const out = [];
  const attrRe = /\b(?:src|href|poster|data-src|data-href)\s*=\s*(['"])(.*?)\1/gi;
  let m;
  while ((m = attrRe.exec(html))) {
    const u = normalize(m[2]);
    if (!u || u.startsWith("data:") || u.startsWith("javascript:") || u.startsWith("#")) continue;
    if (likelyAsset(u) || u.startsWith("/")) out.push(u);
  }
  return out;
}

// JS string extractor: '/lib/...png' 같은 패턴을 잡음
function extractJsRefs(js) {
  const out = [];
  // 1) /lib/... 또는 /js/... 또는 /mirror/... 형태
  const re1 = /(["'`])((?:\/(?:lib|js|img|images|assets|static)\/)[^"'`\\]+?\.(?:png|jpg|jpeg|gif|webp|svg|ico|ttf|otf|woff2?|eot|json|wasm|mp3|wav|ogg|mp4|webm))\1/gi;
  let m;
  while ((m = re1.exec(js))) out.push(m[2]);

  // 2) 상대경로 ./ ../ 로 시작하는 것 (확장자 필수)
  const re2 = /(["'`])((?:\.{1,2}\/)[^"'`\\]+?\.(?:png|jpg|jpeg|gif|webp|svg|ico|ttf|otf|woff2?|eot|json|wasm|mp3|wav|ogg|mp4|webm))\1/gi;
  while ((m = re2.exec(js))) out.push(m[2]);

  // 3) http(s) 직접 박힌 에셋
  const re3 = /(["'`])(https?:\/\/[^"'`\\]+?\.(?:png|jpg|jpeg|gif|webp|svg|ico|ttf|otf|woff2?|eot|json|wasm|mp3|wav|ogg|mp4|webm)(?:\?[^"'`]*)?)\1/gi;
  while ((m = re3.exec(js))) out.push(m[2]);

  return out;
}

// URL -> 로컬 경로 결정
function resolveToLocal(ref, baseFileAbs) {
  // http(s) -> mirror/<host>/<path>
  if (isHttp(ref)) {
    const clean = stripQuery(ref);
    const u = new URL(clean);
    return path.join(www, "mirror", u.host, u.pathname.replace(/^\//, ""));
  }

  // 절대경로(/lib/...) -> www/lib/...
  if (ref.startsWith("/")) {
    return path.join(www, ref.replace(/^\//, ""));
  }

  // 상대경로 -> base 파일 기준
  return path.join(path.dirname(baseFileAbs), ref);
}

// ref가 로컬에 없으면, 어떤 원격에서 받을지 후보 생성
function candidateUrlsFor(ref, baseFileAbs) {
  // http(s)는 그 자체
  if (isHttp(ref)) return [stripQuery(ref)];

  // 절대(/lib/...)면 P1/P2 붙이기
  if (ref.startsWith("/")) return [`${P1}${ref}`, `${P2}${ref}`];

  // 상대경로면 baseFile이 로컬이므로 “원격 기준”을 모르지만,
  // 보통 playentry lib 구조를 따라가므로, 로컬에서 '/lib/...' 형태로 재구성 가능한 경우만 시도.
  // (여기선 안전하게: 상대는 우선 로컬 존재 여부만 보고, 없으면 패스/로그)
  return [];
}

function ensureDownloaded(ref, baseFileAbs) {
  const outPath = resolveToLocal(ref, baseFileAbs);
  if (fs.existsSync(outPath)) return { ok: true, outPath, downloaded: false };

  const candidates = candidateUrlsFor(ref, baseFileAbs);
  if (!candidates.length) {
    return { ok: false, outPath, downloaded: false, reason: "no remote base for relative ref" };
  }

  for (const url of candidates) {
    try {
      console.log(`[DOM/JS] GET ${url}`);
      runCurl(url, outPath);
      return { ok: true, outPath, downloaded: true };
    } catch (e) {
      console.log(`[DOM/JS] MISS ${url}`);
    }
  }
  return { ok: false, outPath, downloaded: false, reason: "all candidates failed" };
}

// HTML에서 http(s) 에셋을 mirror 로 rewrite (가능한 것만)
function rewriteHtmlToLocal(html, fileAbs) {
  let changed = false;

  const attrRe = /\b(?:src|href|poster|data-src|data-href)\s*=\s*(['"])(.*?)\1/gi;

  html = html.replace(attrRe, (full, q, v) => {
    const u = normalize(v);
    if (!u || u.startsWith("data:") || u.startsWith("javascript:") || u.startsWith("#")) return full;

    if (isHttp(u) && likelyAsset(u)) {
      const local = resolveToLocal(u, fileAbs);
      const rel = path.relative(path.dirname(fileAbs), local).replace(/\\/g, "/");
      changed = true;
      return full.replace(v, rel);
    }
    return full;
  });

  return { html, changed };
}

const files = walk(www);
const htmlFiles = files.filter(f => f.endsWith(".html"));
const jsFiles = files.filter(f => f.endsWith(".js"));

let totalRefs = 0;
let downloaded = 0;
let failed = 0;
let rewrote = 0;

const failLog = [];

for (const f of htmlFiles) {
  const html = fs.readFileSync(f, "utf8");
  const refs = extractHtmlRefs(html);
  totalRefs += refs.length;

  // 다운로드
  for (const r of refs) {
    const res = ensureDownloaded(r, f);
    if (res.downloaded) downloaded++;
    if (!res.ok) {
      failed++;
      failLog.push(`[HTML] ${toPosix(path.relative(www, f))} -> ${r}  (need: ${toPosix(path.relative(www, res.outPath))})  reason=${res.reason || ""}`);
    }
  }

  // http 에셋은 mirror로 rewrite
  const rr = rewriteHtmlToLocal(html, f);
  if (rr.changed) {
    writeMaybeUpdated(f, rr.html);
    rewrote++;
  }
}

for (const f of jsFiles) {
  const js = fs.readFileSync(f, "utf8");
  const refs = extractJsRefs(js);
  totalRefs += refs.length;

  for (const r of refs) {
    const res = ensureDownloaded(r, f);
    if (res.downloaded) downloaded++;
    if (!res.ok) {
      failed++;
      failLog.push(`[JS] ${toPosix(path.relative(www, f))} -> ${r}  (need: ${toPosix(path.relative(www, res.outPath))})  reason=${res.reason || ""}`);
    }
  }
}

console.log(`DOM/JS deps done. refs=${totalRefs}, downloaded=${downloaded}, failed=${failed}, html_rewritten=${rewrote}`);

if (failLog.length) {
  const p = path.join(www, ".dom_js_missing.txt");
  fs.writeFileSync(p, failLog.join("\n") + "\n", "utf8");
  console.log("Wrote missing list ->", p);
        }
