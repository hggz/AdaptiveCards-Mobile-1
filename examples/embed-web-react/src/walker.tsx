/**
 * wasm-port: IR JSON -> React element walker.
 *
 * Mirrors the W2-W7 switch in
 * `ios/Sources/AdaptiveCardsWebUI/DOMRenderer.swift` and the W10
 * vanilla walker in `examples/embed-web-vanilla/src/walker.js`.
 * CSS class names + `data-ac-*` attributes are byte-identical so a
 * single stylesheet can serve all three paths.
 */
import * as React from "react";

export type ActionKind =
  | { kind: "submit"; dataJSON?: string | null }
  | { kind: "openUrl"; openUrl: string }
  | { kind: "showCard" }
  | { kind: "execute" }
  | { kind: "toggleVisibility" }
  | { kind: "popover" }
  | { kind: "runCommands" }
  | { kind: "openUrlDialog" }
  | { kind: "unknown"; unknown: string };

export interface IRNode {
  type: string;
  [k: string]: unknown;
}

export interface WalkerContext {
  /** Map of input-id -> current live value (for submit-payload merge). */
  inputState: Map<string, unknown>;
  setInput(id: string, value: unknown): void;
  onAction(action: ActionKind): void;
  /** Build a fully-merged submit payload from `originalJSON` + inputs. */
  buildSubmitPayload(originalJSON: string | null | undefined): string;
}

function actionTag(a?: { kind?: string } | null): string {
  return a?.kind ?? "unknown";
}

function classes(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(" ");
}

// =============================================================
// Display-only node renderers
// =============================================================

function renderText(node: any, key: React.Key) {
  return (
    <div
      key={key}
      data-ac-node="text"
      className={classes(
        "ac-text",
        `ac-text-size-${node.size}`,
        `ac-text-weight-${node.weight}`,
        node.isSubtle && "ac-text-subtle"
      )}
      style={{ whiteSpace: node.wrap ? "pre-wrap" : "nowrap" }}
    >
      {node.string}
    </div>
  );
}

function renderRichRun(node: any, key: React.Key) {
  const deco: string[] = [];
  if (node.underline) deco.push("underline");
  if (node.strikethrough) deco.push("line-through");
  return (
    <span
      key={key}
      data-ac-node="richRun"
      className={classes(
        "ac-rich-run",
        `ac-text-size-${node.size}`,
        `ac-text-weight-${node.weight}`,
        node.isSubtle && "ac-text-subtle"
      )}
      style={{
        ...(node.italic ? { fontStyle: "italic" } : {}),
        ...(deco.length ? { textDecoration: deco.join(" ") } : {}),
      }}
    >
      {node.string}
    </span>
  );
}

function renderImage(node: any, key: React.Key) {
  return (
    <img
      key={key}
      data-ac-node="image"
      src={node.url}
      alt={node.alt}
      className={`ac-image ac-image-${node.displayHint}`}
    />
  );
}

function renderStack(node: any, key: React.Key, ctx: WalkerContext, dir: "vertical" | "horizontal") {
  return (
    <div
      key={key}
      data-ac-node={`${dir}Stack`}
      className={`ac-stack ac-${dir}-stack ac-spacing-${node.spacing}`}
      style={{
        display: "flex",
        flexDirection: dir === "vertical" ? "column" : "row",
        gap: `${node.spacing}px`,
      }}
    >
      {(node.children ?? []).map((c: IRNode, i: number) => walk(c, ctx, i))}
    </div>
  );
}

function renderFacts(node: any, key: React.Key) {
  return (
    <dl key={key} data-ac-node="facts" className="ac-facts">
      {(node.pairs ?? []).flatMap((p: any, i: number) => [
        <dt key={`t${i}`} className="ac-fact-title">{p.title}</dt>,
        <dd key={`v${i}`} className="ac-fact-value">{p.value}</dd>,
      ])}
    </dl>
  );
}

function renderCode(node: any, key: React.Key) {
  return (
    <pre
      key={key}
      data-ac-node="code"
      className="ac-code"
      style={{ whiteSpace: node.wrap ? "pre-wrap" : "pre" }}
    >
      <code
        {...(node.language
          ? { className: `language-${node.language}`, "data-ac-language": node.language }
          : {})}
      >
        {node.text}
      </code>
    </pre>
  );
}

function renderProgressBar(node: any, key: React.Key) {
  return (
    <div key={key} data-ac-node="progressBar" className="ac-progressbar-row">
      {node.label && <span className="ac-progressbar-label">{node.label}</span>}
      <progress
        className="ac-progressbar"
        max={1}
        value={node.value}
        {...(node.label ? { "aria-label": node.label } : {})}
      />
    </div>
  );
}

function renderSpinner(node: any, key: React.Key) {
  return (
    <div
      key={key}
      data-ac-node="spinner"
      className="ac-spinner"
      role="status"
      {...(node.label ? { "aria-label": node.label } : {})}
    >
      {node.label && <span className="ac-spinner-label">{node.label}</span>}
    </div>
  );
}

function renderAccordion(node: any, key: React.Key, ctx: WalkerContext) {
  return (
    <div key={key} data-ac-node="accordion" className="ac-accordion">
      {(node.panels ?? []).map((p: any, i: number) => (
        <details
          key={i}
          className="ac-accordion-panel"
          {...(p.isExpanded ? { open: true } : {})}
        >
          <summary className="ac-accordion-summary">{p.title}</summary>
          {(p.content ?? []).map((c: IRNode, j: number) => walk(c, ctx, j))}
        </details>
      ))}
    </div>
  );
}

function renderTable(node: any, key: React.Key, ctx: WalkerContext) {
  return (
    <table key={key} data-ac-node="table" className="ac-table">
      {node.headers && node.headers.length > 0 && (
        <thead>
          <tr>
            {node.headers.map((cell: IRNode[], i: number) => (
              <th key={i} scope="col" className="ac-table-header">
                {cell.map((c, j) => walk(c, ctx, j))}
              </th>
            ))}
          </tr>
        </thead>
      )}
      <tbody>
        {(node.rows ?? []).map((row: IRNode[][], rIdx: number) => (
          <tr key={rIdx}>
            {row.map((cell, cIdx) => (
              <td key={cIdx} className="ac-table-cell">
                {cell.map((c, j) => walk(c, ctx, j))}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function renderRating(node: any, key: React.Key) {
  const filled = Math.round(node.value);
  let glyphs = "";
  for (let i = 0; i < node.max; i++) glyphs += i < filled ? "★" : "☆";
  const countSuffix = node.count != null ? `, ${node.count} ratings` : "";
  return (
    <div
      key={key}
      data-ac-node="rating"
      className="ac-rating-display"
      role="img"
      aria-label={`${node.value} of ${node.max}${countSuffix}`}
      data-ac-rating-value={String(node.value)}
      data-ac-rating-max={String(node.max)}
    >
      <span className="ac-rating-glyphs">{glyphs}</span>
      {node.count != null && <span className="ac-rating-count">{` (${node.count})`}</span>}
    </div>
  );
}

// =============================================================
// Input renderers (controlled via ctx.inputState)
// =============================================================

function inputRow(
  id: string,
  label: string | null | undefined,
  dataAcNode: string,
  isRequired: boolean,
  inner: React.ReactNode,
  key: React.Key
) {
  return (
    <div
      key={key}
      data-ac-node={dataAcNode}
      className={`ac-input-row ac-input-${dataAcNode}`}
      data-ac-input-id={id}
      {...(isRequired ? { "data-ac-required": "true" } : {})}
    >
      {label && (
        <label className="ac-input-label" htmlFor={`ac-input-${id}`}>
          {label}
        </label>
      )}
      {inner}
    </div>
  );
}

function renderTextField(node: any, key: React.Key, ctx: WalkerContext) {
  const id = node.id as string;
  const initial = (node.value as string | null | undefined) ?? "";
  if (!ctx.inputState.has(id)) ctx.inputState.set(id, initial);
  const value = ctx.inputState.get(id) as string;
  const props = {
    id: `ac-input-${id}`,
    name: id,
    placeholder: node.placeholder ?? undefined,
    required: !!node.isRequired,
    value,
    onChange: (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
      ctx.setInput(id, e.target.value),
    className: "ac-input ac-input-text",
  };
  const inner = node.isMultiline
    ? <textarea {...(props as any)} />
    : <input type="text" {...(props as any)} />;
  return inputRow(id, node.label, "textField", !!node.isRequired, inner, key);
}

function renderNumberField(node: any, key: React.Key, ctx: WalkerContext) {
  const id = node.id as string;
  const initial = node.value != null ? String(node.value) : "";
  if (!ctx.inputState.has(id)) ctx.inputState.set(id, initial);
  const value = ctx.inputState.get(id) as string;
  const inner = (
    <input
      type="number"
      id={`ac-input-${id}`}
      name={id}
      placeholder={node.placeholder ?? undefined}
      required={!!node.isRequired}
      value={value}
      onChange={(e) => ctx.setInput(id, e.target.value)}
      className="ac-input ac-input-number"
    />
  );
  return inputRow(id, node.label, "numberField", !!node.isRequired, inner, key);
}

function renderToggleField(node: any, key: React.Key, ctx: WalkerContext) {
  const id = node.id as string;
  if (!ctx.inputState.has(id)) ctx.inputState.set(id, !!node.value);
  const checked = ctx.inputState.get(id) as boolean;
  const inner = (
    <span className="ac-input-toggle-row">
      <input
        type="checkbox"
        id={`ac-input-${id}`}
        name={id}
        required={!!node.isRequired}
        checked={checked}
        onChange={(e) => ctx.setInput(id, e.target.checked)}
        className="ac-input ac-input-toggle"
        data-ac-value-on={node.valueOn}
        data-ac-value-off={node.valueOff}
      />
      <span className="ac-input-toggle-title">{node.title}</span>
    </span>
  );
  return inputRow(id, node.label, "toggleField", !!node.isRequired, inner, key);
}

function renderChoiceField(node: any, key: React.Key, ctx: WalkerContext) {
  const id = node.id as string;
  const isMulti = !!node.isMultiSelect;
  if (!ctx.inputState.has(id)) {
    if (isMulti) {
      const initial = String(node.selected ?? "")
        .split(",")
        .map((s: string) => s.trim())
        .filter(Boolean);
      ctx.inputState.set(id, initial);
    } else {
      ctx.inputState.set(id, node.selected ?? "");
    }
  }
  const current = ctx.inputState.get(id);
  const inner = (
    <select
      id={`ac-input-${id}`}
      name={id}
      multiple={isMulti}
      required={!!node.isRequired}
      value={current as any}
      onChange={(e) => {
        if (isMulti) {
          ctx.setInput(
            id,
            Array.from(e.target.selectedOptions).map((o) => o.value)
          );
        } else {
          ctx.setInput(id, e.target.value);
        }
      }}
      className="ac-input ac-input-choice"
    >
      {(node.choices ?? []).map((c: any) => (
        <option key={c.value} value={c.value}>{c.title}</option>
      ))}
    </select>
  );
  return inputRow(id, node.label, "choiceField", !!node.isRequired, inner, key);
}

function renderDateOrTimeField(
  node: any, key: React.Key, ctx: WalkerContext,
  inputType: "date" | "time", dataAcNode: string
) {
  const id = node.id as string;
  const initial = (node.value as string | null | undefined) ?? "";
  if (!ctx.inputState.has(id)) ctx.inputState.set(id, initial);
  const value = ctx.inputState.get(id) as string;
  const inner = (
    <input
      type={inputType}
      id={`ac-input-${id}`}
      name={id}
      placeholder={node.placeholder ?? undefined}
      required={!!node.isRequired}
      value={value}
      onChange={(e) => ctx.setInput(id, e.target.value)}
      className={`ac-input ac-input-${inputType}`}
    />
  );
  return inputRow(id, node.label, dataAcNode, !!node.isRequired, inner, key);
}

function renderRatingField(node: any, key: React.Key, ctx: WalkerContext) {
  const id = node.id as string;
  if (!ctx.inputState.has(id)) ctx.inputState.set(id, String(Math.round(node.value)));
  const value = ctx.inputState.get(id) as string;
  const inner = (
    <input
      type="range"
      id={`ac-input-${id}`}
      name={id}
      min={0}
      max={node.max}
      step={1}
      required={!!node.isRequired}
      value={value}
      onChange={(e) => ctx.setInput(id, e.target.value)}
      className="ac-input ac-input-rating"
    />
  );
  return inputRow(id, node.label, "ratingField", !!node.isRequired, inner, key);
}

// =============================================================
// Composite / media renderers
// =============================================================

function renderChart(node: any, key: React.Key) {
  return (
    <figure
      key={key}
      data-ac-node="chart"
      className={`ac-chart ac-chart-${node.kind}`}
      data-ac-chart-kind={node.kind}
      data-ac-show-legend={node.showLegend ? "true" : "false"}
    >
      {node.title && <figcaption className="ac-chart-title">{node.title}</figcaption>}
      <table className="ac-chart-table">
        <tbody>
          {(node.data ?? []).map((d: any, i: number) => (
            <tr key={i} className="ac-chart-datum">
              {d.color && (
                <td
                  className="ac-chart-swatch"
                  data-ac-chart-color={d.color}
                  style={{ backgroundColor: d.color }}
                />
              )}
              <td className="ac-chart-label">{d.label}</td>
              <td className="ac-chart-value">{String(d.value)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </figure>
  );
}

function renderTabSet(node: any, key: React.Key, ctx: WalkerContext) {
  const tabs = node.tabs ?? [];
  const clamped =
    node.selectedTabIndex >= 0 && node.selectedTabIndex < tabs.length
      ? node.selectedTabIndex : 0;
  return (
    <div
      key={key}
      data-ac-node="tabSet"
      className="ac-tabset"
      data-ac-selected-tab-index={String(node.selectedTabIndex)}
    >
      <div role="tablist" className="ac-tabset-tablist">
        {tabs.map((t: any, idx: number) => (
          <button
            key={idx}
            type="button"
            role="tab"
            data-ac-tab-id={t.id}
            data-ac-tab-index={String(idx)}
            aria-selected={idx === clamped}
            tabIndex={idx === clamped ? 0 : -1}
            className={`ac-tabset-tab${idx === clamped ? " ac-tabset-tab-selected" : ""}`}
          >
            {t.title}
          </button>
        ))}
      </div>
      {tabs[clamped] && (
        <div role="tabpanel" className="ac-tabset-panel" data-ac-tab-id={tabs[clamped].id}>
          {(tabs[clamped].content ?? []).map((c: IRNode, j: number) => walk(c, ctx, j))}
        </div>
      )}
    </div>
  );
}

function renderCarousel(node: any, key: React.Key, ctx: WalkerContext) {
  const pages = node.pages ?? [];
  const clamped =
    node.selectedPageIndex >= 0 && node.selectedPageIndex < pages.length
      ? node.selectedPageIndex : 0;
  return (
    <section
      key={key}
      data-ac-node="carousel"
      className="ac-carousel"
      aria-roledescription="carousel"
      data-ac-selected-page-index={String(node.selectedPageIndex)}
      {...(node.autoAdvanceMs != null
        ? { "data-ac-auto-advance-ms": String(node.autoAdvanceMs) }
        : {})}
    >
      <div role="tablist" className="ac-carousel-dots">
        {pages.map((p: any, idx: number) => (
          <span
            key={idx}
            role="tab"
            data-ac-page-id={p.id}
            data-ac-page-index={String(idx)}
            aria-selected={idx === clamped}
            aria-label={`Page ${idx + 1} of ${pages.length}`}
            className={`ac-carousel-dot${idx === clamped ? " ac-carousel-dot-selected" : ""}`}
          />
        ))}
      </div>
      {node.autoAdvanceMs != null && (
        <button
          type="button"
          className="ac-carousel-pause"
          aria-label="Pause auto-advancing carousel (WCAG SC 2.2.2)"
          data-ac-carousel-pause="true"
        >⏸</button>
      )}
      {pages[clamped] && (
        <div
          role="tabpanel"
          className="ac-carousel-page"
          data-ac-page-id={pages[clamped].id}
          {...(pages[clamped].selectAction
            ? { "data-ac-select-action-kind": actionTag(pages[clamped].selectAction) }
            : {})}
        >
          {(pages[clamped].content ?? []).map((c: IRNode, j: number) => walk(c, ctx, j))}
        </div>
      )}
    </section>
  );
}

function renderList(node: any, key: React.Key, ctx: WalkerContext) {
  const Tag: any = node.style === "bulleted" ? "ul" : node.style === "numbered" ? "ol" : "div";
  const markerless = node.style === "default";
  return (
    <Tag
      key={key}
      data-ac-node="list"
      className={`ac-list ac-list-${node.style}`}
      data-ac-list-style={node.style}
    >
      {(node.items ?? []).map((item: IRNode, i: number) =>
        markerless
          ? walk(item, ctx, i)
          : <li key={i} className="ac-list-item">{walk(item, ctx, 0)}</li>
      )}
    </Tag>
  );
}

function renderMedia(node: any, key: React.Key) {
  const sources = node.sources ?? [];
  const videos = sources.filter((s: any) => s.mimeType?.startsWith("video/"));
  const audios = sources.filter((s: any) => s.mimeType?.startsWith("audio/"));
  let player: React.ReactNode = null;
  if (videos.length) {
    player = (
      <video
        controls
        poster={node.posterURL ?? undefined}
        aria-label={node.altText ?? undefined}
        className="ac-media-video"
      >
        {videos.map((s: any, i: number) => (
          <source key={i} src={s.url} type={s.mimeType} />
        ))}
      </video>
    );
  } else if (audios.length) {
    player = (
      <audio controls aria-label={node.altText ?? undefined} className="ac-media-audio">
        {audios.map((s: any, i: number) => (
          <source key={i} src={s.url} type={s.mimeType} />
        ))}
      </audio>
    );
  } else {
    player = (
      <>
        {node.posterURL && (
          <img className="ac-media-poster" src={node.posterURL} alt={node.altText ?? ""} />
        )}
        {sources.map((s: any, i: number) => (
          <div key={i} className="ac-media-source" data-ac-mime={s.mimeType}>
            {`${s.mimeType}: ${s.url}`}
          </div>
        ))}
      </>
    );
  }
  return (
    <figure key={key} data-ac-node="media" className="ac-media">
      {player}
      {node.altText && <figcaption className="ac-media-caption">{node.altText}</figcaption>}
    </figure>
  );
}

function renderCompoundButton(node: any, key: React.Key, ctx: WalkerContext) {
  const tag = actionTag(node.action);
  const onClick = () => {
    if (!node.action) return;
    if (node.action.kind === "submit") {
      const merged = ctx.buildSubmitPayload(node.action.dataJSON ?? null);
      ctx.onAction({ kind: "submit", dataJSON: merged });
    } else {
      ctx.onAction(node.action);
    }
  };
  return (
    <button
      key={key}
      type="button"
      data-ac-node="compoundButton"
      className="ac-compound-button"
      {...(node.action ? { "data-ac-action-kind": tag } : {})}
      onClick={onClick}
    >
      {node.icon && (
        <img className="ac-compound-button-icon" src={node.icon} alt="" />
      )}
      <span className="ac-compound-button-text">
        <span className="ac-compound-button-title">{node.title}</span>
        {node.subtitle && (
          <span className="ac-compound-button-subtitle">{node.subtitle}</span>
        )}
      </span>
    </button>
  );
}

function renderButton(node: any, key: React.Key, ctx: WalkerContext) {
  const tag = actionTag(node.kind);
  const onClick = () => {
    if (node.kind.kind === "submit") {
      const merged = ctx.buildSubmitPayload(node.kind.dataJSON ?? null);
      ctx.onAction({ kind: "submit", dataJSON: merged });
    } else {
      ctx.onAction(node.kind);
    }
  };
  return (
    <button
      key={key}
      type="button"
      data-ac-node="button"
      data-ac-action-kind={tag}
      className={`ac-button ac-action-${tag}`}
      onClick={onClick}
    >
      {node.title}
    </button>
  );
}

function renderUnsupported(node: any, key: React.Key) {
  return (
    <div
      key={key}
      data-ac-node="unsupported"
      className="ac-unsupported"
      data-ac-unsupported-case={node.typeString ?? node.type}
    >
      [unsupported node]
    </div>
  );
}

// =============================================================
// Switch
// =============================================================

export function walk(node: IRNode, ctx: WalkerContext, key: React.Key): React.ReactNode {
  switch (node.type) {
    case "text":            return renderText(node, key);
    case "richRun":         return renderRichRun(node, key);
    case "image":           return renderImage(node, key);
    case "verticalStack":   return renderStack(node, key, ctx, "vertical");
    case "horizontalStack": return renderStack(node, key, ctx, "horizontal");
    case "facts":           return renderFacts(node, key);
    case "code":            return renderCode(node, key);
    case "progressBar":     return renderProgressBar(node, key);
    case "spinner":         return renderSpinner(node, key);
    case "accordion":       return renderAccordion(node, key, ctx);
    case "table":           return renderTable(node, key, ctx);
    case "rating":          return renderRating(node, key);
    case "textField":       return renderTextField(node, key, ctx);
    case "numberField":     return renderNumberField(node, key, ctx);
    case "toggleField":     return renderToggleField(node, key, ctx);
    case "choiceField":     return renderChoiceField(node, key, ctx);
    case "dateField":       return renderDateOrTimeField(node, key, ctx, "date", "dateField");
    case "timeField":       return renderDateOrTimeField(node, key, ctx, "time", "timeField");
    case "ratingField":     return renderRatingField(node, key, ctx);
    case "chart":           return renderChart(node, key);
    case "tabSet":          return renderTabSet(node, key, ctx);
    case "carousel":        return renderCarousel(node, key, ctx);
    case "list":            return renderList(node, key, ctx);
    case "media":           return renderMedia(node, key);
    case "compoundButton":  return renderCompoundButton(node, key, ctx);
    case "button":          return renderButton(node, key, ctx);
    default:                return renderUnsupported(node, key);
  }
}
