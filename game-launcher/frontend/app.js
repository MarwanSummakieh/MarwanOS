/* Game Launcher frontend — vanilla JS, no build step. */
"use strict";

const state = {
  session: localStorage.getItem("gl_session") || "",
  games: [],
  view: "library",
  editingId: null,
  browseTarget: null, // which input the file browser writes to
};

// --- API helper --------------------------------------------------------------
async function api(path, opts = {}) {
  const headers = Object.assign({ "Content-Type": "application/json" }, opts.headers || {});
  if (state.session) headers["X-Session"] = state.session;
  const res = await fetch(path, { ...opts, headers });
  if (res.status === 401) {
    showLogin();
    throw new Error("Authentication required");
  }
  if (!res.ok) {
    let msg = res.statusText;
    try { msg = (await res.json()).detail || msg; } catch (_) {}
    throw new Error(msg);
  }
  return res.status === 204 ? null : res.json();
}

// --- Toasts ------------------------------------------------------------------
function toast(message, kind = "info") {
  const host = document.getElementById("toasts");
  const el = document.createElement("div");
  el.className = `toast ${kind}`;
  el.textContent = message;
  host.appendChild(el);
  setTimeout(() => { el.style.opacity = "0"; setTimeout(() => el.remove(), 300); }, 3800);
}

// --- Auth --------------------------------------------------------------------
function showLogin() { document.getElementById("login-overlay").classList.remove("hidden"); }
function hideLogin() { document.getElementById("login-overlay").classList.add("hidden"); }

document.getElementById("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const token = document.getElementById("login-token").value;
  try {
    const r = await api("/api/login", { method: "POST", body: JSON.stringify({ token }) });
    state.session = r.session;
    localStorage.setItem("gl_session", r.session);
    hideLogin();
    boot();
  } catch (err) {
    const e2 = document.getElementById("login-error");
    e2.textContent = err.message; e2.classList.remove("hidden");
  }
});

// --- Views -------------------------------------------------------------------
document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", () => switchView(tab.dataset.view));
});

function switchView(view) {
  state.view = view;
  document.querySelectorAll(".tab").forEach((t) => t.classList.toggle("active", t.dataset.view === view));
  const show = (id, on) => document.getElementById(id).classList.toggle("hidden", !on);
  show("grid", view === "library" || view === "installed");
  show("filters", view === "library" || view === "installed");
  show("history-view", view === "history");
  show("settings-view", view === "settings");
  document.getElementById("empty").classList.add("hidden");
  if (view === "history") loadHistory();
  else if (view === "settings") loadSettings();
  else renderGrid();
}

// --- Library -----------------------------------------------------------------
async function loadGames() {
  try {
    state.games = await api("/api/games");
    populateFilters();
    renderGrid();
  } catch (err) { toast(err.message, "error"); }
}

function populateFilters() {
  const genres = [...new Set(state.games.map((g) => g.genre).filter(Boolean))].sort();
  const years = [...new Set(state.games.map((g) => g.year).filter(Boolean))].sort((a, b) => b - a);
  const gSel = document.getElementById("filter-genre");
  const ySel = document.getElementById("filter-year");
  gSel.innerHTML = '<option value="">All genres</option>' + genres.map((g) => `<option>${esc(g)}</option>`).join("");
  ySel.innerHTML = '<option value="">All years</option>' + years.map((y) => `<option>${y}</option>`).join("");
}

function currentFilter() {
  return {
    search: document.getElementById("search").value.trim().toLowerCase(),
    genre: document.getElementById("filter-genre").value,
    year: document.getElementById("filter-year").value,
    stateSel: document.getElementById("filter-state").value,
  };
}

function renderGrid() {
  const grid = document.getElementById("grid");
  const empty = document.getElementById("empty");
  const f = currentFilter();
  let list = state.games.filter((g) => {
    if (state.view === "installed" && g.install_status !== "installed") return false;
    if (f.search && !g.title.toLowerCase().includes(f.search)) return false;
    if (f.genre && g.genre !== f.genre) return false;
    if (f.year && String(g.year) !== f.year) return false;
    if (f.stateSel === "installed" && g.install_status !== "installed") return false;
    if (f.stateSel === "not-installed" && g.install_status === "installed") return false;
    return true;
  });

  grid.innerHTML = "";
  if (!list.length) {
    empty.textContent = state.view === "installed"
      ? "No installed games yet. Install one from your Library."
      : "Your library is empty. Click “+ Add game” to add a Windows installer you own.";
    empty.classList.remove("hidden");
    return;
  }
  empty.classList.add("hidden");
  for (const g of list) grid.appendChild(card(g));
}

function card(g) {
  const el = document.createElement("div");
  el.className = "card";
  el.dataset.gameId = g.id;
  const installed = g.install_status === "installed";
  const cover = g.image_url
    ? `<img src="${esc(g.image_url)}" alt="" onerror="this.remove()" />`
    : "🎮";
  el.innerHTML = `
    <div class="cover">${cover}${installed ? '<span class="badge installed">Installed</span>' : ""}</div>
    <div class="card-body">
      <div class="card-title">${esc(g.title)}</div>
      <div class="card-meta">
        ${g.genre ? `<span>${esc(g.genre)}</span>` : ""}
        ${g.year ? `<span>${g.year}</span>` : ""}
        ${g.size_bytes ? `<span>${fmtSize(g.size_bytes)}</span>` : ""}
      </div>
      <div class="progress hidden"><i></i></div>
      <div class="progress-msg"></div>
      <div class="card-actions">
        ${installed
          ? `<button class="btn btn-primary btn-sm act-play">▶ Play</button>
             <button class="btn btn-danger btn-sm act-uninstall">Uninstall</button>`
          : `<button class="btn btn-primary btn-sm act-install">⬇ Install</button>
             <button class="btn btn-ghost btn-sm act-edit">Edit</button>`}
      </div>
    </div>`;

  el.querySelector(".act-install")?.addEventListener("click", () => install(g, el));
  el.querySelector(".act-uninstall")?.addEventListener("click", () => uninstall(g, el));
  el.querySelector(".act-play")?.addEventListener("click", () => play(g));
  el.querySelector(".act-edit")?.addEventListener("click", () => openGameModal(g));
  return el;
}

// --- Install with live progress (SSE) ---------------------------------------
async function install(g, el) {
  const actions = el.querySelector(".card-actions");
  const bar = el.querySelector(".progress");
  const fill = el.querySelector(".progress i");
  const msg = el.querySelector(".progress-msg");
  bar.classList.remove("hidden");
  actions.innerHTML = `<button class="btn btn-danger btn-sm">Cancel</button>`;

  let job;
  try {
    job = await api(`/api/games/${g.id}/install`, { method: "POST", body: JSON.stringify({}) });
  } catch (err) { toast(err.message, "error"); renderGrid(); return; }

  actions.querySelector("button").addEventListener("click", async () => {
    try { await api(`/api/jobs/${job.job_id}/cancel`, { method: "POST" }); } catch (_) {}
  });

  const url = `/api/jobs/${job.job_id}/stream` + (state.session ? `?session=${encodeURIComponent(state.session)}` : "");
  const es = new EventSource(url);
  es.onmessage = (ev) => {
    const d = JSON.parse(ev.data);
    if (d._done) {
      es.close();
      loadGames();
      return;
    }
    fill.style.width = `${Math.round((d.fraction || 0) * 100)}%`;
    msg.textContent = d.message || "";
    if (d.status === "done") { toast(`${g.title} installed`, "success"); es.close(); loadGames(); }
    else if (d.status === "error") { toast(`${g.title}: ${d.error}`, "error"); es.close(); renderGrid(); }
    else if (d.status === "cancelled") { toast(`${g.title} cancelled`, "warn"); es.close(); renderGrid(); }
  };
  es.onerror = () => { es.close(); };
}

async function uninstall(g) {
  if (!confirm(`Remove "${g.title}" from installed games?`)) return;
  try {
    const job = await api(`/api/games/${g.id}/uninstall`, { method: "POST" });
    const url = `/api/jobs/${job.job_id}/stream` + (state.session ? `?session=${encodeURIComponent(state.session)}` : "");
    const es = new EventSource(url);
    es.onmessage = (ev) => {
      const d = JSON.parse(ev.data);
      if (d._done || d.status === "done") { es.close(); toast(`${g.title} uninstalled`, "success"); loadGames(); }
    };
  } catch (err) { toast(err.message, "error"); }
}

async function play(g) {
  try {
    const r = await api(`/api/games/${g.id}/launch`, { method: "POST" });
    toast(`${g.title}: ${r.status}`, "success");
  } catch (err) { toast(err.message, "error"); }
}

// --- Add / edit game modal ---------------------------------------------------
function openGameModal(game) {
  state.editingId = game ? game.id : null;
  document.getElementById("modal-title").textContent = game ? "Edit game" : "Add game";
  document.getElementById("f-title").value = game?.title || "";
  document.getElementById("f-installer").value = game?.installer_path || "";
  document.getElementById("f-image").value = game?.image_url || "";
  document.getElementById("f-genre").value = game?.genre || "";
  document.getElementById("f-year").value = game?.year || "";
  document.getElementById("f-desc").value = game?.description || "";
  document.getElementById("game-modal").classList.remove("hidden");
}

document.getElementById("add-game").addEventListener("click", () => openGameModal(null));
document.getElementById("game-cancel").addEventListener("click", () =>
  document.getElementById("game-modal").classList.add("hidden"));

document.getElementById("game-save").addEventListener("click", async () => {
  const body = {
    title: document.getElementById("f-title").value.trim(),
    installer_path: document.getElementById("f-installer").value.trim(),
    image_url: document.getElementById("f-image").value.trim(),
    genre: document.getElementById("f-genre").value.trim(),
    year: parseInt(document.getElementById("f-year").value) || null,
    description: document.getElementById("f-desc").value.trim(),
  };
  if (!body.title) { toast("Title is required", "warn"); return; }
  try {
    if (state.editingId) await api(`/api/games/${state.editingId}`, { method: "PUT", body: JSON.stringify(body) });
    else await api("/api/games", { method: "POST", body: JSON.stringify(body) });
    document.getElementById("game-modal").classList.add("hidden");
    toast("Saved", "success");
    loadGames();
  } catch (err) { toast(err.message, "error"); }
});

// --- File browser ------------------------------------------------------------
document.getElementById("browse-btn").addEventListener("click", () => {
  state.browseTarget = document.getElementById("f-installer");
  openBrowser(null);
});
document.getElementById("browse-close").addEventListener("click", () =>
  document.getElementById("browse-modal").classList.add("hidden"));

async function openBrowser(path) {
  try {
    const data = await api("/api/browse" + (path ? `?path=${encodeURIComponent(path)}` : ""));
    document.getElementById("browse-cwd").textContent = data.cwd;
    const list = document.getElementById("browse-list");
    list.innerHTML = "";
    if (data.parent) list.appendChild(browseRow("📁 ..", () => openBrowser(data.parent)));
    for (const e of data.entries) {
      if (e.is_dir) {
        list.appendChild(browseRow(`📁 ${e.name}`, () => openBrowser(e.path)));
      } else {
        list.appendChild(browseRow(`📦 ${e.name}`, () => {
          state.browseTarget.value = e.path;
          if (!document.getElementById("f-title").value) {
            document.getElementById("f-title").value = e.name.replace(/\.(exe|msi|bat|sh|bin)$/i, "");
          }
          document.getElementById("browse-modal").classList.add("hidden");
        }, fmtSize(e.size)));
      }
    }
    document.getElementById("browse-modal").classList.remove("hidden");
  } catch (err) { toast(err.message, "error"); }
}

function browseRow(label, onClick, size) {
  const d = document.createElement("div");
  d.innerHTML = `<span>${esc(label)}</span>${size ? `<span class="size">${size}</span>` : ""}`;
  d.addEventListener("click", onClick);
  return d;
}

// --- History -----------------------------------------------------------------
async function loadHistory() {
  try {
    const rows = await api("/api/history");
    const body = document.getElementById("history-body");
    body.innerHTML = rows.map((r) => `
      <tr>
        <td>${new Date(r.created_at * 1000).toLocaleString()}</td>
        <td>${esc(r.title || "—")}</td>
        <td>${esc(r.action)}</td>
        <td class="status-${r.status}">${esc(r.status)}</td>
        <td class="muted">${esc(r.detail || "")}</td>
      </tr>`).join("");
  } catch (err) { toast(err.message, "error"); }
}

// --- Settings ----------------------------------------------------------------
const SETTING_FIELDS = [
  ["test_mode", "Test mode (simulate everything — no Bottles needed)", "select", ["true", "false"]],
  ["bottles_cli", "bottles-cli command (or 'auto')", "text"],
  ["default_bottle", "Default bottle name", "text"],
  ["gaming_deps", "Gaming dependencies (comma-separated)", "text"],
  ["installer_root", "Installer browse root (folder)", "text"],
  ["install_root", "Install data root (folder)", "text"],
  ["metadata_provider", "Cover-art provider", "select", ["none", "igdb", "steamgriddb"]],
  ["access_token", "Access token (blank = no login required)", "password"],
];

async function loadSettings() {
  try {
    const s = await api("/api/settings");
    const form = document.getElementById("settings-form");
    form.innerHTML = SETTING_FIELDS.map(([key, label, type, opts]) => {
      if (type === "select") {
        return `<label>${esc(label)}
          <select data-key="${key}">${opts.map((o) => `<option ${s[key] === o ? "selected" : ""}>${o}</option>`).join("")}</select></label>`;
      }
      const val = key === "access_token" ? "" : esc(s[key] || "");
      const ph = key === "access_token" && s[key] === "set" ? "•••••• (set — leave blank to keep)" : "";
      return `<label>${esc(label)}
        <input type="${type}" data-key="${key}" value="${val}" placeholder="${ph}" /></label>`;
    }).join("");
  } catch (err) { toast(err.message, "error"); }
}

document.getElementById("settings-save").addEventListener("click", async () => {
  const body = {};
  document.querySelectorAll("#settings-form [data-key]").forEach((el) => {
    if (el.dataset.key === "access_token" && !el.value) return; // keep existing
    body[el.dataset.key] = el.value;
  });
  try {
    await api("/api/settings", { method: "PUT", body: JSON.stringify(body) });
    toast("Settings saved", "success");
    refreshBottleStatus();
  } catch (err) { toast(err.message, "error"); }
});

document.getElementById("export-btn").addEventListener("click", async () => {
  const data = await api("/api/export");
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "game-library.json";
  a.click();
});

document.getElementById("import-file").addEventListener("change", async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  try {
    const games = JSON.parse(await file.text());
    const r = await api("/api/import", { method: "POST", body: JSON.stringify(games) });
    toast(`Imported ${r.imported} games`, "success");
    loadGames();
  } catch (err) { toast("Import failed: " + err.message, "error"); }
});

// --- Search + filters --------------------------------------------------------
const searchEl = document.getElementById("search");
searchEl.addEventListener("input", () => { renderGrid(); showSuggest(); });
searchEl.addEventListener("blur", () => setTimeout(() => document.getElementById("suggest").classList.add("hidden"), 150));

function showSuggest() {
  const q = searchEl.value.trim().toLowerCase();
  const box = document.getElementById("suggest");
  if (!q) { box.classList.add("hidden"); return; }
  const matches = state.games.filter((g) => g.title.toLowerCase().includes(q)).slice(0, 6);
  if (!matches.length) { box.classList.add("hidden"); return; }
  box.innerHTML = matches.map((g) => `<div data-t="${esc(g.title)}">${esc(g.title)}</div>`).join("");
  box.querySelectorAll("div").forEach((d) => d.addEventListener("mousedown", () => {
    searchEl.value = d.dataset.t; box.classList.add("hidden"); renderGrid();
  }));
  box.classList.remove("hidden");
}

["filter-genre", "filter-year", "filter-state"].forEach((id) =>
  document.getElementById(id).addEventListener("change", renderGrid));
document.getElementById("refresh-btn").addEventListener("click", loadGames);

// --- Bottle status pill ------------------------------------------------------
async function refreshBottleStatus() {
  const pill = document.getElementById("bottle-status");
  try {
    const s = await api("/api/bottles");
    if (s.test_mode) { pill.textContent = "Test mode"; pill.className = "pill test"; }
    else if (s.available) { pill.textContent = `Bottles ✓ (${s.bottles.length})`; pill.className = "pill ok"; }
    else { pill.textContent = "Bottles not found"; pill.className = "pill off"; }
  } catch (_) { pill.textContent = "—"; pill.className = "pill"; }
}

// --- Helpers -----------------------------------------------------------------
function esc(s) { return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }
function fmtSize(b) {
  if (!b) return "";
  const u = ["B", "KB", "MB", "GB", "TB"]; let i = 0; let n = b;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return `${n.toFixed(n < 10 && i > 0 ? 1 : 0)} ${u[i]}`;
}

// --- Boot --------------------------------------------------------------------
async function boot() {
  await loadGames();
  refreshBottleStatus();
}

(async function init() {
  try {
    const st = await fetch("/api/auth-status").then((r) => r.json());
    if (st.auth_required && !state.session) { showLogin(); return; }
    boot();
  } catch (_) { boot(); }
})();
