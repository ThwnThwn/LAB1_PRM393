import 'dart:async';

import 'package:fap_attendance_app/models/attendance_session.dart';
import 'package:fap_attendance_app/models/student.dart';
import 'package:fap_attendance_app/providers/attendance_provider.dart';
import 'package:fap_attendance_app/services/attendance_api_service.dart';
import 'package:fap_attendance_app/services/attendance_live_service.dart';
import 'package:fap_attendance_app/widgets/roster_table_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _DraftApi extends AttendanceApiService {
  _DraftApi({this.hasSession = true});

  final bool hasSession;
  bool failSave = false;
  bool commitThenFail = false;
  int batchCalls = 0;
  int singleRowCalls = 0;
  List<Map<String, String>>? savedChanges;
  String remoteFirstStatus = 'ABSENT';
  String remoteSecondStatus = 'PRESENT';

  List<Map<String, dynamic>> get _students => [
    {
      'rollNo': 'SE192001',
      'fullName': 'Sinh viên 1',
      'email': 'se192001@fpt.edu.vn',
      'status': remoteFirstStatus,
    },
    {
      'rollNo': 'SE192002',
      'fullName': 'Sinh viên 2',
      'email': 'se192002@fpt.edu.vn',
      'status': remoteSecondStatus,
    },
  ];

  Map<String, dynamic> get _snapshot => {
    'sessionId': 'closed-session',
    'classCode': 'SE1920',
    'subjectCode': 'HCM202',
    'slot': 1,
    'date': '2026-09-22',
    'sessionNumber': 4,
    'totalSessions': 20,
    'isOpen': false,
    'closedAt': '2026-09-22T10:00:00Z',
    'students': _students,
    'deviceBindings': <Map<String, dynamic>>[],
  };

  @override
  Future<Map<String, dynamic>> getGoogleSheetsConfiguration({
    bool verify = false,
  }) async => {'isReachable': true};

  @override
  Future<List<Map<String, dynamic>>> getSessions({
    int limit = 100,
    String? classCode,
    String? subjectCode,
    int? slot,
  }) async {
    if (!hasSession) return [];
    const dates = ['2026-09-01', '2026-09-08', '2026-09-15', '2026-09-22'];
    return List.generate(4, (index) {
      final isCurrentSession = index == 3;
      return {
        ..._snapshot,
        'sessionId': isCurrentSession
            ? 'closed-session'
            : 'history-${index + 1}',
        'date': dates[index],
        'sessionNumber': index + 1,
        'closedAt': '${dates[index]}T10:00:00Z',
        'students': [
          {
            ..._students[0],
            'status': isCurrentSession ? remoteFirstStatus : 'ABSENT',
          },
          {
            ..._students[1],
            'status': isCurrentSession ? remoteSecondStatus : 'PRESENT',
          },
        ],
      };
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getClassRoster(String classCode) async =>
      _students;

  @override
  Future<Map<String, dynamic>> getSession(String sessionId) async => _snapshot;

  @override
  Future<List<Map<String, dynamic>>> getAuditLogs(String sessionId) async => [];

  @override
  Future<Map<String, dynamic>> updateAttendance(
    String sessionId,
    String rollNo,
    AttendanceStatus status, {
    String reason = 'Giảng viên cập nhật từ dashboard',
    AttendanceStatus? expectedStatus,
  }) async {
    singleRowCalls++;
    throw StateError('Closed sessions must use batch save');
  }

  @override
  Future<Map<String, dynamic>> saveAttendanceBatch(
    AttendanceSession session,
    List<Map<String, String>> changes,
  ) async {
    batchCalls++;
    savedChanges = changes;
    if (failSave) throw const AttendanceApiException('Sheet tạm lỗi', 502);
    if (commitThenFail) {
      remoteFirstStatus = changes.first['status']!;
      throw const AttendanceApiException('Mất phản hồi sau khi lưu', 502);
    }
    for (final change in changes) {
      switch (change['rollNo']) {
        case 'SE192001':
          remoteFirstStatus = change['status']!;
        case 'SE192002':
          remoteSecondStatus = change['status']!;
      }
    }
    final statuses = {
      for (final change in changes) change['rollNo']!: change['status']!,
    };
    return {
      'message': 'Đã lưu',
      'session': {
        ..._snapshot,
        'sessionId': session.serverSessionId ?? 'new-closed-session',
        'students': [
          for (final student in _students)
            {
              ...student,
              'status': statuses[student['rollNo']] ?? student['status'],
            },
        ],
      },
    };
  }
}

class _DraftLiveService extends AttendanceLiveService {
  @override
  Future<void> connect({
    required String baseUrl,
    required String sessionId,
    required void Function(String eventName) onEvent,
  }) async {}
}

Future<AttendanceProvider> _loadedProvider(_DraftApi api) async {
  final provider = AttendanceProvider(
    attendanceApi: api,
    liveService: _DraftLiveService(),
  );
  provider.goToDate(DateTime(2026, 9, 22));
  final slot = provider.classSlots.firstWhere(
    (item) => item.id == 'hcm202-tue-1',
  );
  final loaded = Completer<void>();
  provider.addListener(() {
    if (!provider.loadingSelectedSession &&
        provider.students.length == 2 &&
        !loaded.isCompleted) {
      loaded.complete();
    }
  });
  provider.selectTimetableSlot(slot);
  await loaded.future.timeout(const Duration(seconds: 2));
  return provider;
}

void main() {
  test(
    'closed session stages multiple rows and saves with one request',
    () async {
      final api = _DraftApi();
      final provider = await _loadedProvider(api);
      addTearDown(provider.dispose);

      provider.toggleStudentStatus(
        provider.students[0],
        AttendanceStatus.present,
      );
      provider.toggleStudentStatus(
        provider.students[1],
        AttendanceStatus.absent,
      );
      expect(provider.unsavedAttendanceCount, 2);
      expect(api.batchCalls, 0);
      expect(api.singleRowCalls, 0);

      await provider.refreshSessionDashboard();
      expect(provider.students[0].status, AttendanceStatus.present);
      expect(provider.students[1].status, AttendanceStatus.absent);

      expect(await provider.saveAttendanceDraft(), isTrue);
      expect(api.batchCalls, 1);
      expect(api.savedChanges, [
        {'rollNo': 'SE192001', 'status': 'PRESENT', 'expectedStatus': 'ABSENT'},
        {'rollNo': 'SE192002', 'status': 'ABSENT', 'expectedStatus': 'PRESENT'},
      ]);
      expect(provider.hasUnsavedAttendanceChanges, isFalse);
      expect(provider.courseCompletedSessions, 4);
      expect(provider.attendanceWarnings, isEmpty);
    },
  );

  test('slot without a QR session can be edited and saved as closed', () async {
    final api = _DraftApi(hasSession: false);
    final provider = await _loadedProvider(api);
    addTearDown(provider.dispose);
    expect(provider.serverSessionId, isNull);

    provider.toggleStudentStatus(
      provider.students[0],
      AttendanceStatus.present,
    );
    expect(await provider.saveAttendanceDraft(), isTrue);
    expect(api.batchCalls, 1);
    expect(provider.serverSessionId, 'new-closed-session');
    expect(provider.isSessionOpen, isFalse);
  });

  test('failed save keeps draft; discard restores last Sheet status', () async {
    final api = _DraftApi()..failSave = true;
    final provider = await _loadedProvider(api);
    addTearDown(provider.dispose);

    provider.toggleStudentStatus(
      provider.students[0],
      AttendanceStatus.present,
    );
    expect(await provider.saveAttendanceDraft(), isFalse);
    expect(provider.hasUnsavedAttendanceChanges, isTrue);
    expect(provider.students[0].status, AttendanceStatus.present);

    provider.discardAttendanceDraft();
    expect(provider.hasUnsavedAttendanceChanges, isFalse);
    expect(provider.students[0].status, AttendanceStatus.absent);
  });

  test('timed-out response is reconciled without another write', () async {
    final api = _DraftApi()..commitThenFail = true;
    final provider = await _loadedProvider(api);
    addTearDown(provider.dispose);

    provider.toggleStudentStatus(
      provider.students[0],
      AttendanceStatus.present,
    );
    expect(await provider.saveAttendanceDraft(), isTrue);
    expect(api.batchCalls, 1);
    expect(provider.hasUnsavedAttendanceChanges, isFalse);
    expect(provider.students[0].status, AttendanceStatus.present);
  });

  test(
    'matching remote edit resolves the local draft without another write',
    () async {
      final api = _DraftApi();
      final provider = await _loadedProvider(api);
      addTearDown(provider.dispose);

      provider.toggleStudentStatus(
        provider.students[0],
        AttendanceStatus.present,
      );
      api.remoteFirstStatus = 'PRESENT';
      await provider.refreshSessionDashboard();
      expect(provider.students[0].status, AttendanceStatus.present);
      expect(provider.hasUnsavedAttendanceChanges, isFalse);
      expect(api.batchCalls, 0);
    },
  );

  test('switching slots while draft exists does not drop changes', () async {
    final api = _DraftApi();
    final provider = await _loadedProvider(api);
    addTearDown(provider.dispose);

    provider.toggleStudentStatus(
      provider.students[0],
      AttendanceStatus.present,
    );
    final other = provider.classSlots.firstWhere(
      (item) => item.id == 'hcm202-fri-1',
    );
    expect(provider.selectTimetableSlot(other), isFalse);
    expect(provider.hasUnsavedAttendanceChanges, isTrue);
    expect(provider.selectedSlot?.id, 'hcm202-tue-1');
  });

  testWidgets('save action appears below roster only when rows are drafted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _DraftApi();
    final provider = await _loadedProvider(api);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: RosterTableWidget())),
      ),
    );
    expect(
      find.textContaining('dòng chưa lưu lên Google Sheets'),
      findsNothing,
    );

    provider.toggleStudentStatus(
      provider.students[0],
      AttendanceStatus.present,
    );
    provider.toggleStudentStatus(provider.students[1], AttendanceStatus.absent);
    await tester.pump();
    expect(find.text('2 dòng chưa lưu lên Google Sheets'), findsOneWidget);
    expect(find.text('Lưu 2 dòng'), findsOneWidget);

    await tester.tap(find.text('Lưu 2 dòng'));
    await tester.pump();
    expect(api.batchCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
