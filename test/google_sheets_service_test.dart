import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/services/google_sheets_service.dart';

void main() {
  test('Apps Script template supports idempotent demo seeding', () {
    final script = GoogleSheetsService.sampleAppsScriptCode;

    expect(script, contains('data.action === "seedDemo"'));
    expect(script, contains('DEMO-SE1917-PRN232'));
    expect(script, contains('DEMO-20260914-SE1918-PRM393-S2'));
    expect(script, contains('DEMO-20260917-SE1918-PRM393-S2'));
    expect(script, contains('DEMO-20260924-SE1920-HCM202-S4'));
    expect(
      script,
      contains(
        'subjectCode: "HCM202", slot: 1, sessionNumber: 5, totalSessions: 20, date: "2026-09-22"',
      ),
    );
    expect(
      script,
      contains(
        'subjectCode: "HCM202", slot: 1, sessionNumber: 6, totalSessions: 20, date: "2026-09-25"',
      ),
    );
    expect(script, contains('var demoSchedule = ['));
    expect(script, contains('indexOf("DEMO-") === 0'));
    expect(script, contains('studentCount: names.length'));
    expect(
      script,
      contains('rosterRowCount: demoClasses.length * names.length'),
    );
    expect(script, contains('sessionCount: demoSchedule.length'));
    expect(script, contains('var status = "ABSENT"'));
    expect(script, contains('isAttendanceRiskDemo'));
    expect(script, contains('demoClassSession.sessionNumber <= 4 && a === 0'));
    expect(script, isNot(contains('"NOT CHECKED"')));
    expect(script, isNot(contains('var status = "LATE"')));
  });

  test('Apps Script template exposes the complete Google-Sheets-only API', () {
    final script = GoogleSheetsService.sampleAppsScriptCode;

    expect(script, contains('version: 7'));
    expect(script, contains('CourseMeetings: ["MeetingId"'));
    expect(script, contains('upsertCourseMeeting(session, now)'));
    expect(
      script,
      contains('sessionNumber: Number(session.MeetingNumber || 0)'),
    );
    expect(script, contains('else if (prepareForWrite)'));
    expect(script, isNot(contains('for (var name in SCHEMA) getSheet(name)')));
    expect(script, contains('action === "getSessions"'));
    expect(script, contains('data.action === "syncCourseMeetings"'));
    expect(script, contains('data.action === "normalizeDuplicateSessions"'));
    expect(script, contains('closedSessions: normalizeResult.closedSessions'));
    expect(script, contains('DUPLICATE_MEETING'));
    expect(script, contains('buildSessionPayload'));
    expect(script, contains('deviceHash: item.DeviceHash'));
    expect(script, contains('auditLogs: auditLogs'));
  });
}
