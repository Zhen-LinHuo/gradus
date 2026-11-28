/* Gradus web app — vanilla client shell.
   Talks to the Guile core API (docs/webui.md). Until the endpoints land,
   it renders against a local demo contract so the frame can be styled and
   reviewed in a browser with zero backend. */

"use strict";

/* ── core contract (docs/webui.md §Endpoints) ────────────────────── */
const API = {
  wizard:   "/api/wizard",
  next:     "/api/wizard/next",
  back:     "/api/wizard/back",
  values:   "/api/wizard/values",
  begin:    "/api/install/begin",
  review:   "/api/review",
  run:      "/api/install/run",
  progress: "/api/progress",
};

const DEMO = !location.origin.startsWith("http"); // file:// preview mode

/* ── demo contract: same shapes the Guile core emits ─────────────── */
const DEMO_STEPS = [
  { id: "language", title: "Language", kind: "choice",
    options: ["English", "Español", "Français", "Deutsch", "日本語",
              "简体中文", "繁體中文", "Português", "Italiano", "Svenska"] },
  { id: "locale", title: "Localisation", kind: "form",
    fields: [
      { key: "keyboard", label: "Keyboard layout", kind: "choice", value: "us",
        options: ["us", "gb", "de", "fr", "es", "it", "se", "dvorak"] },
      { key: "timezone", label: "Timezone", kind: "choice", value: "UTC",
        options: ["UTC", "Europe/London", "Europe/Berlin", "Europe/Paris",
                  "Asia/Shanghai", "Asia/Tokyo", "America/New_York", "Asia/Kolkata"] },
      { key: "locale", label: "Locale", kind: "choice", value: "en_US.utf8",
        options: ["en_US.utf8", "en_GB.utf8", "de_DE.utf8", "fr_FR.utf8",
                  "zh_CN.utf8", "ja_JP.utf8"] },
      { key: "ntp", label: "NTP time sync", kind: "choice", value: "yes",
        options: ["yes", "no"] },
    ] },
  { id: "storage", title: "Storage", kind: "storage" },
  { id: "source", title: "Install source", kind: "form",
    fields: [
      { key: "substitutes", label: "Substitute servers (tried in order)",
        kind: "list", value: ["https://mirror.sjtu.edu.cn/guix", "https://ci.guix.gnu.org"] },
      { key: "proxy", label: "HTTP proxy (empty = none)", kind: "text", value: "" },
    ] },
  { id: "software", title: "Software", kind: "checks",
    groups: {
      "console": ["mg", "neovim", "tmux"],
      "enhanced_base": ["man-pages", "texinfo", "git", "make", "wget"],
      "network_admin": ["whois", "wireshark-cli"],
    } },
  { id: "boot", title: "Boot", kind: "form",
    fields: [
      { key: "bootloader", label: "Boot loader", kind: "choice", value: "auto",
        options: ["auto", "grub-bios", "grub-efi"] },
      { key: "serial", label: "Serial console", kind: "choice", value: "no",
        options: ["no", "ttyS0"] },
    ] },
  { id: "network", title: "Network", kind: "form",
    fields: [
      { key: "hostname", label: "Host name", kind: "text", value: "gradus" },
      { key: "address", label: "Address", kind: "choice", value: "dhcp",
        options: ["dhcp", "static"] },
    ] },
  { id: "users", title: "Users", kind: "users" },
  { id: "review", title: "Review", kind: "review" },
  { id: "install", title: "Install", kind: "install" },
];

/* ── state ────────────────────────────────────────────────────────── */
let steps = DEMO_STEPS;
let current = 0;
const answers = {};

/* ── api (demo mode short-circuits to the local contract) ────────── */
async function api(path, body) {
  if (DEMO) return { ok: true };
  const res = await fetch(path, {
    method: body ? "POST" : "GET",
    headers: { "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`${path}: ${res.status}`);
  return res.json();
}

/* ── rail ─────────────────────────────────────────────────────────── */
function renderRail() {
  const rail = document.getElementById("rail");
  rail.innerHTML = "";
  steps.forEach((s, i) => {
    const el = document.createElement("span");
    el.className = "step";
    el.dataset.state = i < current ? "done" : i === current ? "current" : "todo";
    el.textContent = s.title;
    rail.appendChild(el);
  });
}

/* ── field renderers ─────────────────────────────────────────────── */
function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") node.className = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of children) node.appendChild(c);
  return node;
}

function choiceField(stepId, key, label, value, options) {
  const wrap = el("div", { class: "field" });
  wrap.appendChild(el("label", { for: `f-${key}` }, label));
  const filter = el("input", {
    id: `f-${key}-filter`, class: "filter", type: "text",
    placeholder: "Type to filter…", "aria-label": `Filter ${label}`,
  });
  const select = el("select", { id: `f-${key}`, size: Math.min(10, options.length) });
  const fill = (needle = "") =>
    options.filter(o => o.toLowerCase().includes(needle.toLowerCase())).forEach(o => {
      const opt = el("option", { value: o }, o);
      if (o === value) opt.selected = true;
      select.appendChild(opt);
    });
  fill();
  filter.addEventListener("input", () => { select.innerHTML = ""; fill(filter.value); });
  select.addEventListener("change", () => { answers[key] = select.value; });
  answers[key] = answers[key] ?? value;
  wrap.appendChild(filter);
  wrap.appendChild(select);
  return wrap;
}

function textField(stepId, key, label, value, secret) {
  const wrap = el("div", { class: "field" });
  wrap.appendChild(el("label", { for: `f-${key}` }, label));
  const input = el("input", {
    id: `f-${key}`, type: secret ? "password" : "text", value: value ?? "",
  });
  input.addEventListener("change", () => { answers[key] = input.value; });
  wrap.appendChild(input);
  return wrap;
}

function listField(stepId, key, label, values) {
  const wrap = el("div", { class: "field" });
  wrap.appendChild(el("label", {}, label));
  const box = el("div", { class: "checks" });
  (values ?? []).forEach((v, i) => {
    const row = el("label", {});
    const cb = el("input", { type: "checkbox", checked: "checked" });
    cb.addEventListener("change", () => {
      answers[key] = answers[key].filter((_, j) => j !== i);
    });
    row.appendChild(cb); row.appendChild(el("span", {}, v));
    box.appendChild(row);
  });
  wrap.appendChild(box);
  return wrap;
}

function checksField(stepId, groups) {
  const wrap = el("div", { class: "field" });
  for (const [group, pkgs] of Object.entries(groups)) {
    wrap.appendChild(el("h2", {}, group));
    const box = el("div", { class: "checks" });
    pkgs.forEach(p => {
      const row = el("label", {});
      const cb = el("input", { type: "checkbox" });
      cb.addEventListener("change", () => {
        answers[group] = answers[group] ?? [];
        cb.checked ? answers[group].push(p)
                   : answers[group] = answers[group].filter(x => x !== p);
      });
      row.appendChild(cb); row.appendChild(el("span", {}, p));
      box.appendChild(row);
    });
    wrap.appendChild(box);
  }
  return wrap;
}

/* storage step: multi-disk aware (TUI gap #2) */
function storageField(step) {
  const wrap = el("div", { class: "field" });
  wrap.appendChild(el("h2", {}, "Disks"));
  const box = el("div", { class: "checks" });
  (step.disks ?? [
    { path: "/dev/vda", size: "20 GB", role: "system", fs: "ext4",
      esp: 1024, swap: 2048, root: 0, encrypt: false },
  ]).forEach((d, i) => {
    const row = el("details", { open: i === 0 });
    row.appendChild(el("summary", {}, `${d.path} (${d.size}) — ${d.role}`));
    const inner = el("div", { class: "checks" });
    inner.appendChild(textField(step.id, `disk-${i}-esp`, "ESP size (MiB, 0 = skip)", d.esp));
    inner.appendChild(textField(step.id, `disk-${i}-swap`, "Swap size (MiB, 0 = none)", d.swap));
    inner.appendChild(textField(step.id, `disk-${i}-root`, "Root size (MiB, 0 = rest)", d.root));
    inner.appendChild(choiceField(step.id, `disk-${i}-fs`, "Filesystem", d.fs,
                                  ["ext4", "btrfs", "xfs"]));
    inner.appendChild(choiceField(step.id, `disk-${i}-enc`, "Encrypt root (LUKS1)",
                                  d.encrypt ? "yes" : "no", ["no", "yes"]));
    row.appendChild(inner);
    box.appendChild(row);
  });
  wrap.appendChild(box);
  wrap.appendChild(el("p", { class: "hint" },
    "Data disks are adopted, never formatted. Every value is editable; 0 = rest of disk."));
  return wrap;
}

/* ── step renderers ───────────────────────────────────────────────── */
function renderStep() {
  const view = document.getElementById("view");
  view.innerHTML = "";
  const step = steps[current];
  renderRail();
  view.appendChild(el("h1", {}, step.title));

  if (step.kind === "choice") {
    view.appendChild(choiceField(step.id, step.id, step.title,
                                 step.options[0], step.options));
  } else if (step.kind === "form") {
    step.fields.forEach(f => {
      if (f.kind === "choice") view.appendChild(choiceField(step.id, f.key, f.label, f.value, f.options));
      else if (f.kind === "list") view.appendChild(listField(step.id, f.key, f.label, f.value));
      else view.appendChild(textField(step.id, f.key, f.label, f.value, /pass|secret/i.test(f.key)));
    });
  } else if (step.kind === "checks") {
    view.appendChild(checksField(step.id, step.groups));
  } else if (step.kind === "storage") {
    view.appendChild(storageField(step));
  } else if (step.kind === "users") {
    view.appendChild(textField(step.id, "user", "User name", "user"));
    view.appendChild(textField(step.id, "user-pass", "User password", "", true));
    view.appendChild(textField(step.id, "root-pass", "Root password", "", true));
  } else if (step.kind === "review") {
    const pre = el("pre", { class: "log" });
    pre.textContent = JSON.stringify(answers, null, 2);
    view.appendChild(el("p", { class: "hint" },
      "The full declaration review (inspect, hand-edit, re-sync) uses the core review state machine."));
    view.appendChild(pre);
  } else if (step.kind === "install") {
    view.appendChild(el("p", { class: "hint" },
      "Gate 1 (erase) and gate 2 (install) confirmations render here; progress streams from /api/progress."));
    const pre = el("pre", { class: "log" });
    pre.textContent = "==> waiting to begin\n";
    view.appendChild(pre);
  }
}

/* ── nav ──────────────────────────────────────────────────────────── */
async function advance(delta) {
  const step = steps[current];
  if (delta > 0) {
    try { await api(API.values, { step: step.id, answers }); }
    catch (e) { alert(e.message); return; }
  }
  current = Math.max(0, Math.min(steps.length - 1, current + delta));
  renderStep();
}

/* ── theme & style pickers ────────────────────────────────────────── */
document.getElementById("style-picker").addEventListener("change", e => {
  document.getElementById("style-link").href = `tokens/${e.target.value}.css`;
});
document.getElementById("theme-picker").addEventListener("change", e => {
  document.documentElement.setAttribute("data-theme", e.target.value);
});

document.getElementById("btn-back").addEventListener("click", () => advance(-1));
document.getElementById("btn-continue").addEventListener("click", () => advance(1));

renderStep();
