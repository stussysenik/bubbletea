// Browser-side key codes match the numeric normalization expected by the
// freestanding Zig host. Printable keys still use Unicode scalar values.
const SPECIAL_KEYS = Object.freeze({
  ArrowUp: 1001,
  ArrowDown: 1002,
  ArrowLeft: 1003,
  ArrowRight: 1004,
  Home: 1005,
  End: 1006,
  Delete: 1007,
  PageUp: 1008,
  PageDown: 1009,
  ShiftTab: 1010,
});

const POINTER_BUTTONS = Object.freeze({
  0: 1,
  1: 2,
  2: 3,
});

const POINTER_ACTIONS = Object.freeze({
  press: 1,
  release: 2,
  drag: 3,
  move: 4,
  scroll: 5,
});

const MODIFIER_SHIFT = 1;
const MODIFIER_ALT = 2;
const MODIFIER_CTRL = 4;
const textDecoder = new TextDecoder();
const textEncoder = new TextEncoder();

const state = {
  exports: null,
  lastFrame: "",
  lastTreeJson: "",
  lastTimestamp: 0,
  lastCols: 0,
  lastRows: 0,
  focused: false,
};

const elements = {
  shell: document.getElementById("terminal-shell"),
  tree: document.getElementById("tree-output"),
  output: document.getElementById("terminal-output"),
  measure: document.getElementById("cell-measure"),
  runtime: document.getElementById("status-runtime"),
  size: document.getElementById("status-size"),
  focus: document.getElementById("status-focus"),
  frame: document.getElementById("status-frame"),
  focusButton: document.getElementById("focus-terminal"),
};

boot().catch((error) => {
  setRuntimeStatus(`boot failed: ${error.message}`);
  console.error(error);
});

async function boot() {
  const { instance } = await loadWasm("./bubbletea-zig-showcase.wasm");
  state.exports = instance.exports;

  if (!state.exports.bt_init()) {
    throw new Error("runtime rejected bt_init");
  }

  bindHostEvents();
  syncGeometry();
  renderOutputs();
  setRuntimeStatus("runtime ready");
  focusTerminal();
  requestAnimationFrame(frameLoop);
}

// The host is intentionally static-file friendly so `zig build web` can emit a
// directory that works behind any plain HTTP server.
async function loadWasm(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`unable to fetch ${url}`);
  }

  if (WebAssembly.instantiateStreaming) {
    try {
      return await WebAssembly.instantiateStreaming(response.clone(), {});
    } catch {
      // Static file servers do not always return `application/wasm`, so keep a
      // byte-buffer fallback for simple local hosting.
    }
  }

  const bytes = await response.arrayBuffer();
  return WebAssembly.instantiate(bytes, {});
}

function bindHostEvents() {
  const resizeObserver = new ResizeObserver(() => {
    syncGeometry();
  });
  resizeObserver.observe(elements.shell);

  elements.focusButton.addEventListener("click", () => {
    focusTerminal();
  });

  elements.shell.addEventListener("focus", () => {
    updateFocus(true);
  });
  elements.shell.addEventListener("blur", () => {
    updateFocus(false);
  });
  elements.shell.addEventListener("keydown", handleKeyDown);
  elements.shell.addEventListener("paste", handlePaste);
  elements.shell.addEventListener("mousedown", handleMouseDown);
  elements.shell.addEventListener("mouseup", handleMouseUp);
  elements.shell.addEventListener("mousemove", handleMouseMove);
  elements.shell.addEventListener("wheel", handleWheel, { passive: false });
  elements.shell.addEventListener("contextmenu", (event) => {
    event.preventDefault();
  });

  window.addEventListener("focus", () => {
    if (document.activeElement === elements.shell) {
      updateFocus(true);
    }
  });
  window.addEventListener("blur", () => {
    updateFocus(false);
  });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      updateFocus(false);
      return;
    }
    if (document.activeElement === elements.shell) {
      updateFocus(true);
    }
  });
}

function focusTerminal() {
  elements.shell.focus({ preventScroll: true });
}

function handleKeyDown(event) {
  if (!state.exports || event.metaKey) return;

  const keyCode = normalizeKey(event);
  if (keyCode == null) return;

  event.preventDefault();
  sendRuntime(() => state.exports.bt_send_key(keyCode), "key");
}

function normalizeKey(event) {
  if (event.ctrlKey && !event.altKey) {
    const lowerKey = event.key.toLowerCase();
    if (lowerKey === "c") return 3;
    if (lowerKey === "z") return 26;
    return null;
  }

  if (event.key === "Tab" && event.shiftKey) return SPECIAL_KEYS.ShiftTab;
  if (event.key in SPECIAL_KEYS) return SPECIAL_KEYS[event.key];

  switch (event.key) {
    case "Tab":
      return 9;
    case "Enter":
      return 13;
    case "Escape":
      return 27;
    case "Backspace":
      return 127;
    default:
      break;
  }

  if (event.key.length !== 1 || event.altKey) return null;
  return event.key.codePointAt(0);
}

function handlePaste(event) {
  if (!state.exports) return;
  const text = event.clipboardData?.getData("text/plain");
  if (!text) return;

  event.preventDefault();
  sendPasteText(text);
}

// Pasted text is chunked through the runtime scratch buffer so large payloads
// never require one giant allocation on the JS side.
function sendPasteText(text) {
  const capacity = state.exports.bt_input_capacity();
  let remaining = text;

  while (remaining.length > 0) {
    const ptr = state.exports.bt_input_ptr();
    const scratch = new Uint8Array(state.exports.memory.buffer, ptr, capacity);
    const result = textEncoder.encodeInto(remaining, scratch);
    if (!result.written || !result.read) {
      setRuntimeStatus("paste payload exceeded bridge capacity");
      return;
    }

    const accepted = state.exports.bt_send_paste(result.written);
    if (!accepted) {
      setRuntimeStatus("runtime rejected paste");
      return;
    }

    remaining = remaining.slice(result.read);
  }

  renderOutputs();
}

function handleMouseDown(event) {
  focusTerminal();
  event.preventDefault();
  dispatchMouse(event, POINTER_ACTIONS.press);
}

function handleMouseUp(event) {
  if (!state.exports) return;
  event.preventDefault();
  dispatchMouse(event, POINTER_ACTIONS.release);
}

function handleMouseMove(event) {
  if (!state.exports) return;
  const action = event.buttons ? POINTER_ACTIONS.drag : POINTER_ACTIONS.move;
  dispatchMouse(event, action);
}

function handleWheel(event) {
  if (!state.exports) return;
  event.preventDefault();

  const button =
    Math.abs(event.deltaX) > Math.abs(event.deltaY)
      ? event.deltaX < 0
        ? 6
        : 7
      : event.deltaY < 0
        ? 4
        : 5;

  dispatchMouse(event, POINTER_ACTIONS.scroll, button);
}

function dispatchMouse(event, action, overrideButton) {
  const position = pointerToCell(event);
  const button = overrideButton ?? normalizeMouseButton(event, action);
  if (button == null) return;

  sendRuntime(
    () =>
      state.exports.bt_send_mouse(
        button,
        action,
        position.x,
        position.y,
        mouseModifiers(event),
      ),
    "mouse",
  );
}

function normalizeMouseButton(event, action) {
  if (action === POINTER_ACTIONS.move) return 0;
  if (action === POINTER_ACTIONS.drag) {
    if (event.buttons & 1) return 1;
    if (event.buttons & 4) return 2;
    if (event.buttons & 2) return 3;
    return 0;
  }
  return POINTER_BUTTONS[event.button] ?? 0;
}

function mouseModifiers(event) {
  return (
    (event.shiftKey ? MODIFIER_SHIFT : 0) |
    (event.altKey ? MODIFIER_ALT : 0) |
    (event.ctrlKey ? MODIFIER_CTRL : 0)
  );
}

function pointerToCell(event) {
  const rect = elements.shell.getBoundingClientRect();
  const metrics = shellMetrics();
  const { cellWidth, cellHeight } = measureCell();
  const x = clampCell(
    Math.floor((event.clientX - rect.left - metrics.leftInset) / cellWidth),
    state.lastCols,
  );
  const y = clampCell(
    Math.floor((event.clientY - rect.top - metrics.topInset) / cellHeight),
    state.lastRows,
  );
  return { x, y };
}

function measureCell() {
  const rect = elements.measure.getBoundingClientRect();
  return {
    cellWidth: Math.max(1, rect.width / 10),
    cellHeight: Math.max(1, rect.height / 2),
  };
}

function syncGeometry() {
  if (!state.exports) return;

  const metrics = shellMetrics();
  const { cellWidth, cellHeight } = measureCell();
  const cols = Math.max(20, Math.floor(metrics.width / cellWidth));
  const rows = Math.max(12, Math.floor(metrics.height / cellHeight));

  if (cols === state.lastCols && rows === state.lastRows) return;
  state.lastCols = cols;
  state.lastRows = rows;
  elements.size.textContent = `${cols} cols x ${rows} rows`;

  sendRuntime(() => state.exports.bt_resize(cols, rows), "resize");
}

function updateFocus(focused) {
  if (!state.exports || state.focused === focused) return;
  state.focused = focused;
  elements.focus.textContent = focused ? "focused" : "blurred";
  sendRuntime(() => state.exports.bt_set_focus(focused), "focus");
}

function frameLoop(timestamp) {
  if (state.exports) {
    const delta = state.lastTimestamp === 0 ? 16 : Math.max(0, Math.min(250, timestamp - state.lastTimestamp));
    state.lastTimestamp = timestamp;
    if (state.exports.bt_tick(Math.round(delta))) {
      renderOutputs();
    }
  }

  requestAnimationFrame(frameLoop);
}

function sendRuntime(call, label) {
  if (!call()) {
    setRuntimeStatus(`runtime rejected ${label}`);
    return;
  }
  renderOutputs();
}

function renderOutputs() {
  const frame = readFrame();
  if (frame !== state.lastFrame) {
    state.lastFrame = frame;
    elements.output.textContent = frame;
    elements.frame.textContent = `${textEncoder.encode(frame).length} bytes`;
  }

  const treeJson = readTreeJson();
  if (treeJson === state.lastTreeJson) return;

  state.lastTreeJson = treeJson;

  try {
    renderTree(JSON.parse(treeJson));
  } catch (error) {
    setRuntimeStatus(`tree parse failed: ${error.message}`);
  }
}

function readFrame() {
  const ptr = state.exports.bt_render_ptr();
  const len = state.exports.bt_render_len();
  const bytes = new Uint8Array(state.exports.memory.buffer, ptr, len);
  return textDecoder.decode(bytes);
}

function readTreeJson() {
  const ptr = state.exports.bt_tree_ptr();
  const len = state.exports.bt_tree_len();
  const bytes = new Uint8Array(state.exports.memory.buffer, ptr, len);
  return textDecoder.decode(bytes);
}

function setRuntimeStatus(message) {
  elements.runtime.textContent = message;
}

function shellMetrics() {
  const styles = getComputedStyle(elements.shell);
  const leftInset = Number.parseFloat(styles.paddingLeft) || 0;
  const rightInset = Number.parseFloat(styles.paddingRight) || 0;
  const topInset = Number.parseFloat(styles.paddingTop) || 0;
  const bottomInset = Number.parseFloat(styles.paddingBottom) || 0;

  return {
    width: Math.max(1, elements.shell.clientWidth - leftInset - rightInset),
    height: Math.max(1, elements.shell.clientHeight - topInset - bottomInset),
    leftInset,
    topInset,
    bottomInset,
  };
}

function clampCell(value, max) {
  return Math.max(0, Math.min(Math.max(0, max - 1), value));
}

// The DOM host deliberately mirrors the semantic Zig node types instead of
// trying to parse the flattened text frame back into panels.
function renderTree(snapshot) {
  const metrics = measureCell();
  elements.tree.replaceChildren(buildTreeNode(snapshot, metrics));
}

function buildTreeNode(node, metrics) {
  switch (node.kind) {
    case "text":
      return buildTextNode(node, metrics);
    case "row":
    case "column":
      return buildStackNode(node, metrics);
    case "box":
      return buildBoxNode(node, metrics);
    case "spacer":
      return buildSpacerNode(node, metrics);
    case "rule":
      return buildRuleNode(node, metrics);
    default:
      return buildUnknownNode(node);
  }
}

function buildTextNode(node, metrics) {
  const element = document.createElement("div");
  element.className = `ui-node ui-text tone-${node.tone} align-${node.alignment}`;
  element.textContent = node.content;
  applyNodeLayout(element, node.layout, metrics, { exactWidth: true });
  return element;
}

function buildStackNode(node, metrics) {
  const element = document.createElement("div");
  element.className = `ui-node ui-${node.kind}`;
  applyNodeLayout(element, node.layout, metrics, { exactWidth: true });

  if (node.kind === "row") {
    element.style.columnGap = cellsToPixels(node.gap, metrics);
    element.style.rowGap = "0px";
  } else {
    element.style.rowGap = linesToPixels(node.gap, metrics);
    element.style.columnGap = "0px";
  }

  for (const child of node.children) {
    element.append(buildTreeNode(child, metrics));
  }

  return element;
}

function buildBoxNode(node, metrics) {
  const element = document.createElement("section");
  element.className = `ui-node ui-box tone-${node.tone} border-${node.border}`;
  applyNodeLayout(element, node.layout, metrics, { exactWidth: true });

  if (node.title) {
    const title = document.createElement("div");
    title.className = `ui-box__title tone-${node.tone}`;
    title.textContent = node.title;
    element.append(title);
  }

  const body = document.createElement("div");
  body.className = `ui-box__body align-${node.alignment}`;
  body.style.padding = formatPadding(node.padding, metrics);
  body.style.minWidth = cellsToPixels(innerWidth(node), metrics);
  body.style.minHeight = linesToPixels(innerHeight(node), metrics);
  body.style.alignItems = alignToItems(node.alignment);
  body.append(buildTreeNode(node.child, metrics));
  element.append(body);
  return element;
}

function buildSpacerNode(node, metrics) {
  const element = document.createElement("div");
  element.className = "ui-node ui-spacer";
  applyNodeLayout(element, node.layout, metrics, {
    exactWidth: true,
    exactHeight: true,
  });
  return element;
}

function buildRuleNode(node, metrics) {
  const element = document.createElement("div");
  element.className = `ui-node ui-rule tone-${node.tone}`;
  applyNodeLayout(element, node.layout, metrics, { exactWidth: true });
  element.textContent = node.glyph.repeat(Math.max(1, node.width));
  return element;
}

function buildUnknownNode(node) {
  const element = document.createElement("div");
  element.className = "ui-node ui-text tone-warning";
  element.textContent = `unknown node: ${node.kind}`;
  return element;
}

function applyNodeLayout(element, layout, metrics, options = {}) {
  if (!layout) return;

  element.dataset.gridX = String(layout.x);
  element.dataset.gridY = String(layout.y);
  element.dataset.gridWidth = String(layout.width);
  element.dataset.gridHeight = String(layout.height);
  element.style.minWidth = cellsToPixels(layout.width, metrics);
  element.style.minHeight = linesToPixels(layout.height, metrics);

  if (options.exactWidth) {
    element.style.width = cellsToPixels(layout.width, metrics);
  }
  if (options.exactHeight) {
    element.style.height = linesToPixels(layout.height, metrics);
  }
}

function cellsToPixels(value, metrics) {
  return `${Math.max(0, value) * metrics.cellWidth}px`;
}

function linesToPixels(value, metrics) {
  return `${Math.max(0, value) * metrics.cellHeight}px`;
}

function innerWidth(node) {
  const border = node.border === "single" ? 2 : 0;
  return Math.max(0, node.layout.width - border - node.padding.left - node.padding.right);
}

function innerHeight(node) {
  const border = node.border === "single" ? 2 : 0;
  return Math.max(0, node.layout.height - border - node.padding.top - node.padding.bottom);
}

function alignToItems(alignment) {
  switch (alignment) {
    case "center":
      return "center";
    case "right":
      return "flex-end";
    default:
      return "flex-start";
  }
}

function formatPadding(padding, metrics) {
  const top = linesToPixels(padding.top, metrics);
  const right = cellsToPixels(padding.right, metrics);
  const bottom = linesToPixels(padding.bottom, metrics);
  const left = cellsToPixels(padding.left, metrics);
  return `${top} ${right} ${bottom} ${left}`;
}
