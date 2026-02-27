/* www/local_backend.js
 *
 * 목적:
 * - Entry(웹)에서 "오브젝트/모양/소리 추가(업로드)" + "데이터테이블" 같은 기능이
 *   원래는 서버(/rest/...)를 호출하는데, APK(WebView)에는 서버가 없으니
 *   fetch/XHR을 가로채서 "가짜 백엔드"처럼 동작하게 함.
 *
 * 저장소:
 * - IndexedDB에 Blob(이미지/사운드)와 JSON(테이블 등)을 저장
 *
 * 경로 규칙:
 * - fileId 생성 후 앞 4글자로 /aa/bb/ 폴더 구조를 구성
 * - uploads/aa/bb/{image|thumb|sound}/fileId.(png|mp3 등)
 */

(function () {
  "use strict";

  const DB_NAME = "entry_offline_local_backend_v1";
  const DB_VER = 1;

  const STORES = {
    blobs: "blobs", // key: "uploads/aa/bb/type/file.ext"  value: {blob, ct, ts, size}
    json: "json",   // key: string                         value: any json
  };

  function now() { return Date.now(); }

  function guessContentTypeByExt(path) {
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

  function normalizeUrl(u) {
    if (u == null) return "";
    u = String(u);

    // entry./ 오타 보정 (사용자 로그에 실제로 등장)
    u = u.replace("/lib/@entrylabs/entry./", "/lib/@entrylabs/entry/");
    u = u.replace("lib/@entrylabs/entry./", "lib/@entrylabs/entry/");

    // 쿼리 제거
    const q = u.indexOf("?");
    if (q >= 0) u = u.slice(0, q);

    // 앞에 ./, / 제거는 "업로드 저장키" 만들 때만 사용
    return u;
  }

  function stripLeadingDotsAndSlashes(u) {
    u = String(u || "");
    // "./uploads/.." "/uploads/.." "uploads/.." 모두 "uploads/.."로
    while (u.startsWith("./")) u = u.slice(2);
    while (u.startsWith("/")) u = u.slice(1);
    return u;
  }

  function isUploadGetPath(u) {
    u = stripLeadingDotsAndSlashes(normalizeUrl(u));
    return u.startsWith("uploads/") || u.startsWith("src/renderer/resources/uploads/") || u.startsWith("resources/uploads/");
  }

  function isUploadApi(u) {
    u = normalizeUrl(u);

    // 최대한 넓게 커버 (Entry 버전별로 endpoint가 조금씩 다름)
    // - /rest/sound/upload
    // - /rest/image/upload
    // - /rest/project/upload*
    // - /rest/upload*
    return (
      /\/rest\/sound\/upload\b/i.test(u) ||
      /\/rest\/image\/upload\b/i.test(u) ||
      /\/rest\/project\/upload/i.test(u) ||
      /\/rest\/upload/i.test(u)
    );
  }

  function isDataTableApi(u) {
    u = normalizeUrl(u);
    // 데이터테이블 관련 endpoint 폭넓게 (버전차 대비)
    return /\/rest\/datatable\b/i.test(u) || /\/rest\/dataTable\b/i.test(u);
  }

  function randomBase36(len) {
    const bytes = new Uint8Array(len);
    crypto.getRandomValues(bytes);
    let out = "";
    for (let i = 0; i < bytes.length; i++) out += (bytes[i] % 36).toString(36);
    return out;
  }

  // uid(8)+puid.generate()를 100% 재현할 필요는 없고 "충돌 거의 없는 문자열"이면 됩니다.
  function createFileId() {
    // 예: e49448cdlyy4s42e0013f820158i7nqj 같은 느낌
    const a = randomBase36(8);
    const b = (now().toString(36)).padStart(8, "0");
    const c = randomBase36(16);
    return (a + b + c).slice(0, 32);
  }

  function splitPrefix(fileId) {
    const id = String(fileId);
    const a = id.slice(0, 2) || "00";
    const b = id.slice(2, 4) || "00";
    return { a, b };
  }

  function ensureExtByMimeOrName(file, fallbackExt) {
    const name = (file && file.name) ? String(file.name) : "";
    const lower = name.toLowerCase();
    const hasDot = lower.lastIndexOf(".") >= 0;
    if (hasDot) return lower.slice(lower.lastIndexOf("."));
    // mime 기반 추정
    const t = (file && file.type) ? String(file.type) : "";
    if (t === "image/png") return ".png";
    if (t === "image/jpeg") return ".jpg";
    if (t === "image/webp") return ".webp";
    if (t === "audio/mpeg") return ".mp3";
    if (t === "audio/wav") return ".wav";
    if (t === "audio/ogg") return ".ogg";
    return fallbackExt || ".bin";
  }

  async function makeThumbPngFromImageBlob(blob, maxW = 320, maxH = 320) {
    try {
      const bmp = await createImageBitmap(blob);
      const w = bmp.width, h = bmp.height;
      if (!w || !h) throw new Error("bitmap empty");
      const scale = Math.min(maxW / w, maxH / h, 1);
      const tw = Math.max(1, Math.round(w * scale));
      const th = Math.max(1, Math.round(h * scale));

      const c = document.createElement("canvas");
      c.width = tw; c.height = th;
      const ctx = c.getContext("2d");
      ctx.drawImage(bmp, 0, 0, tw, th);

      const out = await new Promise((resolve) => c.toBlob(resolve, "image/png"));
      if (!out) throw new Error("toBlob failed");
      return out;
    } catch (e) {
      // 실패 시 썸네일은 원본으로 대체(Entry가 thumb가 꼭 필요하진 않음)
      return blob;
    }
  }

  class IDBWrap {
    constructor() { this._dbp = null; }

    async db() {
      if (this._dbp) return this._dbp;
      this._dbp = new Promise((resolve, reject) => {
        const req = indexedDB.open(DB_NAME, DB_VER);
        req.onupgradeneeded = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains(STORES.blobs)) {
            db.createObjectStore(STORES.blobs);
          }
          if (!db.objectStoreNames.contains(STORES.json)) {
            db.createObjectStore(STORES.json);
          }
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
      return this._dbp;
    }

    async put(store, key, value) {
      const db = await this.db();
      return await new Promise((resolve, reject) => {
        const tx = db.transaction(store, "readwrite");
        tx.objectStore(store).put(value, key);
        tx.oncomplete = () => resolve(true);
        tx.onerror = () => reject(tx.error);
      });
    }

    async get(store, key) {
      const db = await this.db();
      return await new Promise((resolve, reject) => {
        const tx = db.transaction(store, "readonly");
        const req = tx.objectStore(store).get(key);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    }
  }

  const idb = new IDBWrap();

  async function storeBlob(pathKey, blob, contentType) {
    const key = stripLeadingDotsAndSlashes(normalizeUrl(pathKey));
    const ct = contentType || blob.type || guessContentTypeByExt(key);
    await idb.put(STORES.blobs, key, {
      blob,
      ct,
      ts: now(),
      size: blob.size || 0,
    });
    return key;
  }

  async function loadBlob(pathKey) {
    const key = stripLeadingDotsAndSlashes(normalizeUrl(pathKey));
    const v = await idb.get(STORES.blobs, key);
    return v || null;
  }

  async function storeJSON(key, obj) {
    await idb.put(STORES.json, key, obj);
  }

  async function loadJSON(key) {
    const v = await idb.get(STORES.json, key);
    return (v === undefined) ? null : v;
  }

  function buildUploadPath(fileId, kind, ext) {
    const { a, b } = splitPrefix(fileId);
    const safeKind = (kind === "sound" || kind === "thumb" || kind === "image") ? kind : "image";
    const safeExt = (ext && ext.startsWith(".")) ? ext : ".bin";
    return `uploads/${a}/${b}/${safeKind}/${fileId}${safeExt}`;
  }

  function jsonResponse(obj, status = 200) {
    return new Response(JSON.stringify(obj), {
      status,
      headers: { "content-type": "application/json; charset=utf-8" }
    });
  }

  async function handleUploadFromFormData(url, formData) {
    // formData 안에서 "파일"을 최대한 찾아냄
    let file = null;
    let fieldName = null;

    for (const [k, v] of formData.entries()) {
      if (v instanceof File || v instanceof Blob) {
        file = v;
        fieldName = k;
        break;
      }
    }

    if (!file) {
      return jsonResponse({ ok: false, message: "no file in form-data" }, 400);
    }

    // 어떤 업로드인지 대충 판별 (sound/image)
    const isSound = /sound/i.test(url) || (file.type && file.type.startsWith("audio/"));
    const kind = isSound ? "sound" : "image";

    const fileId = createFileId();
    const ext = ensureExtByMimeOrName(file, isSound ? ".mp3" : ".png");

    const mainPath = buildUploadPath(fileId, kind, ext);
    await storeBlob(mainPath, file, file.type || guessContentTypeByExt(mainPath));

    // 이미지면 thumb도 같이 만들어서 저장 (Entry UI에서 썸네일을 자주 씀)
    let thumbPath = null;
    if (!isSound) {
      const thumbBlob = await makeThumbPngFromImageBlob(file);
      thumbPath = buildUploadPath(fileId, "thumb", ".png");
      await storeBlob(thumbPath, thumbBlob, "image/png");
    }

    // Entry가 기대할 법한 응답 형태를 넓게 제공(버전차 대비)
    // - fileId / filename / path / url / image / sound 등 다양하게
    const out = {
      ok: true,
      fileId,
      id: fileId,
      field: fieldName,
      path: "/" + mainPath,
      url: "./" + mainPath,
      // 일부 구현은 "image" / "sound" 같은 키로 내려줌
      image: !isSound ? { fileId, path: "/" + mainPath, url: "./" + mainPath, thumb: thumbPath ? ("./" + thumbPath) : null } : undefined,
      sound: isSound ? { fileId, path: "/" + mainPath, url: "./" + mainPath } : undefined,
      thumb: thumbPath ? ("./" + thumbPath) : null,
      contentType: file.type || guessContentTypeByExt(mainPath),
      size: file.size || 0,
    };

    return jsonResponse(out, 200);
  }

  async function handleUploadsGET(url) {
    // url: "./uploads/aa/bb/..." or "/uploads/..."
    const key = stripLeadingDotsAndSlashes(normalizeUrl(url));

    const found = await loadBlob(key);
    if (!found) {
      return new Response("Not Found", { status: 404 });
    }
    return new Response(found.blob, {
      status: 200,
      headers: {
        "content-type": found.ct || guessContentTypeByExt(key),
        "cache-control": "no-store",
      }
    });
  }

  async function handleDataTable(reqUrl, reqInit) {
    // 아주 단순한 KV 저장 형태로만 제공:
    // - GET  /rest/datatable/<key>
    // - POST /rest/datatable/<key>  (body json)
    // - PUT  /rest/datatable/<key>
    // - DELETE /rest/datatable/<key>
    //
    // 실제 Entry가 어떤 URL을 쓰더라도 최소한 "저장/불러오기"가 되도록 설계

    const u = new URL(reqUrl, location.href);
    const path = u.pathname; // /rest/datatable/....
    const key = "datatable:" + path; // path 자체를 키로 씀(버전차 무시)

    const method = (reqInit && reqInit.method) ? String(reqInit.method).toUpperCase() : "GET";

    if (method === "GET") {
      const v = await loadJSON(key);
      return jsonResponse(v ?? { ok: true, data: null }, 200);
    }

    if (method === "DELETE") {
      await storeJSON(key, null);
      return jsonResponse({ ok: true }, 200);
    }

    // POST/PUT: body json 저장
    let bodyObj = null;
    try {
      if (reqInit && reqInit.body) {
        if (typeof reqInit.body === "string") bodyObj = JSON.parse(reqInit.body);
        else if (reqInit.body instanceof Blob) bodyObj = JSON.parse(await reqInit.body.text());
        else bodyObj = null;
      }
    } catch (_) {
      bodyObj = null;
    }
    await storeJSON(key, bodyObj);
    return jsonResponse({ ok: true }, 200);
  }

  function installFetchInterceptor(basePrefix = "./") {
    if (window.__LOCAL_BACKEND_FETCH_INSTALLED__) return;
    window.__LOCAL_BACKEND_FETCH_INSTALLED__ = true;

    const _fetch = window.fetch.bind(window);

    window.fetch = async (input, init) => {
      try {
        const url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
        const u0 = normalizeUrl(url);

        // 1) uploads GET
        if (isUploadGetPath(u0)) {
          return await handleUploadsGET(u0);
        }

        // 2) upload API
        if (isUploadApi(u0)) {
          // fetch(Request)면 request.formData()로 안전하게 파싱 가능
          if (typeof input !== "string" && input instanceof Request) {
            const fd = await input.formData();
            return await handleUploadFromFormData(u0, fd);
          }

          // fetch(url, {body: FormData})
          if (init && init.body && init.body instanceof FormData) {
            return await handleUploadFromFormData(u0, init.body);
          }

          // 그 외는 원래 fetch로 (혹시 서버가 있는 환경 대비)
          return await _fetch(input, init);
        }

        // 3) dataTable API
        if (isDataTableApi(u0)) {
          return await handleDataTable(u0, init || {});
        }

        return await _fetch(input, init);
      } catch (e) {
        // fail-safe: 원래 fetch로
        return await _fetch(input, init);
      }
    };
  }

  function installXHRInterceptor() {
    if (window.__LOCAL_BACKEND_XHR_INSTALLED__) return;
    window.__LOCAL_BACKEND_XHR_INSTALLED__ = true;

    const NativeXHR = window.XMLHttpRequest;

    function FakeXHR() {
      const xhr = new NativeXHR();

      // 상태 저장
      xhr.__lb = {
        method: "GET",
        url: "",
        async: true,
        handled: false,
        requestBody: null,
      };

      const _open = xhr.open;
      xhr.open = function (method, url, async = true, ...rest) {
        xhr.__lb.method = String(method || "GET").toUpperCase();
        xhr.__lb.url = url;
        xhr.__lb.async = async !== false;

        // entry./ 오타 보정만 여기서도 1회
        const fixedUrl = normalizeUrl(url);

        return _open.call(xhr, method, fixedUrl, async, ...rest);
      };

      const _send = xhr.send;
      xhr.send = function (body) {
        const url = normalizeUrl(xhr.__lb.url);

        // uploads GET은 createjs/preloadjs가 XHR로 때릴 수 있음 → 여기서 처리
        if (isUploadGetPath(url) && xhr.__lb.method === "GET") {
          xhr.__lb.handled = true;
          (async () => {
            const res = await handleUploadsGET(url);

            xhr.status = res.status;
            xhr.readyState = 4;

            // responseType 대응(최소)
            const rt = xhr.responseType || "";
            if (rt === "arraybuffer") {
              const ab = await res.arrayBuffer();
              xhr.response = ab;
            } else if (rt === "blob") {
              const b = await res.blob();
              xhr.response = b;
            } else {
              const t = await res.text();
              xhr.responseText = t;
              xhr.response = t;
            }

            try { xhr.onreadystatechange && xhr.onreadystatechange(); } catch (_) {}
            try { xhr.onload && xhr.onload(); } catch (_) {}
          })();
          return;
        }

        // upload API도 XHR로 올 수 있음 → FormData면 처리
        if (isUploadApi(url) && (xhr.__lb.method === "POST" || xhr.__lb.method === "PUT")) {
          xhr.__lb.handled = true;
          (async () => {
            let res;
            if (body instanceof FormData) {
              res = await handleUploadFromFormData(url, body);
            } else {
              // FormData가 아니면 원래로 보내되, 실패할 수 있음
              res = null;
            }

            if (!res) {
              // fallback
              _send.call(xhr, body);
              return;
            }

            xhr.status = res.status;
            xhr.readyState = 4;

            const txt = await res.text();
            xhr.responseText = txt;
            xhr.response = txt;

            try { xhr.onreadystatechange && xhr.onreadystatechange(); } catch (_) {}
            try { xhr.onload && xhr.onload(); } catch (_) {}
          })();
          return;
        }

        // datatable API도 XHR로 올 수 있음
        if (isDataTableApi(url)) {
          xhr.__lb.handled = true;
          (async () => {
            const init = { method: xhr.__lb.method };
            if (body != null) init.body = body;
            const res = await handleDataTable(url, init);

            xhr.status = res.status;
            xhr.readyState = 4;
            const txt = await res.text();
            xhr.responseText = txt;
            xhr.response = txt;

            try { xhr.onreadystatechange && xhr.onreadystatechange(); } catch (_) {}
            try { xhr.onload && xhr.onload(); } catch (_) {}
          })();
          return;
        }

        return _send.call(xhr, body);
      };

      return xhr;
    }

    // 전역 교체
    window.XMLHttpRequest = FakeXHR;
  }

  const LocalBackend = {
    // index.html에서 BASE 탐지한 뒤 호출 권장
    install(BASE = "./") {
      installFetchInterceptor(BASE);
      installXHRInterceptor();

      // 디버그 출력(원하면 주석)
      try {
        if (window.bootLine) window.bootLine("LocalBackend installed (uploads+datatable via IndexedDB)", "ok");
      } catch (_) {}
    },

    // 디버깅용 공개
    __debug: {
      createFileId,
      buildUploadPath,
      storeBlob,
      loadBlob,
      storeJSON,
      loadJSON,
    }
  };

  window.LocalBackend = LocalBackend;
})();
