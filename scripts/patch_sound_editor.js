/**
 * scripts/patch_sound_editor.js
 * - Ensure www/lib/external/sound/sound-editor.js exists
 * - Ensure it exports EntrySoundEditor.renderSoundEditor as a FUNCTION
 * - If existing file looks like "stub (disabled)" or missing function, overwrite safely.
 */
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const TARGET = path.join(ROOT, "www", "lib", "external", "sound", "sound-editor.js");

const STUB = `/* www/lib/external/sound/sound-editor.js
 * EntrySoundEditor minimal stub:
 * Entry expects renderSoundEditor() to be a FUNCTION.
 * This stub prevents Entry.init crash during boot.
 */
(function (global) {
  function noop() {}

  function renderSoundEditor() {
    var el = document.createElement("div");
    el.style.display = "none";
    el.setAttribute("data-entry-sound-editor", "stub");
    return el;
  }

  var api = {
    renderSoundEditor: renderSoundEditor,
    show: noop,
    hide: noop,
    open: noop,
    close: noop,
    destroy: noop,
  };

  global.EntrySoundEditor = api;
  global.renderSoundEditor = renderSoundEditor;
})(window);
`;

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function readFileIfExists(p) {
  try {
    return fs.readFileSync(p, "utf8");
  } catch {
    return null;
  }
}

function needsPatch(content) {
  if (!content) return true;

  // If it explicitly says stub disabled or is empty-ish
  const c = content.trim();
  if (c.length < 40) return true;

  // If renderSoundEditor is missing entirely
  if (!/renderSoundEditor/.test(content)) return true;

  // If renderSoundEditor exists but not a function (heuristic)
  // examples: renderSoundEditor: "disabled", renderSoundEditor = "stub"
  if (/renderSoundEditor\s*[:=]\s*['"]/.test(content)) return true;

  // If it references React without bundling, likely wrong file
  if (/\bReact\b/.test(content) && !/\brenderSoundEditor\b/.test(content)) return true;

  // If it contains your previous marker
  if (/EntrySoundEditor\s*=\s*stub/i.test(content)) return true;

  return false;
}

function main() {
  const dir = path.dirname(TARGET);
  ensureDir(dir);

  const old = readFileIfExists(TARGET);
  const patch = needsPatch(old);

  if (patch) {
    fs.writeFileSync(TARGET, STUB, "utf8");
    console.log(`[patch_sound_editor] Patched: ${TARGET}`);
  } else {
    console.log(`[patch_sound_editor] OK (no change): ${TARGET}`);
  }
}

main();
