import * as React from "react";
import { renderIR } from "./wasm";
import { walk, type ActionKind, type IRNode, type WalkerContext } from "./walker";

export interface AdaptiveCardProps {
  /** Adaptive Card JSON document as a UTF-8 string. */
  json: string;
  /** Called when a `.button` or `.compoundButton` is clicked. */
  onAction?: (action: ActionKind) => void;
}

/**
 * React component that renders an Adaptive Card via the
 * `AdaptiveCardsWasmCABI` module. Lazy-loads the WASM module on first
 * use; subsequent renders share the singleton instance.
 */
export function AdaptiveCard({ json, onAction }: AdaptiveCardProps): React.ReactElement {
  const [ir, setIR] = React.useState<IRNode | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  // Live input state for submit-payload merge. Stored in a ref so the
  // walker can mutate without re-rendering on every keystroke; React's
  // own controlled-input state is held by useState (`tick`).
  const inputStateRef = React.useRef<Map<string, unknown>>(new Map());
  const [, forceTick] = React.useState(0);

  React.useEffect(() => {
    let cancelled = false;
    inputStateRef.current = new Map();
    setError(null);
    renderIR(json)
      .then((tree) => {
        if (!cancelled) setIR(tree as IRNode);
      })
      .catch((e) => {
        if (!cancelled) setError(String(e?.message ?? e));
      });
    return () => { cancelled = true; };
  }, [json]);

  const ctx: WalkerContext = React.useMemo(() => ({
    inputState: inputStateRef.current,
    setInput: (id, value) => {
      inputStateRef.current.set(id, value);
      // Trigger re-render so React's controlled inputs reflect the new
      // value. `forceTick((x) => x + 1)` is cheaper than threading state
      // through every input call site.
      forceTick((x) => x + 1);
    },
    onAction: (a) => onAction?.(a),
    buildSubmitPayload: (originalJSON) => {
      let base: Record<string, unknown> = {};
      if (originalJSON) {
        try {
          const parsed = JSON.parse(originalJSON);
          if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
            base = parsed as Record<string, unknown>;
          }
        } catch { /* fall through with {} */ }
      }
      for (const [k, v] of inputStateRef.current.entries()) {
        if (v != null && v !== "") base[k] = v;
      }
      const sorted: Record<string, unknown> = {};
      for (const k of Object.keys(base).sort()) sorted[k] = base[k];
      return JSON.stringify(sorted);
    },
  }), [onAction]);

  if (error) {
    return (
      <div className="ac-unsupported" role="alert">{`AdaptiveCard error: ${error}`}</div>
    );
  }
  if (!ir) {
    return <div className="ac-status">loading…</div>;
  }
  return <>{walk(ir, ctx, 0)}</>;
}
