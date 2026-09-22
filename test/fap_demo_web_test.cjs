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

test("selected session is added to the attendance endpoint", () => {
  const context = createAppContext();
  assert.equal(
    vm.runInContext('attendanceEndpoint("session 01")', context),
    "/api/attendance?sessionId=session%2001",
  );
  assert.equal(
    vm.runInContext('attendanceEndpoint("")', context),
    "/api/attendance",
  );
});

test("class picker label includes slot, date and session state", () => {
  const context = createAppContext();
  context.session = {
    subjectCode: "EXE201",
    slot: 2,
    date: "2026-09-22",
    isOpen: false,
  };
  assert.equal(
    vm.runInContext("sessionOptionLabel(session)", context),
    "EXE201 · Slot 2 · 22/09/2026 · Đã đóng",
  );
});

test("initial load prioritizes attendance before slower Google Sheets checks", async () => {
  const context = createAppContext();
  context.events = [];
  context.window.setInterval = () => {
    context.events.push("poll timer");
    return 1;
  };
  const startup = vm.runInContext(`
    refreshData = async () => events.push("attendance");
    loadServiceStatus = async () => events.push("health");
    loadSessions = async () => events.push("sessions");
    initialize();
  `, context);
  await startup;
  assert.deepEqual(context.events, [
    "poll timer", "poll timer", "attendance", "health", "sessions",
  ]);
});

test("failed attendance reads retry automatically and recover without manual reload", async () => {
  const context = createAppContext();
  let attempts = 0;
  context.fetch = async () => {
    attempts += 1;
    if (attempts === 1) {
      return {
        ok: false,
        status: 502,
        json: async () => ({ message: "Google tạm thời trả HTML 404" }),
      };
    }
    return {
      ok: true,
      json: async () => ({
        status: "success",
        sessionId: "session-1",
        classCode: "SE1917",
        subjectCode: "PRN232",
        slot: 1,
        count: 1,
        students: [{ rollNo: "SE191709", status: "ABSENT" }],
      }),
    };
  };

  await vm.runInContext("refreshData()", context);
  assert.equal(vm.runInContext("state.retryDelayMs", context), 5000);
  assert.match(context.document.querySelector("#system-message").textContent, /tự thử lại/);
  await vm.runInContext("refreshData()", context);
  assert.equal(attempts, 1, "background polling observes the retry backoff");

  await vm.runInContext("refreshData({ force: true })", context);
  assert.equal(attempts, 2);
  assert.equal(vm.runInContext("state.retryDelayMs", context), 0);
  assert.equal(vm.runInContext("state.connected", context), true);
  assert.equal(vm.runInContext("state.snapshot.students[0].status", context), "ABSENT");
});

test("desktop close reaches the open FAP page even when a Sheet read is stale", async () => {
  const context = createAppContext();
  let liveSource;
  context.window.EventSource = class {
    constructor(url) {
      assert.equal(url, "/api/updates");
      this.listeners = new Map();
      liveSource = this;
    }
    addEventListener(name, listener) { this.listeners.set(name, listener); }
  };
  context.openSnapshot = {
    sessionId: "session-1",
    classCode: "SE1917",
    subjectCode: "PRN232",
    slot: 1,
    isOpen: true,
    count: 1,
    students: [{ rollNo: "SE191709", status: "NOT CHECKED" }],
  };
  vm.runInContext("mergeSnapshot(openSnapshot, true); connectLiveUpdates()", context);

  let resolveFetch;
  context.fetch = () => new Promise((resolve) => { resolveFetch = resolve; });
  const stalePoll = vm.runInContext("refreshData()", context);

  const closedSnapshot = {
    ...context.openSnapshot,
    isOpen: false,
    students: [{ rollNo: "SE191709", status: "ABSENT" }],
  };
  liveSource.listeners.get("attendance")({
    data: JSON.stringify({ eventName: "SessionClosed", snapshot: closedSnapshot }),
  });
  resolveFetch({ ok: true, json: async () => context.openSnapshot });
  await stalePoll;

  assert.equal(vm.runInContext("state.snapshot.isOpen", context), false);
  assert.equal(vm.runInContext("state.snapshot.students[0].status", context), "ABSENT");
  assert.equal(vm.runInContext("state.sessions[0].isOpen", context), false);
  assert.match(vm.runInContext("sessionOptionLabel(state.sessions[0])", context), /Đã đóng/);

  context.fetch = async () => ({
    ok: true,
    json: async () => ({ sessions: [context.openSnapshot] }),
  });
  await vm.runInContext("loadSessions()", context);
  assert.equal(vm.runInContext("state.sessions[0].isOpen", context), false);
});
