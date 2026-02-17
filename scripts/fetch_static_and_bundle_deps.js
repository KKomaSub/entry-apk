// scripts/fetch_static_and_bundle_deps.js
"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const root = path.join(__dirname, "..");
const www = path.join(root, "www");

const P1 = "https://playentry.org";
const P2 = "https://entry-cdn.pstatic.net";

const TARGETS = [
  "lib/entryjs/extern/util/static.js",
  "lib/entryjs/dist/entry.min.js",
  "lib/entry-tool/dist/entry-tool.js",
  "lib/entry-paint/dist/static/js/entry-paint.js",
];

const exts = "(?:png|jpg|jpeg|gif|webp|svg|ico|json|wasm|mp3|wav|ogg|mp4|webm|ttf|otf|woff2?|eot)";
const RE_ABS = new RegExp(String.raw`(["'\`])((?:\/(?:lib|js|img|images|assets|static)\/)[^"'\`\\]+?\.` + exts + String.raw`)(?:\?[^"'\`]*)?\1`, "g");
const RE_HTTP = new RegExp(String.raw`(["'\`])(https?:\/\/[^"'\`\\]+?\.` + exts + String.raw`(?:\?[^"'\`]*)?)\1`, "g");

function toPosix(p) { return p.replace(/\\/g, "/"); }
function stripQuery(u) { return u.split("?")[0].split("#")[0]; }
function isHttp(u) { return /^https?:\/\//i.test(u); }

function runCurl(url, outPath) {
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  execFileSync("curl", ["-L", "--retry", "3", "--retry-delay", "1", "--fail", "-o", outPath, url], {
    stdio: "inherit",
  });
}

function ensureFromCandidates(outPath, candidates) {
  if (fs.existsSync(outPath)) return { ok: true, downloaded: false };
  for (const url of candidates) {
    try {
      console.log(`[STATIC-DEPS] GET ${url}`);
      runCurl(url, outPath);
      return { ok: true, downloaded: true };
    } catch {
      console.log(`[STATIC-DEPS] MISS ${url}`);
    }
  }
  return { ok: false, downloaded: false };
}

function outPathForRef(ref) {
  if (isHttp(ref)) {
    const clean = stripQuery(ref);
    const u = new URL(clean);
    return path.join(www, "mirror", u.host, u.pathname.replace(/^\//, ""));
  }
  if (ref.startsWith("/")) {
    return path.join(www, ref.replace(/^\//, ""));
  }
  return null;
}

function candidatesForRef(ref) {
  if (isHttp(ref)) return [stripQuery(ref)];
  if (ref.startsWith("/")) return [`${P1}${ref}`, `${P2}${ref}`];
  return [];
}

function extractRefs(text) {
  const set = new Set();

  // /lib/... 같은 절대경로
  let m;
  while ((m = RE_ABS.exec(text))) set.add(m[2]);

  // https://... 직접 박힌 것
  while ((m = RE_HTTP.exec(text))) set.add(m[2]);

  return Array.from(set);
}

let total = 0, downloaded = 0, failed = 0;
const failList = [];

for (const rel of TARGETS) {
  const f = path.join(www, rel);
  if (!fs.existsSync(f)) continue;

  const text = fs.readFileSync(f, "utf8");
  const refs = extractRefs(text);

  console.log(`== Scan ${rel}: found ${refs.length} refs ==`);
  total += refs.length;

  for (const r of refs) {
    const out = outPathForRef(r);
    if (!out) continue;

    const cand = candidatesForRef(r);
    if (!cand.length) continue;

    const res = ensureFromCandidates(out, cand);
    if (res.downloaded) downloaded++;
    if (!res.ok) {
      failed++;
      failList.push(`${rel} -> ${r}  (need ${toPosix(path.relative(www, out))})`);
    }
  }
}

const logPath = path.join(www, ".static_bundle_missing.txt");
if (failList.length) fs.writeFileSync(logPath, failList.join("\n") + "\n", "utf8");

console.log(`STATIC/BUNDLE deps done. total_refs=${total}, downloaded=${downloaded}, failed=${failed}`);
if (failList.length) console.log(`Missing list written -> ${logPath}`);
