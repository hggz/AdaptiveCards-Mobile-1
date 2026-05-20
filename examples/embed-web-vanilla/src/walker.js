/**
 * wasm-port: IR JSON -> DOM walker.
 *
 * Mirrors the W2-W7 switch in `ios/Sources/AdaptiveCardsWebUI/DOMRenderer.swift`.
 * CSS class names + `data-ac-*` attributes are byte-identical so a
 * single stylesheet can serve both paths.
 *
 * Inputs:
 *   - `node` is a `RenderingNode` JSON object as emitted by
 *     `ac_host_render_json`. Discriminator: `node.type`.
 *   - `ctx` is the per-walk context, providing the `document` to
 *     create elements against plus a `registeredInputs` array for
 *     submit-payload collection.
 *
 * Output: a DOM Element. Caller appends.
 */

function makeElement(tag, dataAcNode, ctx) {
  const el = ctx.document.createElement(tag);
  el.setAttribute("data-ac-node", dataAcNode);
  return el;
}

function walkChildren(node, parent, ctx, key = "children") {
  for (const child of node[key] ?? []) {
    parent.appendChild(walk(child, ctx));
  }
}

function makeTextElement(node, ctx) {
  const el = makeElement("div", "text", ctx);
  const classes = [
    "ac-text",
    `ac-text-size-${node.size}`,
    `ac-text-weight-${node.weight}`,
  ];
  if (node.isSubtle) classes.push("ac-text-subtle");
  el.className = classes.join(" ");
  el.textContent = node.string;
  el.style.whiteSpace = node.wrap ? "pre-wrap" : "nowrap";
  return el;
}

function makeRichRunElement(node, ctx) {
  const el = makeElement("span", "richRun", ctx);
  const classes = [
    "ac-rich-run",
    `ac-text-size-${node.size}`,
    `ac-text-weight-${node.weight}`,
  ];
  if (node.isSubtle) classes.push("ac-text-subtle");
  el.className = classes.join(" ");
  el.textContent = node.string;
  if (node.italic) el.style.fontStyle = "italic";
  const deco = [];
  if (node.underline) deco.push("underline");
  if (node.strikethrough) deco.push("line-through");
  if (deco.length) el.style.textDecoration = deco.join(" ");
  return el;
}

function makeImageElement(node, ctx) {
  const el = makeElement("img", "image", ctx);
  el.setAttribute("src", node.url);
  el.setAttribute("alt", node.alt);
  el.className = `ac-image ac-image-${node.displayHint}`;
  return el;
}

function makeStackElement(node, ctx, direction) {
  const el = makeElement("div", `${direction}Stack`, ctx);
  el.className = `ac-stack ac-${direction}-stack ac-spacing-${node.spacing}`;
  el.style.display = "flex";
  el.style.flexDirection = direction === "vertical" ? "column" : "row";
  el.style.gap = `${node.spacing}px`;
  walkChildren(node, el, ctx);
  return el;
}

function makeFactsElement(node, ctx) {
  const el = makeElement("dl", "facts", ctx);
  el.className = "ac-facts";
  for (const pair of node.pairs ?? []) {
    const dt = ctx.document.createElement("dt");
    dt.className = "ac-fact-title";
    dt.textContent = pair.title;
    el.appendChild(dt);
    const dd = ctx.document.createElement("dd");
    dd.className = "ac-fact-value";
    dd.textContent = pair.value;
    el.appendChild(dd);
  }
  return el;
}

function makeCodeElement(node, ctx) {
  const pre = makeElement("pre", "code", ctx);
  pre.className = "ac-code";
  pre.style.whiteSpace = node.wrap ? "pre-wrap" : "pre";
  const code = ctx.document.createElement("code");
  if (node.language) {
    code.className = `language-${node.language}`;
    code.setAttribute("data-ac-language", node.language);
  }
  code.textContent = node.text;
  pre.appendChild(code);
  return pre;
}

function makeProgressBarElement(node, ctx) {
  const row = makeElement("div", "progressBar", ctx);
  row.className = "ac-progressbar-row";
  if (node.label) {
    const labelEl = ctx.document.createElement("span");
    labelEl.className = "ac-progressbar-label";
    labelEl.textContent = node.label;
    row.appendChild(labelEl);
  }
  const progress = ctx.document.createElement("progress");
  progress.className = "ac-progressbar";
  progress.setAttribute("max", "1");
  progress.setAttribute("value", String(node.value));
  if (node.label) progress.setAttribute("aria-label", node.label);
  row.appendChild(progress);
  return row;
}

function makeSpinnerElement(node, ctx) {
  const el = makeElement("div", "spinner", ctx);
  el.className = "ac-spinner";
  el.setAttribute("role", "status");
  if (node.label) {
    el.setAttribute("aria-label", node.label);
    const sr = ctx.document.createElement("span");
    sr.className = "ac-spinner-label";
    sr.textContent = node.label;
    el.appendChild(sr);
  }
  return el;
}

function makeAccordionElement(node, ctx) {
  const el = makeElement("div", "accordion", ctx);
  el.className = "ac-accordion";
  for (const panel of node.panels ?? []) {
    const details = ctx.document.createElement("details");
    details.className = "ac-accordion-panel";
    if (panel.isExpanded) details.setAttribute("open", "");
    const summary = ctx.document.createElement("summary");
    summary.className = "ac-accordion-summary";
    summary.textContent = panel.title;
    details.appendChild(summary);
    for (const child of panel.content ?? []) {
      details.appendChild(walk(child, ctx));
    }
    el.appendChild(details);
  }
  return el;
}

function makeTableElement(node, ctx) {
  const el = makeElement("table", "table", ctx);
  el.className = "ac-table";
  if (node.headers && node.headers.length) {
    const thead = ctx.document.createElement("thead");
    const tr = ctx.document.createElement("tr");
    for (const cell of node.headers) {
      const th = ctx.document.createElement("th");
      th.className = "ac-table-header";
      th.setAttribute("scope", "col");
      for (const child of cell) th.appendChild(walk(child, ctx));
      tr.appendChild(th);
    }
    thead.appendChild(tr);
    el.appendChild(thead);
  }
  const tbody = ctx.document.createElement("tbody");
  for (const row of node.rows ?? []) {
    const tr = ctx.document.createElement("tr");
    for (const cell of row) {
      const td = ctx.document.createElement("td");
      td.className = "ac-table-cell";
      for (const child of cell) td.appendChild(walk(child, ctx));
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
  el.appendChild(tbody);
  return el;
}

function makeRatingDisplayElement(node, ctx) {
  const el = makeElement("div", "rating", ctx);
  el.className = "ac-rating-display";
  el.setAttribute("role", "img");
  const countSuffix = node.count != null ? `, ${node.count} ratings` : "";
  el.setAttribute("aria-label", `${node.value} of ${node.max}${countSuffix}`);
  el.setAttribute("data-ac-rating-value", String(node.value));
  el.setAttribute("data-ac-rating-max", String(node.max));
  const filled = Math.round(node.value);
  let glyphs = "";
  for (let i = 0; i < node.max; i++) glyphs += i < filled ? "★" : "☆";
  const glyphSpan = ctx.document.createElement("span");
  glyphSpan.className = "ac-rating-glyphs";
  glyphSpan.textContent = glyphs;
  el.appendChild(glyphSpan);
  if (node.count != null) {
    const countSpan = ctx.document.createElement("span");
    countSpan.className = "ac-rating-count";
    countSpan.textContent = ` (${node.count})`;
    el.appendChild(countSpan);
  }
  return el;
}

function wrapInputRow(id, label, dataAcNode, isRequired, innerInput, ctx) {
  const row = makeElement("div", dataAcNode, ctx);
  row.className = `ac-input-row ac-input-${dataAcNode}`;
  row.setAttribute("data-ac-input-id", id);
  if (isRequired) row.setAttribute("data-ac-required", "true");
  if (label) {
    const labelEl = ctx.document.createElement("label");
    labelEl.className = "ac-input-label";
    labelEl.textContent = label;
    labelEl.setAttribute("for", `ac-input-${id}`);
    row.appendChild(labelEl);
  }
  row.appendChild(innerInput);
  return row;
}

function makeTextFieldElement(node, ctx) {
  let input;
  if (node.isMultiline) {
    input = ctx.document.createElement("textarea");
    input.textContent = node.value ?? "";
  } else {
    input = ctx.document.createElement("input");
    input.setAttribute("type", "text");
    if (node.value != null) input.setAttribute("value", node.value);
  }
  input.setAttribute("id", `ac-input-${node.id}`);
  input.setAttribute("name", node.id);
  if (node.placeholder) input.setAttribute("placeholder", node.placeholder);
  if (node.isRequired) input.setAttribute("required", "");
  input.className = "ac-input ac-input-text";
  ctx.registeredInputs.push({ id: node.id, read: () => input.value });
  return wrapInputRow(node.id, node.label, "textField", node.isRequired, input, ctx);
}

function makeNumberFieldElement(node, ctx) {
  const input = ctx.document.createElement("input");
  input.setAttribute("type", "number");
  input.setAttribute("id", `ac-input-${node.id}`);
  input.setAttribute("name", node.id);
  if (node.value != null) input.setAttribute("value", String(node.value));
  if (node.placeholder) input.setAttribute("placeholder", node.placeholder);
  if (node.isRequired) input.setAttribute("required", "");
  input.className = "ac-input ac-input-number";
  ctx.registeredInputs.push({
    id: node.id,
    read: () => (input.value === "" ? null : Number(input.value)),
  });
  return wrapInputRow(node.id, node.label, "numberField", node.isRequired, input, ctx);
}

function makeToggleFieldElement(node, ctx) {
  const input = ctx.document.createElement("input");
  input.setAttribute("type", "checkbox");
  input.setAttribute("id", `ac-input-${node.id}`);
  input.setAttribute("name", node.id);
  if (node.value) input.setAttribute("checked", "");
  if (node.isRequired) input.setAttribute("required", "");
  input.className = "ac-input ac-input-toggle";
  input.setAttribute("data-ac-value-on", node.valueOn);
  input.setAttribute("data-ac-value-off", node.valueOff);
  ctx.registeredInputs.push({
    id: node.id,
    read: () => (input.checked ? node.valueOn : node.valueOff),
  });
  const inline = ctx.document.createElement("span");
  inline.className = "ac-input-toggle-title";
  inline.textContent = node.title;
  const wrap = ctx.document.createElement("span");
  wrap.className = "ac-input-toggle-row";
  wrap.appendChild(input);
  wrap.appendChild(inline);
  return wrapInputRow(node.id, node.label, "toggleField", node.isRequired, wrap, ctx);
}

function makeChoiceFieldElement(node, ctx) {
  const select = ctx.document.createElement("select");
  select.setAttribute("id", `ac-input-${node.id}`);
  select.setAttribute("name", node.id);
  if (node.isMultiSelect) select.setAttribute("multiple", "");
  if (node.isRequired) select.setAttribute("required", "");
  select.className = "ac-input ac-input-choice";
  let selectedSet;
  if (node.isMultiSelect) {
    selectedSet = new Set(
      String(node.selected ?? "").split(",").map((s) => s.trim()).filter(Boolean)
    );
  } else if (node.selected != null) {
    selectedSet = new Set([node.selected]);
  } else {
    selectedSet = new Set();
  }
  for (const choice of node.choices ?? []) {
    const opt = ctx.document.createElement("option");
    opt.setAttribute("value", choice.value);
    opt.textContent = choice.title;
    if (selectedSet.has(choice.value)) opt.setAttribute("selected", "");
    select.appendChild(opt);
  }
  ctx.registeredInputs.push({
    id: node.id,
    read: () =>
      node.isMultiSelect
        ? Array.from(select.selectedOptions).map((o) => o.value)
        : select.value,
  });
  return wrapInputRow(node.id, node.label, "choiceField", node.isRequired, select, ctx);
}

function makeDateOrTimeFieldElement(node, ctx, inputType, dataAcNode) {
  const input = ctx.document.createElement("input");
  input.setAttribute("type", inputType);
  input.setAttribute("id", `ac-input-${node.id}`);
  input.setAttribute("name", node.id);
  if (node.value != null) input.setAttribute("value", node.value);
  if (node.placeholder) input.setAttribute("placeholder", node.placeholder);
  if (node.isRequired) input.setAttribute("required", "");
  input.className = `ac-input ac-input-${inputType}`;
  ctx.registeredInputs.push({ id: node.id, read: () => input.value });
  return wrapInputRow(node.id, node.label, dataAcNode, node.isRequired, input, ctx);
}

function makeRatingFieldElement(node, ctx) {
  const input = ctx.document.createElement("input");
  input.setAttribute("type", "range");
  input.setAttribute("id", `ac-input-${node.id}`);
  input.setAttribute("name", node.id);
  input.setAttribute("min", "0");
  input.setAttribute("max", String(node.max));
  input.setAttribute("step", "1");
  input.setAttribute("value", String(Math.round(node.value)));
  if (node.isRequired) input.setAttribute("required", "");
  input.className = "ac-input ac-input-rating";
  ctx.registeredInputs.push({
    id: node.id,
    read: () => (input.value === "" ? null : Number(input.value)),
  });
  return wrapInputRow(node.id, node.label, "ratingField", node.isRequired, input, ctx);
}

function makeChartElement(node, ctx) {
  const el = makeElement("figure", "chart", ctx);
  el.className = `ac-chart ac-chart-${node.kind}`;
  el.setAttribute("data-ac-chart-kind", node.kind);
  el.setAttribute("data-ac-show-legend", node.showLegend ? "true" : "false");
  if (node.title) {
    const caption = ctx.document.createElement("figcaption");
    caption.className = "ac-chart-title";
    caption.textContent = node.title;
    el.appendChild(caption);
  }
  const table = ctx.document.createElement("table");
  table.className = "ac-chart-table";
  const tbody = ctx.document.createElement("tbody");
  for (const datum of node.data ?? []) {
    const tr = ctx.document.createElement("tr");
    tr.className = "ac-chart-datum";
    if (datum.color) {
      const swatch = ctx.document.createElement("td");
      swatch.className = "ac-chart-swatch";
      swatch.setAttribute("data-ac-chart-color", datum.color);
      swatch.style.backgroundColor = datum.color;
      tr.appendChild(swatch);
    }
    const labelCell = ctx.document.createElement("td");
    labelCell.className = "ac-chart-label";
    labelCell.textContent = datum.label;
    tr.appendChild(labelCell);
    const valueCell = ctx.document.createElement("td");
    valueCell.className = "ac-chart-value";
    valueCell.textContent = String(datum.value);
    tr.appendChild(valueCell);
    tbody.appendChild(tr);
  }
  table.appendChild(tbody);
  el.appendChild(table);
  return el;
}

function makeTabSetElement(node, ctx) {
  const el = makeElement("div", "tabSet", ctx);
  el.className = "ac-tabset";
  el.setAttribute("data-ac-selected-tab-index", String(node.selectedTabIndex));
  const tabs = node.tabs ?? [];
  const clamped = node.selectedTabIndex >= 0 && node.selectedTabIndex < tabs.length
    ? node.selectedTabIndex : 0;
  const tablist = ctx.document.createElement("div");
  tablist.className = "ac-tabset-tablist";
  tablist.setAttribute("role", "tablist");
  tabs.forEach((tab, idx) => {
    const btn = ctx.document.createElement("button");
    btn.className =
      "ac-tabset-tab" + (idx === clamped ? " ac-tabset-tab-selected" : "");
    btn.setAttribute("type", "button");
    btn.setAttribute("role", "tab");
    btn.setAttribute("data-ac-tab-id", tab.id);
    btn.setAttribute("data-ac-tab-index", String(idx));
    btn.setAttribute("aria-selected", idx === clamped ? "true" : "false");
    btn.setAttribute("tabindex", idx === clamped ? "0" : "-1");
    btn.textContent = tab.title;
    tablist.appendChild(btn);
  });
  el.appendChild(tablist);
  if (tabs[clamped]) {
    const panel = ctx.document.createElement("div");
    panel.className = "ac-tabset-panel";
    panel.setAttribute("role", "tabpanel");
    panel.setAttribute("data-ac-tab-id", tabs[clamped].id);
    for (const child of tabs[clamped].content ?? []) {
      panel.appendChild(walk(child, ctx));
    }
    el.appendChild(panel);
  }
  return el;
}

function actionKindTag(action) {
  if (!action) return null;
  // The IR encodes ActionKind as { kind: "...", ... }. Map to the same
  // string tags the Swift renderer emits.
  return action.kind;
}

function makeCompoundButtonElement(node, ctx) {
  const el = makeElement("button", "compoundButton", ctx);
  el.className = "ac-compound-button";
  el.setAttribute("type", "button");
  const kindTag = actionKindTag(node.action);
  if (kindTag) el.setAttribute("data-ac-action-kind", kindTag);
  if (node.icon) {
    const img = ctx.document.createElement("img");
    img.className = "ac-compound-button-icon";
    img.setAttribute("src", node.icon);
    img.setAttribute("alt", "");
    el.appendChild(img);
  }
  const stack = ctx.document.createElement("span");
  stack.className = "ac-compound-button-text";
  const titleEl = ctx.document.createElement("span");
  titleEl.className = "ac-compound-button-title";
  titleEl.textContent = node.title;
  stack.appendChild(titleEl);
  if (node.subtitle) {
    const sub = ctx.document.createElement("span");
    sub.className = "ac-compound-button-subtitle";
    sub.textContent = node.subtitle;
    stack.appendChild(sub);
  }
  el.appendChild(stack);
  if (node.action) attachClickDispatch(el, node.action, ctx);
  return el;
}

function makeButtonElement(node, ctx) {
  const tag = actionKindTag(node.kind) ?? "unknown";
  const el = makeElement("button", "button", ctx);
  el.className = `ac-button ac-action-${tag}`;
  el.setAttribute("type", "button");
  el.setAttribute("data-ac-action-kind", tag);
  el.textContent = node.title;
  attachClickDispatch(el, node.kind, ctx);
  return el;
}

function attachClickDispatch(el, action, ctx) {
  el.addEventListener("click", () => {
    if (action.kind === "submit") {
      const merged = mergeSubmitPayload(action.dataJSON, ctx);
      ctx.dispatcher?.({ kind: "submit", dataJSON: merged });
    } else {
      ctx.dispatcher?.(action);
    }
  });
}

function mergeSubmitPayload(originalJSON, ctx) {
  let base = {};
  if (originalJSON) {
    try {
      const parsed = JSON.parse(originalJSON);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        base = parsed;
      }
    } catch {
      // Fall through with {}: the renderer treats unparseable dataJSON
      // exactly like the Swift side does.
    }
  }
  for (const entry of ctx.registeredInputs) {
    const v = entry.read();
    if (v != null) base[entry.id] = v;
  }
  // Deterministic ordering to match the Swift side's
  // [.sortedKeys] output.
  const sorted = {};
  for (const k of Object.keys(base).sort()) sorted[k] = base[k];
  return JSON.stringify(sorted);
}

function makeCarouselElement(node, ctx) {
  const el = makeElement("section", "carousel", ctx);
  el.className = "ac-carousel";
  el.setAttribute("aria-roledescription", "carousel");
  el.setAttribute("data-ac-selected-page-index", String(node.selectedPageIndex));
  if (node.autoAdvanceMs != null) {
    el.setAttribute("data-ac-auto-advance-ms", String(node.autoAdvanceMs));
  }
  const pages = node.pages ?? [];
  const clamped = node.selectedPageIndex >= 0 && node.selectedPageIndex < pages.length
    ? node.selectedPageIndex : 0;
  const dots = ctx.document.createElement("div");
  dots.className = "ac-carousel-dots";
  dots.setAttribute("role", "tablist");
  pages.forEach((page, idx) => {
    const dot = ctx.document.createElement("span");
    dot.className =
      "ac-carousel-dot" + (idx === clamped ? " ac-carousel-dot-selected" : "");
    dot.setAttribute("role", "tab");
    dot.setAttribute("data-ac-page-id", page.id);
    dot.setAttribute("data-ac-page-index", String(idx));
    dot.setAttribute("aria-selected", idx === clamped ? "true" : "false");
    dot.setAttribute("aria-label", `Page ${idx + 1} of ${pages.length}`);
    dots.appendChild(dot);
  });
  el.appendChild(dots);
  if (node.autoAdvanceMs != null) {
    const pause = ctx.document.createElement("button");
    pause.className = "ac-carousel-pause";
    pause.setAttribute("type", "button");
    pause.setAttribute(
      "aria-label",
      "Pause auto-advancing carousel (WCAG SC 2.2.2)"
    );
    pause.setAttribute("data-ac-carousel-pause", "true");
    pause.textContent = "⏸";
    el.appendChild(pause);
  }
  if (pages[clamped]) {
    const panel = ctx.document.createElement("div");
    panel.className = "ac-carousel-page";
    panel.setAttribute("role", "tabpanel");
    panel.setAttribute("data-ac-page-id", pages[clamped].id);
    if (pages[clamped].selectAction) {
      panel.setAttribute(
        "data-ac-select-action-kind",
        actionKindTag(pages[clamped].selectAction)
      );
    }
    for (const child of pages[clamped].content ?? []) {
      panel.appendChild(walk(child, ctx));
    }
    el.appendChild(panel);
  }
  return el;
}

function makeListElement(node, ctx) {
  const tag = node.style === "bulleted" ? "ul" : node.style === "numbered" ? "ol" : "div";
  const el = makeElement(tag, "list", ctx);
  el.className = `ac-list ac-list-${node.style}`;
  el.setAttribute("data-ac-list-style", node.style);
  const markerless = node.style === "default";
  for (const item of node.items ?? []) {
    if (markerless) {
      el.appendChild(walk(item, ctx));
    } else {
      const li = ctx.document.createElement("li");
      li.className = "ac-list-item";
      li.appendChild(walk(item, ctx));
      el.appendChild(li);
    }
  }
  return el;
}

function makeMediaElement(node, ctx) {
  const el = makeElement("figure", "media", ctx);
  el.className = "ac-media";
  const sources = node.sources ?? [];
  const videoSources = sources.filter((s) => s.mimeType?.startsWith("video/"));
  const audioSources = sources.filter((s) => s.mimeType?.startsWith("audio/"));
  if (videoSources.length) {
    const video = ctx.document.createElement("video");
    video.className = "ac-media-video";
    video.setAttribute("controls", "");
    if (node.posterURL) video.setAttribute("poster", node.posterURL);
    if (node.altText) video.setAttribute("aria-label", node.altText);
    for (const s of videoSources) {
      const sEl = ctx.document.createElement("source");
      sEl.setAttribute("src", s.url);
      sEl.setAttribute("type", s.mimeType);
      video.appendChild(sEl);
    }
    el.appendChild(video);
  } else if (audioSources.length) {
    const audio = ctx.document.createElement("audio");
    audio.className = "ac-media-audio";
    audio.setAttribute("controls", "");
    if (node.altText) audio.setAttribute("aria-label", node.altText);
    for (const s of audioSources) {
      const sEl = ctx.document.createElement("source");
      sEl.setAttribute("src", s.url);
      sEl.setAttribute("type", s.mimeType);
      audio.appendChild(sEl);
    }
    el.appendChild(audio);
  } else {
    if (node.posterURL) {
      const poster = ctx.document.createElement("img");
      poster.className = "ac-media-poster";
      poster.setAttribute("src", node.posterURL);
      poster.setAttribute("alt", node.altText ?? "");
      el.appendChild(poster);
    }
    for (const s of sources) {
      const row = ctx.document.createElement("div");
      row.className = "ac-media-source";
      row.setAttribute("data-ac-mime", s.mimeType);
      row.textContent = `${s.mimeType}: ${s.url}`;
      el.appendChild(row);
    }
  }
  if (node.altText) {
    const caption = ctx.document.createElement("figcaption");
    caption.className = "ac-media-caption";
    caption.textContent = node.altText;
    el.appendChild(caption);
  }
  return el;
}

function makeUnsupportedElement(node, ctx) {
  const el = makeElement("div", "unsupported", ctx);
  el.className = "ac-unsupported";
  el.setAttribute("data-ac-unsupported-case", node.typeString ?? node.type);
  el.textContent = "[unsupported node]";
  return el;
}

export function walk(node, ctx) {
  switch (node.type) {
    case "text":            return makeTextElement(node, ctx);
    case "richRun":         return makeRichRunElement(node, ctx);
    case "image":           return makeImageElement(node, ctx);
    case "verticalStack":   return makeStackElement(node, ctx, "vertical");
    case "horizontalStack": return makeStackElement(node, ctx, "horizontal");
    case "facts":           return makeFactsElement(node, ctx);
    case "code":            return makeCodeElement(node, ctx);
    case "textField":       return makeTextFieldElement(node, ctx);
    case "numberField":     return makeNumberFieldElement(node, ctx);
    case "toggleField":     return makeToggleFieldElement(node, ctx);
    case "choiceField":     return makeChoiceFieldElement(node, ctx);
    case "progressBar":     return makeProgressBarElement(node, ctx);
    case "spinner":         return makeSpinnerElement(node, ctx);
    case "accordion":       return makeAccordionElement(node, ctx);
    case "table":           return makeTableElement(node, ctx);
    case "rating":          return makeRatingDisplayElement(node, ctx);
    case "dateField":       return makeDateOrTimeFieldElement(node, ctx, "date", "dateField");
    case "timeField":       return makeDateOrTimeFieldElement(node, ctx, "time", "timeField");
    case "ratingField":     return makeRatingFieldElement(node, ctx);
    case "chart":           return makeChartElement(node, ctx);
    case "tabSet":          return makeTabSetElement(node, ctx);
    case "carousel":        return makeCarouselElement(node, ctx);
    case "list":            return makeListElement(node, ctx);
    case "media":           return makeMediaElement(node, ctx);
    case "compoundButton":  return makeCompoundButtonElement(node, ctx);
    case "button":          return makeButtonElement(node, ctx);
    default:                return makeUnsupportedElement(node, ctx);
  }
}

/**
 * Render an IR JSON tree into `parent`. Returns the registered inputs
 * + dispatcher so callers can hook submit / OpenUrl manually if they
 * want to bypass the default `console.warn` policy.
 */
export function renderInto(parent, tree, options = {}) {
  const ctx = {
    document: parent.ownerDocument ?? document,
    registeredInputs: [],
    dispatcher:
      options.dispatcher ??
      ((action) => {
        if (action.kind === "openUrl") {
          window.open(action.openUrl ?? action.value ?? "", "_blank");
        } else if (action.kind === "submit") {
          console.warn("ac:submit", action.dataJSON ?? "<no-payload>");
        } else {
          console.warn("ac:action-unsupported", action.kind);
        }
      }),
  };
  parent.appendChild(walk(tree, ctx));
  return ctx;
}
