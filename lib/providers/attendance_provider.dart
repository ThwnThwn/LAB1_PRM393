import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student.dart';
import '../models/attendance_session.dart';
import '../models/fap_class_slot.dart';
import '../services/otp_service.dart';
import '../services/google_sheets_service.dart';
import '../services/attendance_api_service.dart';
import '../services/attendance_session_matcher.dart';
import '../services/attendance_live_service.dart';
import '../services/student_csv_import_service.dart';
import '../services/student_roster_import_service.dart';
import 'otp_provider.dart';

class AttendanceProvider extends ChangeNotifier {
  static const String _timetablePreferenceKey =
      'fap_attendance_teacher_timetable_v1';
  static const String _timetableAnchorWeekPreferenceKey =
      'fap_attendance_teacher_timetable_anchor_week_v1';
  static const String _lastSelectedSlotPreferenceKey =
      'fap_attendance_last_selected_slot_v1';
  late AttendanceSession _currentSession;
  List<Student> _students = [];
  Timer? _dashboardPollTimer;
  final GoogleSheetsService _sheetsService = GoogleSheetsService();
  final AttendanceApiService _attendanceApi;
  final AttendanceLiveService _liveService;
  OtpProvider? _otpProvider;
  bool _sessionOperationInProgress = false;
  bool _loadingSelectedSession = false;
  bool _refreshingDashboard = false;
  bool _otpPauseOperationInProgress = false;
  Future<void>? _rosterLoadFuture;
  List<Map<String, dynamic>> _auditLogs = [];
  List<Map<String, dynamic>> _deviceBindings = [];
  bool _deviceReleaseInProgress = false;
  bool _sheetsConfigurationInProgress = false;
  bool _demoSeedInProgress = false;
  final Set<String> _pendingAttendanceRollNos = {};
  final Map<String, _AttendanceDraft> _attendanceDrafts = {};
  final Map<String, Student> _latestServerStudents = {};
  bool _savingAttendanceDraft = false;
  int _draftSaveGeneration = 0;
  bool _sheetsReachable = false;

  // --- Cache fields (Fix 3) ---
  int _studentsVersion = 0;
  List<Student>? _cachedFilteredStudents;
  String _cachedSearchQuery = '';
  AttendanceStatus? _cachedFilterStatus;
  int _cachedFilterVersion = -1;
  int _cachedCountPresent = 0;
  int _cachedCountAbsent = 0;
  int _cachedCountVersion = -1;
  List<String>? _cachedClassCodes;
  String? _sheetsConfigurationMessage;

  String _searchQuery = '';
  AttendanceStatus? _filterStatus;
  String? _lastCheckinNotification;

  // --- Timetable & Class/Slot Management ---
  List<FapClassSlot> _classSlots = [];
  late final Future<void> _timetableLoadFuture;
  Future<bool>? _initialDashboardSelectionFuture;
  bool _initialDashboardLoadInProgress = false;
  String? _lastSelectedSlotId;
  List<Map<String, dynamic>>? _initialDashboardSessions;
  FapClassSlot? _selectedSlot;
  DateTime _currentWeekStart = _getWeekStart(DateTime.now());
  DateTime _timetableMeetingAnchorWeekStart = _getWeekStart(DateTime.now());
  String? _classCodeFilter;

  // Per-class student rosters: classCode -> List<Student>
  final Map<String, List<Student>> _classRosters = {};
  final Map<String, int> _courseAbsenceCounts = {};
  int _courseTotalSessions = 20;
  int _courseCompletedSessions = 0;

  // Navigation callback (set by dashboard to switch tabs)
  VoidCallback? onNavigateToAttendance;

  AttendanceProvider({
    AttendanceApiService? attendanceApi,
    AttendanceLiveService? liveService,
  }) : _attendanceApi = attendanceApi ?? AttendanceApiService(),
       _liveService = liveService ?? AttendanceLiveService() {
    _currentSession = AttendanceSession(
      classCode: '',
      subjectCode: '',
      slot: 0,
      date: DateTime.now(),
    );
    _loadSampleTimetable();
    _timetableLoadFuture = _loadSavedTimetable();
    unawaited(_timetableLoadFuture);
    unawaited(loadGoogleSheetsConfiguration(verify: true));
  }

  /// Injects [OtpProvider] reference. Called from MultiProvider setup.
  set otpProvider(OtpProvider provider) => _otpProvider = provider;

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
  DateTime get timetableMeetingAnchorWeekStart =>
      _timetableMeetingAnchorWeekStart;
  String? get classCodeFilter => _classCodeFilter;
  List<String> get availableClassCodes {
    return _cachedClassCodes ??= () {
      final codes =
          _classSlots
              .map((slot) => slot.classCode.trim().toUpperCase())
              .where((code) => code.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return codes;
    }();
  }

  bool get isSessionOpen => _currentSession.isOpen;
  bool get sessionOperationInProgress => _sessionOperationInProgress;
  bool get loadingSelectedSession => _loadingSelectedSession;
  bool get initialDashboardLoadInProgress => _initialDashboardLoadInProgress;
  bool get isOtpPaused => _otpProvider?.isPaused ?? false;
  bool get otpPauseOperationInProgress => _otpPauseOperationInProgress;
  String? get serverSessionId => _currentSession.serverSessionId;
  bool isStatusUpdatePending(String rollNo) =>
      _pendingAttendanceRollNos.contains(rollNo);
  bool get hasUnsavedAttendanceChanges => _attendanceDrafts.isNotEmpty;
  int get unsavedAttendanceCount => _attendanceDrafts.length;
  bool get savingAttendanceDraft => _savingAttendanceDraft;
  bool isAttendanceDrafted(String rollNo) =>
      _attendanceDrafts.containsKey(rollNo);
  bool isAttendanceDraftConflicted(String rollNo) {
    final draft = _attendanceDrafts[rollNo];
    final remote = _latestServerStudents[rollNo];
    return draft != null &&
        remote != null &&
        remote.status != draft.originalStatus;
  }

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
    if (_cachedFilteredStudents != null &&
        _cachedSearchQuery == _searchQuery &&
        _cachedFilterStatus == _filterStatus &&
        _cachedFilterVersion == _studentsVersion) {
      return _cachedFilteredStudents!;
    }
    final query = _searchQuery.toLowerCase();
    _cachedFilteredStudents = _students.where((s) {
      final matchesSearch =
          query.isEmpty ||
          s.rollNo.toLowerCase().contains(query) ||
          s.fullName.toLowerCase().contains(query) ||
          s.email.toLowerCase().contains(query);
      final matchesFilter = _filterStatus == null || s.status == _filterStatus;
      return matchesSearch && matchesFilter;
    }).toList();
    _cachedSearchQuery = _searchQuery;
    _cachedFilterStatus = _filterStatus;
    _cachedFilterVersion = _studentsVersion;
    return _cachedFilteredStudents!;
  }

  void _refreshCounts() {
    if (_cachedCountVersion == _studentsVersion) return;
    _cachedCountPresent = 0;
    _cachedCountAbsent = 0;
    for (final s in _students) {
      if (s.status == AttendanceStatus.present) {
        _cachedCountPresent++;
      } else if (s.status == AttendanceStatus.absent) {
        _cachedCountAbsent++;
      }
    }
    _cachedCountVersion = _studentsVersion;
  }

  int get countPresent {
    _refreshCounts();
    return _cachedCountPresent;
  }

  int get countAbsent {
    _refreshCounts();
    return _cachedCountAbsent;
  }

  int get countTotal => _students.length;
  double get attendancePercentage =>
      countTotal == 0 ? 0 : countPresent / countTotal * 100;

  int get courseCompletedSessions => _courseCompletedSessions;

  List<CourseAttendanceWarning> get attendanceWarnings {
    final totalSessions = _courseTotalSessions <= 0 ? 20 : _courseTotalSessions;
    final warningThreshold = (totalSessions + 4) ~/ 5;
    final warnings = _students
        .map((student) {
          final absentSessions = _courseAbsenceCounts[student.rollNo] ?? 0;
          return CourseAttendanceWarning(
            student: student,
            absentSessions: absentSessions,
            totalSessions: totalSessions,
          );
        })
        .where((warning) => warning.absentSessions >= warningThreshold)
        .toList();
    warnings.sort((left, right) {
      final absenceComparison = right.absentSessions.compareTo(
        left.absentSessions,
      );
      return absenceComparison != 0
          ? absenceComparison
          : left.student.rollNo.compareTo(right.student.rollNo);
    });
    return warnings;
  }

  void clearLastCheckinNotification() {
    if (_lastCheckinNotification == null) return;
    _lastCheckinNotification = null;
    notifyListeners();
  }

  // Week navigation
  String get currentWeekLabel {
    final end = _currentWeekStart.add(const Duration(days: 6));
    return '${_formatDate(_currentWeekStart)} → ${_formatDate(end)}';
  }

  void previousWeek() {
    if (!_canChangeWeek()) return;
    _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
    notifyListeners();
  }

  void nextWeek() {
    if (!_canChangeWeek()) return;
    _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    notifyListeners();
  }

  void goToCurrentWeek() {
    if (!_canChangeWeek()) return;
    _currentWeekStart = _getWeekStart(DateTime.now());
    notifyListeners();
  }

  void goToDate(DateTime date) {
    if (!_canChangeWeek()) return;
    _currentWeekStart = _getWeekStart(date);
    notifyListeners();
  }

  bool _canChangeWeek() {
    if (!hasUnsavedAttendanceChanges && !_savingAttendanceDraft) return true;
    _lastCheckinNotification =
        '⚠️ Hãy lưu hoặc hủy bản nháp điểm danh trước khi đổi tuần.';
    notifyListeners();
    return false;
  }

  /// Get slots for a specific day column and slot row in the timetable
  List<FapClassSlot> getSlotsForCell(int dayOfWeek, int slotNumber) {
    final date = getDateForDay(dayOfWeek);
    return _classSlots
        .where(
          (s) =>
              s.dayOfWeek == dayOfWeek &&
              s.slot == slotNumber &&
              (_classCodeFilter == null ||
                  s.classCode.toUpperCase() == _classCodeFilter),
        )
        .map((slot) => meetingOccurrenceForDate(slot, date))
        .whereType<FapClassSlot>()
        .toList();
  }

  void setClassCodeFilter(String? classCode) {
    final normalized = classCode?.trim().toUpperCase();
    final nextFilter = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (_currentSession.isOpen &&
        normalized != null &&
        normalized.isNotEmpty &&
        normalized != _currentSession.classCode.toUpperCase()) {
      _lastCheckinNotification =
          'Hãy đóng phiên ${_currentSession.classCode} trước khi lọc sang lớp khác.';
      notifyListeners();
      return;
    }
    if (hasUnsavedAttendanceChanges &&
        nextFilter != null &&
        _selectedSlot != null &&
        _selectedSlot!.classCode.toUpperCase() != nextFilter) {
      _lastCheckinNotification =
          '⚠️ Còn $unsavedAttendanceCount dòng chưa lưu. Hãy lưu hoặc hủy bản nháp trước khi đổi lớp.';
      notifyListeners();
      return;
    }
    _classCodeFilter = nextFilter;
    if (!_currentSession.isOpen &&
        _classCodeFilter != null &&
        _selectedSlot != null &&
        _selectedSlot!.classCode.toUpperCase() != _classCodeFilter) {
      _dashboardPollTimer?.cancel();
      unawaited(_liveService.disconnect());
      _selectedSlot = null;
      _students = [];
      _studentsVersion++;
      _latestServerStudents.clear();
      _courseAbsenceCounts.clear();
      _courseCompletedSessions = 0;
      _currentSession = AttendanceSession(
        classCode: '',
        subjectCode: '',
        slot: 0,
        date: DateTime.now(),
      );
    }
    notifyListeners();
  }

  /// Get date for a specific day column in the current week
  DateTime getDateForDay(int dayOfWeek) {
    return _currentWeekStart.add(Duration(days: dayOfWeek - 1));
  }

  /// Resolves a recurring timetable template into its chronological course
  /// meeting for [date]. The template's meeting number anchors the current
  /// timetable week; other weeks advance by the number of weekly meetings.
  FapClassSlot? meetingOccurrenceForDate(FapClassSlot template, DateTime date) {
    final targetDate = DateUtils.dateOnly(date);
    if (targetDate.weekday != template.dayOfWeek) return null;

    final courseSlots =
        _classSlots.where((slot) {
          return slot.classCode.trim().toUpperCase() ==
                  template.classCode.trim().toUpperCase() &&
              slot.subjectCode.trim().toUpperCase() ==
                  template.subjectCode.trim().toUpperCase();
        }).toList()..sort((left, right) {
          final dayOrder = left.dayOfWeek.compareTo(right.dayOfWeek);
          if (dayOrder != 0) return dayOrder;
          final slotOrder = left.slot.compareTo(right.slot);
          if (slotOrder != 0) return slotOrder;
          return left.id.compareTo(right.id);
        });
    if (courseSlots.isEmpty) return null;

    final templateIndex = courseSlots.indexWhere(
      (slot) => slot.id == template.id,
    );
    if (templateIndex < 0) return null;

    var anchorMeetingNumber = courseSlots.first.sessionNumber;
    var totalSessions = courseSlots.first.totalSessions;
    for (final slot in courseSlots.skip(1)) {
      if (slot.sessionNumber < anchorMeetingNumber) {
        anchorMeetingNumber = slot.sessionNumber;
      }
      if (slot.totalSessions > totalSessions) {
        totalSessions = slot.totalSessions;
      }
    }
    if (anchorMeetingNumber < 1) anchorMeetingNumber = 1;
    if (totalSessions < anchorMeetingNumber) {
      totalSessions = anchorMeetingNumber;
    }

    final targetWeekStart = _getWeekStart(targetDate);
    final weekOffset =
        targetWeekStart.difference(_timetableMeetingAnchorWeekStart).inDays ~/
        7;
    final meetingNumber =
        anchorMeetingNumber + weekOffset * courseSlots.length + templateIndex;
    if (meetingNumber < 1 || meetingNumber > totalSessions) return null;

    return FapClassSlot(
      id: template.id,
      subjectCode: template.subjectCode,
      subjectName: template.subjectName,
      classCode: template.classCode,
      slot: template.slot,
      dayOfWeek: template.dayOfWeek,
      room: template.room,
      slotTime: template.slotTime,
      sessionNumber: meetingNumber,
      totalSessions: totalSessions,
      instructor: template.instructor,
      campus: template.campus,
      meetUrl: template.meetUrl,
      isOnline: template.isOnline,
    );
  }

  // OTP engine moved to OtpProvider (Fix 1).

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
      sessionNumber: _currentSession.sessionNumber,
      totalSessions: _currentSession.totalSessions,
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
    if (hasUnsavedAttendanceChanges || _savingAttendanceDraft) {
      _lastCheckinNotification =
          '⚠️ Hãy lưu hoặc hủy các dòng đã sửa trước khi mở phiên.';
      notifyListeners();
      return false;
    }
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
      _otpProvider?.resume();
      await _refreshSelectedCourseAttendanceHistory();
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
        isOtpPaused) {
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
        !isOtpPaused) {
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
      _otpProvider?.resume();
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
    if (sessionId == null || _refreshingDashboard || _savingAttendanceDraft) {
      return;
    }

    _refreshingDashboard = true;
    final saveGeneration = _draftSaveGeneration;
    try {
      final snapshot = await _attendanceApi.getSession(sessionId);
      if (_currentSession.serverSessionId != sessionId ||
          _savingAttendanceDraft ||
          saveGeneration != _draftSaveGeneration) {
        return;
      }
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
      final logs = await _attendanceApi.getAuditLogs(sessionId);
      if (_currentSession.serverSessionId != sessionId) return;
      _auditLogs = logs;
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
      if (_currentSession.serverSessionId != sessionId) {
        await _liveService.disconnect();
      }
    } catch (error) {
      debugPrint('SignalR connection failed; polling remains active: $error');
    }
  }

  void _startDashboardPolling() {
    _dashboardPollTimer?.cancel();
    // Fix 4: increased from 5s to 15s — SignalR is the primary update channel.
    _dashboardPollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(refreshSessionDashboard()),
    );
  }

  void _applyServerSnapshot(Map<String, dynamic> snapshot) {
    final previousBlockedAttempts = _deviceBindings.fold<int>(
      0,
      (total, binding) =>
          total + (binding['blockedAttempts'] as num? ?? 0).toInt(),
    );
    _currentSession.serverSessionId = snapshot['sessionId']?.toString();
    final serverSessionNumber = (snapshot['sessionNumber'] as num?)?.toInt();
    final serverTotalSessions = (snapshot['totalSessions'] as num?)?.toInt();
    if (_selectedSlot != null) {
      // The calendar occurrence is chronological and wins over legacy rows
      // whose MeetingNumber was saved before date-based numbering existed.
      _currentSession.sessionNumber = _selectedSlot!.sessionNumber;
      _currentSession.totalSessions = _selectedSlot!.totalSessions;
    } else if (serverSessionNumber != null && serverSessionNumber > 0) {
      _currentSession.sessionNumber = serverSessionNumber;
    }
    if (_selectedSlot == null &&
        serverTotalSessions != null &&
        serverTotalSessions > 0) {
      _currentSession.totalSessions = serverTotalSessions;
    }
    _currentSession.isOpen = snapshot['isOpen'] == true;
    _currentSession.openedAt = DateTime.tryParse(
      snapshot['openedAt']?.toString() ?? '',
    )?.toLocal();
    _currentSession.closedAt = DateTime.tryParse(
      snapshot['closedAt']?.toString() ?? '',
    )?.toLocal();

    // Keep the session fields populated for standalone widgets/tests, while
    // the isolated provider remains the high-frequency source in the app.
    final pausedOtp = snapshot['pausedOtp']?.toString();
    final remainingSeconds = (snapshot['otpRemainingSeconds'] as num?)?.toInt();
    if (pausedOtp != null && pausedOtp.length == 6) {
      _currentSession.activeOtp = pausedOtp;
    }
    if (remainingSeconds != null) {
      _currentSession.otpRemainingSeconds = remainingSeconds;
    }

    // Delegate OTP pause state to the isolated OtpProvider (Fix 1).
    _otpProvider?.syncFromSnapshot(
      paused: snapshot['otpPaused'] == true,
      frozenOtp: pausedOtp,
      frozenSeconds: remainingSeconds,
    );

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
      _studentsVersion++; // Invalidate caches (Fix 3).
      _latestServerStudents
        ..clear()
        ..addEntries(
          _students.map(
            (student) => MapEntry(
              student.rollNo,
              Student(
                rollNo: student.rollNo,
                fullName: student.fullName,
                email: student.email,
                group: student.group,
                status: student.status,
                checkinTime: student.checkinTime,
                notes: student.notes,
              ),
            ),
          ),
        );
      for (final student in _students) {
        final draft = _attendanceDrafts[student.rollNo];
        if (draft != null) {
          if (student.status == draft.status) {
            _attendanceDrafts.remove(student.rollNo);
            continue;
          }
          student.status = draft.status;
          student.checkinTime = draft.checkinTime;
        }
      }
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
    final sessionDate = getDateForDay(slot.dayOfWeek);
    final occurrence = meetingOccurrenceForDate(slot, sessionDate);
    if (occurrence == null) {
      _lastCheckinNotification =
          'Ngày này nằm ngoài ${slot.totalSessions} buổi của môn ${slot.subjectCode}.';
      notifyListeners();
      return false;
    }
    if ((_selectedSlot?.id != occurrence.id ||
            !DateUtils.isSameDay(_currentSession.date, sessionDate)) &&
        (hasUnsavedAttendanceChanges || _savingAttendanceDraft)) {
      _lastCheckinNotification =
          '⚠️ Còn $unsavedAttendanceCount dòng chưa lưu. Hãy lưu hoặc hủy bản nháp trước khi đổi ca.';
      notifyListeners();
      return false;
    }
    if (_currentSession.isOpen && _selectedSlot?.id != occurrence.id) {
      _lastCheckinNotification =
          'Hãy đóng phiên ${_currentSession.subjectCode} - ${_currentSession.classCode} trước khi chọn ca khác.';
      notifyListeners();
      return false;
    }

    if (_currentSession.isOpen && _selectedSlot?.id == occurrence.id) {
      return true;
    }
    if (_selectedSlot?.id == occurrence.id &&
        _currentSession.serverSessionId != null &&
        DateUtils.isSameDay(_currentSession.date, sessionDate)) {
      return true;
    }

    _dashboardPollTimer?.cancel();
    unawaited(_liveService.disconnect());
    _selectedSlot = occurrence;
    _lastSelectedSlotId = slot.id;
    unawaited(_persistLastSelectedSlotId(slot.id));
    _latestServerStudents.clear();
    _otpProvider?.resume();
    _deviceBindings = [];
    _courseAbsenceCounts.clear();
    _courseTotalSessions = occurrence.totalSessions;
    _courseCompletedSessions = 0;
    _currentSession = AttendanceSession(
      classCode: occurrence.classCode,
      subjectCode: occurrence.subjectCode,
      slot: occurrence.slot,
      date: sessionDate,
      sessionNumber: occurrence.sessionNumber,
      totalSessions: occurrence.totalSessions,
    );

    _students = [];
    _studentsVersion++;
    _loadingSelectedSession = true;
    _lastCheckinNotification =
        'Đang tải ${occurrence.subjectCode} - ${occurrence.classCode} (Buổi ${occurrence.sessionNumber}/${occurrence.totalSessions} · Slot ${occurrence.slot}) từ Google Sheets...';
    notifyListeners();
    _rosterLoadFuture = _loadPersistedClassRoster(
      occurrence.classCode,
      occurrence.id,
    );
    unawaited(_rosterLoadFuture);
    return true;
  }

  /// Loads the most relevant class when the dashboard first opens so roster
  /// statistics and attendance warnings never depend on a manual click.
  Future<bool> loadInitialDashboardSelection({DateTime? referenceDate}) {
    return _initialDashboardSelectionFuture ??= _loadInitialDashboardSelection(
      referenceDate ?? DateTime.now(),
    );
  }

  Future<bool> _loadInitialDashboardSelection(DateTime referenceDate) async {
    _initialDashboardLoadInProgress = true;
    notifyListeners();
    try {
      await _timetableLoadFuture;
      if (_selectedSlot != null) {
        await _rosterLoadFuture;
        return true;
      }
      if (_classSlots.isEmpty) return false;

      _currentWeekStart = _getWeekStart(referenceDate);
      final cutoffDate = DateUtils.dateOnly(referenceDate);
      final rememberedTarget = _templateById(_lastSelectedSlotId);
      FapClassSlot? target;

      try {
        final sessions = await _attendanceApi.getSessions(limit: 100);
        _initialDashboardSessions = sessions;
        final groupedSessions = <String, List<Map<String, dynamic>>>{};
        for (final session in sessions) {
          final classCode = session['classCode']
              ?.toString()
              .trim()
              .toUpperCase();
          final subjectCode = session['subjectCode']
              ?.toString()
              .trim()
              .toUpperCase();
          if (classCode == null ||
              classCode.isEmpty ||
              subjectCode == null ||
              subjectCode.isEmpty) {
            continue;
          }
          groupedSessions
              .putIfAbsent('$classCode|$subjectCode', () => [])
              .add(session);
        }

        final atRiskCourses = <String>{};
        for (final entry in groupedSessions.entries) {
          final aggregate = _aggregateCourseAttendance(
            entry.value,
            cutoffDate: cutoffDate,
            fallbackTotalSessions: 20,
          );
          if (aggregate.hasWarning) atRiskCourses.add(entry.key);
        }
        if (rememberedTarget != null) {
          final rememberedKey =
              '${rememberedTarget.classCode.trim().toUpperCase()}|${rememberedTarget.subjectCode.trim().toUpperCase()}';
          if (atRiskCourses.contains(rememberedKey)) {
            target = rememberedTarget;
          }
        }
        if (atRiskCourses.isNotEmpty) {
          target ??= _bestInitialTemplate(
            referenceDate,
            preferredCourseKeys: atRiskCourses,
          );
        }
      } catch (error) {
        debugPrint('Initial attendance warning preload failed: $error');
      }

      target ??= rememberedTarget;
      target ??= _bestInitialTemplate(referenceDate);
      if (target == null || !selectTimetableSlot(target)) return false;
      await _rosterLoadFuture;
      return _selectedSlot?.id == target.id;
    } finally {
      _initialDashboardLoadInProgress = false;
      notifyListeners();
    }
  }

  FapClassSlot? _templateById(String? slotId) {
    if (slotId == null || slotId.isEmpty) return null;
    for (final slot in _classSlots) {
      if (slot.id == slotId) return slot;
    }
    return null;
  }

  FapClassSlot? _bestInitialTemplate(
    DateTime referenceDate, {
    Set<String> preferredCourseKeys = const {},
  }) {
    final candidates = preferredCourseKeys.isEmpty
        ? [..._classSlots]
        : _classSlots.where((slot) {
            final key =
                '${slot.classCode.trim().toUpperCase()}|${slot.subjectCode.trim().toUpperCase()}';
            return preferredCourseKeys.contains(key);
          }).toList();
    if (candidates.isEmpty && preferredCourseKeys.isNotEmpty) return null;

    final referenceWeekday = referenceDate.weekday;
    candidates.sort((left, right) {
      int dayDistance(FapClassSlot slot) {
        final distance = slot.dayOfWeek - referenceWeekday;
        return distance >= 0 ? distance : distance.abs() + 7;
      }

      final leftDistance = dayDistance(left);
      final rightDistance = dayDistance(right);
      final dayOrder = leftDistance.compareTo(rightDistance);
      if (dayOrder != 0) return dayOrder;
      final slotOrder = left.slot.compareTo(right.slot);
      if (slotOrder != 0) return slotOrder;
      return left.subjectCode.compareTo(right.subjectCode);
    });
    return candidates.firstOrNull;
  }

  /// Selects a slot and waits until its stored session or roster has loaded.
  ///
  /// Dashboard actions that immediately navigate or export use this method so
  /// they never operate on the previously selected class while the new class
  /// is still being fetched.
  Future<bool> selectTimetableSlotAndWait(FapClassSlot slot) async {
    final accepted = selectTimetableSlot(slot);
    if (!accepted) return false;
    await _rosterLoadFuture;
    return _selectedSlot?.id == slot.id &&
        DateUtils.isSameDay(
          _currentSession.date,
          getDateForDay(slot.dayOfWeek),
        );
  }

  Future<void> _loadPersistedClassRoster(
    String classCode,
    String slotId,
  ) async {
    final selectedDate = _currentSession.date;
    final selectedSubject = _currentSession.subjectCode;
    final selectedSlotNumber = _currentSession.slot;

    bool sameSelection() =>
        _selectedSlot?.id == slotId &&
        DateUtils.isSameDay(_currentSession.date, selectedDate);
    bool selectionChanged() =>
        !sameSelection() || _currentSession.serverSessionId != null;

    try {
      final preloadedSessions = _initialDashboardSessions;
      _initialDashboardSessions = null;
      final sessions = preloadedSessions == null
          ? await _attendanceApi.getSessions(
              classCode: classCode,
              subjectCode: selectedSubject,
            )
          : preloadedSessions.where((session) {
              return session['classCode']?.toString().trim().toUpperCase() ==
                      classCode.trim().toUpperCase() &&
                  session['subjectCode']?.toString().trim().toUpperCase() ==
                      selectedSubject.trim().toUpperCase();
            }).toList();
      if (selectionChanged()) return;
      _applyCourseAttendanceHistory(sessions);
      final matching = AttendanceSessionMatcher.forTimetableSlot(
        sessions,
        classCode: classCode,
        subjectCode: selectedSubject,
        slot: selectedSlotNumber,
        date: selectedDate,
      );
      if (matching != null) {
        _applyServerSnapshot(matching);
        _lastCheckinNotification =
            'Đã đồng bộ phiên $selectedSubject - $classCode từ Google Sheets.';
        _startDashboardPolling();
        unawaited(_connectLiveUpdates());
        unawaited(loadAuditLogs());
        return;
      }

      final roster = await _attendanceApi.getClassRoster(classCode);
      if (selectionChanged()) return;
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
      _studentsVersion++;
      _latestServerStudents
        ..clear()
        ..addEntries(
          students.map(
            (student) => MapEntry(
              student.rollNo,
              Student(
                rollNo: student.rollNo,
                fullName: student.fullName,
                email: student.email,
                group: student.group,
              ),
            ),
          ),
        );
      _lastCheckinNotification =
          'Ca này chưa có phiên điểm danh; đã tải $classCode từ Google Sheets.';
      notifyListeners();
    } catch (error) {
      debugPrint('Không thể tải phiên điểm danh đã lưu: $error');
      if (selectionChanged()) return;
      _lastCheckinNotification =
          'Không thể đồng bộ phiên từ Google Sheets: $error';
      notifyListeners();
    } finally {
      if (sameSelection()) {
        _loadingSelectedSession = false;
        notifyListeners();
      }
    }
  }

  /// Select a timetable slot and switch to attendance mode.
  void selectSlotAndStartAttendance(FapClassSlot slot) {
    if (!selectTimetableSlot(slot)) return;

    // Trigger navigation to attendance tab
    onNavigateToAttendance?.call();
  }

  /// Add a new class slot to the timetable
  void addClassSlot(FapClassSlot newSlot) {
    _classSlots.add(newSlot);
    _cachedClassCodes = null; // Invalidate cache (Fix 3).
    unawaited(_persistTimetable());
    notifyListeners();
  }

  /// Remove a class slot
  void removeClassSlot(String slotId) {
    _classSlots.removeWhere((s) => s.id == slotId);
    _cachedClassCodes = null; // Invalidate cache (Fix 3).
    unawaited(_persistTimetable());
    notifyListeners();
  }

  Future<int> importTimetableSlots(
    List<FapClassSlot> slots, {
    bool replaceExisting = true,
  }) async {
    await _timetableLoadFuture;
    if (_currentSession.isOpen) {
      throw StateError(
        'Hãy đóng phiên điểm danh trước khi thay đổi thời khóa biểu.',
      );
    }
    if (hasUnsavedAttendanceChanges || _savingAttendanceDraft) {
      throw StateError(
        'Hãy lưu hoặc hủy bản nháp điểm danh trước khi nhập lịch.',
      );
    }

    final normalized = slots
        .where(
          (slot) =>
              slot.subjectCode.trim().isNotEmpty &&
              slot.classCode.trim().isNotEmpty &&
              slot.dayOfWeek >= 1 &&
              slot.dayOfWeek <= 7 &&
              slot.slot >= 1 &&
              slot.slot <= 8,
        )
        .map(
          (slot) => FapClassSlot(
            id: slot.id,
            subjectCode: slot.subjectCode.trim().toUpperCase(),
            subjectName: slot.subjectName.trim().isEmpty
                ? slot.subjectCode.trim().toUpperCase()
                : slot.subjectName.trim(),
            classCode: slot.classCode.trim().toUpperCase(),
            slot: slot.slot,
            dayOfWeek: slot.dayOfWeek,
            room: slot.room.trim().toUpperCase(),
            slotTime: FapClassSlot.getSlotTimeRange(slot.slot),
            sessionNumber: slot.sessionNumber,
            totalSessions: slot.totalSessions,
            instructor: slot.instructor.trim(),
            campus: slot.campus.trim().isEmpty ? 'FUHCM' : slot.campus.trim(),
            meetUrl: slot.meetUrl,
            isOnline: slot.isOnline,
          ),
        )
        .toList();
    if (normalized.isEmpty) {
      throw StateError('Không có ca học hợp lệ để nhập.');
    }

    final nextAnchorWeekStart = _getWeekStart(DateTime.now());

    final next = replaceExisting ? <FapClassSlot>[] : [..._classSlots];
    final keys = next.map(_slotIdentity).toSet();
    var importedCount = 0;
    for (final slot in normalized) {
      if (!keys.add(_slotIdentity(slot))) continue;
      next.add(slot);
      importedCount++;
    }
    next.sort((a, b) {
      final dayComparison = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (dayComparison != 0) return dayComparison;
      final slotComparison = a.slot.compareTo(b.slot);
      if (slotComparison != 0) return slotComparison;
      return a.subjectCode.compareTo(b.subjectCode);
    });

    final meetingPlan = _buildCourseMeetingPlan(next, nextAnchorWeekStart);
    await _attendanceApi.syncCourseMeetings(meetingPlan);

    _timetableMeetingAnchorWeekStart = nextAnchorWeekStart;
    _classSlots = next;
    _cachedClassCodes = null;
    _classCodeFilter = null;
    if (_selectedSlot != null &&
        !_classSlots.any((slot) => slot.id == _selectedSlot!.id)) {
      _dashboardPollTimer?.cancel();
      unawaited(_liveService.disconnect());
      _selectedSlot = null;
      _students = [];
      _studentsVersion++;
      _latestServerStudents.clear();
      _currentSession = AttendanceSession(
        classCode: '',
        subjectCode: '',
        slot: 0,
        date: DateTime.now(),
      );
    }
    await _persistTimetable();
    notifyListeners();
    return importedCount;
  }

  static List<Map<String, dynamic>> _buildCourseMeetingPlan(
    List<FapClassSlot> slots,
    DateTime anchorWeekStart,
  ) {
    final courses = <String, List<FapClassSlot>>{};
    for (final slot in slots) {
      final key =
          '${slot.classCode.trim().toUpperCase()}|${slot.subjectCode.trim().toUpperCase()}';
      courses.putIfAbsent(key, () => []).add(slot);
    }

    final meetings = <Map<String, dynamic>>[];
    for (final courseSlots in courses.values) {
      courseSlots.sort((left, right) {
        final dayOrder = left.dayOfWeek.compareTo(right.dayOfWeek);
        if (dayOrder != 0) return dayOrder;
        final slotOrder = left.slot.compareTo(right.slot);
        if (slotOrder != 0) return slotOrder;
        return left.id.compareTo(right.id);
      });
      if (courseSlots.isEmpty) continue;

      var firstMeeting = courseSlots.first.sessionNumber;
      var totalMeetings = courseSlots.first.totalSessions;
      for (final slot in courseSlots.skip(1)) {
        if (slot.sessionNumber < firstMeeting) {
          firstMeeting = slot.sessionNumber;
        }
        if (slot.totalSessions > totalMeetings) {
          totalMeetings = slot.totalSessions;
        }
      }
      if (firstMeeting < 1) firstMeeting = 1;
      if (totalMeetings < firstMeeting) totalMeetings = firstMeeting;

      for (
        var meetingNumber = 1;
        meetingNumber <= totalMeetings;
        meetingNumber++
      ) {
        final relative = meetingNumber - firstMeeting;
        final weekOffset = (relative / courseSlots.length).floor();
        final templateIndex = relative - weekOffset * courseSlots.length;
        final template = courseSlots[templateIndex];
        final date = anchorWeekStart.add(
          Duration(days: weekOffset * 7 + template.dayOfWeek - 1),
        );
        meetings.add({
          'classCode': template.classCode.trim().toUpperCase(),
          'subjectCode': template.subjectCode.trim().toUpperCase(),
          'meetingNumber': meetingNumber,
          'totalMeetings': totalMeetings,
          'date': _dateKey(date),
          'slot': template.slot,
        });
      }
    }
    meetings.sort((left, right) {
      final classOrder = (left['classCode'] as String).compareTo(
        right['classCode'] as String,
      );
      if (classOrder != 0) return classOrder;
      final subjectOrder = (left['subjectCode'] as String).compareTo(
        right['subjectCode'] as String,
      );
      if (subjectOrder != 0) return subjectOrder;
      return (left['meetingNumber'] as int).compareTo(
        right['meetingNumber'] as int,
      );
    });
    return meetings;
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _loadSavedTimetable() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _lastSelectedSlotId = preferences.getString(
        _lastSelectedSlotPreferenceKey,
      );
      final encodedAnchor = preferences.getString(
        _timetableAnchorWeekPreferenceKey,
      );
      final parsedAnchor = DateTime.tryParse(encodedAnchor ?? '');
      if (parsedAnchor != null) {
        _timetableMeetingAnchorWeekStart = _getWeekStart(parsedAnchor);
      } else {
        await preferences.setString(
          _timetableAnchorWeekPreferenceKey,
          _timetableMeetingAnchorWeekStart.toIso8601String(),
        );
      }
      final encoded = preferences.getString(_timetablePreferenceKey);
      if (encoded == null || encoded.trim().isEmpty) return;
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return;
      final slots = decoded
          .whereType<Map>()
          .map((item) => FapClassSlot.fromJson(Map<String, dynamic>.from(item)))
          .where(
            (slot) =>
                slot.id.isNotEmpty &&
                slot.subjectCode.isNotEmpty &&
                slot.classCode.isNotEmpty,
          )
          .toList();
      if (slots.isEmpty) return;
      _classSlots = slots;
      _cachedClassCodes = null;
      notifyListeners();
    } on MissingPluginException {
      // Unit tests and non-plugin isolates do not register SharedPreferences.
    } catch (error) {
      debugPrint('Không thể tải thời khóa biểu đã lưu: $error');
    }
  }

  Future<void> _persistLastSelectedSlotId(String slotId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_lastSelectedSlotPreferenceKey, slotId);
    } on MissingPluginException {
      // Unit tests and non-plugin isolates do not register SharedPreferences.
    } catch (error) {
      debugPrint('Không thể lưu ca được chọn gần nhất: $error');
    }
  }

  Future<void> _persistTimetable() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _timetablePreferenceKey,
        jsonEncode(_classSlots.map((slot) => slot.toJson()).toList()),
      );
      await preferences.setString(
        _timetableAnchorWeekPreferenceKey,
        _timetableMeetingAnchorWeekStart.toIso8601String(),
      );
    } on MissingPluginException {
      // Unit tests and non-plugin isolates do not register SharedPreferences.
    } catch (error) {
      debugPrint('Không thể lưu thời khóa biểu: $error');
    }
  }

  static String _slotIdentity(FapClassSlot slot) =>
      '${slot.subjectCode.trim().toUpperCase()}|'
      '${slot.classCode.trim().toUpperCase()}|'
      '${slot.dayOfWeek}|${slot.slot}';

  /// Import students for a specific class from CSV content
  StudentRosterImportResult parseStudentCsv(String rawCsv, String classCode) {
    return StudentCsvImportService.parse(rawCsv, fallbackGroup: classCode);
  }

  StudentRosterImportResult parseStudentFile(
    List<int> bytes,
    String fileName,
    String classCode,
  ) {
    return StudentRosterImportService.parseFile(
      bytes,
      fileName: fileName,
      fallbackGroup: classCode,
    );
  }

  Future<StudentRosterImportResult> importStudentsForClass(
    String classCode,
    String rawCsv,
  ) async {
    final result = parseStudentCsv(rawCsv, classCode);
    return _saveImportedRoster(classCode, result);
  }

  Future<StudentRosterImportResult> importStudentFileForClass(
    String classCode,
    List<int> bytes,
    String fileName,
  ) async {
    final result = parseStudentFile(bytes, fileName, classCode);
    return _saveImportedRoster(classCode, result);
  }

  Future<StudentRosterImportResult> _saveImportedRoster(
    String classCode,
    StudentRosterImportResult result,
  ) async {
    if (hasUnsavedAttendanceChanges || _savingAttendanceDraft) {
      throw StateError(
        'Hãy lưu hoặc hủy các dòng đã sửa trước khi import danh sách sinh viên.',
      );
    }
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
        _studentsVersion++;
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
        _studentsVersion++;
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
        final sessions = await _attendanceApi.getSessions(
          classCode: slot.classCode,
          subjectCode: slot.subjectCode,
        );
        if (_selectedSlot?.id == slot.id) {
          _applyCourseAttendanceHistory(sessions);
        }
        if (_currentSession.serverSessionId == null) {
          await _loadPersistedClassRoster(slot.classCode, slot.id);
        } else {
          await refreshSessionDashboard();
        }
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

  void _applyCourseAttendanceHistory(List<Map<String, dynamic>> sessions) {
    final aggregate = _aggregateCourseAttendance(
      sessions,
      cutoffDate: DateUtils.dateOnly(_currentSession.date),
      fallbackTotalSessions: _currentSession.totalSessions,
    );

    _courseAbsenceCounts
      ..clear()
      ..addAll(aggregate.absenceCounts);
    _courseTotalSessions = aggregate.totalSessions;
    _courseCompletedSessions = aggregate.completedSessions;
  }

  static _CourseAttendanceAggregate _aggregateCourseAttendance(
    List<Map<String, dynamic>> sessions, {
    required DateTime cutoffDate,
    required int fallbackTotalSessions,
  }) {
    final absenceCounts = <String, int>{};
    final countedMeetings = <String>{};
    var totalSessions = fallbackTotalSessions;
    final attendanceCutoffDate = DateUtils.dateOnly(cutoffDate);

    for (final session in sessions) {
      final sessionTotal = (session['totalSessions'] as num?)?.toInt() ?? 0;
      if (sessionTotal > totalSessions) totalSessions = sessionTotal;

      final sessionDate = AttendanceSessionMatcher.calendarDate(
        session['date'],
      );
      if (sessionDate == null ||
          DateUtils.dateOnly(sessionDate).isAfter(attendanceCutoffDate)) {
        continue;
      }

      final closedAt = session['closedAt']?.toString().trim() ?? '';
      if (session['isOpen'] == true || closedAt.isEmpty) continue;

      final meetingNumber = (session['sessionNumber'] as num?)?.toInt() ?? 0;
      final sessionId = session['sessionId']?.toString() ?? '';
      final meetingKey = meetingNumber > 0
          ? 'meeting:$meetingNumber'
          : sessionId;
      if (meetingKey.isEmpty || !countedMeetings.add(meetingKey)) continue;

      final students = session['students'];
      if (students is! List) continue;
      for (final rawStudent in students.whereType<Map>()) {
        final rollNo = rawStudent['rollNo']?.toString().trim().toUpperCase();
        final status = rawStudent['status']?.toString().trim().toUpperCase();
        if (rollNo == null || rollNo.isEmpty || status != 'ABSENT') continue;
        absenceCounts[rollNo] = (absenceCounts[rollNo] ?? 0) + 1;
      }
    }

    final normalizedTotalSessions = totalSessions <= 0 ? 20 : totalSessions;
    final warningThreshold = (normalizedTotalSessions + 4) ~/ 5;
    return _CourseAttendanceAggregate(
      absenceCounts: absenceCounts,
      totalSessions: normalizedTotalSessions,
      completedSessions: countedMeetings.length,
      hasWarning: absenceCounts.values.any(
        (count) => count >= warningThreshold,
      ),
    );
  }

  Future<void> _refreshSelectedCourseAttendanceHistory() async {
    final slot = _selectedSlot;
    if (slot == null) return;

    try {
      final sessions = await _attendanceApi.getSessions(
        classCode: slot.classCode,
        subjectCode: slot.subjectCode,
      );
      final currentSlot = _selectedSlot;
      if (currentSlot?.id != slot.id ||
          currentSlot?.classCode != slot.classCode ||
          currentSlot?.subjectCode != slot.subjectCode) {
        return;
      }
      _applyCourseAttendanceHistory(sessions);
      notifyListeners();
    } catch (error) {
      // Saving the attendance itself already succeeded. Keep that success and
      // let the next slot selection retry the course-level summary refresh.
      debugPrint('Course attendance history refresh failed: $error');
    }
  }

  void toggleStudentStatus(Student student, AttendanceStatus newStatus) {
    final sessionId = _currentSession.serverSessionId;
    if (_savingAttendanceDraft || _loadingSelectedSession) return;
    if (student.status == newStatus ||
        _pendingAttendanceRollNos.contains(student.rollNo)) {
      return;
    }
    if (!_currentSession.isOpen) {
      final remote = _latestServerStudents[student.rollNo];
      final originalStatus =
          _attendanceDrafts[student.rollNo]?.originalStatus ??
          remote?.status ??
          student.status;
      if (newStatus == (remote?.status ?? originalStatus)) {
        _attendanceDrafts.remove(student.rollNo);
        student.status = remote?.status ?? originalStatus;
        student.checkinTime = remote?.checkinTime;
      } else {
        final checkinTime = newStatus == AttendanceStatus.present
            ? student.checkinTime ?? DateTime.now()
            : null;
        _attendanceDrafts[student.rollNo] = _AttendanceDraft(
          originalStatus: originalStatus,
          status: newStatus,
          checkinTime: checkinTime,
        );
        student.status = newStatus;
        student.checkinTime = checkinTime;
      }
      _studentsVersion++;
      notifyListeners();
      return;
    }
    if (sessionId == null) return;
    final previousStatus = student.status;
    _pendingAttendanceRollNos.add(student.rollNo);
    student.status = newStatus;
    student.checkinTime = newStatus == AttendanceStatus.present
        ? DateTime.now()
        : null;
    _studentsVersion++; // Invalidate caches (Fix 3).
    notifyListeners();
    unawaited(
      _updateServerAttendance(sessionId, student, newStatus, previousStatus),
    );
  }

  void discardAttendanceDraft() {
    if (_savingAttendanceDraft || _attendanceDrafts.isEmpty) return;
    for (final student in _students) {
      if (!_attendanceDrafts.containsKey(student.rollNo)) continue;
      final remote = _latestServerStudents[student.rollNo];
      student.status = remote?.status ?? AttendanceStatus.absent;
      student.checkinTime = remote?.checkinTime;
    }
    _attendanceDrafts.clear();
    _studentsVersion++;
    _lastCheckinNotification = 'Đã hủy các thay đổi chưa lưu.';
    notifyListeners();
  }

  Future<bool> saveAttendanceDraft() async {
    if (_savingAttendanceDraft ||
        _attendanceDrafts.isEmpty ||
        _currentSession.isOpen ||
        _selectedSlot == null) {
      return false;
    }
    final conflicted = _attendanceDrafts.keys
        .where(isAttendanceDraftConflicted)
        .toList();
    if (conflicted.isNotEmpty) {
      _lastCheckinNotification =
          '⚠️ ${conflicted.length} dòng đã đổi trên Google Sheets (${conflicted.join(', ')}). Hãy chọn lại trạng thái hoặc hủy bản nháp trước khi lưu.';
      notifyListeners();
      return false;
    }
    final session = _currentSession;
    final changes = _attendanceDrafts.entries
        .map(
          (entry) => <String, String>{
            'rollNo': entry.key,
            'status': entry.value.status.toLabel(),
            'expectedStatus': entry.value.originalStatus.toLabel(),
          },
        )
        .toList();
    _savingAttendanceDraft = true;
    _draftSaveGeneration++;
    notifyListeners();
    try {
      final payload = await _attendanceApi.saveAttendanceBatch(
        session,
        changes,
      );
      final snapshot = payload['session'];
      if (snapshot is! Map) {
        throw const AttendanceApiException(
          'API không trả về phiên đã lưu.',
          500,
        );
      }
      _attendanceDrafts.clear();
      _applyServerSnapshot(Map<String, dynamic>.from(snapshot));
      await _refreshSelectedCourseAttendanceHistory();
      _lastCheckinNotification =
          payload['message']?.toString() ?? 'Đã lưu lên Google Sheets.';
      _startDashboardPolling();
      unawaited(_connectLiveUpdates());
      unawaited(loadAuditLogs());
      return true;
    } catch (error) {
      // A slow Apps Script can commit and then time out before responding.
      // Read back once before offering a retry, avoiding a duplicate session.
      try {
        Map<String, dynamic>? latest;
        if (session.serverSessionId != null) {
          latest = await _attendanceApi.getSession(session.serverSessionId!);
        } else {
          final sessions = await _attendanceApi.getSessions(
            classCode: session.classCode,
            subjectCode: session.subjectCode,
            slot: session.slot,
          );
          latest = AttendanceSessionMatcher.forTimetableSlot(
            sessions,
            classCode: session.classCode,
            subjectCode: session.subjectCode,
            slot: session.slot,
            date: session.date,
          );
        }
        if (latest != null) {
          _applyServerSnapshot(latest);
          if (_attendanceDrafts.isEmpty) {
            await _refreshSelectedCourseAttendanceHistory();
          }
          _startDashboardPolling();
          unawaited(_connectLiveUpdates());
        }
      } catch (readError) {
        debugPrint('Cannot verify batch save after error: $readError');
      }
      _lastCheckinNotification = _attendanceDrafts.isEmpty
          ? 'Đã xác nhận các thay đổi trên Google Sheets sau khi kết nối gián đoạn.'
          : '⚠️ Chưa lưu được bản nháp: $error. Các dòng đã sửa vẫn được giữ lại.';
      return _attendanceDrafts.isEmpty;
    } finally {
      _savingAttendanceDraft = false;
      notifyListeners();
    }
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
      _studentsVersion++;

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
      _studentsVersion++;
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

  Future<StudentRosterImportResult> importCsvContent(String rawCsv) {
    return importStudentsForClass(_currentSession.classCode, rawCsv);
  }

  Future<StudentRosterImportResult> importStudentFile(
    List<int> bytes,
    String fileName,
  ) {
    return importStudentFileForClass(
      _currentSession.classCode,
      bytes,
      fileName,
    );
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
        sessionNumber: 3,
        instructor: 'PhuongLHK',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'exe201-wed-2',
        subjectCode: 'EXE201',
        subjectName: 'Experiential Entrepreneurship 1',
        classCode: 'SE1919',
        slot: 2,
        dayOfWeek: 3,
        room: 'NVH 707',
        slotTime: '9:30 - 11:45',
        sessionNumber: 5,
        instructor: 'ThanhNV',
        campus: 'FUHCM',
        isOnline: true,
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
        sessionNumber: 4,
        instructor: 'PhuongLHK',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'hcm202-tue-1',
        subjectCode: 'HCM202',
        subjectName: 'Ho Chi Minh Ideology',
        classCode: 'SE1920',
        slot: 1,
        dayOfWeek: 2,
        room: 'NVH 307',
        slotTime: '7:00 - 9:15',
        sessionNumber: 5,
        instructor: 'HaNT',
        campus: 'FUHCM',
      ),
      FapClassSlot(
        id: 'hcm202-fri-1',
        subjectCode: 'HCM202',
        subjectName: 'Ho Chi Minh Ideology',
        classCode: 'SE1920',
        slot: 1,
        dayOfWeek: 5,
        room: 'NVH 307',
        slotTime: '7:00 - 9:15',
        sessionNumber: 6,
        instructor: 'HaNT',
        campus: 'FUHCM',
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
    _dashboardPollTimer?.cancel();
    unawaited(_liveService.disconnect());
    super.dispose();
  }
}

class CourseAttendanceWarning {
  final Student student;
  final int absentSessions;
  final int totalSessions;

  const CourseAttendanceWarning({
    required this.student,
    required this.absentSessions,
    required this.totalSessions,
  });

  double get absencePercentage =>
      totalSessions <= 0 ? 0 : absentSessions * 100 / totalSessions;

  bool get exceedsExamThreshold => absentSessions * 5 > totalSessions;
}

class _AttendanceDraft {
  final AttendanceStatus originalStatus;
  final AttendanceStatus status;
  final DateTime? checkinTime;

  const _AttendanceDraft({
    required this.originalStatus,
    required this.status,
    required this.checkinTime,
  });
}

class _CourseAttendanceAggregate {
  final Map<String, int> absenceCounts;
  final int totalSessions;
  final int completedSessions;
  final bool hasWarning;

  const _CourseAttendanceAggregate({
    required this.absenceCounts,
    required this.totalSessions,
    required this.completedSessions,
    required this.hasWarning,
  });
}
