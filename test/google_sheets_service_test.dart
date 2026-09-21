import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/services/google_sheets_service.dart';

void main() {
  test('Apps Script template supports idempotent demo seeding', () {
    final script = GoogleSheetsService.sampleAppsScriptCode;

    expect(script, contains('data.action === "seedDemo"'));
    expect(script, contains('DEMO-SE1917-PRN232'));
    expect(script, contains('indexOf("DEMO-") === 0'));
    expect(script, contains('studentCount: demoClasses.length * names.length'));
  });
}
