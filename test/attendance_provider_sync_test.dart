import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/models/student.dart';
import 'package:fap_attendance_app/providers/attendance_provider.dart';
import 'package:fap_attendance_app/screens/teacher_dashboard_screen.dart';
import 'package:fap_attendance_app/services/attendance_api_service.dart';
import 'package:fap_attendance_app/services/attendance_live_service.dart';
import 'package:fap_attendance_app/widgets/qr_generator_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAttendanceApi extends AttendanceApiService {
  static const sessionId = 'DEMO-20260924-SE1917-PRN232-S1';
  String studentStatus = 'ABSENT';

  @override
  Future<Map<String, dynamic>> getGoogleSheetsConfiguration({
    bool verify = false,
  }) async => {'isReachable': true};

  @override
  Future<List<Map<String, dynamic>>> getClassRoster(String classCode) async => [
    {
      'rollNo': 'SE191709',
      'fullName': 'Phan Thị Thảo Vy',
      'email': 'se191709@fpt.edu.vn',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getSessions({
    int limit = 100,
    String? classCode,
    String? subjectCode,
    int? slot,
  }) async => List.generate(5, (index) {
    final meetingNumber = index + 1;
    const dates = [
      '2026-09-13T17:00:00Z',
      '2026-09-16T17:00:00Z',
      '2026-09-20T17:00:00Z',
      '2026-09-23T17:00:00Z',
      '2026-09-30T17:00:00Z',
    ];
    return {
      'sessionId': meetingNumber == 4 ? sessionId : 'history-$meetingNumber',
      'classCode': 'SE1917',
      'subjectCode': 'PRN232',
      'slot': 1,
      'date': dates[index],
      'sessionNumber': meetingNumber,
      'totalSessions': 20,
      'isOpen': false,
      'closedAt': dates[index],
      'students': [
        {
          'rollNo': 'SE191709',
          'fullName': 'Phan Thị Thảo Vy',
          'email': 'se191709@fpt.edu.vn',
          'status': 'ABSENT',
        },
      ],
    };
  });

  @override
  Future<Map<String, dynamic>> getSession(String sessionId) async => {
    'sessionId': sessionId,
    'classCode': 'SE1917',
    'subjectCode': 'PRN232',
    'slot': 1,
    'date': '2026-09-23T17:00:00Z',
    'isOpen': false,
    'students': [
      {
        'rollNo': 'SE191709',
        'fullName': 'Phan Thị Thảo Vy',
        'email': 'se191709@fpt.edu.vn',
        'status': studentStatus,
        'checkinTime': null,
      },
    ],
    'deviceBindings': [],
  };

  @override
  Future<List<Map<String, dynamic>>> getAuditLogs(String sessionId) async => [];
}

class _FakeLiveService extends AttendanceLiveService {
  @override
  Future<void> connect({
    required String baseUrl,
    required String sessionId,
    required void Function(String eventName) onEvent,
  }) async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'dashboard startup selects and loads an at-risk class automatically',
    () async {
      final provider = AttendanceProvider(
        attendanceApi: _FakeAttendanceApi(),
        liveService: _FakeLiveService(),
      );
      addTearDown(provider.dispose);

      expect(provider.selectedSlot, isNull);
      expect(
        await provider.loadInitialDashboardSelection(
          referenceDate: DateTime(2026, 9, 24),
        ),
        isTrue,
      );

      expect(provider.selectedSlot?.id, 'prn232-thu-1');
      expect(provider.loadingSelectedSession, isFalse);
      expect(provider.students.single.rollNo, 'SE191709');
      expect(provider.attendanceWarnings.single.absentSessions, 4);
    },
  );

  testWidgets(
    'warning identifies the subject and class without another click',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = AttendanceProvider(
        attendanceApi: _FakeAttendanceApi(),
        liveService: _FakeLiveService(),
      );
      await provider.loadInitialDashboardSelection(
        referenceDate: DateTime(2026, 9, 24),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(home: TeacherDashboardScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('PRN232 · Lớp SE1917'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    },
  );

  test(
    'selected slot counts closed history through its date, not future sessions',
    () async {
      final api = _FakeAttendanceApi();
      final provider = AttendanceProvider(
        attendanceApi: api,
        liveService: _FakeLiveService(),
      );
      addTearDown(provider.dispose);

      provider.goToDate(DateTime(2026, 9, 24));
      final slot = provider.classSlots.firstWhere(
        (item) =>
            item.classCode == 'SE1917' &&
            item.subjectCode == 'PRN232' &&
            item.dayOfWeek == 4,
      );

      final attached = Completer<void>();
      provider.addListener(() {
        if (provider.serverSessionId == _FakeAttendanceApi.sessionId &&
            !attached.isCompleted) {
          attached.complete();
        }
      });
      provider.selectTimetableSlot(slot);
      await attached.future.timeout(const Duration(seconds: 2));

      expect(provider.serverSessionId, _FakeAttendanceApi.sessionId);
      expect(provider.students.single.rollNo, 'SE191709');
      expect(provider.students.single.status, AttendanceStatus.absent);
      expect(provider.courseCompletedSessions, 4);
      expect(provider.attendanceWarnings, hasLength(1));
      expect(provider.attendanceWarnings.single.absentSessions, 4);
      expect(provider.attendanceWarnings.single.totalSessions, 20);
      expect(provider.attendanceWarnings.single.exceedsExamThreshold, isFalse);

      api.studentStatus = 'PRESENT';
      await provider.refreshSessionDashboard();
      expect(provider.students.single.status, AttendanceStatus.present);
    },
  );

  testWidgets('a stored closed session offers to reopen the same session', (
    tester,
  ) async {
    final provider = AttendanceProvider(
      attendanceApi: _FakeAttendanceApi(),
      liveService: _FakeLiveService(),
    );
    provider.goToDate(DateTime(2026, 9, 24));
    final slot = provider.classSlots.firstWhere(
      (item) => item.classCode == 'SE1917' && item.dayOfWeek == 4,
    );
    final attached = Completer<void>();
    provider.addListener(() {
      if (provider.serverSessionId == _FakeAttendanceApi.sessionId &&
          !attached.isCompleted) {
        attached.complete();
      }
    });
    provider.selectTimetableSlot(slot);
    await attached.future.timeout(const Duration(seconds: 2));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: QrGeneratorWidget())),
      ),
    );
    expect(find.text('Phiên điểm danh đã đóng'), findsOneWidget);
    expect(find.text('Mở lại phiên'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
