const POLL_INTERVAL_MS = 2000;

// Public launcher uses the query token once to establish an HttpOnly teacher
// cookie. Remove it from the address bar immediately after the page loads.
const launchUrl = new URL(window.location.href);
if (launchUrl.searchParams.has("teacherToken")) {
  launchUrl.searchParams.delete("teacherToken");
  const cleanUrl = `${launchUrl.pathname}${launchUrl.search}${launchUrl.hash}`;
  window.history.replaceState({}, "", cleanUrl);
}

const API = {
  attendance: "/api/attendance",
  health: "/api/health",
  sheets: "/api/config/google-sheets",
};

const state = {
  snapshot: null,
  drafts: new Map(),
  dirty: new Set(),
  baseStatuses: new Map(),
  query: "",
  filter: "ALL",
  loading: true,
  saving: false,
  connected: false,
  sheetsConfigured: false,
  toastTimer: null,
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
  const value = String(status || "NOT CHECKED").toUpperCase();
  return ["PRESENT", "LATE", "ABSENT", "NOT CHECKED"].includes(value)
    ? value
    : "NOT CHECKED";
}

function markForStatus(status) {
  const normalized = normalizeStatus(status);
  if (normalized === "PRESENT" || normalized === "LATE") return "PRESENT";
  if (normalized === "ABSENT") return "ABSENT";
  return "";
}

function statusPresentation(status) {
  switch (normalizeStatus(status)) {
    case "PRESENT": return { label: "Có mặt", className: "present" };
    case "LATE": return { label: "Đi trễ", className: "late" };
    case "ABSENT": return { label: "Vắng", className: "absent" };
    default: return { label: "Chưa điểm danh", className: "neutral" };
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

async function loadServiceStatus() {
  try {
    const [healthResponse, sheetsResponse] = await Promise.all([
      fetch(API.health, { cache: "no-store" }),
      fetch(`${API.sheets}?verify=false`, { cache: "no-store" }),
    ]);
    const health = await readJson(healthResponse);
    const sheets = await readJson(sheetsResponse);
    state.sheetsConfigured = Boolean(sheets.isConfigured && health.googleSheetsConfigured);
    if (!state.sheetsConfigured) {
      showSystemMessage("Google Sheets chưa được cấu hình. Hãy mở desktop app → Cấu hình Google Sheets để bật lưu điểm danh.");
    } else {
      showSystemMessage("");
    }
  } catch (error) {
    state.sheetsConfigured = false;
    showSystemMessage(`Không đọc được trạng thái Google Sheets: ${error.message}`);
  }
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

async function refreshData({ manual = false, force = false } = {}) {
  if (state.saving) return;
  if (manual) elements.refreshButton.disabled = true;

  try {
    const response = await fetch(API.attendance, { cache: "no-store" });
    const snapshot = await readJson(response);
    mergeSnapshot(snapshot, force);
    state.loading = false;
    setConnection("online", state.sheetsConfigured ? "Google Sheets đã kết nối" : "Máy chủ đang hoạt động");
    render();
    const now = new Intl.DateTimeFormat("vi-VN", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
    }).format(new Date());
    elements.lastUpdated.textContent = `Cập nhật lúc ${now} · tự động mỗi 2 giây`;
    if (manual) showToast("Đã nạp dữ liệu mới nhất.");
  } catch (error) {
    state.loading = false;
    setConnection("error", "Mất kết nối máy chủ");
    showSystemMessage(`Không thể tải danh sách điểm danh: ${error.message}`);
    render();
  } finally {
    elements.refreshButton.disabled = false;
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
  sessionStatus.textContent = hasSession ? (snapshot.isOpen ? "Đang mở" : "Đã đóng") : "Chưa có ca học";
  sessionStatus.className = `status-chip ${hasSession ? (snapshot.isOpen ? "open" : "closed") : "neutral"}`;

  setText(
    "#session-description",
    hasSession
      ? `${snapshot.subjectCode || "Môn học"} · ${snapshot.classCode || "Lớp học"} · Slot ${snapshot.slot ?? "—"}`
      : "Mở một phiên điểm danh trên desktop app để bắt đầu."
  );

  const stats = snapshot?.stats || {};
  setText("#stat-total", stats.total ?? snapshot?.count ?? 0);
  setText("#stat-present", stats.present ?? 0);
  setText("#stat-late", stats.late ?? 0);
  setText("#stat-absent", stats.absent ?? 0);
  setText("#stat-pending", stats.notChecked ?? snapshot?.count ?? 0);
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
    elements.rows.innerHTML = '<tr class="empty-row"><td colspan="9">Chưa có ca học. Hãy mở phiên điểm danh trên desktop app.</td></tr>';
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

elements.refreshButton.addEventListener("click", () => refreshData({ manual: true, force: state.dirty.size === 0 }));
elements.saveButton.addEventListener("click", saveChanges);

document.addEventListener("visibilitychange", () => {
  if (!document.hidden) refreshData();
});

async function initialize() {
  await loadServiceStatus();
  await refreshData({ force: true });
  window.setInterval(() => {
    if (!document.hidden) refreshData();
  }, POLL_INTERVAL_MS);
}

initialize();
