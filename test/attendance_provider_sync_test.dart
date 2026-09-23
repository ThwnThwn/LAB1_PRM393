import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/models/student.dart';
import 'package:fap_attendance_app/providers/attendance_provider.dart';
import 'package:fap_attendance_app/services/attendance_api_service.dart';
import 'package:fap_attendance_app/services/attendance_live_service.dart';
import 'package:fap_attendance_app/widgets/qr_generator_widget.dart';
import 'package:provider/provider.dart';

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
  }) async => [
    {
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
          'status': 'ABSENT',
        },
      ],
    },
  ];

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
  test(
    'selecting a seeded slot attaches its Sheet session and status',
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
