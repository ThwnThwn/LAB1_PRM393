const POLL_INTERVAL_MS = 5000;
const SESSION_LIST_POLL_INTERVAL_MS = 30000;

// Public launcher uses the query token once to establish an HttpOnly teacher
// cookie. Remove it from the address bar immediately after the page loads.
const launchUrl = new URL(window.location.href);
const initialSessionId = launchUrl.searchParams.get("sessionId") || "";
if (launchUrl.searchParams.has("teacherToken")) {
  launchUrl.searchParams.delete("teacherToken");
  const cleanUrl = `${launchUrl.pathname}${launchUrl.search}${launchUrl.hash}`;
  window.history.replaceState({}, "", cleanUrl);
}

const API = {
  attendance: "/api/attendance",
  health: "/api/health",
  sheets: "/api/config/google-sheets",
  sessions: "/api/sessions?limit=40",
  updates: "/api/updates",
};

const state = {
  snapshot: null,
  sessions: [],
  selectedSessionId: initialSessionId,
  pinnedSessionId: initialSessionId,
  sessionsLoading: true,
  sessionsRefreshing: false,
  sessionsError: "",
  classFilter: "",
  subjectFilter: "",
  filtersHydrated: false,
  filteredEmpty: false,
  selectionSerial: 0,
  refreshRequestId: 0,
  drafts: new Map(),
  dirty: new Set(),
  baseStatuses: new Map(),
  query: "",
  filter: "ALL",
  loading: true,
  refreshing: false,
  saving: false,
  connected: false,
  sheetsConfigured: false,
  sheetsMessage: "",
  toastTimer: null,
  retryDelayMs: 0,
  nextRetryAt: 0,
  liveUpdateSerial: 0,
  liveSource: null,
};

const elements = {
  rows: document.querySelector("#student-rows"),
  refreshButton: document.querySelector("#refresh-button"),
  saveButton: document.querySelector("#save-button"),
  changeCount: document.querySelector("#change-count"),
  search: document.querySelector("#student-search"),
  filter: document.querySelector("#status-filter"),
  syncState: document.querySelector("#sync-state"),
  syncLabel: document.querySelector("#sync-label"),
  message: document.querySelector("#system-message"),
  lastUpdated: document.querySelector("#last-updated"),
  toast: document.querySelector("#toast"),
  classFilter: document.querySelector("#class-filter"),
  subjectFilter: document.querySelector("#subject-filter"),
  sessionPickerHelp: document.querySelector("#session-picker-help"),
};

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function initials(fullName, rollNo) {
  const words = String(fullName || "").trim().split(/\s+/).filter(Boolean);
  if (words.length > 0) {
    return `${words[0][0] || ""}${words.at(-1)[0] || ""}`.toUpperCase();
  }
  return String(rollNo || "SV").slice(-2).toUpperCase();
}

function normalizeStatus(status) {
  const value = String(status || "ABSENT").toUpperCase();
  return value === "PRESENT" || value === "LATE" ? "PRESENT" : "ABSENT";
}

function markForStatus(status) {
  return normalizeStatus(status);
}

function statusPresentation(status) {
  switch (normalizeStatus(status)) {
    case "PRESENT": return { label: "Có mặt", className: "present" };
    default: return { label: "Vắng", className: "absent" };
  }
}

function formatCheckin(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("vi-VN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
    timeZone: "Asia/Ho_Chi_Minh",
  }).format(date);
}

function formatSessionDate(value) {
  if (!value) return "—";
  const isoLike = /^\d{4}-\d{2}-\d{2}$/.test(value) ? `${value}T00:00:00` : value;
  const date = new Date(isoLike);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("vi-VN", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).format(date);
}

function setText(selector, value) {
  const element = document.querySelector(selector);
  if (element) element.textContent = value;
}

function setConnection(stateName, label) {
  state.connected = stateName === "online";
  elements.syncState.dataset.state = stateName;
  elements.syncLabel.textContent = label;
}

function showSystemMessage(message) {
  elements.message.hidden = !message;
  elements.message.textContent = message || "";
}

function showToast(message, isError = false) {
  window.clearTimeout(state.toastTimer);
  elements.toast.textContent = message;
  elements.toast.classList.toggle("error", isError);
  elements.toast.hidden = false;
  state.toastTimer = window.setTimeout(() => {
    elements.toast.hidden = true;
  }, 3600);
}

async function readJson(response) {
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.message || `Máy chủ trả về lỗi ${response.status}.`);
  }
  return body;
}

function attendanceEndpoint(sessionId) {
  return sessionId
    ? `${API.attendance}?sessionId=${encodeURIComponent(sessionId)}`
    : API.attendance;
}

function sessionMatchesFilters(session) {
  return (!state.classFilter || session.classCode === state.classFilter) &&
    (!state.subjectFilter || session.subjectCode === state.subjectFilter);
}

function filteredSessions() {
  return state.sessions.filter(sessionMatchesFilters).sort((a, b) => {
    const dateOrder = String(b.date || "").localeCompare(String(a.date || ""));
    if (dateOrder) return dateOrder;
    const openedOrder = String(b.openedAt || "").localeCompare(String(a.openedAt || ""));
    return openedOrder || (Number(b.slot) || 0) - (Number(a.slot) || 0);
  });
}

function availableSubjects() {
  return [...new Set(state.sessions
    .filter((session) => !state.classFilter || session.classCode === state.classFilter)
    .map((session) => session.subjectCode)
    .filter(Boolean))].sort((a, b) => a.localeCompare(b, "vi"));
}

function updateSessionUrl() {
  const url = new URL(window.location.href);
  url.searchParams.delete("teacherToken");
  if (state.pinnedSessionId) {
    url.searchParams.set("sessionId", state.pinnedSessionId);
  } else {
    url.searchParams.delete("sessionId");
  }
  window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
}

function renderSessionPicker() {
  const classes = [...new Set(state.sessions.map((session) => session.classCode).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b, "vi"));
  const classSignature = classes.join("|");
  if (elements.classFilter.dataset.optionsSignature !== classSignature) {
    elements.classFilter.innerHTML = `
      <option value="">Tất cả lớp</option>
      ${classes.map((classCode) => `<option value="${escapeHtml(classCode)}">${escapeHtml(classCode)}</option>`).join("")}
    `;
    elements.classFilter.dataset.optionsSignature = classSignature;
  }
  if (elements.classFilter.value !== state.classFilter) elements.classFilter.value = state.classFilter;

  const subjects = availableSubjects();
  const subjectSignature = `${state.classFilter}|${subjects.join("|")}`;
  if (elements.subjectFilter.dataset.optionsSignature !== subjectSignature) {
    elements.subjectFilter.innerHTML = `
      <option value="">Tất cả môn học</option>
      ${subjects.map((subjectCode) => `<option value="${escapeHtml(subjectCode)}">${escapeHtml(subjectCode)}</option>`).join("")}
    `;
    elements.subjectFilter.dataset.optionsSignature = subjectSignature;
  }
  if (elements.subjectFilter.value !== state.subjectFilter) elements.subjectFilter.value = state.subjectFilter;

  const visibleSessions = filteredSessions();
  const hasUnsavedChanges = state.dirty.size > 0;
  const filtersDisabled = state.sessionsLoading || state.saving || hasUnsavedChanges || state.sessions.length === 0;
  elements.classFilter.disabled = filtersDisabled;
  elements.subjectFilter.disabled = filtersDisabled || subjects.length === 0;
  if (state.sessionsError) {
    elements.sessionPickerHelp.textContent = `Không tải được danh sách lớp: ${state.sessionsError}`;
  } else if (hasUnsavedChanges) {
    elements.sessionPickerHelp.textContent = `Hãy lưu hoặc hoàn tác ${state.dirty.size} thay đổi trước khi đổi lớp hoặc môn học.`;
  } else if (visibleSessions.length === 0 && !state.sessionsLoading) {
    elements.sessionPickerHelp.textContent = "Không có ca học phù hợp. Hãy chọn lớp hoặc môn học khác.";
  } else if (state.pinnedSessionId) {
    elements.sessionPickerHelp.textContent = "Đang xem ca học từ liên kết. Đổi lớp hoặc môn học để tự theo ca mới nhất.";
  } else if (state.classFilter && subjects.length === 1) {
    elements.sessionPickerHelp.textContent = "Lớp này chỉ có một môn học; đang tự theo ca mới nhất. Ngày và slot hiển thị bên dưới.";
  } else {
    elements.sessionPickerHelp.textContent = "Đang tự theo ca mới nhất phù hợp. Ngày và slot hiển thị bên dưới.";
  }
}

async function loadSessions({ manual = false } = {}) {
  if (state.sessionsRefreshing) return;
  state.sessionsRefreshing = true;
  if (state.sessions.length === 0) state.sessionsLoading = true;
  let loaded = false;
  try {
    const response = await fetch(API.sessions, { cache: "no-store" });
    const body = await readJson(response);
    state.sessions = Array.isArray(body.sessions) ? body.sessions : [];
    if (state.snapshot?.sessionId) upsertSessionSummary(state.snapshot);
    if (!state.filtersHydrated) {
      const linked = state.sessions.find((session) => session.sessionId === state.pinnedSessionId);
      if (linked) {
        state.classFilter = linked.classCode || "";
        state.subjectFilter = linked.subjectCode || "";
        state.filtersHydrated = true;
      } else if (!state.pinnedSessionId) {
        state.filtersHydrated = true;
      }
    }
    state.sessionsError = "";
    loaded = true;
  } catch (error) {
    state.sessionsError = error.message;
    if (manual) showToast(`Không thể nạp danh sách lớp: ${error.message}`, true);
  } finally {
    state.sessionsRefreshing = false;
    state.sessionsLoading = false;
    if (loaded && !state.pinnedSessionId && !state.saving && state.dirty.size === 0) {
      await applySessionFilters();
    }
    renderSessionPicker();
  }
}

async function loadServiceStatus() {
  try {
    const [healthResponse, sheetsResponse] = await Promise.all([
      fetch(API.health, { cache: "no-store" }),
      fetch(`${API.sheets}?verify=true`, { cache: "no-store" }),
    ]);
    const health = await readJson(healthResponse);
    const sheets = await readJson(sheetsResponse);
    state.sheetsConfigured = Boolean(
      sheets.isConfigured && sheets.isReachable && health.googleSheetsConfigured,
    );
    state.sheetsMessage = sheets.message || "";
    if (!state.sheetsConfigured) {
      showSystemMessage(
        sheets.message || "Google Sheets chưa được cấu hình. Hãy mở desktop app → Cấu hình Google Sheets để bật lưu điểm danh.",
      );
    } else {
      showSystemMessage("");
    }
  } catch (error) {
    state.sheetsConfigured = false;
    state.sheetsMessage = error.message;
    showSystemMessage(`Không đọc được trạng thái Google Sheets: ${error.message}`);
  }
}

function upsertSessionSummary(snapshot) {
  if (!snapshot?.sessionId) return;
  const index = state.sessions.findIndex((session) => session.sessionId === snapshot.sessionId);
  if (index < 0) state.sessions.unshift(snapshot);
  else state.sessions[index] = { ...state.sessions[index], ...snapshot };
}

function mergeSnapshot(snapshot, force) {
  const previousSessionId = state.snapshot?.sessionId;
  if (previousSessionId && snapshot.sessionId && previousSessionId !== snapshot.sessionId) {
    state.drafts.clear();
    state.dirty.clear();
    state.baseStatuses.clear();
    showToast("Đã chuyển sang ca học mới nhất.");
  }

  state.snapshot = snapshot;
  upsertSessionSummary(snapshot);
  let conflictingRows = 0;
  for (const student of snapshot.students || []) {
    if (state.dirty.has(student.rollNo) &&
        state.baseStatuses.get(student.rollNo) !== normalizeStatus(student.status)) {
      // A saved edit on desktop wins over a stale, unsaved web draft.
      state.dirty.delete(student.rollNo);
      state.baseStatuses.delete(student.rollNo);
      conflictingRows += 1;
    }
    if (force || !state.dirty.has(student.rollNo)) {
      state.drafts.set(student.rollNo, markForStatus(student.status));
    }
  }
  if (conflictingRows > 0) {
    showToast(`${conflictingRows} dòng đã đổi trên desktop. Hãy chọn lại nếu muốn sửa tiếp.`, true);
  }
}

function applySuccessfulSnapshot(snapshot, force, source = "poll") {
  mergeSnapshot(snapshot, force);
  state.loading = false;
  state.sheetsConfigured = true;
  state.sheetsMessage = "";
  state.retryDelayMs = 0;
  state.nextRetryAt = 0;
  showSystemMessage("");
  setConnection("online", "Google Sheets đã kết nối");
  render();
  const now = new Intl.DateTimeFormat("vi-VN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date());
  elements.lastUpdated.textContent = source === "live"
    ? `Cập nhật trực tiếp lúc ${now} · đã ghi Google Sheets`
    : `Cập nhật lúc ${now} · tự động mỗi 5 giây`;
}

async function refreshData({ manual = false, force = false } = {}) {
  if (state.filteredEmpty) {
    state.loading = false;
    render();
    return;
  }
  if (state.saving || (state.refreshing && !force)) return;
  if (!manual && !force && Date.now() < state.nextRetryAt) return;
  const requestId = ++state.refreshRequestId;
  const selectionSerialAtStart = state.selectionSerial;
  state.refreshing = true;
  const liveSerialAtStart = state.liveUpdateSerial;
  if (manual) elements.refreshButton.disabled = true;

  try {
    const response = await fetch(attendanceEndpoint(state.selectedSessionId), { cache: "no-store" });
    const snapshot = await readJson(response);
    if (requestId !== state.refreshRequestId ||
        selectionSerialAtStart !== state.selectionSerial ||
        liveSerialAtStart !== state.liveUpdateSerial) return;
    applySuccessfulSnapshot(snapshot, force);
    if (manual) showToast("Đã nạp dữ liệu mới nhất.");
  } catch (error) {
    if (requestId !== state.refreshRequestId ||
        selectionSerialAtStart !== state.selectionSerial ||
        liveSerialAtStart !== state.liveUpdateSerial) return;
    state.loading = false;
    state.sheetsConfigured = false;
    state.retryDelayMs = state.retryDelayMs
      ? Math.min(state.retryDelayMs * 2, 60000)
      : POLL_INTERVAL_MS;
    state.nextRetryAt = Date.now() + state.retryDelayMs;
    const detail = error.message;
    const needsScriptUpdate = /Apps Script.*(bản cũ|phiên bản 4|cập nhật)/i.test(detail);
    setConnection("error", needsScriptUpdate ? "Apps Script cần cập nhật" : "Đang tự kết nối lại");
    showSystemMessage(`Chưa tải được điểm danh: ${detail} Trang sẽ tự thử lại, không cần bấm Nạp lại.`);
    render();
  } finally {
    if (requestId === state.refreshRequestId) {
      state.refreshing = false;
      elements.refreshButton.disabled = false;
    }
  }
}

function renderSession() {
  const snapshot = state.snapshot;
  const hasSession = Boolean(snapshot?.sessionId);
  setText("#subject-code", hasSession ? snapshot.subjectCode || "—" : "—");
  setText("#class-code", hasSession ? snapshot.classCode || "—" : "—");
  setText("#slot-number", hasSession ? `Slot ${snapshot.slot ?? "—"}` : "—");
  setText("#session-date", hasSession ? formatSessionDate(snapshot.date) : "—");

  const sessionStatus = document.querySelector("#session-status");
  sessionStatus.textContent = hasSession
    ? (snapshot.isOpen ? "Đang mở" : "Đã đóng")
    : (state.loading ? "Đang tải" : (state.connected ? "Chưa có ca học" : "Đang kết nối lại"));
  sessionStatus.className = `status-chip ${hasSession ? (snapshot.isOpen ? "open" : "closed") : "neutral"}`;

  setText(
    "#session-description",
    hasSession
      ? `${snapshot.subjectCode || "Môn học"} · ${snapshot.classCode || "Lớp học"} · Slot ${snapshot.slot ?? "—"}`
      : (state.filteredEmpty
        ? "Không có ca học phù hợp với lớp và môn học đã chọn."
        : "Mở một phiên điểm danh trên desktop app để bắt đầu.")
  );

  const stats = snapshot?.stats || {};
  setText("#stat-total", stats.total ?? snapshot?.count ?? 0);
  setText("#stat-present", stats.present ?? 0);
  setText("#stat-absent", stats.absent ?? 0);
}

function filteredStudents() {
  const students = state.snapshot?.students || [];
  const query = state.query.trim().toLocaleLowerCase("vi");
  return students.filter((student) => {
    const status = normalizeStatus(student.status);
    const matchesStatus = state.filter === "ALL" || status === state.filter;
    const haystack = `${student.rollNo || ""} ${student.fullName || ""} ${student.email || ""}`.toLocaleLowerCase("vi");
    return matchesStatus && (!query || haystack.includes(query));
  });
}

function renderRows() {
  if (state.loading) {
    elements.rows.innerHTML = '<tr class="loading-row"><td colspan="9">Đang tải danh sách sinh viên...</td></tr>';
    return;
  }

  const students = filteredStudents();
  if (!state.snapshot?.sessionId) {
    elements.rows.innerHTML = state.filteredEmpty
      ? '<tr class="empty-row"><td colspan="9">Không có ca học phù hợp. Hãy chọn lớp hoặc môn học khác.</td></tr>'
      : state.connected
      ? '<tr class="empty-row"><td colspan="9">Chưa có ca học. Hãy mở phiên điểm danh trên desktop app.</td></tr>'
      : '<tr class="empty-row"><td colspan="9">Chưa tải được dữ liệu. Trang sẽ tự kết nối lại.</td></tr>';
    return;
  }
  if (students.length === 0) {
    elements.rows.innerHTML = '<tr class="empty-row"><td colspan="9">Không tìm thấy sinh viên phù hợp với bộ lọc.</td></tr>';
    return;
  }

  const allStudents = state.snapshot.students || [];
  elements.rows.innerHTML = students.map((student) => {
    const originalIndex = allStudents.findIndex((item) => item.rollNo === student.rollNo);
    const rowKey = `student-${originalIndex}`;
    const presentation = statusPresentation(student.status);
    const draft = state.drafts.get(student.rollNo) ?? markForStatus(student.status);
    const dirty = state.dirty.has(student.rollNo);
    const disabled = state.saving || !state.sheetsConfigured;
    return `
      <tr data-roll-no="${escapeHtml(student.rollNo)}" data-dirty="${dirty}">
        <td class="student-index">${originalIndex + 1}</td>
        <td><span class="student-avatar" aria-label="Ảnh đại diện chữ cái">${escapeHtml(initials(student.fullName, student.rollNo))}</span></td>
        <td class="roll-number">${escapeHtml(student.rollNo || "—")}</td>
        <td class="student-name">${escapeHtml(student.fullName || "Chưa có họ tên")}${dirty ? '<span class="dirty-label">Chưa lưu</span>' : ""}</td>
        <td class="student-email">${escapeHtml(student.email || "—")}</td>
        <td class="attendance-radio">
          <input type="radio" id="${rowKey}-present" name="${rowKey}-attendance" value="PRESENT" data-roll-no="${escapeHtml(student.rollNo)}" aria-label="Đánh dấu ${escapeHtml(student.fullName || student.rollNo)} có mặt" ${draft === "PRESENT" ? "checked" : ""} ${disabled ? "disabled" : ""}>
        </td>
        <td class="attendance-radio">
          <input type="radio" id="${rowKey}-absent" name="${rowKey}-attendance" value="ABSENT" data-roll-no="${escapeHtml(student.rollNo)}" aria-label="Đánh dấu ${escapeHtml(student.fullName || student.rollNo)} vắng" ${draft === "ABSENT" ? "checked" : ""} ${disabled ? "disabled" : ""}>
        </td>
        <td class="checkin-time">${escapeHtml(formatCheckin(student.checkinTime))}</td>
        <td><span class="status-chip ${presentation.className}">${presentation.label}</span></td>
      </tr>`;
  }).join("");
}

function renderActions() {
  const count = state.dirty.size;
  elements.changeCount.textContent = String(count);
  elements.changeCount.hidden = count === 0;
  elements.saveButton.disabled = count === 0 || state.saving || !state.sheetsConfigured || !state.snapshot?.sessionId;
  elements.saveButton.firstChild.textContent = state.saving ? "Đang lưu " : "Lưu điểm danh ";
}

function render() {
  renderSessionPicker();
  renderSession();
  renderRows();
  renderActions();
}

async function saveChanges() {
  if (state.saving || state.dirty.size === 0 || !state.snapshot?.sessionId) return;
  state.saving = true;
  render();

  const pending = [...state.dirty];
  let savedCount = 0;
  try {
    for (const rollNo of pending) {
      const response = await fetch(
        `/api/sessions/${encodeURIComponent(state.snapshot.sessionId)}/attendance/${encodeURIComponent(rollNo)}`,
        {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            status: state.drafts.get(rollNo),
            expectedStatus: state.baseStatuses.get(rollNo),
            actor: "Cổng FAP mô phỏng",
            reason: "Điểm danh thủ công từ website mô phỏng của Lab 1",
          }),
        }
      );
      await readJson(response);
      state.dirty.delete(rollNo);
      state.baseStatuses.delete(rollNo);
      savedCount += 1;
    }
    showToast(`Đã lưu ${savedCount} thay đổi vào Google Sheets.`);
  } catch (error) {
    showToast(`Lưu chưa hoàn tất: ${error.message}`, true);
  } finally {
    state.saving = false;
    await refreshData();
  }
}

elements.rows.addEventListener("change", (event) => {
  const input = event.target.closest('input[type="radio"][data-roll-no]');
  if (!input) return;
  const rollNo = input.dataset.rollNo;
  const student = (state.snapshot?.students || []).find((item) => item.rollNo === rollNo);
  if (!student) return;
  const currentStatus = normalizeStatus(student.status);
  if (input.value === markForStatus(currentStatus)) {
    state.dirty.delete(rollNo);
    state.baseStatuses.delete(rollNo);
  } else {
    if (!state.dirty.has(rollNo)) state.baseStatuses.set(rollNo, currentStatus);
    state.dirty.add(rollNo);
  }
  state.drafts.set(rollNo, input.value);
  render();
});

elements.search.addEventListener("input", () => {
  state.query = elements.search.value;
  renderRows();
});

elements.filter.addEventListener("change", () => {
  state.filter = elements.filter.value;
  renderRows();
});

async function selectSession(sessionId, toastMessage = "") {
  if (state.saving || state.dirty.size > 0) {
    renderSessionPicker();
    if (toastMessage) showToast("Hãy lưu hoặc hoàn tác thay đổi trước khi đổi lớp hoặc môn học.", true);
    return false;
  }

  state.filteredEmpty = Boolean(state.classFilter || state.subjectFilter) && filteredSessions().length === 0;
  if (sessionId === state.selectedSessionId && !state.filteredEmpty) {
    renderSessionPicker();
    return true;
  }
  state.selectedSessionId = sessionId;
  state.selectionSerial += 1;
  state.snapshot = null;
  state.drafts.clear();
  state.dirty.clear();
  state.baseStatuses.clear();
  state.loading = !state.filteredEmpty;
  updateSessionUrl();
  render();
  if (!state.filteredEmpty) await refreshData({ force: true });
  if (toastMessage) showToast(toastMessage);
  return true;
}

async function applySessionFilters() {
  const visible = filteredSessions();
  const target = !state.classFilter && !state.subjectFilter
    ? ""
    : visible[0]?.sessionId || "";
  await selectSession(target);
}

elements.classFilter.addEventListener("change", async () => {
  if (state.dirty.size > 0 || state.saving) {
    renderSessionPicker();
    return;
  }
  state.filtersHydrated = true;
  state.pinnedSessionId = "";
  updateSessionUrl();
  state.classFilter = elements.classFilter.value;
  const subjects = availableSubjects();
  state.subjectFilter = subjects.length === 1 ? subjects[0] : "";
  await applySessionFilters();
});

elements.subjectFilter.addEventListener("change", async () => {
  if (state.dirty.size > 0 || state.saving) {
    renderSessionPicker();
    return;
  }
  state.filtersHydrated = true;
  state.pinnedSessionId = "";
  updateSessionUrl();
  state.subjectFilter = elements.subjectFilter.value;
  await applySessionFilters();
});

elements.refreshButton.addEventListener("click", async () => {
  await refreshData({ manual: true, force: state.dirty.size === 0 });
  await loadServiceStatus();
  await loadSessions({ manual: true });
});
elements.saveButton.addEventListener("click", saveChanges);

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    refreshData({ force: true });
    loadSessions();
  }
});

function connectLiveUpdates() {
  if (!window.EventSource) return;
  const source = new window.EventSource(API.updates);
  state.liveSource = source;
  source.addEventListener("attendance", (event) => {
    try {
      const update = JSON.parse(event.data);
      const snapshot = update.snapshot;
      if (!snapshot?.sessionId) return;
      upsertSessionSummary(snapshot);
      if (state.pinnedSessionId && snapshot.sessionId !== state.pinnedSessionId) return;
      if (state.classFilter || state.subjectFilter) {
        if (!sessionMatchesFilters(snapshot)) return;
        const latest = filteredSessions()[0];
        if (latest?.sessionId !== state.selectedSessionId) {
          if (state.pinnedSessionId || state.saving || state.dirty.size > 0 ||
              latest?.sessionId !== snapshot.sessionId) return;
          state.filteredEmpty = false;
          state.selectedSessionId = snapshot.sessionId;
          state.selectionSerial += 1;
        }
      }
      if (state.selectedSessionId && snapshot.sessionId !== state.selectedSessionId) return;
      if (!state.selectedSessionId &&
          state.snapshot?.sessionId !== snapshot.sessionId &&
          update.eventName !== "SessionOpened") return;
      state.liveUpdateSerial += 1;
      applySuccessfulSnapshot(snapshot, false, "live");
    } catch (error) {
      console.warn("Không đọc được cập nhật trực tiếp; tự nạp lại vẫn hoạt động.", error);
    }
  });
}

async function initialize() {
  connectLiveUpdates();
  window.setInterval(() => {
    if (!document.hidden) refreshData();
  }, POLL_INTERVAL_MS);
  window.setInterval(() => {
    if (!document.hidden) loadSessions();
  }, SESSION_LIST_POLL_INTERVAL_MS);
  await refreshData({ force: true });
  await loadServiceStatus();
  await loadSessions();
}

initialize();
