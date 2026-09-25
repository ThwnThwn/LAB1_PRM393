import 'dart:async';
import 'package:flutter/material.dart';
import '../services/otp_service.dart';

/// Isolated provider that owns the 1-second OTP timer.
///
/// By separating OTP state from [AttendanceProvider], the timer's
/// `notifyListeners()` call only rebuilds widgets that actually display
/// the OTP / countdown (QR panel, student check-in screen) instead of
/// triggering a full rebuild of the entire widget tree.
class OtpProvider extends ChangeNotifier {
  String _activeOtp = '';
  int _remainingSeconds = 10;
  bool _paused = false;
  Timer? _timer;

  String get activeOtp => _activeOtp;
  int get remainingSeconds => _remainingSeconds;
  bool get isPaused => _paused;

  OtpProvider() {
    _refreshOtp();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      final newRemaining = OtpService.getRemainingSeconds();
      final needsNewOtp = newRemaining == 10 || _activeOtp.isEmpty;

      // Only notify when the value actually changed.
      if (newRemaining != _remainingSeconds || needsNewOtp) {
        _remainingSeconds = newRemaining;
        if (needsNewOtp) _refreshOtp();
        notifyListeners();
      }
    });
  }

  void _refreshOtp() {
    _activeOtp = OtpService.generateOtpForTimeWindow();
  }

  /// Called by [AttendanceProvider] when the server confirms OTP pause.
  void pause(String frozenOtp, int frozenSeconds) {
    _paused = true;
    _activeOtp = frozenOtp;
    _remainingSeconds = frozenSeconds;
    notifyListeners();
  }

  /// Called by [AttendanceProvider] when the server confirms OTP resume.
  void resume() {
    _paused = false;
    _refreshOtp();
    _remainingSeconds = OtpService.getRemainingSeconds();
    notifyListeners();
  }

  /// Called by [AttendanceProvider._applyServerSnapshot] to sync pause
  /// state from the server without triggering a full provider rebuild.
  void syncFromSnapshot({
    required bool paused,
    String? frozenOtp,
    int? frozenSeconds,
  }) {
    if (paused) {
      _paused = true;
      if (frozenOtp != null && frozenOtp.length == 6) {
        _activeOtp = frozenOtp;
      }
      if (frozenSeconds != null) {
        _remainingSeconds = frozenSeconds;
      }
    } else if (_paused) {
      // Was paused, now resumed
      _paused = false;
      _refreshOtp();
      _remainingSeconds = OtpService.getRemainingSeconds();
    }
    // No notifyListeners() here — the caller decides whether to notify.
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
