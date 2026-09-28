const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function templateSource() {
  const dart = fs.readFileSync(
    path.join(__dirname, "..", "lib", "services", "google_sheets_service.dart"),
    "utf8",
  );
  const match = dart.match(/sampleAppsScriptCode\s*=>\s*'''([\s\S]*?)''';/);
  assert.ok(match, "Apps Script template was not found");
  return match[1].replaceAll("\\\\", "\\");
}

class MemoryRange {
  constructor(sheet, row = 1, column = 1, rowCount, columnCount) {
    this.sheet = sheet;
    this.row = row;
    this.column = column;
    this.rowCount = rowCount;
    this.columnCount = columnCount;
  }

  getValues() {
    if (this.rowCount == null) return this.sheet.values.map((row) => [...row]);
    return Array.from({ length: this.rowCount }, (_, r) =>
      Array.from(
        { length: this.columnCount },
        (_, c) => this.sheet.values[this.row - 1 + r]?.[this.column - 1 + c] ?? "",
      ),
    );
  }

  setValues(values) {
    for (let r = 0; r < values.length; r++) {
      const targetRow = this.row - 1 + r;
      this.sheet.values[targetRow] ??= [];
      for (let c = 0; c < values[r].length; c++) {
        this.sheet.values[targetRow][this.column - 1 + c] = values[r][c];
      }
    }
    return this;
  }

  setFontWeight() { return this; }
  setBackground() { return this; }
  setFontColor() { return this; }
}

class MemorySheet {
  constructor(book, name, values = []) {
    this.book = book;
    this.name = name;
    this.values = values.map((row) => [...row]);
  }

  getLastRow() { return this.values.length; }
  getDataRange() { return new MemoryRange(this); }
  getRange(row, column, rowCount, columnCount) {
    return new MemoryRange(this, row, column, rowCount, columnCount);
  }
  clearContents() { this.values = []; }
  setFrozenRows() {}
  getName() { return this.name; }
  setName(name) { this.name = name; return this; }
  copyTo(book) {
    const copy = new MemorySheet(book, `${this.name} copy`, this.values);
    book.sheets.push(copy);
    return copy;
  }
}

class MemoryBook {
  constructor(name = "Attendance", withDefault = false) {
    this.name = name;
    this.sheets = withDefault ? [new MemorySheet(this, "Sheet1")] : [];
  }

  getName() { return this.name; }
  getUrl() { return "https://docs.google.com/spreadsheets/d/backup"; }
  getSheetByName(name) { return this.sheets.find((sheet) => sheet.name === name) ?? null; }
  insertSheet(name) {
    const sheet = new MemorySheet(this, name);
    this.sheets.push(sheet);
    return sheet;
  }
  getSheets() { return [...this.sheets]; }
  deleteSheet(sheet) { this.sheets = this.sheets.filter((item) => item !== sheet); }
}

function createContext(seed = {}) {
  const book = new MemoryBook();
  for (const [name, values] of Object.entries(seed)) {
    book.sheets.push(new MemorySheet(book, name, values));
  }
  const context = vm.createContext({
    console,
    Date,
    JSON,
    Math,
    Object,
    String,
    Number,
    isNaN,
    SpreadsheetApp: {
      getActiveSpreadsheet: () => book,
      create: (name) => new MemoryBook(name, true),
    },
    Utilities: {
      formatDate: (value, _zone, format) => {
        assert.equal(format === "yyyy-MM-dd" || format === "yyyyMMdd-HHmmss", true);
        let date = new Date(value);
        if (format === "yyyyMMdd-HHmmss") return "20260928-080000";
        date = new Date(date.getTime() + 7 * 60 * 60 * 1000);
        return date.toISOString().slice(0, 10);
      },
    },
    LockService: {
      getScriptLock: () => ({ waitLock() {}, releaseLock() {} }),
    },
    ContentService: {
      MimeType: { JSON: "json" },
      createTextOutput: (text) => ({
        text,
        setMimeType() { return this; },
      }),
    },
  });
  vm.runInContext(templateSource(), context);
  return { book, context };
}

test("Apps Script template parses and normalizes meeting dates", () => {
  const { context } = createContext();
  assert.equal(context.normalizeMeetingDate("2026-09-20T17:00:00Z"), "2026-09-21");
  assert.equal(context.normalizeMeetingDate("2026-09-21"), "2026-09-21");
});

test("normalization keeps one closed session and merges PRESENT attendance", () => {
  const { book, context } = createContext({
    Sessions: [
      contextHeaders("Sessions"),
      ["old", "SE1917", "PRN232", 1, "2026-09-21", true, "2026-09-21T00:00:00Z", "", 10, false, "2026-09-21T01:00:00Z", 3, 20],
      ["new", "SE1917", "PRN232", 1, "2026-09-21", false, "2026-09-21T02:00:00Z", "2026-09-21T03:00:00Z", 10, false, "2026-09-21T03:00:00Z", 0, 20],
    ],
    CourseMeetings: [contextHeaders("CourseMeetings")],
    Attendance: [
      contextHeaders("Attendance"),
      ["old", "SE001", "Student", "s@fpt.edu.vn", "SE1917", "PRN232", 1, "PRESENT", "2026-09-21T00:05:00Z", "", "", ""],
      ["new", "SE001", "Student", "s@fpt.edu.vn", "SE1917", "PRN232", 1, "ABSENT", "", "", "", ""],
    ],
    DeviceBindings: [contextHeaders("DeviceBindings")],
    AuditLog: [contextHeaders("AuditLog")],
  });

  const result = context.normalizeDuplicateSessions("2026-09-28T01:00:00Z");
  assert.equal(result.duplicateGroups, 1);
  assert.equal(result.removedSessions, 1);
  assert.equal(result.closedSessions, 1);
  assert.equal(result.backupUrl, "https://docs.google.com/spreadsheets/d/backup");
  assert.equal(book.getSheetByName("Sessions").values.length, 2);
  assert.equal(book.getSheetByName("Sessions").values[1][5], false);
  assert.equal(book.getSheetByName("Sessions").values[1][7], "2026-09-28T01:00:00Z");
  assert.equal(book.getSheetByName("Attendance").values.length, 2);
  assert.equal(book.getSheetByName("Attendance").values[1][7], "PRESENT");
});

test("normalization closes open sessions even when no duplicates exist", () => {
  const { book, context } = createContext({
    Sessions: [
      contextHeaders("Sessions"),
      ["only", "SE1920", "HCM202", 1, "2026-09-22", true, "2026-09-22T00:00:00Z", "", 10, false, "2026-09-22T01:00:00Z", 1, 20],
    ],
    CourseMeetings: [
      contextHeaders("CourseMeetings"),
      ["SE1920|HCM202|1", "SE1920", "HCM202", 1, 20, "2026-09-22", 1, "only", "OPEN", "2026-09-22T01:00:00Z"],
    ],
    Attendance: [contextHeaders("Attendance")],
    DeviceBindings: [contextHeaders("DeviceBindings")],
    AuditLog: [contextHeaders("AuditLog")],
  });

  const result = context.normalizeDuplicateSessions("2026-09-28T01:00:00Z");
  assert.equal(result.duplicateGroups, 0);
  assert.equal(result.removedSessions, 0);
  assert.equal(result.closedSessions, 1);
  assert.equal(result.backupUrl, "https://docs.google.com/spreadsheets/d/backup");
  assert.equal(book.getSheetByName("Sessions").values[1][5], false);
  assert.equal(book.getSheetByName("CourseMeetings").values[1][8], "CLOSED");
});

function contextHeaders(name) {
  const schemas = {
    Sessions: ["SessionId", "ClassCode", "SubjectCode", "Slot", "SessionDate", "IsOpen", "OpenedAt", "ClosedAt", "LateAfterMinutes", "OtpPaused", "UpdatedAt", "MeetingNumber", "TotalMeetings"],
    CourseMeetings: ["MeetingId", "ClassCode", "SubjectCode", "MeetingNumber", "TotalMeetings", "SessionDate", "Slot", "SessionId", "Status", "UpdatedAt"],
    Attendance: ["SessionId", "RollNo", "FullName", "Email", "ClassCode", "SubjectCode", "Slot", "Status", "CheckinTime", "Notes", "ConfirmationCode", "UpdatedAt"],
    DeviceBindings: ["SessionId", "BindingId", "DeviceCode", "RollNo", "FirstSeen", "LastSeen", "BlockedAttempts", "LastBlockedRollNo", "LastBlockedAt", "UpdatedAt", "DeviceHash", "NetworkHash", "UserAgentHash"],
    AuditLog: ["SessionId", "AuditId", "RollNo", "Action", "PreviousStatus", "NewStatus", "Actor", "Reason", "CreatedAt", "UpdatedAt"],
  };
  return schemas[name];
}
