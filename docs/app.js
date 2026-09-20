/**
 * FAP Student Attendance Portal - Logic & Authentication Script
 * Supports student identification, camera QR scanning, 10s OTP verification, and digital ticket generation.
 */

document.addEventListener('DOMContentLoaded', () => {
  // State
  let currentUser = null;
  let html5QrScanner = null;
  let activeSession = {
    sessionId: '',
    classCode: 'SE1801',
    subjectCode: 'PRN231',
    slot: 1,
    otp: ''
  };

  // DOM Elements
  const authView = document.getElementById('auth-view');
  const checkinView = document.getElementById('checkin-view');
  const ticketView = document.getElementById('ticket-view');
  const userProfileBadge = document.getElementById('user-profile-badge');
  const userDisplayEmail = document.getElementById('user-display-email');
  const btnLogout = document.getElementById('btn-logout');

  const studentLoginForm = document.getElementById('student-login-form');
  const inputRollNo = document.getElementById('input-roll-no');
  const inputEmail = document.getElementById('input-email');
  const quickChips = document.querySelectorAll('.chip');

  const studentAvatarLetter = document.getElementById('student-avatar-letter');
  const studentNameText = document.getElementById('student-name-text');
  const studentMetaText = document.getElementById('student-meta-text');

  const tabBtnCamera = document.getElementById('tab-btn-camera');
  const tabBtnOtp = document.getElementById('tab-btn-otp');
  const cameraModeContainer = document.getElementById('camera-mode-container');
  const otpModeContainer = document.getElementById('otp-mode-container');
  const inputOtp = document.getElementById('input-otp');
  const btnSubmitOtp = document.getElementById('btn-submit-otp');
  const timerSec = document.getElementById('timer-sec');
  const classInfoDisplay = document.getElementById('class-info-display');

  const btnDoneNewScan = document.getElementById('btn-done-new-scan');

  // Parse URL Parameters (if student scanned QR code directly with phone camera)
  const urlParams = new URLSearchParams(window.location.search);
  const configuredApiBase = urlParams.get('api') || '';
  if (urlParams.get('session')) activeSession.sessionId = urlParams.get('session');
  if (urlParams.get('class')) activeSession.classCode = urlParams.get('class');
  if (urlParams.get('subject')) activeSession.subjectCode = urlParams.get('subject');
  if (urlParams.get('slot')) activeSession.slot = parseInt(urlParams.get('slot'), 10) || 1;

  // Update class display text
  classInfoDisplay.textContent = `${activeSession.subjectCode} • Lớp ${activeSession.classCode} (Slot ${activeSession.slot})`;

  // 10s OTP Countdown Clock
  function updateOtpCountdown() {
    const nowSec = Math.floor(Date.now() / 1000);
    const remaining = 10 - (nowSec % 10);
    timerSec.textContent = `${remaining}s`;
    if (remaining <= 3) {
      timerSec.className = 'text-orange font-bold';
      timerSec.style.color = '#DC2626';
    } else {
      timerSec.style.color = '#F36F21';
    }
  }
  setInterval(updateOtpCountdown, 1000);
  updateOtpCountdown();

  // Handle Quick Chips
  quickChips.forEach(chip => {
    chip.addEventListener('click', () => {
      inputRollNo.value = chip.dataset.rollNo;
      inputEmail.value = chip.dataset.email;
      inputEmail.focus();
    });
  });

  studentLoginForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const rollNo = inputRollNo.value.trim().toUpperCase();
    const email = inputEmail.value.trim().toLowerCase();
    loginWithStudent(rollNo, email);
  });

  function loginWithStudent(rollNo, email, optionalName) {
    if (!rollNo) {
      alert('Vui lòng nhập MSSV.');
      return;
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      alert('Vui lòng nhập một địa chỉ email hợp lệ.');
      return;
    }

    const name = optionalName || (rollNo === 'SE182173' ? 'Bùi Nhật Minh' : rollNo);

    currentUser = {
      email: email,
      rollNo: rollNo,
      fullName: name
    };

    // Update Header Badge
    userDisplayEmail.textContent = email;
    userProfileBadge.style.display = 'flex';

    // Update Profile Strip
    studentAvatarLetter.textContent = name.charAt(0).toUpperCase();
    studentNameText.textContent = name;
    studentMetaText.textContent = `${rollNo} • ${email}`;

    // Switch to Check-in View
    authView.style.display = 'none';
    checkinView.style.display = 'block';

    // QR identifies the attendance session only. OTP must always be entered
    // manually from the lecturer screen so a stale QR never submits an old OTP.
    inputOtp.value = '';
    activeSession.otp = '';
    if (activeSession.sessionId) {
      switchTab('otp');
    } else {
      startCameraScanner();
    }
  }

  // Logout
  btnLogout.addEventListener('click', () => {
    currentUser = null;
    stopCameraScanner();
    userProfileBadge.style.display = 'none';
    checkinView.style.display = 'none';
    ticketView.style.display = 'none';
    authView.style.display = 'block';
  });

  // Mode Tabs
  tabBtnCamera.addEventListener('click', () => switchTab('camera'));
  tabBtnOtp.addEventListener('click', () => switchTab('otp'));

  function switchTab(mode) {
    if (mode === 'camera') {
      tabBtnCamera.classList.add('active');
      tabBtnOtp.classList.remove('active');
      cameraModeContainer.style.display = 'block';
      otpModeContainer.style.display = 'none';
      startCameraScanner();
    } else {
      tabBtnOtp.classList.add('active');
      tabBtnCamera.classList.remove('active');
      cameraModeContainer.style.display = 'none';
      otpModeContainer.style.display = 'block';
      stopCameraScanner();
      inputOtp.focus();
    }
  }

  // Camera QR Scanner using html5-qrcode
  function startCameraScanner() {
    if (typeof Html5QrcodeScanner === 'undefined') {
      console.warn('Html5QrcodeScanner library is loading...');
      return;
    }

    if (!html5QrScanner) {
      try {
        html5QrScanner = new Html5QrcodeScanner(
          'qr-reader',
          { fps: 10, qrbox: { width: 250, height: 250 } },
          /* verbose= */ false
        );
        html5QrScanner.render(onScanSuccess, onScanError);
      } catch (err) {
        console.error('Error starting camera scanner:', err);
      }
    }
  }

  function stopCameraScanner() {
    if (html5QrScanner) {
      try {
        html5QrScanner.clear();
      } catch (e) {}
      html5QrScanner = null;
    }
  }

  function onScanSuccess(decodedText) {
    console.log('[QR Scanned]:', decodedText);
    stopCameraScanner();

    // Parse session metadata only. Never pre-fill or auto-submit the OTP.
    if (decodedText.includes('FAP_ATTENDANCE')) {
      const parts = decodedText.split('|');
      if (parts.length >= 4) {
        activeSession.subjectCode = parts[1];
        activeSession.classCode = parts[2];
        activeSession.slot = parseInt(parts[3].replace('Slot', ''), 10) || 1;
      }
    } else if (decodedText.includes('session=')) {
      try {
        const url = new URL(decodedText);
        activeSession.sessionId = url.searchParams.get('session') || '';
        if (url.searchParams.get('class')) activeSession.classCode = url.searchParams.get('class');
        if (url.searchParams.get('subject')) activeSession.subjectCode = url.searchParams.get('subject');
        if (url.searchParams.get('slot')) activeSession.slot = parseInt(url.searchParams.get('slot'), 10) || 1;
      } catch (e) {}
    }

    classInfoDisplay.textContent = `${activeSession.subjectCode} • Lớp ${activeSession.classCode} (Slot ${activeSession.slot})`;
    activeSession.otp = '';
    inputOtp.value = '';
    switchTab('otp');
  }

  function onScanError(errorMessage) {
    // Suppress regular frame scan failures
  }

  // Manual OTP Submit Button
  btnSubmitOtp.addEventListener('click', () => {
    const otp = inputOtp.value.trim();
    if (otp.length !== 6) {
      alert('Vui lòng nhập đầy đủ mã OTP 6 chữ số đang hiển thị trên màn hình!');
      return;
    }
    performAttendance(otp);
  });

  // Perform Attendance Verification
  async function performAttendance(otp) {
    if (!currentUser) {
      alert('Vui lòng nhập thông tin sinh viên trước!');
      return;
    }

    btnSubmitOtp.disabled = true;
    btnSubmitOtp.innerHTML = '<span>Đang xác thực điểm danh...</span>';

    try {
      const apiUrl = configuredApiBase
        ? `${configuredApiBase.replace(/\/$/, '')}/api/attendance`
        : `${window.location.origin}/api/attendance`;
      const response = await fetch(apiUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: currentUser.email,
          rollNo: currentUser.rollNo,
          fullName: currentUser.fullName,
          sessionId: activeSession.sessionId,
          classCode: activeSession.classCode,
          subjectCode: activeSession.subjectCode,
          slot: activeSession.slot,
          otp: otp
        })
      });
      const result = await response.json().catch(() => ({}));

      if (!response.ok || result.success !== true) {
        throw new Error(result.message || 'Không thể xác nhận điểm danh với máy chủ.');
      }

      displaySuccessTicket(result.student);
    } catch (error) {
      alert(error.message || 'Không thể kết nối tới máy chủ điểm danh.');
    } finally {
      btnSubmitOtp.disabled = false;
      btnSubmitOtp.innerHTML = '<span>🚀 Xác Nhận Điểm Danh</span>';
    }
  }

  function displaySuccessTicket(serverStudent) {
    stopCameraScanner();
    checkinView.style.display = 'none';
    ticketView.style.display = 'block';

    const now = new Date();
    const timeStr = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')} ${now.getDate().toString().padStart(2, '0')}/${(now.getMonth()+1).toString().padStart(2, '0')}/${now.getFullYear()}`;
    const hash = serverStudent?.confirmationCode || `FAP-${currentUser.rollNo}-${now.getTime().toString(16).toUpperCase().slice(-6)}`;

    document.getElementById('ticket-student-name').textContent = currentUser.fullName;
    document.getElementById('ticket-student-roll').textContent = currentUser.rollNo;
    document.getElementById('ticket-student-email').textContent = currentUser.email;
    document.getElementById('ticket-class-info').textContent = `${activeSession.subjectCode} - Lớp ${activeSession.classCode}`;
    document.getElementById('ticket-slot').textContent = `Slot ${activeSession.slot} (${getSlotTimeRange(activeSession.slot)})`;
    document.getElementById('ticket-timestamp').textContent = timeStr;
    document.getElementById('ticket-hash').textContent = hash;
  }

  function getSlotTimeRange(slot) {
    switch (slot) {
      case 1: return '7:00 - 9:15';
      case 2: return '9:30 - 11:45';
      case 3: return '12:30 - 14:45';
      case 4: return '15:00 - 17:15';
      case 5: return '17:30 - 19:45';
      case 6: return '20:00 - 22:15';
      default: return '7:00 - 9:15';
    }
  }

  // Done Ticket / New Scan
  btnDoneNewScan.addEventListener('click', () => {
    ticketView.style.display = 'none';
    checkinView.style.display = 'block';
    inputOtp.value = '';
    switchTab('camera');
  });
});
