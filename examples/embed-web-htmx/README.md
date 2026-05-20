# `examples/embed-web-htmx/`

wasm-port: htmx integration sample. Shows the Adaptive Cards
renderer working alongside [htmx](https://htmx.org), the analogue
pattern for the many server-rendered web apps (Rails / Django /
Phoenix / ASP.NET Core / FastAPI / Laravel / …) that lean on htmx
for client-side interactivity.

## Pattern at a glance

* Every card-trigger button carries htmx attributes:
  ```html
  <button hx-get="./cards/simple-text.json"
          hx-target="#ac-card-mount">simple-text</button>
  ```
* The page intercepts `htmx:beforeSwap`. When the target is the AC
  mount, we cancel htmx's default raw-HTML swap and route the
  response into the WASM renderer instead:
  ```js
  document.body.addEventListener("htmx:beforeSwap", (evt) => {
    if (evt.detail.target.id !== "ac-card-mount") return;
    evt.detail.shouldSwap = false;
    ac.render(evt.detail.serverResponse,
              document.getElementById("ac-card-mount"));
  });
  ```

Net effect:
* htmx remains the event + request engine. `hx-trigger`,
  `hx-indicator`, `hx-confirm`, `hx-on::after-request`, etc. all
  keep working.
* The renderer remains the content engine. Same WASM module, same
  `ac-embed.js`, same `data-ac-node` + `ac-*` selectors.

This mirrors the pattern any "X × htmx" integration takes when X is
a client-side rendering library (charts, maps, code editors, etc.)
and you want htmx's declarative request lifecycle without giving up
X's DOM-emission contract.

## Layout

```
examples/embed-web-htmx/
├── README.md            this file
├── index.html           htmx-wired host page
├── ac-embed.js          (copy of examples/embed-web-snippet/ac-embed.js)
├── ac-host.css          (copy of examples/embed-web-snippet/ac-host.css)
├── .gitignore           ignores ac.wasm + cards/
└── (runtime)
    ├── ac.wasm          built locally per the setup steps below
    └── cards/           copied from ../../shared/test-cards/
```

## Setup (one-time)

```bash
# 1. Build the WASM module from the repo root.
cd ../../ios
. ~/.local/share/swiftly/env.sh
swift build -c release \
    --swift-sdk swift-6.3.2-RELEASE_wasm \
    --product AdaptiveCardsWasmCABI

# 2. Copy the wasm next to ac-embed.js.
cd ../examples/embed-web-htmx
cp ../../ios/.build/wasm32-unknown-wasip1/release/AdaptiveCardsWasmCABI.wasm \
   ./ac.wasm

# 3. Reference cards.
mkdir -p cards
cp ../../shared/test-cards/*.json cards/
```

## Serving

Any static HTTP server. Recommended:

```bash
python3 -m http.server 8080
# or
npx http-server -p 8080
```

Open <http://localhost:8080/>. WASM streaming + htmx CDN both work
under the default static-server `Content-Type`s.

## Production deployment

Server-rendered hosts (Rails / Django / Phoenix / etc.) typically
already serve htmx from a CDN and expose JSON endpoints. To add
Adaptive Cards rendering:

1. Drop `ac-embed.js`, `ac-host.css`, and `ac.wasm` into the host's
   static asset directory.
2. Add the `htmx:beforeSwap` handler from `index.html` somewhere
   that runs on every page that needs cards.
3. Use `hx-get="/your/card/endpoint"` + `hx-target="#card-mount"`
   anywhere you want a card to render. Your endpoint returns the
   card JSON as it would for any JSON API.

No server-side changes beyond that. The renderer runs entirely in
the browser; the server only emits card JSON.
