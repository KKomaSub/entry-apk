/* www/local_backend.js (v2)
 * - XHR 교체 금지: prototype open/send patch (axios/라이브러리 호환)
 * - /rest/** 전부 가로채기:
 *    - FormData => 업로드(이미지/사운드/썸네일)
 *    - JSON => 저장(테이블 포함)
 *    - GET => 저장된 blob/json 반환
 * - uploads 저장경로:
 *    uploads/aa/bb/{image|thumb|sound}/fileId.ext
 * - Blob/JSON 저장: IndexedDB
 */

(function () {
  "use strict";

  const DB_NAME = "entry_offline_local_backend_v2";
  const DB_VER = 1;

  const STORE_BLOBS = "blobs"; // key: "uploads/aa/bb/type/file.ext"
  const STORE_JSON  = "json";  // key: "rest:/rest/...." or "rest-body:/rest/..."

  const log = (msg) => {
    try { if (window.bootLine) window.bootLine(msg, "dim"); } catch (_) {}
  };

  const once = (k, fn) => {
    if (window[k]) return;
    window[k] = true;
    fn();
  };

  function now() { return Date.now(); }

  function normalizeUrl(u) {
    if (u == null) return "";
    u = String(u);

    // entry./ 오타 보정
    u = u.replace("/lib/@entrylabs/entry./", "/lib/@entrylabs/entry/");
    u = u.replace("lib/@entrylabs/entry./", "lib/@entrylabs/entry/");

    // 쿼리 제거
    const q = u.indexOf("?");
    if (q >= 0) u = u.slice(0, q);
    return u;
  }

  function stripLeading(u) {
    u = String(u || "");
    while (u.startsWith("./")) u = u.slice(2);
    while (u.startsWith("/")) u = u.slice(1);
    return u;
  }

  function isRest(u) {
    u = normalizeUrl(u);
    // absolute URL도 처리
    try {
      const uu = new URL(u, location.href);
      return uu.pathname.startsWith("/rest/");
    } catch (_) {
      return u.includes("/rest/");
    }
  }

  function restPathKey(u) {
    try {
      const uu = new URL(u, location.href);
      return "rest:" + uu.pathname; // /rest/...
    } catch (_) {
      // fallback
      const i = u.indexOf("/rest/");
      return "rest:" + (i >= 0 ? u.slice(i) : u);
    }
  }

  function isUploadsPath(u) {
    u = stripLeading(normalizeUrl(u));
    return u.startsWith("uploads/") ||
           u.startsWith("src/renderer/resources/uploads/") ||
           u.startsWith("renderer/resources/uploads/") ||
           u.startsWith("resources/uploads/");
  }

  function guessCT(path) {
    const p = String(path || "").toLowerCase();
    if (p.endsWith(".png")) return "image/png";
    if (p.endsWith(".jpg") || p.endsWith(".jpeg")) return "image/jpeg";
    if (p.endsWith(".webp")) return "image/webp";
    if (p.endsWith(".gif")) return "image/gif";
    if (p.endsWith(".svg")) return "image/svg+xml";
    if (p.endsWith(".mp3")) return "audio/mpeg";
    if (p.endsWith(".wav")) return "audio/wav";
    if (p.endsWith(".ogg")) return "audio/ogg";
    if (p.endsWith(".m4a")) return "audio/mp4";
    if (p.endsWith(".json")) return "application/json";
    return "application/octet-stream";
  }

  function random36(len) {
    const bytes = new Uint8Array(len);
    crypto.getRandomValues(bytes);
    let out = "";
    for (let i = 0; i < bytes.length; i++) out += (bytes[i] % 36).toString(36);
    return out;
  }

  function createFileId() {
    // 충돌 거의 없는 32자
    const a = random36(8);
    const b = now().toString(36).padStart(8, "0");
    const c = random36(16);
    return (a + b + c).slice(0, 32);
  }

  function splitPrefix(fileId) {
    const id = String(fileId);
    const a = id.slice(0, 2) || "00";
    const b = id.slice(2, 4) || "00";
    return { a, b };
  }

  function extFromFile(file, fallback) {
    const name = (file && file.name) ? String(file.name) : "";
    const dot = name.lastIndexOf(".");
    if (dot >= 0) return name.slice(dot).toLowerCase();
    const t = (file && file.type) ? String(file.type) : "";
    if (t === "image/png") return ".png";
    if (t === "image/jpeg") return ".jpg";
    if (t === "image/webp") return ".webp";
    if (t === "audio/mpeg") return ".mp3";
    if (t === "audio/wav") return ".wav";
    if (t === "audio/ogg") return ".ogg";
    return fallback || ".bin";
  }

  async function makeThumbPng(blob, maxW = 320, maxH = 320) {
    try {
      const bmp = await createImageBitmap(blob);
      const w = bmp.width, h = bmp.height;
      if (!w || !h) throw 0;

      const scale = Math.min(maxW / w, maxH / h, 1);
      const tw = Math.max(1, Math.round(w * scale));
      const th = Math.max(1, Math.round(h * scale));

      const c = document.createElement("canvas");
      c.width = tw; c.height = th;
      const ctx = c.getContext("2d");
      ctx.drawImage(bmp, 0, 0, tw, th);

      const out = await new Promise((resolve) => c.toBlob(resolve, "image/png"));
      return out || blob;
    } catch (_) {
      return blob;
    }
  }

  // IndexedDB
  function openDB() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VER);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(STORE_BLOBS)) db.createObjectStore(STORE_BLOBS);
        if (!db.objectStoreNames.contains(STORE_JSON))  db.createObjectStore(STORE_JSON);
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  async function idbPut(store, key, val) {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(store, "readwrite");
      tx.objectStore(store).put(val, key);
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => reject(tx.error);
    });
  }

  async function idbGet(store, key) {
    const db = await openDB();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(store, "readonly");
      const rq = tx.objectStore(store).get(key);
      rq.onsuccess = () => resolve(rq.result);
      rq.onerror = () => reject(rq.error);
    });
  }

  async function storeBlob(pathKey, blob, ct) {
    const key = stripLeading(normalizeUrl(pathKey));
    await idbPut(STORE_BLOBS, key, {
      blob,
      ct: ct || blob.type || guessCT(key),
      ts: now(),
      size: blob.size || 0,
    });
    return key;
  }

  async function loadBlob(pathKey) {
    const key = stripLeading(normalizeUrl(pathKey));
    return (await idbGet(STORE_BLOBS, key)) || null;
  }

  function uploadPath(fileId, kind, ext) {
    const { a, b } = splitPrefix(fileId);
    const k = (kind === "sound" || kind === "thumb" || kind === "image") ? kind : "image";
    const e = (ext && ext.startsWith(".")) ? ext : ".bin";
    return `uploads/${a}/${b}/${k}/${fileId}${e}`;
  }

  function jsonResponse(obj, status = 200) {
    return new Response(JSON.stringify(obj), {
      status,
      headers: { "content-type": "application/json; charset=utf-8" }
    });
  }

  async function handleUploadsGET(u) {
    const key = stripLeading(normalizeUrl(u));
    const found = await loadBlob(key);
    if (!found) return new Response("Not Found", { status: 404 });
    return new Response(found.blob, {
      status: 200,
      headers: {
        "content-type": found.ct || guessCT(key),
        "cache-control": "no-store",
      }
    });
  }

  async function handleUploadFormData(reqUrl, fd) {
    // 파일 1개 찾기
    let file = null;
    let field = null;
    for (const [k, v] of fd.entries()) {
      if (v instanceof File || v instanceof Blob) { file = v; field = k; break; }
    }
    if (!file) return jsonResponse({ ok: false, message: "no file" }, 400);

    const url = normalizeUrl(reqUrl);
    const isSound = /sound/i.test(url) || (file.type && file.type.startsWith("audio/"));
    const kind = isSound ? "sound" : "image";

    const fileId = createFileId();
    const ext = extFromFile(file, isSound ? ".mp3" : ".png");

    const main = uploadPath(fileId, kind, ext);
    await storeBlob(main, file, file.type || guessCT(main));

    let thumb = null;
    if (!isSound) {
      const tb = await makeThumbPng(file);
      thumb = uploadPath(fileId, "thumb", ".png");
      await storeBlob(thumb, tb, "image/png");
    }

    // ✅ “버전별로 다른 응답”을 최대한 다 커버
    // Entry가 path/url/filename/fileId/id/image/sound/thumb 중 무엇을 보든 걸리게
    const out = {
      ok: true,
      success: true,

      fileId,
      id: fileId,

      path: "/" + main,
      url: "./" + main,
      filename: fileId + ext,
      originalname: (file && file.name) ? file.name : (fileId + ext),

      // 흔히 쓰는 구조도 같이 제공
      image: !isSound ? {
        fileId,
        path: "/" + main,
        url: "./" + main,
        thumb: thumb ? ("./" + thumb) : null,
        thumbPath: thumb ? ("/" + thumb) : null,
      } : undefined,

      sound: isSound ? {
        fileId,
        path: "/" + main,
        url: "./" + main,
      } : undefined,

      thumb: thumb ? ("./" + thumb) : null,
      thumbPath: thumb ? ("/" + thumb) : null,

      contentType: file.type || guessCT(main),
      size: file.size || 0,
      field,
    };

    return jsonResponse(out, 200);
  }

  async function handleRestJSON(reqUrl, reqInit) {
    // 저장 Key는 URL(path) 기준
    const key = restPathKey(reqUrl);
    const method = (reqInit && reqInit.method) ? String(reqInit.method).toUpperCase() : "GET";

    if (method === "GET") {
      const v = await idbGet(STORE_JSON, key);
      return jsonResponse(v ?? { ok: true, data: null }, 200);
    }

    if (method === "DELETE") {
      await idbPut(STORE_JSON, key, null);
      return jsonResponse({ ok: true }, 200);
    }

    // POST/PUT/PATCH
    let bodyObj = null;
    try {
      const b = reqInit && reqInit.body;
      if (typeof b === "string") bodyObj = JSON.parse(b);
      else if (b instanceof Blob) bodyObj = JSON.parse(await b.text());
      else bodyObj = null;
    } catch (_) {
      bodyObj = null;
    }

    await idbPut(STORE_JSON, key, bodyObj);

    // Entry가 "저장 결과 객체"를 기대하면 그대로 돌려줌
    return jsonResponse({ ok: true, data: bodyObj }, 200);
  }

  // ===== install =====

  function installFetch() {
    if (window.__LB_FETCH_V2__) return;
    window.__LB_FETCH_V2__ = true;

    const _fetch = window.fetch.bind(window);

    window.fetch = async (input, init) => {
      const url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
      const u = normalizeUrl(url);

      // (딱 1줄) 최초 REST 요청 경로 확인
      once("__LB_PROBE_FETCH__", () => {
        if (u.includes("/rest/")) log("PROBE FETCH.url = " + u);
      });

      try {
        // uploads GET
        if (isUploadsPath(u)) return await handleUploadsGET(u);

        // rest 전체
        if (isRest(u)) {
          // Request.formData() 경로
          if (typeof input !== "string" && input instanceof Request) {
            const ct = input.headers.get("content-type") || "";
            if (ct.includes("multipart/form-data")) {
              const fd = await input.formData();
              return await handleUploadFormData(u, fd);
            }
            // JSON 등
            return await handleRestJSON(u, { method: input.method, body: await input.clone().text() });
          }

          // fetch(url, {body: FormData})
          if (init && init.body instanceof FormData) {
            return await handleUploadFormData(u, init.body);
          }

          // fetch(url, json)
          return await handleRestJSON(u, init || {});
        }

        return await _fetch(input, init);
      } catch (e) {
        return await _fetch(input, init);
      }
    };
  }

  function installXHR() {
    if (window.__LB_XHR_V2__) return;
    window.__LB_XHR_V2__ = true;

    const XHRp = XMLHttpRequest.prototype;
    const _open = XHRp.open;
    const _send = XHRp.send;

    XHRp.open = function (method, url, async, user, pass) {
      this.__lb = this.__lb || {};
      this.__lb.method = String(method || "GET").toUpperCase();
      this.__lb.url = normalizeUrl(url);

      // (딱 1줄) 최초 XHR 요청 경로 확인
      once("__LB_PROBE_XHR__", () => {
        log("PROBE XHR.url = " + this.__lb.url);
      });

      return _open.call(this, method, this.__lb.url, async, user, pass);
    };

    XHRp.send = function (body) {
      const method = (this.__lb && this.__lb.method) ? this.__lb.method : "GET";
      const url = (this.__lb && this.__lb.url) ? this.__lb.url : "";

      // uploads GET
      if (method === "GET" && isUploadsPath(url)) {
        const xhr = this;
        (async () => {
          const res = await handleUploadsGET(url);
          const buf = await res.arrayBuffer();

          try {
            Object.defineProperty(xhr, "status", { value: res.status });
            Object.defineProperty(xhr, "readyState", { value: 4 });
            Object.defineProperty(xhr, "response", { value: buf });
            Object.defineProperty(xhr, "responseText", { value: "" });
          } catch (_) {}

          xhr.onload && xhr.onload();
          xhr.onreadystatechange && xhr.onreadystatechange();
        })();
        return;
      }

      // /rest/** 처리
      if (isRest(url)) {
        const xhr = this;

        (async () => {
          let res;

          // FormData면 업로드
          if (body instanceof FormData) {
            res = await handleUploadFormData(url, body);
          } else {
            // JSON 등
            res = await handleRestJSON(url, { method, body });
          }

          const txt = await res.text();

          try {
            Object.defineProperty(xhr, "status", { value: res.status });
            Object.defineProperty(xhr, "readyState", { value: 4 });
            Object.defineProperty(xhr, "responseText", { value: txt });
            Object.defineProperty(xhr, "response", { value: txt });
          } catch (_) {}

          xhr.onload && xhr.onload();
          xhr.onreadystatechange && xhr.onreadystatechange();
        })();

        return;
      }

      return _send.call(this, body);
    };
  }

  window.LocalBackend = {
    install(BASE = "./") {
      // BASE는 지금은 저장키에 굳이 안 씀. (요청은 /rest, ./uploads 등으로 들어옴)
      installFetch();
      installXHR();
      log("LocalBackend(v2) installed: prototype-patch XHR + catch-all /rest/**");
    }
  };
})();
