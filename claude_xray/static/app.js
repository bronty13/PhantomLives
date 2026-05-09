// Claude XRay — minimal client.

let editor = null;
let currentRoot = "user";
let currentFile = null;       // { root, path, kind, readonly, original }
let dirty = false;
let availableRoots = {};

const $ = (id) => document.getElementById(id);

async function api(path, opts = {}) {
  const res = await fetch(path, opts);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`${res.status}: ${text}`);
  }
  return res.json();
}

function fmtBytes(n) {
  if (n == null) return "";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(2)} MB`;
}

function fmtTime(t) {
  if (!t) return "";
  return new Date(t * 1000).toLocaleString();
}

function modeFor(kind) {
  switch (kind) {
    case "json": return { name: "javascript", json: true };
    case "markdown": return "markdown";
    case "yaml": return "yaml";
    case "shell": return "shell";
    case "python": return "python";
    case "javascript": return "javascript";
    default: return null;
  }
}

// ---------- tree ----------

function renderTree(node, parent) {
  const el = document.createElement("div");
  el.className = "tree-node " + (node.isDir ? "dir" : "file");
  if (node.readonly) el.classList.add("readonly");
  el.dataset.path = node.path;
  el.dataset.name = node.name.toLowerCase();

  const label = document.createElement("span");
  label.className = "label";
  label.textContent = node.name;
  if (node.description) label.title = node.description;
  el.appendChild(label);

  if (node.isDir) {
    const kids = document.createElement("div");
    kids.className = "tree-children";
    if (node.children) {
      node.children.forEach((c) => renderTree(c, kids));
    }
    el.appendChild(kids);
    label.addEventListener("click", (e) => {
      e.stopPropagation();
      el.classList.toggle("open");
    });
  } else {
    label.addEventListener("click", (e) => {
      e.stopPropagation();
      selectFile(el, node);
    });
  }

  parent.appendChild(el);
}

async function loadTree(rootName) {
  currentRoot = rootName;
  $("tree").className = "loading";
  $("tree").textContent = "Loading…";
  document.querySelectorAll(".root-tabs button").forEach((b) => {
    b.classList.toggle("active", b.dataset.root === rootName);
  });

  try {
    const tree = await api(`/api/tree?root=${encodeURIComponent(rootName)}`);
    const container = $("tree");
    container.className = "";
    container.innerHTML = "";
    if (tree.missing) {
      container.innerHTML = `<div style="padding:16px;color:var(--muted)">Root does not exist on disk.</div>`;
      return;
    }
    // Auto-expand the top level
    const wrapper = document.createElement("div");
    if (tree.children) tree.children.forEach((c) => renderTree(c, wrapper));
    container.appendChild(wrapper);
  } catch (err) {
    $("tree").textContent = "Error: " + err.message;
  }
}

// ---------- file view ----------

async function selectFile(el, node) {
  if (dirty) {
    if (!confirm("Discard unsaved changes?")) return;
  }
  document.querySelectorAll(".tree-node.selected").forEach((n) => n.classList.remove("selected"));
  el.classList.add("selected");

  $("emptyState").hidden = true;
  $("fileView").hidden = false;
  $("status").textContent = "Loading…";
  $("status").className = "status";

  try {
    const data = await api(`/api/file?root=${encodeURIComponent(currentRoot)}&path=${encodeURIComponent(node.path)}`);
    currentFile = { root: currentRoot, path: node.path, kind: data.kind, readonly: data.readonly, original: data.content };

    $("filePath").textContent = `${currentRoot}/${node.path}`;
    $("fileMeta").textContent =
      `${fmtBytes(data.size)} • ${fmtTime(data.mtime)}` +
      (data.readonly ? " • read-only" : "") +
      (data.binary ? " • binary" : "") +
      (data.tooLarge ? " • TOO LARGE TO LOAD" : "");

    if (!editor) {
      editor = CodeMirror($("editor"), {
        value: "",
        lineNumbers: true,
        theme: "dracula",
        lineWrapping: true,
      });
      editor.on("change", () => {
        if (!currentFile) return;
        dirty = editor.getValue() !== currentFile.original;
        $("saveBtn").disabled = !dirty || currentFile.readonly;
        $("revertBtn").disabled = !dirty;
        if (dirty) { $("status").textContent = "modified"; $("status").className = "status"; }
      });
    }

    editor.setOption("mode", modeFor(data.kind));
    editor.setOption("readOnly", data.readonly);
    editor.setValue(data.tooLarge ? "// File too large to load in the editor (>5 MB)." : (data.binary ? "// Binary file." : data.content));
    dirty = false;
    $("saveBtn").disabled = true;
    $("revertBtn").disabled = true;
    $("status").textContent = "";

    const desc = data.description;
    $("aboutPanel").innerHTML = desc
      ? `<h3>About this file</h3><p>${escapeHtml(desc)}</p>`
      : `<h3>About this file</h3><p class="nodesc">No description on file. (Add one to descriptions.json keyed by "${escapeHtml(node.path)}".)</p>`;
  } catch (err) {
    $("status").textContent = "Error: " + err.message;
    $("status").className = "status err";
  }
}

async function saveFile() {
  if (!currentFile || currentFile.readonly) return;
  $("status").textContent = "Saving…";
  $("status").className = "status";
  try {
    const content = editor.getValue();
    const res = await api(
      `/api/file?root=${encodeURIComponent(currentFile.root)}&path=${encodeURIComponent(currentFile.path)}`,
      { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ content }) }
    );
    currentFile.original = content;
    dirty = false;
    $("saveBtn").disabled = true;
    $("revertBtn").disabled = true;
    $("status").textContent = `saved ${fmtBytes(res.size)}`;
    $("status").className = "status ok";
    $("fileMeta").textContent = `${fmtBytes(res.size)} • ${fmtTime(res.mtime)}`;
  } catch (err) {
    $("status").textContent = "Error: " + err.message;
    $("status").className = "status err";
  }
}

function revertFile() {
  if (!currentFile) return;
  editor.setValue(currentFile.original);
  dirty = false;
  $("saveBtn").disabled = true;
  $("revertBtn").disabled = true;
  $("status").textContent = "reverted";
  $("status").className = "status";
}

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

// ---------- search filter ----------

function applyFilter(q) {
  q = q.trim().toLowerCase();
  document.querySelectorAll(".tree-node").forEach((n) => {
    const match = !q || n.dataset.name.includes(q) || (n.dataset.path || "").toLowerCase().includes(q);
    n.classList.toggle("hidden", !match);
    if (match && q) {
      // open all ancestors so the match is visible
      let p = n.parentElement;
      while (p && p.classList) {
        if (p.classList.contains("tree-node")) p.classList.add("open");
        p = p.parentElement;
      }
    }
  });
}

// ---------- bootstrap ----------

async function init() {
  availableRoots = await api("/api/roots");
  const tabs = $("rootTabs");
  Object.entries(availableRoots).forEach(([name, fullPath], i) => {
    const b = document.createElement("button");
    b.dataset.root = name;
    b.textContent = name === "user" ? `~/.claude` : `.claude (project)`;
    b.title = fullPath;
    if (i === 0) b.classList.add("active");
    b.addEventListener("click", () => loadTree(name));
    tabs.appendChild(b);
  });

  await loadTree(Object.keys(availableRoots)[0] || "user");

  $("saveBtn").addEventListener("click", saveFile);
  $("revertBtn").addEventListener("click", revertFile);
  $("search").addEventListener("input", (e) => applyFilter(e.target.value));

  document.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "s") {
      e.preventDefault();
      saveFile();
    }
  });

  window.addEventListener("beforeunload", (e) => {
    if (dirty) { e.preventDefault(); e.returnValue = ""; }
  });
}

init();
