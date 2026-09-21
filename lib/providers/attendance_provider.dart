import 'dart:async';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import '../models/student.dart';
import '../models/attendance_session.dart';
import '../models/fap_class_slot.dart';
import '../services/otp_service.dart';
import '../services/google_sheets_service.dart';
import '../services/attendance_api_service.dart';
import '../services/attendance_live_service.dart';
import '../services/student_csv_import_service.dart';

class AttendanceProvider extends ChangeNotifier {
  late AttendanceSession _currentSession;
  List<Student> _students = [];
  Timer? _otpTimer;
  Timer? _dashboardPollTimer;
  final GoogleSheetsService _sheetsService = GoogleSheetsService();
  final AttendanceApiService _attendanceApi = AttendanceApiService();
  final AttendanceLiveService _liveService = AttendanceLiveService();
  bool _sessionOperationInProgress = false;
  bool _refreshingDashboard = false;
  bool _otpRotationPaused = false;
  bool _otpPauseOperationInProgress = false;
  Future<void>? _rosterLoadFuture;
  List<Map<String, dynamic>> _auditLogs = [];
  List<Map<String, dynamic>> _deviceBindings = [];
  bool _deviceReleaseInProgress = false;
  bool _sheetsConfigurationInProgress = false;
  bool _demoSeedInProgress = false;
  final Set<String> _pendingAttendanceRollNos = {};
  bool _sheetsReachable = false;
  String? _sheetsConfigurationMessage;

  String _searchQuery = '';
  AttendanceStatus? _filterStatus;
  String? _lastCheckinNotification;

  // --- Timetable & Class/Slot Management ---
  List<FapClassSlot> _classSlots = [];
  FapClassSlot? _selectedSlot;
  DateTime _currentWeekStart = _getWeekStart(DateTime.now());
  String? _classCodeFilter;

  // Per-class student rosters: classCode -> List<Student>
  final Map<String, List<Student>> _classRosters = {};

  // Navigation callback (set by dashboard to switch tabs)
  VoidCallback? onNavigateToAttendance;

  AttendanceProvider() {
    _currentSession = AttendanceSession(
      classCode: '',
      subjectCode: '',
      slot: 0,
      date: DateTime.now(),
    );
    _loadSampleTimetable();
    _startOtpEngine();
    unawaited(loadGoogleSheetsConfiguration());
  }

  // Getters
  AttendanceSession get currentSession => _currentSession;
  List<Student> get students => _students;
  GoogleSheetsService get sheetsService => _sheetsService;
  String get searchQuery => _searchQuery;
  AttendanceStatus? get filterStatus => _filterStatus;
  String? get lastCheckinNotification => _lastCheckinNotification;
  List<FapClassSlot> get classSlots => _classSlots;
  FapClassSlot? get selectedSlot => _selectedSlot;
  DateTime get currentWeekStart => _currentWeekStart;
  String? get classCodeFilter => _classCodeFilter;
  List<String> get availableClassCodes {
    final codes = _classSlots
        .map((slot) => slot.classCode.trim().toUpperCase())
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();
    codes.sort();
    return codes;
  }

  bool get isSessionOpen => _currentSession.isOpen;
  bool get sessionOperationInProgress => _sessionOperationInProgress;
  bool get isOtpPaused => _otpRotationPaused;
  bool get otpPauseOperationInProgress => _otpPauseOperationInProgress;
  String? get serverSessionId => _currentSession.serverSessionId;
  bool isStatusUpdatePending(String rollNo) =>
      _pendingAttendanceRollNos.contains(rollNo);
  List<Map<String, dynamic>> get auditLogs => List.unmodifiable(_auditLogs);
  List<Map<String, dynamic>> get deviceConflicts => _deviceBindings
      .where((binding) => (binding['blockedAttempts'] as num? ?? 0) > 0)
      .toList(growable: false);
  bool get deviceReleaseInProgress => _deviceReleaseInProgress;
  bool get sheetsConfigurationInProgress => _sheetsConfigurationInProgress;
  bool get demoSeedInProgress => _demoSeedInProgress;
  bool get sheetsReachable => _sheetsReachable;
  String? get sheetsConfigurationMessage => _sheetsConfigurationMessage;
  String? get serverExportUrl => _currentSession.serverSessionId == null
      ? null
      : _attendanceApi.exportUrl(_currentSession.serverSessionId!);

  List<Student> get filteredStudents {
    return _students.where((s) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          s.rollNo.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.email.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesFilter = _filterStatus == null || s.status == _filterStatus;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  int get countPresent =>
      _students.where((s) => s.status == AttendanceStatus.present).length;
  int get countLate =>
      _students.where((s) => s.status == AttendanceStatus.late).length;
  int get countAbsent =>
      _students.where((s) => s.status == AttendanceStatus.absent).length;
  int get countNotChecked =>
      _students.where((s) => s.status == AttendanceStatus.notChecked).length;
  int get countTotal => _students.length;
  double get attendancePercentage =>
      countTotal == 0 ? 0 : (countPresent + countLate) / countTotal * 100;

  // Week navigation
  String get currentWeekLabel {
    final end = _currentWeekStart.add(const Duration(days: 6));
    return '${_formatDate(_currentWeekStart)} → ${_formatDate(end)}';
  }

  void previousWeek() {
    _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
    notifyListeners();
  }

  void nextWeek() {
    _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    notifyListeners();
  }

  void goToCurrentWeek() {
    _currentWeekStart = _getWeekStart(DateTime.now());
    notifyListeners();
  }

  void goToDate(DateTime date) {
    _currentWeekStart = _getWeekStart(date);
    notifyListeners();
  }

  /// Get slots for a specific day column and slot row in the timetable
  List<FapClassSlot> getSlotsForCell(int dayOfWeek, int slotNumber) {
    return _classSlots
        .where(
          (s) =>
              s.dayOfWeek == dayOfWeek &&
              s.slot == slotNumber &&
              (_classCodeFilter == null ||
                  s.classCode.toUpperCase() == _classCodeFilter),
        )
        .toList();
  }

  void setClassCodeFilter(String? classCode) {
    final normalized = classCode?.trim().toUpperCase();
    if (_currentSession.isOpen &&
        normalized != null &&
        normalized.isNotEmpty &&
        normalized != _currentSession.classCode.toUpperCase()) {
      _lastCheckinNotification =
          'Hãy đóng phiên ${_currentSession.classCode} trước khi lọc sang lớp khác.';
      notifyListeners();
      return;
    }
    _classCodeFilter = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (!_currentSession.isOpen &&
        _classCodeFilter != null &&
        _selectedSlot != null &&
        _selectedSlot!.classCode.toUpperCase() != _classCodeFilter) {
      _dashboardPollTimer?.cancel();
      unawaited(_liveService.disconnect());
      _selectedSlot = null;
      _students = [];
      _currentSession = AttendanceSession(
        classCode: '',
        subjectCode: '',
        slot: 0,
        date: DateTime.now(),
        activeOtp: _currentSession.activeOtp,
        otpRemainingSeconds: _currentSession.otpRemainingSeconds,
      );
    }
    notifyListeners();
  }

  /// Get date for a specific day column in the current week
  DateTime getDateForDay(int dayOfWeek) {
    return _currentWeekStart.add(Duration(days: dayOfWeek - 1));
  }

  // --- OTP Engine ---
  void _startOtpEngine() {
    _updateOtp();
    _otpTimer?.cancel();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_otpRotationPaused) return;
      _currentSession.otpRemainingSeconds = OtpService.getRemainingSeconds();
      if (_currentSession.otpRemainingSeconds == 10 ||
          _currentSession.activeOtp.isEmpty) {
        _updateOtp();
      }
      notifyListeners();
    });
  }

  void _updateOtp() {
    _currentSession.activeOtp = OtpService.generateOtpForTimeWindow();
  }

  // --- Search & Filter ---
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilterStatus(AttendanceStatus? status) {
    _filterStatus = status;
    notifyListeners();
  }

  // --- Session Management ---
  void updateSessionInfo({String? classCode, String? subjectCode, int? slot}) {
    _currentSession = AttendanceSession(
      classCode: classCode ?? _currentSession.classCode,
      subjectCode: subjectCode ?? _currentSession.subjectCode,
      slot: slot ?? _currentSession.slot,
      date: _currentSession.date,
      activeOtp: _currentSession.activeOtp,
      otpRemainingSeconds: _currentSession.otpRemainingSeconds,
      serverSessionId: _currentSession.serverSessionId,
      isOpen: _currentSession.isOpen,
      openedAt: _currentSession.openedAt,
      closedAt: _currentSession.closedAt,
    );
    notifyListeners();
  }

  Future<bool> openAttendanceSession() async {
    if (_sessionOperationInProgress) return false;
    await _rosterLoadFuture;
    if (_students.isEmpty) {
      _lastCheckinNotification =
          'Không thể mở phiên khi danh sách sinh viên đang trống.';
      notifyListeners();
      return false;
    }

    _sessionOperationInProgress = true;
    notifyListeners();
    try {
      final payload = await _attendanceApi.openSession(
        _currentSession,
        _students,
      );
      final snapshot = payload['session'];
      if (snapshot is! Map) {
        throw const AttendanceApiException(
          'API không trả về dữ liệu phiên.',
          500,
        );
      }

      _applyServerSnapshot(Map<String, dynamic>.from(snapshot));
      _lastCheckinNotification =
          payload['message']?.toString() ?? 'Đã mở phiên điểm danh.';
      await _connectLiveUpdates();
      _startDashboardPolling();
      await loadAuditLogs();
      return true;
    } catch (error) {
      _lastCheckinNotification = 'Không thể mở phiên: $error';
      return false;
    } finally {
      _sessionOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> closeAttendanceSession() async {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null || _sessionOperationInProgress) return false;

    _sessionOperationInProgress = true;
    notifyListeners();
    try {
      final payload = await _attendanceApi.closeSession(sessionId);
      final snapshot = payload['session'];
      if (snapshot is Map) {
        _applyServerSnapshot(Map<String, dynamic>.from(snapshot));
      }
      _lastCheckinNotification =
          payload['message']?.toString() ?? 'Đã đóng phiên điểm danh.';
      _otpRotationPaused = false;
      // FAP Demo can still correct Present/Absent after closing a session.
      // Keep the same SignalR group and polling fallback until another slot
      // is selected, so the closed-session dashboard remains synchronized.
      await loadAuditLogs();
      return true;
    } catch (error) {
      _lastCheckinNotification = 'Không thể đóng phiên: $error';
      return false;
    } finally {
      _sessionOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> pauseOtpRotation() async {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null ||
        !_currentSession.isOpen ||
        _otpPauseOperationInProgress ||
        _otpRotationPaused) {
      return false;
    }

    _otpPauseOperationInProgress = true;
    notifyListeners();
    try {
      final payload = await _attendanceApi.pauseOtp(sessionId);
      final snapshot = payload['session'];
      if (snapshot is! Map) {
        throw const AttendanceApiException(
          'API không trả về trạng thái OTP.',
          500,
        );
      }
      _applyServerSnapshot(Map<String, dynamic>.from(snapshot));
      _lastCheckinNotification =
          payload['message']?.toString() ?? 'Đã tạm dừng QR và OTP.';
      return true;
    } catch (error) {
      _lastCheckinNotification = 'Không thể tạm dừng OTP: $error';
      return false;
    } finally {
      _otpPauseOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> resumeOtpRotation() async {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null ||
        !_currentSession.isOpen ||
        _otpPauseOperationInProgress ||
        !_otpRotationPaused) {
      return false;
    }

    _otpPauseOperationInProgress = true;
    notifyListeners();
    try {
      final payload = await _attendanceApi.resumeOtp(sessionId);
      final snapshot = payload['session'];
      if (snapshot is! Map) {
        throw const AttendanceApiException(
          'API không trả về trạng thái OTP.',
          500,
        );
      }
      _applyServerSnapshot(Map<String, dynamic>.from(snapshot));
      _updateOtp();
      _currentSession.otpRemainingSeconds = OtpService.getRemainingSeconds();
      _lastCheckinNotification =
          payload['message']?.toString() ?? 'Đã tiếp tục xoay QR và OTP.';
      return true;
    } catch (error) {
      _lastCheckinNotification = 'Không thể tiếp tục OTP: $error';
      return false;
    } finally {
      _otpPauseOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> refreshSessionDashboard() async {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null || _refreshingDashboard) return;

    _refreshingDashboard = true;
    try {
      final snapshot = await _attendanceApi.getSession(sessionId);
      if (_currentSession.serverSessionId != sessionId) return;
      _applyServerSnapshot(snapshot);
    } catch (error) {
      debugPrint('Dashboard refresh failed: $error');
    } finally {
      _refreshingDashboard = false;
    }
  }

  Future<void> loadAuditLogs() async {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null) {
      _auditLogs = [];
      notifyListeners();
      return;
    }

    try {
      _auditLogs = await _attendanceApi.getAuditLogs(sessionId);
      notifyListeners();
    } catch (error) {
      debugPrint('Audit log refresh failed: $error');
    }
  }

  Future<bool> releaseDeviceBinding(int bindingId, String reason) async {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null || _deviceReleaseInProgress) return false;

    _deviceReleaseInProgress = true;
    notifyListeners();
    try {
      final payload = await _attendanceApi.releaseDeviceBinding(
        sessionId,
        bindingId,
        reason,
      );
      final snapshot = payload['session'];
      if (snapshot is Map) {
        _applyServerSnapshot(Map<String, dynamic>.from(snapshot));
      }
      _lastCheckinNotification =
          payload['message']?.toString() ?? 'Đã mở khóa thiết bị.';
      await loadAuditLogs();
      return true;
    } catch (error) {
      _lastCheckinNotification = 'Không thể mở khóa thiết bị: $error';
      return false;
    } finally {
      _deviceReleaseInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _connectLiveUpdates() async {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null) return;
    try {
      await _liveService.connect(
        baseUrl: _attendanceApi.baseUrl,
        sessionId: sessionId,
        onEvent: (eventName) {
          if (eventName == 'AttendanceUpdated' ||
              eventName == 'RosterUpdated' ||
              eventName == 'SessionClosed' ||
              eventName == 'SessionOpened' ||
              eventName == 'OtpPaused' ||
              eventName == 'OtpResumed' ||
              eventName == 'DeviceConflict' ||
              eventName == 'DeviceBindingReleased') {
            unawaited(refreshSessionDashboard());
            unawaited(loadAuditLogs());
          }
        },
      );
    } catch (error) {
      debugPrint('SignalR connection failed; polling remains active: $error');
    }
  }

  void _startDashboardPolling() {
    _dashboardPollTimer?.cancel();
    _dashboardPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(refreshSessionDashboard()),
    );
  }

  void _applyServerSnapshot(Map<String, dynamic> snapshot) {
    final wasOtpPaused = _otpRotationPaused;
    final previousBlockedAttempts = _deviceBindings.fold<int>(
      0,
      (total, binding) =>
          total + (binding['blockedAttempts'] as num? ?? 0).toInt(),
    );
    _currentSession.serverSessionId = snapshot['sessionId']?.toString();
    _currentSession.isOpen = snapshot['isOpen'] == true;
    _currentSession.openedAt = DateTime.tryParse(
      snapshot['openedAt']?.toString() ?? '',
    )?.toLocal();
    _currentSession.closedAt = DateTime.tryParse(
      snapshot['closedAt']?.toString() ?? '',
    )?.toLocal();

    _otpRotationPaused = snapshot['otpPaused'] == true;
    if (_otpRotationPaused) {
      final pausedOtp = snapshot['pausedOtp']?.toString();
      final remainingSeconds = snapshot['otpRemainingSeconds'];
      if (pausedOtp != null && pausedOtp.length == 6) {
        _currentSession.activeOtp = pausedOtp;
      }
      if (remainingSeconds is num) {
        _currentSession.otpRemainingSeconds = remainingSeconds.toInt();
      }
    } else if (wasOtpPaused) {
      _updateOtp();
      _currentSession.otpRemainingSeconds = OtpService.getRemainingSeconds();
    }

    final remoteStudents = snapshot['students'];
    if (remoteStudents is List) {
      _students = remoteStudents
          .whereType<Map>()
          .map((rawStudent) {
            final data = Map<String, dynamic>.from(rawStudent);
            final rollNo = data['rollNo']?.toString() ?? '';
            final status = AttendanceStatusExtension.fromString(
              data['status']?.toString() ?? '',
            );
            final checkinTime = DateTime.tryParse(
              data['checkinTime']?.toString() ?? '',
            )?.toLocal();
            return Student(
              rollNo: rollNo,
              fullName: data['fullName']?.toString() ?? rollNo,
              email: data['email']?.toString() ?? '',
              group: _currentSession.classCode,
              status: status,
              checkinTime: checkinTime,
              notes: data['notes']?.toString() ?? '',
            );
          })
          .where((student) => student.rollNo.isNotEmpty)
          .toList();
      _classRosters[_currentSession.classCode] = _students;
    }

    final remoteDeviceBindings = snapshot['deviceBindings'];
    if (remoteDeviceBindings is List) {
      _deviceBindings = remoteDeviceBindings
          .whereType<Map>()
          .map((binding) => Map<String, dynamic>.from(binding))
          .toList();
      final blockedAttempts = _deviceBindings.fold<int>(
        0,
        (total, binding) =>
            total + (binding['blockedAttempts'] as num? ?? 0).toInt(),
      );
      if (blockedAttempts > previousBlockedAttempts) {
        final latestConflict = deviceConflicts.firstOrNull;
        final attemptedRollNo =
            latestConflict?['lastBlockedRollNo']?.toString() ?? 'MSSV khác';
        _lastCheckinNotification =
            '⚠️ Đã chặn điểm danh hộ: thiết bị vừa thử dùng cho $attemptedRollNo.';
      }
    }

    notifyListeners();
  }

  /// Select a timetable slot without opening or closing an attendance session.
  /// Returns false when another session is currently open.
  bool selectTimetableSlot(FapClassSlot slot) {
    if (_currentSession.isOpen && _selectedSlot?.id != slot.id) {
      _lastCheckinNotification =
          'Hãy đóng phiên ${_currentSession.subjectCode} - ${_currentSession.classCode} trước khi chọn ca khác.';
      notifyListeners();
      return false;
    }

    if (_currentSession.isOpen && _selectedSlot?.id == slot.id) return true;
    if (_selectedSlot?.id == slot.id &&
        _currentSession.serverSessionId != null &&
        DateUtils.isSameDay(
          _currentSession.date,
          getDateForDay(slot.dayOfWeek),
        )) {
      return true;
    }

    _dashboardPollTimer?.cancel();
    unawaited(_liveService.disconnect());
    _selectedSlot = slot;
    _otpRotationPaused = false;
    _deviceBindings = [];
    _currentSession = AttendanceSession(
      classCode: slot.classCode,
      subjectCode: slot.subjectCode,
      slot: slot.slot,
      date: getDateForDay(slot.dayOfWeek),
      activeOtp: _currentSession.activeOtp,
      otpRemainingSeconds: _currentSession.otpRemainingSeconds,
    );

    // Load class-specific roster
    if (_classRosters.containsKey(slot.classCode)) {
      _students = _classRosters[slot.classCode]!
          .map(
            (s) => Student(
              rollNo: s.rollNo,
              fullName: s.fullName,
              email: s.email,
              group: s.group,
              status: AttendanceStatus.notChecked,
            ),
          )
          .toList();
    } else {
      _students = [];
    }

    _lastCheckinNotification =
        'Đã chọn ${slot.subjectCode} - ${slot.classCode} (Slot ${slot.slot})';
    notifyListeners();
    _rosterLoadFuture = _loadPersistedClassRoster(slot.classCode, slot.id);
    unawaited(_rosterLoadFuture);
    return true;
  }

  Future<void> _loadPersistedClassRoster(
    String classCode,
    String slotId,
  ) async {
    try {
      final roster = await _attendanceApi.getClassRoster(classCode);
      if (roster.isEmpty ||
          _selectedSlot?.id != slotId ||
          _currentSession.serverSessionId != null) {
        return;
      }

      final students = roster
          .map((data) {
            return Student(
              rollNo: data['rollNo']?.toString() ?? '',
              fullName: data['fullName']?.toString() ?? '',
              email: data['email']?.toString() ?? '',
              group: classCode,
            );
          })
          .where((student) => student.rollNo.isNotEmpty)
          .toList();
      _classRosters[classCode] = students;
      _students = students;
      notifyListeners();
    } catch (error) {
      debugPrint('Không thể tải roster đã lưu: $error');
    }
  }

  /// Select a timetable slot and switch to attendance mode.
  void selectSlotAndStartAttendance(FapClassSlot slot) {
    if (_selectedSlot?.id != slot.id && !selectTimetableSlot(slot)) return;

    // Trigger navigation to attendance tab
    onNavigateToAttendance?.call();
  }

  /// Add a new class slot to the timetable
  void addClassSlot(FapClassSlot newSlot) {
    _classSlots.add(newSlot);
    notifyListeners();
  }

  /// Remove a class slot
  void removeClassSlot(String slotId) {
    _classSlots.removeWhere((s) => s.id == slotId);
    notifyListeners();
  }

  /// Import students for a specific class from CSV content
  StudentCsvImportResult parseStudentCsv(String rawCsv, String classCode) {
    return StudentCsvImportService.parse(rawCsv, fallbackGroup: classCode);
  }

  Future<StudentCsvImportResult> importStudentsForClass(
    String classCode,
    String rawCsv,
  ) async {
    final result = parseStudentCsv(rawCsv, classCode);
    final payload = await _attendanceApi.syncClassRoster(
      classCode,
      result.students,
      sessionId:
          _currentSession.isOpen && _currentSession.classCode == classCode
          ? _currentSession.serverSessionId
          : null,
    );
    _classRosters[classCode] = result.students;

    // If current session matches, update live student list.
    if (_currentSession.classCode == classCode) {
      final snapshot = payload['session'];
      if (snapshot is Map) {
        _applyServerSnapshot(Map<String, dynamic>.from(snapshot));
      } else {
        _students = result.students;
      }
    }
    _lastCheckinNotification =
        payload['message']?.toString() ??
        'Đã lưu ${result.importedCount} sinh viên vào database.';
    notifyListeners();
    return result;
  }

  /// Import students for a class directly from Google Sheets
  Future<int> importStudentsFromGoogleSheets(
    String classCode,
    String sheetUrl,
  ) async {
    final students = await _sheetsService.fetchStudentsFromSheet(
      sheetUrl,
      classCode,
    );
    if (students.isNotEmpty) {
      await _attendanceApi.syncClassRoster(
        classCode,
        students,
        sessionId:
            _currentSession.isOpen && _currentSession.classCode == classCode
            ? _currentSession.serverSessionId
            : null,
      );
      _classRosters[classCode] = students;
      if (_currentSession.classCode == classCode) {
        _students = students;
      }
      notifyListeners();
      return students.length;
    }
    return 0;
  }

  /// Get student count for a specific class
  int getStudentCountForClass(String classCode) {
    return _classRosters[classCode]?.length ?? 0;
  }

  // --- Google Sheets ---
  Future<void> loadGoogleSheetsConfiguration({bool verify = false}) async {
    try {
      final payload = await _attendanceApi.getGoogleSheetsConfiguration(
        verify: verify,
      );
      final url = payload['webAppUrl']?.toString();
      _sheetsService.webAppUrl = url == null || url.isEmpty ? null : url;
      _sheetsReachable = payload['isReachable'] == true;
      _sheetsConfigurationMessage = payload['message']?.toString();
      notifyListeners();
    } catch (error) {
      _sheetsConfigurationMessage = 'Không thể đọc cấu hình backend: $error';
      notifyListeners();
    }
  }

  Future<bool> setGoogleSheetsUrl(String url) async {
    if (_sheetsConfigurationInProgress) return false;
    _sheetsConfigurationInProgress = true;
    notifyListeners();
    try {
      final payload = await _attendanceApi.configureGoogleSheets(url.trim());
      _sheetsService.webAppUrl = payload['webAppUrl']?.toString();
      _sheetsReachable = payload['isReachable'] == true;
      _sheetsConfigurationMessage = payload['message']?.toString();
      return _sheetsReachable;
    } catch (error) {
      _sheetsReachable = false;
      _sheetsConfigurationMessage = error.toString();
      return false;
    } finally {
      _sheetsConfigurationInProgress = false;
      notifyListeners();
    }
  }

  Future<bool> seedGoogleSheetsDemo() async {
    if (_demoSeedInProgress) return false;
    _demoSeedInProgress = true;
    notifyListeners();
    try {
      final payload = await _attendanceApi.seedGoogleSheetsDemo();
      final classCount = (payload['classCount'] as num?)?.toInt() ?? 0;
      final studentCount = (payload['studentCount'] as num?)?.toInt() ?? 0;
      _sheetsConfigurationMessage =
          payload['message']?.toString() ??
          'Đã tạo dữ liệu demo cho $classCount lớp, $studentCount sinh viên.';
      _lastCheckinNotification = '☁️ $_sheetsConfigurationMessage';

      final slot = _selectedSlot;
      if (slot != null) {
        await _loadPersistedClassRoster(slot.classCode, slot.id);
      }
      return true;
    } catch (error) {
      _sheetsConfigurationMessage =
          'Không seed được dữ liệu. Hãy cập nhật Apps Script lên bản mới rồi deploy lại: $error';
      _lastCheckinNotification = '⚠️ $_sheetsConfigurationMessage';
      return false;
    } finally {
      _demoSeedInProgress = false;
      notifyListeners();
    }
  }

  void toggleStudentStatus(Student student, AttendanceStatus newStatus) {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null) {
      _lastCheckinNotification =
          'Hãy mở phiên điểm danh trước khi sửa trạng thái để đồng bộ với FAP Demo.';
      notifyListeners();
      return;
    }
    if (student.status == newStatus ||
        _pendingAttendanceRollNos.contains(student.rollNo)) {
      return;
    }
    final previousStatus = student.status;
    _pendingAttendanceRollNos.add(student.rollNo);
    student.status = newStatus;
    student.checkinTime =
        (newStatus == AttendanceStatus.present ||
            newStatus == AttendanceStatus.late)
        ? DateTime.now()
        : null;
    notifyListeners();
    unawaited(
      _updateServerAttendance(sessionId, student, newStatus, previousStatus),
    );
  }

  Future<void> _updateServerAttendance(
    String sessionId,
    Student student,
    AttendanceStatus newStatus,
    AttendanceStatus previousStatus,
  ) async {
    try {
      final payload = await _attendanceApi.updateAttendance(
        sessionId,
        student.rollNo,
        newStatus,
        expectedStatus: previousStatus,
      );
      final snapshot = payload['session'];
      if (snapshot is Map && _currentSession.serverSessionId == sessionId) {
        _applyServerSnapshot(Map<String, dynamic>.from(snapshot));
      }
      await loadAuditLogs();
    } catch (error) {
      _lastCheckinNotification = 'Không thể cập nhật trạng thái: $error';
      await refreshSessionDashboard();
      notifyListeners();
    } finally {
      _pendingAttendanceRollNos.remove(student.rollNo);
      notifyListeners();
    }
  }

  /// Student attendance submission via email and 10s OTP
  Map<String, dynamic> checkinStudent({
    required String email,
    required String otp,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    final cleanOtp = otp.trim();

    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(cleanEmail)) {
      return {
        'success': false,
        'message': 'Vui lòng nhập một địa chỉ email hợp lệ.',
      };
    }

    final isValidOtp = OtpService.validateOtp(cleanOtp);
    if (!isValidOtp) {
      return {
        'success': false,
        'message':
            'Mã OTP không hợp lệ hoặc đã hết hạn (Mã OTP tự động thay đổi mỗi 10s).',
      };
    }

    final index = _students.indexWhere(
      (s) =>
          s.email.toLowerCase() == cleanEmail ||
          cleanEmail.contains(s.rollNo.toLowerCase()),
    );

    if (index != -1) {
      final student = _students[index];
      student.status = AttendanceStatus.present;
      student.checkinTime = DateTime.now();
      student.notes = 'Checked in via OTP QR';

      _lastCheckinNotification =
          '✅ ${student.fullName} (${student.rollNo}) đã điểm danh thành công!';
      notifyListeners();

      return {
        'success': true,
        'message':
            'Điểm danh thành công cho sinh viên ${student.fullName} (${student.rollNo})!',
        'student': student,
      };
    } else {
      final newRollNo = cleanEmail.split('@').first.toUpperCase();
      final newStudent = Student(
        rollNo: newRollNo,
        fullName: newRollNo,
        email: cleanEmail,
        group: _currentSession.classCode,
        status: AttendanceStatus.present,
        checkinTime: DateTime.now(),
        notes: 'Auto-added via OTP Check-in',
      );
      _students.add(newStudent);
      _lastCheckinNotification =
          '✅ Thêm & điểm danh thành công cho $cleanEmail!';
      notifyListeners();

      return {
        'success': true,
        'message': 'Thêm sinh viên mới & điểm danh thành công!',
        'student': newStudent,
      };
    }
  }

  Future<StudentCsvImportResult> importCsvContent(String rawCsv) {
    return importStudentsForClass(_currentSession.classCode, rawCsv);
  }

  String exportFapCsv() {
    final List<List<dynamic>> rows = [
      [
        'RollNo',
        'FullName',
        'Email',
        'Group',
        'Status',
        'CheckinTime',
        'Slot',
        'Date',
      ],
    ];

    for (var s in _students) {
      rows.add([
        s.rollNo,
        s.fullName,
        s.email,
        s.group,
        s.status.toLabel(),
        s.checkinTime?.toIso8601String() ?? '',
        _currentSession.slot,
        _currentSession.date.toIso8601String().split('T').first,
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  Future<bool> syncWithGoogleSheets() async {
    final sessionId = _currentSession.serverSessionId;
    if (sessionId == null) {
      _lastCheckinNotification =
          '⚠️ Chưa có phiên điểm danh để đồng bộ Google Sheets.';
      notifyListeners();
      return false;
    }
    try {
      await _attendanceApi.syncSessionToGoogleSheets(sessionId);
      _lastCheckinNotification =
          '☁️ Đã ghi lại phiên vào database Google Sheets.';
      notifyListeners();
      return true;
    } catch (error) {
      _lastCheckinNotification =
          '⚠️ Không thể ghi database Google Sheets: $error';
      notifyListeners();
      return false;
    }
  }

  // --- Sample Data ---
  void _loadSampleTimetable() {
    _classSlots = [
      FapClassSlot(
        id: 'prn232-mon-1',
        subjectCode: 'PRN232',
        subjectName: 'Building Cross-Platform Back-End Application With .NET',
        classCode: 'SE1917',
        slot: 1,
        dayOfWeek: 1,
        room: 'NVH 602',
        slotTime: '7:00 - 9:15',
        sessionNumber: 3,
        instructor: 'PhuongLHK',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'prm393-mon-2',
        subjectCode: 'PRM393',
        subjectName: 'Mobile Development',
        classCode: 'SE1918',
        slot: 2,
        dayOfWeek: 1,
        room: 'NVH 602',
        slotTime: '9:30 - 11:45',
        instructor: 'PhuongLHK',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'exe201-tue-1',
        subjectCode: 'EXE201',
        subjectName: 'Experiential Entrepreneurship 1',
        classCode: 'SE1919',
        slot: 1,
        dayOfWeek: 2,
        room: 'NVH 707',
        slotTime: '7:00 - 9:15',
        instructor: 'ThanhNV',
        campus: 'FUHCM',
        isOnline: true,
      ),
      FapClassSlot(
        id: 'swp391-tue-2',
        subjectCode: 'SWP391',
        subjectName: 'Application development project',
        classCode: 'SE1918',
        slot: 2,
        dayOfWeek: 2,
        room: 'NVH 612',
        slotTime: '9:30 - 11:45',
        instructor: 'TuanPM',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'mln111-tue-3',
        subjectCode: 'MLN111',
        subjectName: 'Philosophy of Marxism-Leninism',
        classCode: 'SE1917',
        slot: 3,
        dayOfWeek: 2,
        room: 'NVH 404',
        slotTime: '12:30 - 14:45',
        instructor: 'HungNQ',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'prn232-thu-1',
        subjectCode: 'PRN232',
        subjectName: 'Building Cross-Platform Back-End Application With .NET',
        classCode: 'SE1917',
        slot: 1,
        dayOfWeek: 4,
        room: 'NVH 602',
        slotTime: '7:00 - 9:15',
        sessionNumber: 4,
        instructor: 'PhuongLHK',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'prm393-thu-2',
        subjectCode: 'PRM393',
        subjectName: 'Mobile Development',
        classCode: 'SE1918',
        slot: 2,
        dayOfWeek: 4,
        room: 'NVH 602',
        slotTime: '9:30 - 11:45',
        instructor: 'PhuongLHK',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'mln111-fri-3',
        subjectCode: 'MLN111',
        subjectName: 'Philosophy of Marxism-Leninism',
        classCode: 'SE1917',
        slot: 3,
        dayOfWeek: 5,
        room: 'NVH 404',
        slotTime: '12:30 - 14:45',
        instructor: 'HungNQ',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'swp391-fri-2',
        subjectCode: 'SWP391',
        subjectName: 'Application development project',
        classCode: 'SE1918',
        slot: 2,
        dayOfWeek: 5,
        room: 'NVH 612',
        slotTime: '9:30 - 11:45',
        instructor: 'TuanPM',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'ite302c-fri-7',
        subjectCode: 'ITE302c',
        subjectName: 'Ethics in IT',
        classCode: 'SE1917',
        slot: 5,
        dayOfWeek: 5,
        room: 'Online',
        slotTime: '17:45 - 19:15',
        instructor: 'LongDT',
        campus: 'FUHCM',
        isOnline: true,
        meetUrl: 'https://meet.google.com/abc-defg-hij',
      ),
      FapClassSlot(
        id: 'mln111-sat-1',
        subjectCode: 'MLN111',
        subjectName: 'Philosophy of Marxism-Leninism',
        classCode: 'SE1917',
        slot: 1,
        dayOfWeek: 6,
        room: 'NVH 612',
        slotTime: '7:00 - 9:15',
        instructor: 'HungNQ',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'hcm202-mon-4',
        subjectCode: 'HCM202',
        subjectName: 'Ho Chi Minh Ideology',
        classCode: 'SE1920',
        slot: 4,
        dayOfWeek: 1,
        room: 'NVH 307',
        slotTime: '15:00 - 17:15',
        sessionNumber: 5,
        instructor: 'HaNT',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'hcm202-thu-4',
        subjectCode: 'HCM202',
        subjectName: 'Ho Chi Minh Ideology',
        classCode: 'SE1920',
        slot: 4,
        dayOfWeek: 4,
        room: 'NVH 307',
        slotTime: '15:00 - 17:15',
        sessionNumber: 6,
        instructor: 'HaNT',
        campus: 'FUHCM',
      ),
    ];

    // Pre-populate rosters
    _classRosters['SE1917'] = [
      Student(
        rollNo: 'SE182173',
        fullName: 'Bùi Nhật Minh',
        email: 'minhnbse182173@fpt.edu.vn',
        group: 'SE1917',
      ),
      Student(
        rollNo: 'SE171234',
        fullName: 'Nguyen Van Nam',
        email: 'namnvse171234@fpt.edu.vn',
        group: 'SE1917',
      ),
      Student(
        rollNo: 'SE180987',
        fullName: 'Tran Thi Mai',
        email: 'maittse180987@fpt.edu.vn',
        group: 'SE1917',
      ),
      Student(
        rollNo: 'SE183456',
        fullName: 'Le Hoang Long',
        email: 'longlhse183456@fpt.edu.vn',
        group: 'SE1917',
      ),
    ];
    _classRosters['SE1918'] = [
      Student(
        rollNo: 'SE182173',
        fullName: 'Bùi Nhật Minh',
        email: 'minhnbse182173@fpt.edu.vn',
        group: 'SE1918',
      ),
      Student(
        rollNo: 'SE185111',
        fullName: 'Pham Thu Ha',
        email: 'haptse185111@fpt.edu.vn',
        group: 'SE1918',
      ),
      Student(
        rollNo: 'SE186222',
        fullName: 'Dao Minh Tuan',
        email: 'tuandmse186222@fpt.edu.vn',
        group: 'SE1918',
      ),
    ];
    _classRosters['SE1919'] = [
      Student(
        rollNo: 'SE191901',
        fullName: 'Nguyễn Minh Anh',
        email: 'anhngmse191901@fpt.edu.vn',
        group: 'SE1919',
      ),
      Student(
        rollNo: 'SE191902',
        fullName: 'Trần Gia Huy',
        email: 'huytgse191902@fpt.edu.vn',
        group: 'SE1919',
      ),
      Student(
        rollNo: 'SE191903',
        fullName: 'Lê Hoàng Yến',
        email: 'yenlhse191903@fpt.edu.vn',
        group: 'SE1919',
      ),
    ];
    _classRosters['SE1920'] = [
      Student(
        rollNo: 'SE192001',
        fullName: 'Phạm Khánh Linh',
        email: 'linhpkse192001@fpt.edu.vn',
        group: 'SE1920',
      ),
      Student(
        rollNo: 'SE192002',
        fullName: 'Võ Quốc Bảo',
        email: 'baovqse192002@fpt.edu.vn',
        group: 'SE1920',
      ),
      Student(
        rollNo: 'SE192003',
        fullName: 'Đỗ Thu Trang',
        email: 'trangdtse192003@fpt.edu.vn',
        group: 'SE1920',
      ),
    ];
  }

  // --- Helpers ---
  static DateTime _getWeekStart(DateTime date) {
    final weekday = date.weekday; // 1=Mon
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: weekday - 1));
  }

  static String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _dashboardPollTimer?.cancel();
    unawaited(_liveService.disconnect());
    super.dispose();
  }
}
