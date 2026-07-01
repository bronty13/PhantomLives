"use strict";
// PeekServer review UI — vanilla JS. Fast grid of cached thumbnails, keyboard-driven decisions,
// detail overlay with full media + metadata. All state shared via the server's one DB.

const $ = (s) => document.querySelector(s);
const api = {
  async get(u) { return (await fetch(u)).json(); },
  async post(u, body) {
    return (await fetch(u, { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {}) })).json();
  },
};

const FILTERS = [
  ["undecided", "Undecided"], ["kept", "Kept"], ["skipped", "Skipped"],
  ["favorite", "Favorites"], ["all", "All"],
];

const S = { roots: [], rootPath: null, filter: "undecided", items: [], total: 0, sel: -1, scanning: false };

// ---------- data ----------
async function loadRoots() {
  const r = await api.get("/api/roots");
  S.roots = r.roots; S.scanning = r.scanning;
  const sel = $("#rootSel");
  sel.innerHTML = "";
  for (const root of S.roots) {
    const o = document.createElement("option");
    o.value = root.path;
    o.textContent = `${root.label}  (${root.total || 0})`;
    sel.appendChild(o);
  }
  if (!S.rootPath && S.roots.length) S.rootPath = S.roots[0].path;
  if (S.rootPath) sel.value = S.rootPath;
  renderFilters();
  updateStatus();
}

async function loadItems() {
  if (!S.rootPath) { S.items = []; renderGrid(); return; }
  const u = `/api/items?root=${encodeURIComponent(S.rootPath)}&decision=${S.filter}&limit=500`;
  const r = await api.get(u);
  S.items = r.items; S.total = r.total;
  S.sel = S.items.length ? 0 : -1;
  renderGrid();
  updateStatus();
}

function currentRoot() { return S.roots.find((r) => r.path === S.rootPath); }

// ---------- render ----------
function renderFilters() {
  const root = currentRoot() || {};
  const counts = { undecided: root.undecided, kept: root.kept, skipped: root.skipped };
  const nav = $("#filters"); nav.innerHTML = "";
  for (const [key, label] of FILTERS) {
    const b = document.createElement("button");
    b.className = key === S.filter ? "active" : "";
    b.innerHTML = label + (counts[key] != null ? ` <span class="n">${counts[key] || 0}</span>` : "");
    b.onclick = () => { S.filter = key; renderFilters(); loadItems(); };
    nav.appendChild(b);
  }
}

let thumbObserver;
function renderGrid() {
  const grid = $("#grid");
  grid.innerHTML = "";
  if (thumbObserver) thumbObserver.disconnect();
  thumbObserver = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        const img = e.target.querySelector("img[data-src]");
        if (img) { img.src = img.dataset.src; img.removeAttribute("data-src"); }
        thumbObserver.unobserve(e.target);
      }
    }
  }, { rootMargin: "300px" });

  S.items.forEach((it, i) => grid.appendChild(makeCell(it, i)));
  if (S.sel >= 0) highlight();
}

function makeCell(it, i) {
  const c = document.createElement("div");
  c.className = "cell" + decisionClass(it);
  c.dataset.i = i;
  if (it.file_type === "audio") {
    c.innerHTML = `<div class="glyph">♪</div>`;
  } else {
    const img = document.createElement("img");
    img.dataset.src = `/thumb/${it.id}`;
    img.alt = it.file_name; img.loading = "lazy";
    img.onerror = () => { c.innerHTML = `<div class="glyph">▢</div>` + c.querySelector(".type")?.outerHTML || ""; };
    c.appendChild(img);
  }
  c.insertAdjacentHTML("beforeend",
    (it.keep === 1 ? `<span class="badge">keep</span>` : it.keep === 0 ? `<span class="badge">skip</span>` : "") +
    (it.is_favorite ? `<span class="fav">★</span>` : "") +
    (it.file_type !== "image" ? `<span class="type">${it.file_type}</span>` : ""));
  c.onclick = () => { S.sel = i; highlight(); openOverlay(); };
  c.onmouseenter = () => { S.sel = i; highlight(); };
  thumbObserver.observe(c);
  return c;
}

function decisionClass(it) {
  return (it.keep === 1 ? " keep" : it.keep === 0 ? " skip" : "");
}

function highlight() {
  document.querySelectorAll(".cell.sel").forEach((c) => c.classList.remove("sel"));
  const cell = document.querySelector(`.cell[data-i="${S.sel}"]`);
  if (cell) { cell.classList.add("sel"); cell.scrollIntoView({ block: "nearest" }); }
}

function refreshCell(i) {
  const it = S.items[i];
  const cell = document.querySelector(`.cell[data-i="${i}"]`);
  if (!cell || !it) return;
  cell.className = "cell sel" + decisionClass(it);
  cell.querySelectorAll(".badge,.fav").forEach((e) => e.remove());
  cell.insertAdjacentHTML("beforeend",
    (it.keep === 1 ? `<span class="badge">keep</span>` : it.keep === 0 ? `<span class="badge">skip</span>` : "") +
    (it.is_favorite ? `<span class="fav">★</span>` : ""));
}

function updateStatus() {
  $("#status").textContent = S.scanning ? "scanning…" : `${S.items.length} shown`;
  $("#scanBtn").classList.toggle("spin", S.scanning);
}

// ---------- decisions ----------
async function decide(i, fields) {
  const it = S.items[i]; if (!it) return;
  Object.assign(it, fields);              // optimistic
  refreshCell(i);
  if (overlayOpen) syncOverlayButtons();
  const rec = await api.post("/api/decision", { id: it.id, ...fields });
  if (rec && rec.id) Object.assign(it, rec);
}

function act(action) {
  if (S.sel < 0) return;
  const it = S.items[S.sel];
  if (action === "keep") decide(S.sel, { keep: 1 });
  else if (action === "skip") decide(S.sel, { keep: 0 });
  else if (action === "undecide") decide(S.sel, { keep: null });
  else if (action === "fav") decide(S.sel, { is_favorite: it.is_favorite ? 0 : 1 });
}

// ---------- overlay ----------
let overlayOpen = false;
function openOverlay() {
  if (S.sel < 0) return;
  overlayOpen = true;
  $("#overlay").classList.remove("hidden");
  renderOverlay();
}
function closeOverlay() { overlayOpen = false; $("#overlay").classList.add("hidden"); $("#viewer").innerHTML = ""; }

function renderOverlay() {
  const it = S.items[S.sel]; if (!it) return;
  const v = $("#viewer");
  if (it.file_type === "video") {
    // /preview = the cached 720p faststart proxy (instant start, smooth over Wi-Fi); the server
    // transparently serves the original if no proxy exists yet. /full stays for import only.
    v.innerHTML = `<video src="/preview/${it.id}" controls autoplay playsinline></video>`;
  } else if (it.file_type === "audio") {
    v.innerHTML = `<audio src="/full/${it.id}" controls autoplay></audio>`;
  } else {
    // /display = screen-size JPEG (~20x fewer bytes than the original, and HEIC decodes
    // everywhere). Fall back to the original for anything /display can't produce.
    v.innerHTML = `<img src="/display/${it.id}" alt="${it.file_name}"
                        onerror="this.onerror=null;this.src='/full/${it.id}'">`;
  }
  $("#metaName").textContent = it.file_name;
  $("#fTitle").value = it.title || "";
  $("#fCaption").value = it.caption || "";
  syncOverlayButtons();
  // load full record for keywords/albums
  api.get(`/api/item/${it.id}`).then((rec) => {
    if (!rec) return;
    $("#fKeywords").value = (rec.keywords || []).join(", ");
    $("#fAlbums").value = (rec.albums || []).join(", ");
  });
}

function syncOverlayButtons() {
  const it = S.items[S.sel]; if (!it) return;
  $(".dKeep").classList.toggle("on", it.keep === 1);
  $(".dSkip").classList.toggle("on", it.keep === 0);
  $(".dFav").classList.toggle("on", !!it.is_favorite);
}

function saveMeta() {
  if (S.sel < 0) return;
  const it = S.items[S.sel];
  const csv = (s) => s.split(",").map((x) => x.trim()).filter(Boolean);
  decide(S.sel, {
    title: $("#fTitle").value || null,
    caption: $("#fCaption").value || null,
    keywords: csv($("#fKeywords").value),
    albums: csv($("#fAlbums").value),
  });
}

// ---------- navigation ----------
function colsPerRow() {
  const grid = $("#grid");
  const cell = grid.querySelector(".cell");
  if (!cell) return 1;
  return Math.max(1, Math.round(grid.clientWidth / (cell.offsetWidth + 10)));
}
function move(d) {
  if (!S.items.length) return;
  S.sel = Math.max(0, Math.min(S.items.length - 1, S.sel + d));
  highlight();
  if (overlayOpen) renderOverlay();
}

// ---------- keyboard ----------
document.addEventListener("keydown", (e) => {
  const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName);
  if (typing) { if (e.key === "Escape") document.activeElement.blur(); return; }
  switch (e.key) {
    case "ArrowRight": move(1); e.preventDefault(); break;
    case "ArrowLeft": move(-1); e.preventDefault(); break;
    case "ArrowDown": move(colsPerRow()); e.preventDefault(); break;
    case "ArrowUp": move(-colsPerRow()); e.preventDefault(); break;
    case "k": case "K": act("keep"); break;
    case "x": case "X": act("skip"); break;
    case "f": case "F": act("fav"); break;
    case "u": case "U": act("undecide"); break;
    case "Enter": overlayOpen ? closeOverlay() : openOverlay(); e.preventDefault(); break;
    case "Escape": if (overlayOpen) closeOverlay(); break;
  }
});

// ---------- wiring ----------
$("#rootSel").onchange = (e) => { S.rootPath = e.target.value; renderFilters(); loadItems(); };
$("#scanBtn").onclick = async () => { await api.post("/api/scan"); pollScan(); };
$("#closeOverlay").onclick = closeOverlay;
document.querySelectorAll(".decisionRow button").forEach((b) =>
  b.onclick = () => act(b.dataset.act));
["fTitle", "fCaption", "fKeywords", "fAlbums"].forEach((id) =>
  $("#" + id).addEventListener("change", saveMeta));

async function pollScan() {
  S.scanning = true; updateStatus();
  const t = setInterval(async () => {
    const r = await api.get("/api/roots");
    S.roots = r.roots; S.scanning = r.scanning;
    renderFilters(); updateStatus();
    if (!r.scanning) { clearInterval(t); await loadRoots(); await loadItems(); }
  }, 1500);
}

(async function init() {
  await loadRoots();
  await loadItems();
  if (S.scanning) pollScan();
})();
