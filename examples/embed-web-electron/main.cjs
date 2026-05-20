// wasm-port: Electron main process. Creates a single BrowserWindow
// that loads `index.html` from the same directory. The renderer
// process treats the file:// scheme as a same-origin web context,
// so the renderer's `fetch("./ac.wasm")` + dynamic ESM imports work
// without extra plumbing.

const { app, BrowserWindow } = require("electron");
const path = require("node:path");

function createWindow() {
  const win = new BrowserWindow({
    width: 960,
    height: 720,
    title: "Adaptive Cards × Electron",
    webPreferences: {
      // Default-on contextIsolation + sandbox keeps the renderer
      // hermetic. The renderer uses the standard browser fetch +
      // WebAssembly globals; no preload bridge is needed.
      contextIsolation: true,
      sandbox: true,
    },
  });
  win.loadFile(path.join(__dirname, "index.html"));
}

app.whenReady().then(createWindow);

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});
