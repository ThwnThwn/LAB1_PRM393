const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function createAppContext(href = "http://localhost:8080/fap-demo/") {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "fap-demo", "app.js"),
    "utf8",
  );
  const withoutStartup = source.replace(/\binitialize\(\);\s*$/, "");
  assert.notEqual(withoutStartup, source, "app.js startup call changed");

  const elements = new Map();
  const location = { href };
  const element = (selector) => {
    if (!elements.has(selector)) {
      elements.set(selector, {
        listeners: new Map(),
        addEventListener(name, listener) { this.listeners.set(name, listener); },
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
      location,
      history: { replaceState(_state, _title, url) { location.href = new URL(url, location.href).href; } },
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

test("class and subject filters narrow sessions and select the latest match", async () => {
  const context = createAppContext();
  context.sessions = [
    { sessionId: "hcm-2", classCode: "SE1920", subjectCode: "HCM202", slot: 2, date: "2026-09-25", isOpen: false },
    { sessionId: "prn-1", classCode: "SE1917", subjectCode: "PRN232", slot: 1, date: "2026-09-24", isOpen: true },
    { sessionId: "hcm-1", classCode: "SE1920", subjectCode: "HCM202", slot: 1, date: "2026-09-22", isOpen: false },
    { sessionId: "exe-1", classCode: "SE1920", subjectCode: "EXE201", slot: 3, date: "2026-09-21", isOpen: false },
  ];
  context.refreshed = [];
  vm.runInContext("state.sessions = sessions; state.sessionsLoading = false; refreshData = async () => refreshed.push(state.selectedSessionId); renderSessionPicker()", context);

  const classFilter = context.document.querySelector("#class-filter");
  const subjectFilter = context.document.querySelector("#subject-filter");
  classFilter.value = "SE1920";
  await classFilter.listeners.get("change")();
  assert.equal(vm.runInContext("state.selectedSessionId", context), "hcm-2");
  assert.equal(vm.runInContext("state.subjectFilter", context), "");
  assert.match(subjectFilter.innerHTML, /HCM202/);
  assert.match(subjectFilter.innerHTML, /EXE201/);
  assert.doesNotMatch(subjectFilter.innerHTML, /PRN232/);

  subjectFilter.value = "EXE201";
  await subjectFilter.listeners.get("change")();
  assert.equal(vm.runInContext("state.selectedSessionId", context), "exe-1");
  assert.deepEqual(context.refreshed, ["hcm-2", "exe-1"]);

  classFilter.value = "SE1917";
  await classFilter.listeners.get("change")();
  assert.equal(vm.runInContext("state.subjectFilter", context), "PRN232");
  assert.equal(subjectFilter.value, "PRN232");
  assert.equal(vm.runInContext("state.selectedSessionId", context), "prn-1");
  assert.doesNotMatch(context.window.location.href, /sessionId=/);
});

test("one-subject class skips session selection and follows its latest date", async () => {
  const context = createAppContext();
  context.sessions = [
    { sessionId: "old", classCode: "SE1801", subjectCode: "PRM393", slot: 2, date: "2026-09-21" },
    { sessionId: "new", classCode: "SE1801", subjectCode: "PRM393", slot: 1, date: "2026-09-25" },
  ];
  context.refreshed = [];
  vm.runInContext("state.sessions = sessions; state.sessionsLoading = false; refreshData = async () => refreshed.push(state.selectedSessionId); renderSessionPicker()", context);

  const classFilter = context.document.querySelector("#class-filter");
  classFilter.value = "SE1801";
  await classFilter.listeners.get("change")();
  assert.equal(vm.runInContext("state.subjectFilter", context), "PRM393");
  assert.equal(context.document.querySelector("#subject-filter").value, "PRM393");
  assert.equal(vm.runInContext("state.selectedSessionId", context), "new");
  assert.deepEqual(context.refreshed, ["new"]);
  assert.match(context.document.querySelector("#session-picker-help").textContent, /chỉ có một môn học/);
  assert.doesNotMatch(fs.readFileSync(path.join(__dirname, "..", "fap-demo", "index.html"), "utf8"), /id="session-picker"/);
});

test("session polling follows a newer matching date without losing unsaved drafts", async () => {
  const context = createAppContext();
  context.sessions = [
    { sessionId: "old", classCode: "SE1801", subjectCode: "PRM393", slot: 2, date: "2026-09-21" },
    { sessionId: "new", classCode: "SE1801", subjectCode: "PRM393", slot: 1, date: "2026-09-25" },
  ];
  context.refreshed = [];
  context.fetch = async () => ({ ok: true, json: async () => ({ sessions: context.sessions }) });
  vm.runInContext(`
    state.sessions = [sessions[0]];
    state.sessionsLoading = false;
    state.classFilter = "SE1801";
    state.subjectFilter = "PRM393";
    state.selectedSessionId = "old";
    state.drafts.set("A", "PRESENT");
    state.dirty.add("A");
    refreshData = async () => refreshed.push(state.selectedSessionId);
  `, context);

  await vm.runInContext("loadSessions()", context);
  assert.equal(vm.runInContext("state.selectedSessionId", context), "old");
  assert.equal(vm.runInContext('state.drafts.get("A")', context), "PRESENT");
  assert.deepEqual(context.refreshed, []);

  vm.runInContext("state.dirty.clear()", context);
  await vm.runInContext("loadSessions()", context);
  assert.equal(vm.runInContext("state.selectedSessionId", context), "new");
  assert.deepEqual(context.refreshed, ["new"]);
});

test("live session opening advances a filtered class but not a pinned link", () => {
  const makeContext = (href) => {
    const context = createAppContext(href);
    let liveSource;
    context.window.EventSource = class {
      constructor() { this.listeners = new Map(); liveSource = this; }
      addEventListener(name, listener) { this.listeners.set(name, listener); }
    };
    vm.runInContext(`
      state.sessions = [{ sessionId: "old", classCode: "SE1801", subjectCode: "PRM393", date: "2026-09-21", students: [] }];
      state.classFilter = "SE1801";
      state.subjectFilter = "PRM393";
      state.selectedSessionId = "old";
      connectLiveUpdates();
    `, context);
    return { context, liveSource };
  };
  const newSnapshot = {
    sessionId: "new", classCode: "SE1801", subjectCode: "PRM393",
    date: "2026-09-25", students: [],
  };

  const automatic = makeContext("http://localhost:8080/fap-demo/");
  automatic.liveSource.listeners.get("attendance")({
    data: JSON.stringify({ eventName: "SessionOpened", snapshot: newSnapshot }),
  });
  assert.equal(vm.runInContext("state.selectedSessionId", automatic.context), "new");
  assert.equal(vm.runInContext("state.snapshot.sessionId", automatic.context), "new");

  const pinned = makeContext("http://localhost:8080/fap-demo/?sessionId=old");
  pinned.liveSource.listeners.get("attendance")({
    data: JSON.stringify({ eventName: "SessionOpened", snapshot: newSnapshot }),
  });
  assert.equal(vm.runInContext("state.selectedSessionId", pinned.context), "old");
  assert.equal(vm.runInContext("state.snapshot", pinned.context), null);
});

test("direct session link initializes class and subject filters", async () => {
  const context = createAppContext("http://localhost:8080/fap-demo/?sessionId=hcm-1");
  context.fetch = async () => ({
    ok: true,
    json: async () => ({ sessions: [
      { sessionId: "hcm-1", classCode: "SE1920", subjectCode: "HCM202", slot: 1, date: "2026-09-22" },
      { sessionId: "hcm-2", classCode: "SE1920", subjectCode: "HCM202", slot: 1, date: "2026-09-25" },
    ] }),
  });
  await vm.runInContext("loadSessions()", context);
  assert.equal(vm.runInContext("state.classFilter", context), "SE1920");
  assert.equal(vm.runInContext("state.subjectFilter", context), "HCM202");
  assert.equal(vm.runInContext("state.selectedSessionId", context), "hcm-1");
  assert.equal(context.document.querySelector("#class-filter").value, "SE1920");
  assert.equal(context.document.querySelector("#subject-filter").value, "HCM202");
  assert.match(context.window.location.href, /sessionId=hcm-1/);

  vm.runInContext("refreshData = async () => {}", context);
  const subjectFilter = context.document.querySelector("#subject-filter");
  subjectFilter.value = "HCM202";
  await subjectFilter.listeners.get("change")();
  assert.equal(vm.runInContext("state.selectedSessionId", context), "hcm-2");
  assert.doesNotMatch(context.window.location.href, /sessionId=/);
});

test("unsaved attendance locks both filters", () => {
  const context = createAppContext();
  vm.runInContext(`
    state.sessions = [{ sessionId: "hcm-1", classCode: "SE1920", subjectCode: "HCM202", slot: 1 }];
    state.sessionsLoading = false;
    state.dirty.add("SE192001");
    renderSessionPicker();
  `, context);
  assert.equal(context.document.querySelector("#class-filter").disabled, true);
  assert.equal(context.document.querySelector("#subject-filter").disabled, true);
});

test("a stale attendance read cannot replace a newly filtered session", async () => {
  const context = createAppContext();
  let resolveOld;
  context.fetch = (url) => url.includes("old-session")
    ? new Promise((resolve) => { resolveOld = resolve; })
    : Promise.resolve({
      ok: true,
      json: async () => ({
        sessionId: "new-session", classCode: "SE1920", subjectCode: "HCM202",
        slot: 1, students: [],
      }),
    });
  vm.runInContext(`
    state.sessions = [
      { sessionId: "old-session", classCode: "SE1917", subjectCode: "PRN232", slot: 1 },
      { sessionId: "new-session", classCode: "SE1920", subjectCode: "HCM202", slot: 1 },
    ];
    state.sessionsLoading = false;
    state.selectedSessionId = "old-session";
    state.classFilter = "SE1920";
    state.subjectFilter = "HCM202";
  `, context);
  const oldRead = vm.runInContext("refreshData({ force: true })", context);
  await vm.runInContext('selectSession("new-session")', context);
  resolveOld({
    ok: true,
    json: async () => ({ sessionId: "old-session", classCode: "SE1917", students: [] }),
  });
  await oldRead;
  assert.equal(vm.runInContext("state.snapshot.sessionId", context), "new-session");
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

  context.fetch = async () => ({
    ok: true,
    json: async () => ({ sessions: [context.openSnapshot] }),
  });
  await vm.runInContext("loadSessions()", context);
  assert.equal(vm.runInContext("state.sessions[0].isOpen", context), false);
});
