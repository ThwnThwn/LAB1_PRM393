const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function createAppContext() {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "fap-demo", "app.js"),
    "utf8",
  );
  const withoutStartup = source.replace(/\binitialize\(\);\s*$/, "");
  assert.notEqual(withoutStartup, source, "app.js startup call changed");

  const elements = new Map();
  const element = (selector) => {
    if (!elements.has(selector)) {
      elements.set(selector, {
        addEventListener() {},
        classList: { toggle() {} },
        dataset: {},
        firstChild: { textContent: "" },
        hidden: false,
      });
    }
    return elements.get(selector);
  };
  const context = vm.createContext({
    URL,
    document: {
      querySelector: element,
      addEventListener() {},
    },
    window: {
      location: { href: "http://localhost:8080/fap-demo/" },
      history: { replaceState() {} },
      clearTimeout() {},
      setTimeout() { return 1; },
    },
  });
  vm.runInContext(withoutStartup, context);
  return context;
}

test("desktop updates replace only conflicting unsaved web drafts", () => {
  const context = createAppContext();
  context.initial = {
    sessionId: "session-1",
    students: [
      { rollNo: "A", status: "NOT CHECKED" },
      { rollNo: "B", status: "NOT CHECKED" },
    ],
  };
  vm.runInContext("mergeSnapshot(initial, true)", context);
  vm.runInContext(`
    state.drafts.set("A", "PRESENT");
    state.dirty.add("A");
    state.baseStatuses.set("A", "NOT CHECKED");
    state.drafts.set("B", "ABSENT");
    state.dirty.add("B");
    state.baseStatuses.set("B", "NOT CHECKED");
  `, context);

  context.updated = {
    sessionId: "session-1",
    students: [
      { rollNo: "A", status: "ABSENT" },
      { rollNo: "B", status: "NOT CHECKED" },
    ],
  };
  vm.runInContext("mergeSnapshot(updated, false)", context);

  assert.equal(vm.runInContext('state.dirty.has("A")', context), false);
  assert.equal(vm.runInContext('state.drafts.get("A")', context), "ABSENT");
  assert.equal(vm.runInContext('state.dirty.has("B")', context), true);
  assert.equal(vm.runInContext('state.drafts.get("B")', context), "ABSENT");
});

test("switching sessions clears drafts from the previous class", () => {
  const context = createAppContext();
  context.initial = {
    sessionId: "session-1",
    students: [{ rollNo: "A", status: "NOT CHECKED" }],
  };
  vm.runInContext("mergeSnapshot(initial, true)", context);
  vm.runInContext(`
    state.drafts.set("A", "PRESENT");
    state.dirty.add("A");
    state.baseStatuses.set("A", "NOT CHECKED");
  `, context);

  context.updated = {
    sessionId: "session-2",
    students: [{ rollNo: "B", status: "PRESENT" }],
  };
  vm.runInContext("mergeSnapshot(updated, false)", context);

  assert.equal(vm.runInContext("state.dirty.size", context), 0);
  assert.equal(vm.runInContext("state.baseStatuses.size", context), 0);
  assert.equal(vm.runInContext('state.drafts.get("B")', context), "PRESENT");
});
