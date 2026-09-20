/**
 * FAP Auto Attendance Assistant - Content Script
 * Injected into fap.fpt.edu.vn to automate attendance taking for lecturers.
 */

(function () {
  console.log('[FAP Assistant] Content script initialized on FAP.');

  // Check if current page is attendance page
  const isAttendancePage =
    window.location.href.includes('TakeAttendance') ||
    window.location.href.includes('Attendance') ||
    document.querySelector('table[id*="Attendance"]') ||
    document.querySelector('input[type="radio"][value="Present"], input[type="radio"][value="P"]');

  // Create and inject the floating assistant panel
  function injectAssistantWidget() {
    if (document.getElementById('fap-attendance-widget')) return;

    const widget = document.createElement('div');
    widget.id = 'fap-attendance-widget';
    widget.innerHTML = `
      <div class="fap-widget-header">
        <div class="fap-logo-badge">FAP</div>
        <div class="fap-title-box">
          <div class="fap-title">Trợ Lý Điểm Danh Tự Động</div>
          <div class="fap-subtitle">Đồng bộ Google Sheets & Desktop App</div>
        </div>
        <button id="fap-toggle-btn" class="fap-btn-icon">−</button>
      </div>
      <div id="fap-widget-body" class="fap-widget-body">
        <div class="fap-status-card">
          <div class="fap-status-dot green"></div>
          <span id="fap-status-text">Sẵn sàng nhận dữ liệu điểm danh</span>
        </div>

        <div class="fap-input-group">
          <label>Google Sheets / API Endpoint:</label>
          <input type="text" id="fap-api-url" placeholder="https://script.google.com/.../exec" />
        </div>

        <div class="fap-actions-grid">
          <button id="fap-btn-fetch" class="fap-btn primary">
            <span class="fap-icon">🔄</span> Đồng bộ từ Google Sheets
          </button>
          <button id="fap-btn-autofill" class="fap-btn success">
            <span class="fap-icon">⚡</span> Tự động tích điểm danh
          </button>
        </div>

        <div id="fap-summary" class="fap-summary-box" style="display:none;">
          <div class="fap-summary-item"><span class="label">Có mặt (P):</span> <strong id="fap-count-present" class="text-green">0</strong></div>
          <div class="fap-summary-item"><span class="label">Vắng (A):</span> <strong id="fap-count-absent" class="text-red">0</strong></div>
          <div class="fap-summary-item"><span class="label">Tổng cộng:</span> <strong id="fap-count-total">0</strong></div>
        </div>

        <div class="fap-footer-actions">
          <button id="fap-btn-save" class="fap-btn fpt-save">
            💾 Lưu kết quả lên FAP
          </button>
        </div>
      </div>
    `;

    document.body.appendChild(widget);

    // Setup event listeners
    setupWidgetEvents();
  }

  function setupWidgetEvents() {
    const toggleBtn = document.getElementById('fap-toggle-btn');
    const body = document.getElementById('fap-widget-body');
    const fetchBtn = document.getElementById('fap-btn-fetch');
    const autofillBtn = document.getElementById('fap-btn-autofill');
    const saveBtn = document.getElementById('fap-btn-save');
    const apiUrlInput = document.getElementById('fap-api-url');
    const statusText = document.getElementById('fap-status-text');

    // Load saved API URL from storage
    chrome.storage.local.get(['fapSheetsUrl'], function (result) {
      if (result.fapSheetsUrl) {
        apiUrlInput.value = result.fapSheetsUrl;
      }
    });

    apiUrlInput.addEventListener('change', function () {
      chrome.storage.local.set({ fapSheetsUrl: apiUrlInput.value.trim() });
    });

    toggleBtn.addEventListener('click', () => {
      if (body.style.display === 'none') {
        body.style.display = 'block';
        toggleBtn.textContent = '−';
      } else {
        body.style.display = 'none';
        toggleBtn.textContent = '+';
      }
    });

    // In-memory student attendance map from sheet / app
    let attendanceMap = {};
    let sessionIsOpen = false;

    fetchBtn.addEventListener('click', async () => {
      const url = apiUrlInput.value.trim();
      statusText.textContent = 'Đang tải dữ liệu điểm danh...';

      try {
        let records = [];

        if (url) {
          // Fetch from Google Apps Script Web App
          const res = await fetch(url + '?action=getAttendance');
          const data = await res.json();
          records = data.students || [];
          sessionIsOpen = data.isOpen === true;
        } else {
          // Fallback: Fetch from local Desktop App server if running
          try {
            const res = await fetch('http://localhost:8080/api/attendance');
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const data = await res.json();
            records = data.students || [];
            sessionIsOpen = data.isOpen === true;
          } catch (err) {
            throw new Error('Không kết nối được ASP.NET Core API tại localhost:8080.');
          }
        }

        attendanceMap = {};
        records.forEach((s) => {
          const roll = (s.rollNo || s.RollNo || '').trim().toUpperCase();
          if (roll) {
            attendanceMap[roll] = (s.status || s.Status || 'ABSENT').toUpperCase();
          }
        });

        statusText.textContent = `Đã nạp ${Object.keys(attendanceMap).length} sinh viên từ hệ thống!`;
        alert(`Đã đồng bộ thành công ${Object.keys(attendanceMap).length} sinh viên điểm danh!`);
      } catch (e) {
        statusText.textContent = 'Lỗi kết nối. Vui lòng kiểm tra lại URL!';
        console.error(e);
      }
    });

    autofillBtn.addEventListener('click', () => {
      if (sessionIsOpen) {
        alert('Phiên điểm danh vẫn đang mở. Hãy đóng phiên trên app giảng viên trước khi tự động tích P/A lên FAP.');
        return;
      }

      // Find table rows on FAP
      const table = document.querySelector('table');
      if (!table) {
        alert('Không tìm thấy bảng điểm danh trên trang FAP hiện tại!');
        return;
      }

      let presentCount = 0;
      let absentCount = 0;
      let totalCount = 0;

      const rows = table.querySelectorAll('tr');

      rows.forEach((row) => {
        const text = row.innerText.toUpperCase();
        // Check for student roll number match (e.g. SE182173, HE123456, QE..., etc.)
        for (const [rollNo, status] of Object.entries(attendanceMap)) {
          if (text.includes(rollNo)) {
            totalCount++;
            // Find radio buttons in this row
            const radios = row.querySelectorAll('input[type="radio"]');

            radios.forEach((radio) => {
              const val = (radio.value || '').toUpperCase();
              const name = (radio.name || '').toUpperCase();

              const isPresentRadio = val === 'P' || val === 'PRESENT' || val === '1' || name.includes('PRESENT');
              const isAbsentRadio = val === 'A' || val === 'ABSENT' || val === '0' || name.includes('ABSENT');

              if ((status === 'PRESENT' || status === 'LATE') && isPresentRadio) {
                radio.checked = true;
                radio.dispatchEvent(new Event('change', { bubbles: true }));
                row.style.backgroundColor = '#E8F5E9'; // Light green highlight
                presentCount++;
              } else if (status !== 'PRESENT' && isAbsentRadio) {
                radio.checked = true;
                radio.dispatchEvent(new Event('change', { bubbles: true }));
                row.style.backgroundColor = '#FFEBEE'; // Light red highlight
                absentCount++;
              }
            });
            break;
          }
        }
      });

      // Update summary box
      document.getElementById('fap-summary').style.display = 'block';
      document.getElementById('fap-count-present').textContent = presentCount;
      document.getElementById('fap-count-absent').textContent = absentCount;
      document.getElementById('fap-count-total').textContent = totalCount;

      statusText.textContent = `⚡ Hoàn thành! Tích ${presentCount} có mặt, ${absentCount} vắng.`;
    });

    saveBtn.addEventListener('click', () => {
      const submitBtn =
        document.querySelector('input[type="submit"][value*="Save"]') ||
        document.querySelector('input[type="submit"][value*="Lưu"]') ||
        document.querySelector('button[type="submit"]');

      if (submitBtn) {
        if (confirm('Xác nhận lưu điểm danh lên FAP?')) {
          submitBtn.click();
        }
      } else {
        alert('Vui lòng bấm nút Lưu điểm danh trên trang FAP để hoàn tất.');
      }
    });
  }

  // Run on page load
  window.addEventListener('load', () => {
    setTimeout(injectAssistantWidget, 800);
  });

  // Also inject immediately if DOM ready
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    injectAssistantWidget();
  }
})();
