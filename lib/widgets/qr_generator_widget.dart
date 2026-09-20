import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';

class QrGeneratorWidget extends StatefulWidget {
  const QrGeneratorWidget({super.key});

  static const String _configuredServerUrl = String.fromEnvironment(
    'ATTENDANCE_SERVER_URL',
    defaultValue: '',
  );

  static String get studentPortalUrl {
    if (_configuredServerUrl.isNotEmpty) {
      return '${_configuredServerUrl.replaceAll(RegExp(r'/$'), '')}/student/';
    }

    if (Uri.base.scheme == 'http' || Uri.base.scheme == 'https') {
      return '${Uri.base.origin}/student/';
    }

    return 'http://localhost:8080/student/';
  }

  @override
  State<QrGeneratorWidget> createState() => _QrGeneratorWidgetState();
}

class _QrGeneratorWidgetState extends State<QrGeneratorWidget> {
  Future<void> _togglePause(AttendanceProvider provider) async {
    final success = provider.isOtpPaused
        ? await provider.resumeOtpRotation()
        : await provider.pauseOtpRotation();
    if (!mounted || success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          provider.lastCheckinNotification ??
              'Không thể thay đổi trạng thái QR/OTP.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final session = provider.currentSession;
    if (!provider.isSessionOpen || provider.serverSessionId == null) {
      return _buildClosedState(context, provider);
    }

    final isPaused = provider.isOtpPaused;
    final liveOtp = session.activeOtp;

    // Live QR Data
    final liveQrData =
        '${QrGeneratorWidget.studentPortalUrl}?subject=${session.subjectCode}&class=${session.classCode}&slot=${session.slot}&session=${provider.serverSessionId}&otp=$liveOtp';

    final displayQrData = liveQrData;
    final displayOtp = liveOtp;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 18.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFF36F21).withValues(alpha: 0.08),
                    const Color(0xFFF36F21).withValues(alpha: 0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFF36F21).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.qr_code_2,
                    color: Color(0xFFF36F21),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${session.subjectCode} - Class ${session.classCode} (Slot ${session.slot})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: Color(0xFF1B2A4A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Pause/Resume Button
            SizedBox(
              width: double.infinity,
              child: isPaused
                  ? FilledButton.icon(
                      onPressed: provider.otpPauseOperationInProgress
                          ? null
                          : () => _togglePause(provider),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text(
                        'Tiếp tục QR & OTP',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: provider.otpPauseOperationInProgress
                          ? null
                          : () => _togglePause(provider),
                      icon: const Icon(Icons.pause_rounded, size: 18),
                      label: const Text(
                        'Tạm dừng QR & OTP',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF36F21),
                        side: const BorderSide(
                          color: Color(0xFFF36F21),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
            ),

            // Paused indicator banner
            if (isPaused) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 13,
                      color: Colors.amber.shade800,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'QR, OTP và bộ đếm đang tạm dừng',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Dynamic QR Code — Double Border Design (Compact & Sharp)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPaused
                      ? Colors.amber.shade200
                      : const Color(0xFFF36F21).withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (isPaused ? Colors.amber : const Color(0xFFF36F21))
                          .withValues(alpha: 0.06),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: displayQrData,
                  version: QrVersions.auto,
                  size: 210.0,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1B2A4A),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1B2A4A),
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // OTP Display
            Text(
              isPaused ? 'MÃ OTP (ĐANG TẠM DỪNG)' : 'MÃ OTP XÁC THỰC (10s)',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isPaused ? Colors.amber.shade800 : Colors.grey[500],
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isPaused
                      ? [Colors.amber.shade700, Colors.amber.shade800]
                      : [const Color(0xFF1B2A4A), const Color(0xFF243B6A)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isPaused
                                ? Colors.amber.shade700
                                : const Color(0xFF1B2A4A))
                            .withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                displayOtp.length == 6
                    ? '${displayOtp.substring(0, 3)} ${displayOtp.substring(3)}'
                    : displayOtp,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: Colors.white,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Ultra-smooth 60FPS countdown timer & aligned progress card
            _SmoothCountdownTimerWidget(
              isPaused: isPaused,
              frozenSecondsLeft: session.otpRemainingSeconds,
            ),
            const SizedBox(height: 12),

            // Deployed Student Portal Info Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Icon(
                          Icons.public_rounded,
                          size: 12,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Flexible(
                        child: Text(
                          'Cổng Điểm Danh Sinh Viên',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    QrGeneratorWidget.studentPortalUrl,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Color(0xFFF36F21),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hướng dẫn:',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '1. Bấm "Tạm dừng QR & OTP" để giữ nguyên mã và bộ đếm nếu cần\n'
                          '2. Sinh viên quét mã QR bằng camera điện thoại\n'
                          '3. Nhập OTP hiện tại rồi xác nhận điểm danh',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.blue.shade700,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedState(BuildContext context, AttendanceProvider provider) {
    final hasSelectedSlot = provider.selectedSlot != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey.shade100, Colors.grey.shade50],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_clock_outlined,
                size: 56,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasSelectedSlot
                  ? 'Phiên điểm danh đang đóng'
                  : 'Chưa chọn ca dạy',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B2A4A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSelectedSlot
                  ? 'Mở phiên để tạo QR và bắt đầu nhận lượt điểm danh.'
                  : 'Chọn một ca trong thời khóa biểu trước khi mở điểm danh.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: provider.sessionOperationInProgress || !hasSelectedSlot
                  ? null
                  : provider.openAttendanceSession,
              icon: provider.sessionOperationInProgress
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(
                hasSelectedSlot
                    ? 'Mở phiên điểm danh'
                    : 'Chọn ca trong thời khóa biểu',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dedicated, ultra-smooth 60FPS countdown timer widget.
/// Uses a [Ticker] to continuously calculate sub-second millisecond elapsed time
/// within the 10-second OTP window, resulting in seamless circular sweep and linear progress animation.
class _SmoothCountdownTimerWidget extends StatefulWidget {
  final bool isPaused;
  final int frozenSecondsLeft;

  const _SmoothCountdownTimerWidget({
    required this.isPaused,
    required this.frozenSecondsLeft,
  });

  @override
  State<_SmoothCountdownTimerWidget> createState() =>
      _SmoothCountdownTimerWidgetState();
}

class _SmoothCountdownTimerWidgetState
    extends State<_SmoothCountdownTimerWidget>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _progress = 1.0;
  int _secondsLeft = 10;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _calculateCurrentState();
    if (!widget.isPaused) {
      _ticker.start();
    }
  }

  void _calculateCurrentState() {
    if (widget.isPaused) {
      _progress = 1.0;
      _secondsLeft = widget.frozenSecondsLeft;
    } else {
      final now = DateTime.now();
      final msInWindow = now.millisecondsSinceEpoch % 10000;
      final msRemaining = 10000 - msInWindow;
      _progress = (msRemaining / 10000.0).clamp(0.0, 1.0);
      _secondsLeft = (msRemaining / 1000.0).ceil().clamp(1, 10);
    }
  }

  @override
  void didUpdateWidget(covariant _SmoothCountdownTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused != oldWidget.isPaused) {
      if (widget.isPaused) {
        _ticker.stop();
        setState(() {
          _progress = 1.0;
          _secondsLeft = widget.frozenSecondsLeft;
        });
      } else {
        _calculateCurrentState();
        if (!_ticker.isActive) {
          _ticker.start();
        }
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (widget.isPaused) return;

    final now = DateTime.now();
    final msInWindow = now.millisecondsSinceEpoch % 10000;
    final msRemaining = 10000 - msInWindow;
    final newProgress = (msRemaining / 10000.0).clamp(0.0, 1.0);
    final newSeconds = (msRemaining / 1000.0).ceil().clamp(1, 10);

    // Update on meaningful progress change (smooth 60fps) or second tick
    if ((newProgress - _progress).abs() >= 0.001 ||
        newSeconds != _secondsLeft) {
      setState(() {
        _progress = newProgress;
        _secondsLeft = newSeconds;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWarning = !widget.isPaused && _secondsLeft <= 3;
    final timerColor = widget.isPaused
        ? Colors.amber.shade700
        : (isWarning ? const Color(0xFFEF4444) : const Color(0xFFF36F21));

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isPaused
              ? Colors.amber.shade50
              : (isWarning ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.isPaused
                ? Colors.amber.shade200
                : (isWarning
                      ? const Color(0xFFFECACA)
                      : const Color(0xFFE2E8F0)),
            width: 1.2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Circular countdown ring with perfectly centered number
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 3.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: widget.isPaused
                        ? Colors.amber.shade100
                        : Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Text(
                      widget.isPaused ? '⏸' : '$_secondsLeft',
                      key: ValueKey(widget.isPaused ? 'paused' : _secondsLeft),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: timerColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Right section: Status title + Linear progress bar
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.isPaused
                            ? 'Mã QR đang giữ cố định'
                            : 'Tự động đổi mã sau',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: widget.isPaused
                              ? Colors.amber.shade900
                              : const Color(0xFF334155),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: timerColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.isPaused ? 'Tạm dừng' : '${_secondsLeft}s',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: timerColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 5,
                      backgroundColor: widget.isPaused
                          ? Colors.amber.shade100
                          : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
