import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/services/otp_service.dart';

void main() {
  test('OTP uses the shared signed 32-bit algorithm', () {
    final fixedTime = DateTime.fromMillisecondsSinceEpoch(
      1700000000000,
      isUtc: true,
    );

    expect(OtpService.generateOtpForTimeWindow(fixedTime), '757842');
  });
}
