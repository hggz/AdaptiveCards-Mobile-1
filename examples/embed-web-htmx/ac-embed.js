/**
 * wasm-port: drop-in embed module. Single self-contained ESM file that
 * any existing web app can include. Depends on @bjorn3/browser_wasi_shim
 * via esm.sh CDN so there's no npm step required.
 *
 * Public surface:
 *   loadAdaptiveCards(wasmUrl) -> Promise<AdaptiveCards>
 *     where AdaptiveCards has:
 *       .render(cardJSON: string, mountEl: HTMLElement, options?) -> Context
 *       .versionString() -> string
 *
 * Usage from any HTML page:
 *
 *   <div id="my-card"></div>
 *   <script type="module">
 *     import { loadAdaptiveCards } from "./ac-embed.js";
 *     const ac = await loadAdaptiveCards("./ac.wasm");
 *     await ac.render(myCardJSON, document.getElementById("my-card"), {
 *       onAction: (action) => console.log("ac:action", action),
 *     });
 *   </script>
 *
 * The walker emits the same `ac-*` CSS classes + `data-ac-node`
 * attributes as `examples/embed-web-vanilla/src/walker.js` and the
 * Swift-side `DOMRenderer`. Style via `ac-host.css` (a copy is
 * shipped alongside this file) or your own stylesheet.
 */

import {
  WASI,
  File,
  OpenFile,
  ConsoleStdout,
} from "https://esm.sh/@bjorn3/browser_wasi_shim@0.3.0";

// ---------------------------------------------------------------
//  IR JSON -> DOM walker.
//
//  Mirrors the W2-W7 switch in
//  `ios/Sources/AdaptiveCardsWebUI/DOMRenderer.swift` and the W10
//  vanilla walker. CSS class names + `data-ac-*` attributes are
//  byte-identical so the same stylesheet serves every host.
// ---------------------------------------------------------------

function el(tag, dataAcNode, ctx) {
  const e = ctx.document.createElement(tag);
  e.setAttribute("data-ac-node", dataAcNode);
  return e;
}

function walkChildren(node, parent, ctx, key = "children") {
  for (const c of node[key] ?? []) parent.appendChild(walk(c, ctx));
}

function makeText(n, c) {
  const e = el("div", "text", c);
  const cls = ["ac-text", `ac-text-size-${n.size}`, `ac-text-weight-${n.weight}`];
  if (n.isSubtle) cls.push("ac-text-subtle");
  e.className = cls.join(" ");
  e.textContent = n.string;
  e.style.whiteSpace = n.wrap ? "pre-wrap" : "nowrap";
  return e;
}

function makeRichRun(n, c) {
  const e = el("span", "richRun", c);
  const cls = ["ac-rich-run", `ac-text-size-${n.size}`, `ac-text-weight-${n.weight}`];
  if (n.isSubtle) cls.push("ac-text-subtle");
  e.className = cls.join(" ");
  e.textContent = n.string;
  if (n.italic) e.style.fontStyle = "italic";
  const d = [];
  if (n.underline) d.push("underline");
  if (n.strikethrough) d.push("line-through");
  if (d.length) e.style.textDecoration = d.join(" ");
  return e;
}

function makeImage(n, c) {
  const e = el("img", "image", c);
  e.setAttribute("src", n.url);
  e.setAttribute("alt", n.alt);
  e.className = `ac-image ac-image-${n.displayHint}`;
  return e;
}

function makeStack(n, c, dir) {
  const e = el("div", `${dir}Stack`, c);
  e.className = `ac-stack ac-${dir}-stack ac-spacing-${n.spacing}`;
  e.style.display = "flex";
  e.style.flexDirection = dir === "vertical" ? "column" : "row";
  e.style.gap = `${n.spacing}px`;
  walkChildren(n, e, c);
  return e;
}

function makeFacts(n, c) {
  const e = el("dl", "facts", c);
  e.className = "ac-facts";
  for (const p of n.pairs ?? []) {
    const dt = c.document.createElement("dt");
    dt.className = "ac-fact-title";
    dt.textContent = p.title;
    e.appendChild(dt);
    const dd = c.document.createElement("dd");
    dd.className = "ac-fact-value";
    dd.textContent = p.value;
    e.appendChild(dd);
  }
  return e;
}

function makeCode(n, c) {
  const pre = el("pre", "code", c);
  pre.className = "ac-code";
  pre.style.whiteSpace = n.wrap ? "pre-wrap" : "pre";
  const code = c.document.createElement("code");
  if (n.language) {
    code.className = `language-${n.language}`;
    code.setAttribute("data-ac-language", n.language);
  }
  code.textContent = n.text;
  pre.appendChild(code);
  return pre;
}

function makeProgress(n, c) {
  const row = el("div", "progressBar", c);
  row.className = "ac-progressbar-row";
  if (n.label) {
    const l = c.document.createElement("span");
    l.className = "ac-progressbar-label";
    l.textContent = n.label;
    row.appendChild(l);
  }
  const p = c.document.createElement("progress");
  p.className = "ac-progressbar";
  p.setAttribute("max", "1");
  p.setAttribute("value", String(n.value));
  if (n.label) p.setAttribute("aria-label", n.label);
  row.appendChild(p);
  return row;
}

function makeSpinner(n, c) {
  const e = el("div", "spinner", c);
  e.className = "ac-spinner";
  e.setAttribute("role", "status");
  if (n.label) {
    e.setAttribute("aria-label", n.label);
    const sr = c.document.createElement("span");
    sr.className = "ac-spinner-label";
    sr.textContent = n.label;
    e.appendChild(sr);
  }
  return e;
}

function makeAccordion(n, c) {
  const e = el("div", "accordion", c);
  e.className = "ac-accordion";
  for (const p of n.panels ?? []) {
    const d = c.document.createElement("details");
    d.className = "ac-accordion-panel";
    if (p.isExpanded) d.setAttribute("open", "");
    const s = c.document.createElement("summary");
    s.className = "ac-accordion-summary";
    s.textContent = p.title;
    d.appendChild(s);
    for (const ch of p.content ?? []) d.appendChild(walk(ch, c));
    e.appendChild(d);
  }
  return e;
}

function makeTable(n, c) {
  const e = el("table", "table", c);
  e.className = "ac-table";
  if (n.headers && n.headers.length) {
    const thead = c.document.createElement("thead");
    const tr = c.document.createElement("tr");
    for (const cell of n.headers) {
      const th = c.document.createElement("th");
      th.className = "ac-table-header";
      th.setAttribute("scope", "col");
      for (const ch of cell) th.appendChild(walk(ch, c));
      tr.appendChild(th);
    }
    thead.appendChild(tr);
    e.appendChild(thead);
  }
  const tbody = c.document.createElement("tbody");
  for (const row of n.rows ?? []) {
    const tr = c.document.createElement("tr");
    for (const cell of row) {
      const td = c.document.createElement("td");
      td.className = "ac-table-cell";
      for (const ch of cell) td.appendChild(walk(ch, c));
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
  e.appendChild(tbody);
  return e;
}

function makeRating(n, c) {
  const e = el("div", "rating", c);
  e.className = "ac-rating-display";
  e.setAttribute("role", "img");
  const cs = n.count != null ? `, ${n.count} ratings` : "";
  e.setAttribute("aria-label", `${n.value} of ${n.max}${cs}`);
  e.setAttribute("data-ac-rating-value", String(n.value));
  e.setAttribute("data-ac-rating-max", String(n.max));
  const filled = Math.round(n.value);
  let g = "";
  for (let i = 0; i < n.max; i++) g += i < filled ? "★" : "☆";
  const gs = c.document.createElement("span");
  gs.className = "ac-rating-glyphs";
  gs.textContent = g;
  e.appendChild(gs);
  if (n.count != null) {
    const cnt = c.document.createElement("span");
    cnt.className = "ac-rating-count";
    cnt.textContent = ` (${n.count})`;
    e.appendChild(cnt);
  }
  return e;
}

function row(id, label, dataAcNode, isRequired, inner, c) {
  const r = el("div", dataAcNode, c);
  r.className = `ac-input-row ac-input-${dataAcNode}`;
  r.setAttribute("data-ac-input-id", id);
  if (isRequired) r.setAttribute("data-ac-required", "true");
  if (label) {
    const l = c.document.createElement("label");
    l.className = "ac-input-label";
    l.textContent = label;
    l.setAttribute("for", `ac-input-${id}`);
    r.appendChild(l);
  }
  r.appendChild(inner);
  return r;
}

function makeText_(n, c) {
  let i;
  if (n.isMultiline) {
    i = c.document.createElement("textarea");
    i.textContent = n.value ?? "";
  } else {
    i = c.document.createElement("input");
    i.setAttribute("type", "text");
    if (n.value != null) i.setAttribute("value", n.value);
  }
  i.setAttribute("id", `ac-input-${n.id}`);
  i.setAttribute("name", n.id);
  if (n.placeholder) i.setAttribute("placeholder", n.placeholder);
  if (n.isRequired) i.setAttribute("required", "");
  i.className = "ac-input ac-input-text";
  c.registeredInputs.push({ id: n.id, read: () => i.value });
  return row(n.id, n.label, "textField", n.isRequired, i, c);
}

function makeNumber(n, c) {
  const i = c.document.createElement("input");
  i.setAttribute("type", "number");
  i.setAttribute("id", `ac-input-${n.id}`);
  i.setAttribute("name", n.id);
  if (n.value != null) i.setAttribute("value", String(n.value));
  if (n.placeholder) i.setAttribute("placeholder", n.placeholder);
  if (n.isRequired) i.setAttribute("required", "");
  i.className = "ac-input ac-input-number";
  c.registeredInputs.push({
    id: n.id,
    read: () => (i.value === "" ? null : Number(i.value)),
  });
  return row(n.id, n.label, "numberField", n.isRequired, i, c);
}

function makeToggle(n, c) {
  const i = c.document.createElement("input");
  i.setAttribute("type", "checkbox");
  i.setAttribute("id", `ac-input-${n.id}`);
  i.setAttribute("name", n.id);
  if (n.value) i.setAttribute("checked", "");
  if (n.isRequired) i.setAttribute("required", "");
  i.className = "ac-input ac-input-toggle";
  i.setAttribute("data-ac-value-on", n.valueOn);
  i.setAttribute("data-ac-value-off", n.valueOff);
  c.registeredInputs.push({
    id: n.id,
    read: () => (i.checked ? n.valueOn : n.valueOff),
  });
  const inline = c.document.createElement("span");
  inline.className = "ac-input-toggle-title";
  inline.textContent = n.title;
  const wrap = c.document.createElement("span");
  wrap.className = "ac-input-toggle-row";
  wrap.appendChild(i);
  wrap.appendChild(inline);
  return row(n.id, n.label, "toggleField", n.isRequired, wrap, c);
}

function makeChoice(n, c) {
  const s = c.document.createElement("select");
  s.setAttribute("id", `ac-input-${n.id}`);
  s.setAttribute("name", n.id);
  if (n.isMultiSelect) s.setAttribute("multiple", "");
  if (n.isRequired) s.setAttribute("required", "");
  s.className = "ac-input ac-input-choice";
  let sel;
  if (n.isMultiSelect) {
    sel = new Set(String(n.selected ?? "").split(",").map((x) => x.trim()).filter(Boolean));
  } else if (n.selected != null) {
    sel = new Set([n.selected]);
  } else {
    sel = new Set();
  }
  for (const ch of n.choices ?? []) {
    const o = c.document.createElement("option");
    o.setAttribute("value", ch.value);
    o.textContent = ch.title;
    if (sel.has(ch.value)) o.setAttribute("selected", "");
    s.appendChild(o);
  }
  c.registeredInputs.push({
    id: n.id,
    read: () =>
      n.isMultiSelect
        ? Array.from(s.selectedOptions).map((o) => o.value)
        : s.value,
  });
  return row(n.id, n.label, "choiceField", n.isRequired, s, c);
}

function makeDateOrTime(n, c, type, dataAcNode) {
  const i = c.document.createElement("input");
  i.setAttribute("type", type);
  i.setAttribute("id", `ac-input-${n.id}`);
  i.setAttribute("name", n.id);
  if (n.value != null) i.setAttribute("value", n.value);
  if (n.placeholder) i.setAttribute("placeholder", n.placeholder);
  if (n.isRequired) i.setAttribute("required", "");
  i.className = `ac-input ac-input-${type}`;
  c.registeredInputs.push({ id: n.id, read: () => i.value });
  return row(n.id, n.label, dataAcNode, n.isRequired, i, c);
}

function makeRatingField(n, c) {
  const i = c.document.createElement("input");
  i.setAttribute("type", "range");
  i.setAttribute("id", `ac-input-${n.id}`);
  i.setAttribute("name", n.id);
  i.setAttribute("min", "0");
  i.setAttribute("max", String(n.max));
  i.setAttribute("step", "1");
  i.setAttribute("value", String(Math.round(n.value)));
  if (n.isRequired) i.setAttribute("required", "");
  i.className = "ac-input ac-input-rating";
  c.registeredInputs.push({
    id: n.id,
    read: () => (i.value === "" ? null : Number(i.value)),
  });
  return row(n.id, n.label, "ratingField", n.isRequired, i, c);
}

function makeChart(n, c) {
  const e = el("figure", "chart", c);
  e.className = `ac-chart ac-chart-${n.kind}`;
  e.setAttribute("data-ac-chart-kind", n.kind);
  e.setAttribute("data-ac-show-legend", n.showLegend ? "true" : "false");
  if (n.title) {
    const cap = c.document.createElement("figcaption");
    cap.className = "ac-chart-title";
    cap.textContent = n.title;
    e.appendChild(cap);
  }
  const t = c.document.createElement("table");
  t.className = "ac-chart-table";
  const tb = c.document.createElement("tbody");
  for (const d of n.data ?? []) {
    const tr = c.document.createElement("tr");
    tr.className = "ac-chart-datum";
    if (d.color) {
      const sw = c.document.createElement("td");
      sw.className = "ac-chart-swatch";
      sw.setAttribute("data-ac-chart-color", d.color);
      sw.style.backgroundColor = d.color;
      tr.appendChild(sw);
    }
    const lc = c.document.createElement("td");
    lc.className = "ac-chart-label";
    lc.textContent = d.label;
    tr.appendChild(lc);
    const vc = c.document.createElement("td");
    vc.className = "ac-chart-value";
    vc.textContent = String(d.value);
    tr.appendChild(vc);
    tb.appendChild(tr);
  }
  t.appendChild(tb);
  e.appendChild(t);
  return e;
}

function makeTabSet(n, c) {
  const e = el("div", "tabSet", c);
  e.className = "ac-tabset";
  e.setAttribute("data-ac-selected-tab-index", String(n.selectedTabIndex));
  const tabs = n.tabs ?? [];
  const cl = n.selectedTabIndex >= 0 && n.selectedTabIndex < tabs.length ? n.selectedTabIndex : 0;
  const tablist = c.document.createElement("div");
  tablist.className = "ac-tabset-tablist";
  tablist.setAttribute("role", "tablist");
  tabs.forEach((t, idx) => {
    const b = c.document.createElement("button");
    b.className = "ac-tabset-tab" + (idx === cl ? " ac-tabset-tab-selected" : "");
    b.setAttribute("type", "button");
    b.setAttribute("role", "tab");
    b.setAttribute("data-ac-tab-id", t.id);
    b.setAttribute("data-ac-tab-index", String(idx));
    b.setAttribute("aria-selected", idx === cl ? "true" : "false");
    b.setAttribute("tabindex", idx === cl ? "0" : "-1");
    b.textContent = t.title;
    tablist.appendChild(b);
  });
  e.appendChild(tablist);
  if (tabs[cl]) {
    const p = c.document.createElement("div");
    p.className = "ac-tabset-panel";
    p.setAttribute("role", "tabpanel");
    p.setAttribute("data-ac-tab-id", tabs[cl].id);
    for (const ch of tabs[cl].content ?? []) p.appendChild(walk(ch, c));
    e.appendChild(p);
  }
  return e;
}

function actionTag(a) {
  return a?.kind ?? "unknown";
}

function attachClick(e, action, c) {
  e.addEventListener("click", () => {
    if (action.kind === "submit") {
      const merged = buildSubmit(action.dataJSON, c);
      c.onAction?.({ kind: "submit", dataJSON: merged });
    } else {
      c.onAction?.(action);
    }
  });
}

function buildSubmit(originalJSON, c) {
  let base = {};
  if (originalJSON) {
    try {
      const p = JSON.parse(originalJSON);
      if (p && typeof p === "object" && !Array.isArray(p)) base = p;
    } catch {
      // ignore
    }
  }
  for (const entry of c.registeredInputs) {
    const v = entry.read();
    if (v != null) base[entry.id] = v;
  }
  const sorted = {};
  for (const k of Object.keys(base).sort()) sorted[k] = base[k];
  return JSON.stringify(sorted);
}

function makeCompound(n, c) {
  const e = el("button", "compoundButton", c);
  e.className = "ac-compound-button";
  e.setAttribute("type", "button");
  const tag = actionTag(n.action);
  if (n.action) e.setAttribute("data-ac-action-kind", tag);
  if (n.icon) {
    const img = c.document.createElement("img");
    img.className = "ac-compound-button-icon";
    img.setAttribute("src", n.icon);
    img.setAttribute("alt", "");
    e.appendChild(img);
  }
  const st = c.document.createElement("span");
  st.className = "ac-compound-button-text";
  const t = c.document.createElement("span");
  t.className = "ac-compound-button-title";
  t.textContent = n.title;
  st.appendChild(t);
  if (n.subtitle) {
    const s = c.document.createElement("span");
    s.className = "ac-compound-button-subtitle";
    s.textContent = n.subtitle;
    st.appendChild(s);
  }
  e.appendChild(st);
  if (n.action) attachClick(e, n.action, c);
  return e;
}

function makeButton(n, c) {
  const tag = actionTag(n.kind);
  const e = el("button", "button", c);
  e.className = `ac-button ac-action-${tag}`;
  e.setAttribute("type", "button");
  e.setAttribute("data-ac-action-kind", tag);
  e.textContent = n.title;
  attachClick(e, n.kind, c);
  return e;
}

function makeCarousel(n, c) {
  const e = el("section", "carousel", c);
  e.className = "ac-carousel";
  e.setAttribute("aria-roledescription", "carousel");
  e.setAttribute("data-ac-selected-page-index", String(n.selectedPageIndex));
  if (n.autoAdvanceMs != null) e.setAttribute("data-ac-auto-advance-ms", String(n.autoAdvanceMs));
  const pages = n.pages ?? [];
  const cl = n.selectedPageIndex >= 0 && n.selectedPageIndex < pages.length ? n.selectedPageIndex : 0;
  const dots = c.document.createElement("div");
  dots.className = "ac-carousel-dots";
  dots.setAttribute("role", "tablist");
  pages.forEach((p, idx) => {
    const d = c.document.createElement("span");
    d.className = "ac-carousel-dot" + (idx === cl ? " ac-carousel-dot-selected" : "");
    d.setAttribute("role", "tab");
    d.setAttribute("data-ac-page-id", p.id);
    d.setAttribute("data-ac-page-index", String(idx));
    d.setAttribute("aria-selected", idx === cl ? "true" : "false");
    d.setAttribute("aria-label", `Page ${idx + 1} of ${pages.length}`);
    dots.appendChild(d);
  });
  e.appendChild(dots);
  if (n.autoAdvanceMs != null) {
    const ps = c.document.createElement("button");
    ps.className = "ac-carousel-pause";
    ps.setAttribute("type", "button");
    ps.setAttribute("aria-label", "Pause auto-advancing carousel (WCAG SC 2.2.2)");
    ps.setAttribute("data-ac-carousel-pause", "true");
    ps.textContent = "⏸";
    e.appendChild(ps);
  }
  if (pages[cl]) {
    const p = c.document.createElement("div");
    p.className = "ac-carousel-page";
    p.setAttribute("role", "tabpanel");
    p.setAttribute("data-ac-page-id", pages[cl].id);
    if (pages[cl].selectAction) {
      p.setAttribute("data-ac-select-action-kind", actionTag(pages[cl].selectAction));
    }
    for (const ch of pages[cl].content ?? []) p.appendChild(walk(ch, c));
    e.appendChild(p);
  }
  return e;
}

function makeList(n, c) {
  const tag = n.style === "bulleted" ? "ul" : n.style === "numbered" ? "ol" : "div";
  const e = el(tag, "list", c);
  e.className = `ac-list ac-list-${n.style}`;
  e.setAttribute("data-ac-list-style", n.style);
  const marker = n.style !== "default";
  for (const it of n.items ?? []) {
    if (!marker) {
      e.appendChild(walk(it, c));
    } else {
      const li = c.document.createElement("li");
      li.className = "ac-list-item";
      li.appendChild(walk(it, c));
      e.appendChild(li);
    }
  }
  return e;
}

function makeMedia(n, c) {
  const e = el("figure", "media", c);
  e.className = "ac-media";
  const ss = n.sources ?? [];
  const vs = ss.filter((s) => s.mimeType?.startsWith("video/"));
  const as = ss.filter((s) => s.mimeType?.startsWith("audio/"));
  if (vs.length) {
    const v = c.document.createElement("video");
    v.className = "ac-media-video";
    v.setAttribute("controls", "");
    if (n.posterURL) v.setAttribute("poster", n.posterURL);
    if (n.altText) v.setAttribute("aria-label", n.altText);
    for (const s of vs) {
      const so = c.document.createElement("source");
      so.setAttribute("src", s.url);
      so.setAttribute("type", s.mimeType);
      v.appendChild(so);
    }
    e.appendChild(v);
  } else if (as.length) {
    const a = c.document.createElement("audio");
    a.className = "ac-media-audio";
    a.setAttribute("controls", "");
    if (n.altText) a.setAttribute("aria-label", n.altText);
    for (const s of as) {
      const so = c.document.createElement("source");
      so.setAttribute("src", s.url);
      so.setAttribute("type", s.mimeType);
      a.appendChild(so);
    }
    e.appendChild(a);
  } else {
    if (n.posterURL) {
      const p = c.document.createElement("img");
      p.className = "ac-media-poster";
      p.setAttribute("src", n.posterURL);
      p.setAttribute("alt", n.altText ?? "");
      e.appendChild(p);
    }
    for (const s of ss) {
      const r = c.document.createElement("div");
      r.className = "ac-media-source";
      r.setAttribute("data-ac-mime", s.mimeType);
      r.textContent = `${s.mimeType}: ${s.url}`;
      e.appendChild(r);
    }
  }
  if (n.altText) {
    const cap = c.document.createElement("figcaption");
    cap.className = "ac-media-caption";
    cap.textContent = n.altText;
    e.appendChild(cap);
  }
  return e;
}

function makeUnsupported(n, c) {
  const e = el("div", "unsupported", c);
  e.className = "ac-unsupported";
  e.setAttribute("data-ac-unsupported-case", n.typeString ?? n.type);
  e.textContent = "[unsupported node]";
  return e;
}

function walk(n, c) {
  switch (n.type) {
    case "text":            return makeText(n, c);
    case "richRun":         return makeRichRun(n, c);
    case "image":           return makeImage(n, c);
    case "verticalStack":   return makeStack(n, c, "vertical");
    case "horizontalStack": return makeStack(n, c, "horizontal");
    case "facts":           return makeFacts(n, c);
    case "code":            return makeCode(n, c);
    case "textField":       return makeText_(n, c);
    case "numberField":     return makeNumber(n, c);
    case "toggleField":     return makeToggle(n, c);
    case "choiceField":     return makeChoice(n, c);
    case "progressBar":     return makeProgress(n, c);
    case "spinner":         return makeSpinner(n, c);
    case "accordion":       return makeAccordion(n, c);
    case "table":           return makeTable(n, c);
    case "rating":          return makeRating(n, c);
    case "dateField":       return makeDateOrTime(n, c, "date", "dateField");
    case "timeField":       return makeDateOrTime(n, c, "time", "timeField");
    case "ratingField":     return makeRatingField(n, c);
    case "chart":           return makeChart(n, c);
    case "tabSet":          return makeTabSet(n, c);
    case "carousel":        return makeCarousel(n, c);
    case "list":            return makeList(n, c);
    case "media":           return makeMedia(n, c);
    case "compoundButton":  return makeCompound(n, c);
    case "button":          return makeButton(n, c);
    default:                return makeUnsupported(n, c);
  }
}

// ---------------------------------------------------------------
//  WASM loader + public API.
// ---------------------------------------------------------------

const defaultDispatcher = (action) => {
  if (action.kind === "openUrl") {
    window.open(action.openUrl ?? action.value ?? "", "_blank");
  } else if (action.kind === "submit") {
    console.warn("ac:submit", action.dataJSON ?? "<no-payload>");
  } else {
    console.warn("ac:action-unsupported", action.kind);
  }
};

async function makeInstance(wasmUrl) {
  const wasi = new WASI(
    [], [],
    [
      new OpenFile(new File([])),
      ConsoleStdout.lineBuffered((m) => console.log("[ac-wasm:stdout]", m)),
      ConsoleStdout.lineBuffered((m) => console.warn("[ac-wasm:stderr]", m)),
    ]
  );
  const { instance } = await WebAssembly.instantiateStreaming(
    fetch(wasmUrl),
    { wasi_snapshot_preview1: wasi.wasiImport }
  );
  wasi.start({ exports: instance.exports });
  return instance;
}

function readCString(inst, ptr) {
  if (!ptr) return null;
  const mem = new Uint8Array(inst.exports.memory.buffer);
  let end = ptr;
  while (mem[end] !== 0) end++;
  return new TextDecoder().decode(mem.subarray(ptr, end));
}

function writeCString(inst, s) {
  const bytes = new TextEncoder().encode(s);
  const ptr = inst.exports.ac_alloc(bytes.length + 1);
  if (!ptr) throw new Error("ac_alloc failed");
  const mem = new Uint8Array(inst.exports.memory.buffer);
  mem.set(bytes, ptr);
  mem[ptr + bytes.length] = 0;
  return ptr;
}

/**
 * Public entry point. Returns an object bound to the loaded WASM
 * instance; multiple `render(...)` calls reuse the same module.
 */
export async function loadAdaptiveCards(wasmUrl) {
  const inst = await makeInstance(wasmUrl);

  function renderIR(cardJSON) {
    const inPtr = writeCString(inst, cardJSON);
    try {
      const outPtr = inst.exports.ac_host_render_json(inPtr);
      if (!outPtr) {
        const errPtr = inst.exports.ac_last_error();
        throw new Error(readCString(inst, errPtr) ?? "ac_host_render_json failed");
      }
      try {
        return JSON.parse(readCString(inst, outPtr));
      } finally {
        inst.exports.ac_free(outPtr);
      }
    } finally {
      inst.exports.ac_free(inPtr);
    }
  }

  return {
    versionString() {
      return readCString(inst, inst.exports.ac_version()) ?? "unknown";
    },
    /**
     * Render `cardJSON` into `mountEl`, returning a Context object
     * with the registered-input map (so hosts that want to read live
     * input values without a submit click can do so directly).
     */
    render(cardJSON, mountEl, options = {}) {
      const ir = renderIR(cardJSON);
      mountEl.replaceChildren();
      const ctx = {
        document: mountEl.ownerDocument ?? document,
        registeredInputs: [],
        onAction: options.onAction ?? defaultDispatcher,
      };
      mountEl.appendChild(walk(ir, ctx));
      return ctx;
    },
  };
}
