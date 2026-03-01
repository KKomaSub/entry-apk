// www/local_backend.js
// ✅ IIFE 없음. renderer_build(Electron 전용)이 웹에서 죽지 않도록 최소 환경 제공.

(function noop(){}) // <- 이것도 싫으면 이 줄도 삭제하세요. (완전 무의미한 안전줄)

// ---- boot log helper ----
function __lb_log(msg) {
  try {
    if (typeof window.bootLine === "function") window.bootLine(String(msg), "dim");
    else console.log("[local_backend]", msg);
  } catch (_) {}
}

// ---- tiny event bus ----
const __lb_events = Object.create(null);

function __lb_on(ch, fn) {
  (__lb_events[ch] ||= []).push(fn);
}
function __lb_emit(ch, ...args) {
  const list = __lb_events[ch] || [];
  for (const fn of list) {
    try { fn(...args); } catch (e) { __lb_log("listener error: " + e); }
  }
}

// ✅ ipcRenderer 스텁(가장 중요)
window.ipcRenderer = window.ipcRenderer || {
  on(channel, listener) { __lb_on(channel, listener); return this; },
  removeListener(channel, listener) {
    const list = __lb_events[channel]; if (!list) return this;
    const i = list.indexOf(listener); if (i >= 0) list.splice(i, 1);
    return this;
  },
  send(channel, ...args) {
    __lb_log("ipcRenderer.send " + channel);
    __lb_emit(channel, ...args);
  },
  async invoke(channel, ...args) {
    __lb_log("ipcRenderer.invoke " + channel);

    const ch = String(channel || "");

    // ✅ UI가 막히지 않도록 “성공형 더미”를 반환
    // (나중에 채널명 확인 후 실제 구현으로 확장)
    if (ch.includes("openDialog") || ch.includes("showOpenDialog") || ch.includes("select")) {
      return { canceled: true, filePaths: [] };
    }
    if (ch.includes("readFile")) return "";
    if (ch.includes("writeFile")) return true;

    // 업로드/에셋/사운드/이미지 저장 계열
    if (ch.includes("upload") || ch.includes("asset") || ch.includes("sound") || ch.includes("image")) {
      return { ok: true };
    }

    // dataTable 계열
    if (ch.toLowerCase().includes("datatable")) {
      return { ok: true, data: [] };
    }

    return null;
  }
};

// ✅ Electron require 스텁 (render.bundle이 require('electron')을 쓰는 경우)
window.require = window.require || function (name) {
  if (name === "electron") return { ipcRenderer: window.ipcRenderer };
  if (name === "path") {
    return {
      join: (...a) => a.filter(Boolean).join("/"),
      basename: (p) => String(p || "").split("/").pop(),
      dirname: (p) => String(p || "").split("/").slice(0, -1).join("/") || "."
    };
  }
  __lb_log("require(" + name + ") -> null");
  return null;
};

// ✅ 일부 번들이 process/Buffer/global을 기대하는 경우가 있어 최소 제공
window.process = window.process || { env: {}, platform: "android" };
window.global = window.global || window;
window.Buffer = window.Buffer || undefined;

__lb_log("local_backend installed: ipcRenderer=" + (typeof window.ipcRenderer) + ", require=" + (typeof window.require));
