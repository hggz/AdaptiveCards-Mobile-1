import * as React from "react";
import { AdaptiveCard } from "./AdaptiveCard";
import { versionString } from "./wasm";

const CARDS = [
  "simple-text.json",
  "containers.json",
  "input-form.json",
  "all-actions.json",
  "table.json",
  "rating.json",
  "edge-empty-card.json",
  "windows-extras.json",
];

export function App(): React.ReactElement {
  const [version, setVersion] = React.useState<string>("");
  const [selected, setSelected] = React.useState<string>(CARDS[0]);
  const [json, setJSON] = React.useState<string | null>(null);

  React.useEffect(() => {
    versionString().then(setVersion).catch(() => setVersion("(load failure)"));
  }, []);

  React.useEffect(() => {
    let cancelled = false;
    fetch(`/cards/${selected}`)
      .then((r) => r.text())
      .then((t) => { if (!cancelled) setJSON(t); })
      .catch((e) => { if (!cancelled) console.error(e); });
    return () => { cancelled = true; };
  }, [selected]);

  return (
    <>
      <header className="ac-host-header">
        <h1>Adaptive Cards — React WASM host</h1>
        <p>
          Single <code>AdaptiveCard</code> React component loading{" "}
          <code>ac.wasm</code> (built from <code>AdaptiveCardsWasmCABI</code>)
          and walking the returned IR JSON into React elements.
        </p>
        <label>
          Card:{" "}
          <select
            id="ac-card-picker"
            value={selected}
            onChange={(e) => setSelected(e.target.value)}
          >
            {CARDS.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </label>
        <span id="ac-status" className="ac-status">
          {version ? `wasm loaded (${version}) — ${selected}` : "loading wasm…"}
        </span>
      </header>
      <main>
        <div id="ac-card-mount" className="ac-card-mount" aria-live="polite">
          {json && (
            <AdaptiveCard
              json={json}
              onAction={(a) => {
                if (a.kind === "openUrl") {
                  window.open((a as any).openUrl, "_blank");
                } else if (a.kind === "submit") {
                  console.warn("ac:submit", a.dataJSON ?? "<no-payload>");
                } else {
                  console.warn("ac:action-unsupported", a.kind);
                }
              }}
            />
          )}
        </div>
      </main>
    </>
  );
}
