import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/services/student_portal_url_service.dart';

void main() {
  test('session QR URL stays independent from the rotating OTP', () {
    final url = StudentPortalUrlService.buildSessionUrl(
      'http://192.168.137.1:8080/student/',
      sessionId: 'session-123',
    );

    final uri = Uri.parse(url);
    expect(uri.queryParameters, {'session': 'session-123'});
    expect(uri.queryParameters, isNot(contains('otp')));
    expect(uri.queryParameters, isNot(contains('class')));
  });
}
