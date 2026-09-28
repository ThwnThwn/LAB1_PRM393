import 'dart:convert';

import 'package:fap_attendance_app/models/fap_class_slot.dart';
import 'package:fap_attendance_app/providers/attendance_provider.dart';
import 'package:fap_attendance_app/services/attendance_api_service.dart';
import 'package:fap_attendance_app/services/attendance_live_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TimetableApi extends AttendanceApiService {
  List<Map<String, dynamic>> syncedMeetings = [];
  Object? syncError;

  @override
  Future<Map<String, dynamic>> getGoogleSheetsConfiguration({
    bool verify = false,
  }) async => {'isReachable': true};

  @override
  Future<Map<String, dynamic>> syncCourseMeetings(
    List<Map<String, dynamic>> meetings,
  ) async {
    if (syncError != null) throw syncError!;
    syncedMeetings = meetings.map(Map<String, dynamic>.from).toList();
    return {'success': true, 'meetingCount': meetings.length};
  }
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

  test('OCR candidate repairs codes and infers slot from FAP time text', () {
    final result = TimetableOcrResult.fromJson({
      'fileName': 'schedule.png',
      'confidence': 0.79,
      'rawText': 'IPRN232 SEI9I7 07h00–09h15 Offline',
      'candidates': [
        {
          'subjectCode': 'IPRN232',
          'subjectName': '© 07h00–09h15 - % Offline',
          'classCode': 'SEI9I7',
          'dayOfWeek': 1,
          'slot': null,
          'room': 'NVH 602',
          'confidence': 0.62,
          'warnings': ['Chưa xác định được slot'],
        },
      ],
    });

    final candidate = result.candidates.single;
    expect(candidate.subjectCode, 'PRN232');
    expect(candidate.classCode, 'SE1917');
    expect(candidate.subjectName, 'PRN232');
    expect(candidate.slot, 1);
    expect(
      candidate.warnings,
      containsAll([
        'Đã tự sửa mã môn IPRN232 → PRN232',
        'Đã tự sửa mã lớp SEI9I7 → SE1917',
        'Đã tự điền Slot 1 từ giờ học',
      ]),
    );
    expect(
      candidate.warnings.any(
        (warning) => warning.contains('Chưa xác định được slot'),
      ),
      isFalse,
    );
  });

  test('OCR time formats map to the corresponding FAP slots', () {
    TimetableOcrCandidate candidateFor(String time) =>
        TimetableOcrCandidate.fromJson({
          'subjectCode': 'PRN232',
          'subjectName': time,
          'classCode': 'SE1917',
        });

    expect(candidateFor('09h30-11h45').slot, 2);
    expect(candidateFor('12:30 - 14:45').slot, 3);
    expect(candidateFor('19.30 - 21.00').slot, 8);
  });

  test('OCR removes a book icon read as TI before the subject code', () {
    final candidate = TimetableOcrCandidate.fromJson({
      'subjectCode': 'TIPRM393',
      'subjectName': '09h30-11h45',
      'classCode': 'SE1917',
      'dayOfWeek': 4,
      'slot': 2,
      'room': 'NVH 602',
      'warnings': <String>[],
    });

    expect(candidate.subjectCode, 'PRM393');
    expect(candidate.warnings, contains('Đã tự sửa mã môn TIPRM393 → PRM393'));
  });

  test('OCR separates the lecturer account from the subject name', () {
    final candidate = TimetableOcrCandidate.fromJson({
      'subjectCode': 'IPRN232',
      'subjectName': '8 PhuongLHK',
      'classCode': 'SE1917',
      'dayOfWeek': 1,
      'slot': 1,
      'room': 'NVH 602',
      'warnings': <String>[],
    });

    expect(candidate.subjectCode, 'PRN232');
    expect(candidate.subjectName, 'PRN232');
    expect(candidate.instructor, 'PhuongLHK');
    expect(
      candidate.warnings,
      contains('Đã tách giảng viên PhuongLHK khỏi tên môn'),
    );
  });

  test('confirmed slots replace, de-duplicate and persist timetable', () async {
    final api = _TimetableApi();
    final provider = AttendanceProvider(
      attendanceApi: api,
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
    expect(api.syncedMeetings, hasLength(20));
    expect(api.syncedMeetings.first['meetingNumber'], 1);
    expect(api.syncedMeetings.last['meetingNumber'], 20);
    expect(api.syncedMeetings.first['classCode'], 'SE1917');

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
    final api = _TimetableApi();
    final provider = AttendanceProvider(
      attendanceApi: api,
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
    expect(api.syncedMeetings, hasLength(20));
    expect(
      api.syncedMeetings.map((meeting) => meeting['meetingNumber']),
      orderedEquals(List<int>.generate(20, (index) => index + 1)),
    );
    expect(api.syncedMeetings[2]['date'], _dateKey(anchor));
    expect(
      api.syncedMeetings[3]['date'],
      _dateKey(anchor.add(const Duration(days: 3))),
    );
    expect(
      provider.meetingOccurrenceForDate(
        mondayTemplate,
        anchor.subtract(const Duration(days: 14)),
      ),
      isNull,
    );
  });

  test(
    'failed Sheets plan sync leaves the local timetable unchanged',
    () async {
      final api = _TimetableApi()..syncError = StateError('Sheets unavailable');
      final provider = AttendanceProvider(
        attendanceApi: api,
        liveService: _TimetableLiveService(),
      );
      addTearDown(provider.dispose);
      final originalIds = provider.classSlots.map((slot) => slot.id).toList();

      await expectLater(
        provider.importTimetableSlots([
          FapClassSlot(
            id: 'new-slot',
            subjectCode: 'PRN232',
            subjectName: 'Backend',
            classCode: 'SE1917',
            slot: 1,
            dayOfWeek: DateTime.monday,
          ),
        ]),
        throwsStateError,
      );

      expect(
        provider.classSlots.map((slot) => slot.id),
        orderedEquals(originalIds),
      );
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('fap_attendance_teacher_timetable_v1'),
        isNull,
      );
    },
  );
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
