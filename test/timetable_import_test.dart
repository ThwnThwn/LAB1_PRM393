import 'dart:convert';

import 'package:fap_attendance_app/models/fap_class_slot.dart';
import 'package:fap_attendance_app/providers/attendance_provider.dart';
import 'package:fap_attendance_app/services/attendance_api_service.dart';
import 'package:fap_attendance_app/services/attendance_live_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TimetableApi extends AttendanceApiService {
  @override
  Future<Map<String, dynamic>> getGoogleSheetsConfiguration({
    bool verify = false,
  }) async => {'isReachable': true};
}

class _TimetableLiveService extends AttendanceLiveService {
  @override
  Future<void> disconnect() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('OCR response maps nullable review fields safely', () {
    final result = TimetableOcrResult.fromJson({
      'fileName': 'schedule.png',
      'confidence': 0.91,
      'rawText': 'PRN232 SE1917 Slot 1',
      'candidates': [
        {
          'subjectCode': 'PRN232',
          'subjectName': 'Backend',
          'classCode': 'SE1917',
          'dayOfWeek': null,
          'slot': 1,
          'room': 'NVH 602',
          'confidence': 0.88,
          'warnings': ['Chưa xác định được thứ'],
        },
      ],
    });

    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.dayOfWeek, isNull);
    expect(result.candidates.single.warnings, ['Chưa xác định được thứ']);
  });

  test('confirmed slots replace, de-duplicate and persist timetable', () async {
    final provider = AttendanceProvider(
      attendanceApi: _TimetableApi(),
      liveService: _TimetableLiveService(),
    );
    addTearDown(provider.dispose);

    FapClassSlot slot(String id) => FapClassSlot(
      id: id,
      subjectCode: 'prn232',
      subjectName: 'Backend',
      classCode: 'se1917',
      slot: 1,
      dayOfWeek: 4,
      room: 'nvh 602',
    );

    final imported = await provider.importTimetableSlots([
      slot('ocr-1'),
      slot('ocr-duplicate'),
    ]);

    expect(imported, 1);
    expect(provider.classSlots, hasLength(1));
    expect(provider.classSlots.single.subjectCode, 'PRN232');
    expect(provider.classSlots.single.classCode, 'SE1917');
    expect(provider.classSlots.single.room, 'NVH 602');

    final preferences = await SharedPreferences.getInstance();
    final persisted =
        jsonDecode(
              preferences.getString('fap_attendance_teacher_timetable_v1')!,
            )
            as List<dynamic>;
    expect(persisted, hasLength(1));
    expect((persisted.single as Map<String, dynamic>)['dayOfWeek'], 4);
  });

  test('course meetings follow calendar date order across weeks', () async {
    final provider = AttendanceProvider(
      attendanceApi: _TimetableApi(),
      liveService: _TimetableLiveService(),
    );
    addTearDown(provider.dispose);

    await provider.importTimetableSlots([
      FapClassSlot(
        id: 'prn-mon',
        subjectCode: 'PRN232',
        subjectName: 'Backend',
        classCode: 'SE1917',
        slot: 1,
        dayOfWeek: DateTime.monday,
        sessionNumber: 4,
        totalSessions: 20,
      ),
      FapClassSlot(
        id: 'prn-thu',
        subjectCode: 'PRN232',
        subjectName: 'Backend',
        classCode: 'SE1917',
        slot: 1,
        dayOfWeek: DateTime.thursday,
        sessionNumber: 3,
        totalSessions: 20,
      ),
    ]);

    final anchor = provider.timetableMeetingAnchorWeekStart;
    final mondayTemplate = provider.classSlots.firstWhere(
      (slot) => slot.dayOfWeek == DateTime.monday,
    );
    final thursdayTemplate = provider.classSlots.firstWhere(
      (slot) => slot.dayOfWeek == DateTime.thursday,
    );
    final meetings = [
      provider.meetingOccurrenceForDate(mondayTemplate, anchor),
      provider.meetingOccurrenceForDate(
        thursdayTemplate,
        anchor.add(const Duration(days: 3)),
      ),
      provider.meetingOccurrenceForDate(
        mondayTemplate,
        anchor.add(const Duration(days: 7)),
      ),
    ];

    expect(meetings.map((slot) => slot?.sessionNumber), [3, 4, 5]);
    expect(
      provider.meetingOccurrenceForDate(
        mondayTemplate,
        anchor.subtract(const Duration(days: 14)),
      ),
      isNull,
    );
  });
}
