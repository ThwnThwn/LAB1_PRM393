import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/otp_provider.dart';
import '../models/student.dart';

/// Modern Material 3 Student QR Scan Result & Attendance Check-in Screen.
/// Displays scanned class data, extracted 10s OTP, email input, and verified digital ticket.
class StudentQrCheckinScreen extends StatefulWidget {
  const StudentQrCheckinScreen({super.key});

  @override
  State<StudentQrCheckinScreen> createState() => _StudentQrCheckinScreenState();
}

class _StudentQrCheckinScreenState extends State<StudentQrCheckinScreen> {
  final _emailController = TextEditingController(
    text: 'minhnbse182173@fpt.edu.vn',
  );
  final _otpController = TextEditingController();

  final bool _isAutoFilledFromQr = true;
  Map<String, dynamic>? _checkinResult;
  String? _digitalTicketHash;

  @override
  void initState() {
    super.initState();
    // Auto-fill active OTP from QR code
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final otpProvider = Provider.of<OtpProvider>(context, listen: false);
      _otpController.text = otpProvider.activeOtp;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _submitAttendance() {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (email.isEmpty || otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập email và mã OTP!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final res = provider.checkinStudent(email: email, otp: otp);
    setState(() {
      _checkinResult = res;
      if (res['success'] == true) {
        // Generate pseudo-cryptographic anti-fraud ticket hash
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _digitalTicketHash =
            'FAP-${email.split('@').first.toUpperCase()}-${timestamp.toRadixString(16).toUpperCase()}';
      }
    });
  }

  void _resetForNewScan() {
    final otpProvider = Provider.of<OtpProvider>(context, listen: false);
    setState(() {
      _checkinResult = null;
      _digitalTicketHash = null;
      _otpController.text = otpProvider.activeOtp;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = Provider.of<AttendanceProvider>(context);
    final otpProvider = Provider.of<OtpProvider>(context);
    final secondsLeft = otpProvider.remainingSeconds;

    // Keep OTP synced if auto-filled
    if (_isAutoFilledFromQr && _checkinResult == null) {
      if (_otpController.text != otpProvider.activeOtp) {
        _otpController.text = otpProvider.activeOtp;
      }
    }

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: _checkinResult != null && _checkinResult!['success'] == true
                ? _buildSuccessTicket(context, provider)
                : _buildCheckinForm(context, provider, secondsLeft),
          ),
        ),
      ),
    );
  }

  /// Form displayed after scanning QR code
  Widget _buildCheckinForm(
    BuildContext context,
    AttendanceProvider provider,
    int secondsLeft,
  ) {
    final session = provider.currentSession;
    const fptOrange = Color(0xFFF36F21);
    const deepBlue = Color(0xFF1B2A4A);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Banner: Scanned QR Info
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: deepBlue,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: fptOrange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'QUÉT MÃ QR THÀNH CÔNG',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Row(
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          color: Colors.white70,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'FAP Verified',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${session.subjectCode} - Lớp ${session.classCode}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Buổi ${session.sessionNumber}/${session.totalSessions} • Slot ${session.slot} • Ngày: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),

          // Main Form Body
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // OTP Extracted Status Box
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: fptOrange.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.vpn_key_rounded,
                          color: fptOrange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mã OTP tự động trích xuất từ QR:',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _otpController.text.length == 6
                                  ? '${_otpController.text.substring(0, 3)} ${_otpController.text.substring(3)}'
                                  : _otpController.text,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                color: deepBlue,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Countdown Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: secondsLeft <= 3
                              ? Colors.red.shade100
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: secondsLeft <= 3
                                  ? Colors.red
                                  : Colors.orange.shade900,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${secondsLeft}s',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: secondsLeft <= 3
                                    ? Colors.red
                                    : Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Email Input Field
                const Text(
                  'Email của sinh viên:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: deepBlue,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    hintText: 'ví dụ: sinhvien@gmail.com',
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: fptOrange,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: fptOrange,
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Email Selectors for Class Demo
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildEmailChip(
                      'minhnbse182173@fpt.edu.vn',
                      'Bùi Nhật Minh',
                    ),
                    _buildEmailChip(
                      'namnvse171234@fpt.edu.vn',
                      'Nguyễn Văn Nam',
                    ),
                    _buildEmailChip('maittse180987@fpt.edu.vn', 'Trần Thị Mai'),
                  ],
                ),
                const SizedBox(height: 24),

                // Confirm Check-in Button
                FilledButton.icon(
                  onPressed: _submitAttendance,
                  icon: const Icon(Icons.how_to_reg_rounded, size: 22),
                  label: const Text(
                    'XÁC NHẬN ĐIỂM DANH NGAY',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: fptOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                ),

                // Error alert if failed
                if (_checkinResult != null &&
                    _checkinResult!['success'] == false) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _checkinResult!['message'] ?? 'Điểm danh thất bại.',
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailChip(String email, String name) {
    final isSelected = _emailController.text.trim() == email;
    return InkWell(
      onTap: () {
        setState(() {
          _emailController.text = email;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF36F21).withValues(alpha: 0.15)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFF36F21) : Colors.transparent,
          ),
        ),
        child: Text(
          '$name ($email)',
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? const Color(0xFFF36F21) : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Digital Attendance Ticket (Thẻ Điểm Danh Điện Tử) — Redesigned
  // ===========================================================================
  Widget _buildSuccessTicket(
    BuildContext context,
    AttendanceProvider provider,
  ) {
    final student = _checkinResult!['student'] as Student?;
    final session = provider.currentSession;
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    const emerald = Color(0xFF059669);
    const emeraldDark = Color(0xFF065F46);
    const deepBlue = Color(0xFF1B2A4A);

    // Slot time range text
    String slotTimeRange = 'Slot ${session.slot}';
    const slotTimes = {
      1: '7:00 - 9:15',
      2: '9:30 - 11:45',
      3: '12:30 - 14:45',
      4: '15:00 - 17:15',
      5: '17:30 - 19:45',
      6: '20:00 - 22:15',
    };
    if (slotTimes.containsKey(session.slot)) {
      slotTimeRange = 'Slot ${session.slot} (${slotTimes[session.slot]})';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: emerald.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: emerald.withValues(alpha: 0.10),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Header: Verified Banner with gradient ───
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF047857)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22.5)),
            ),
            child: Column(
              children: [
                // Check icon with glow ring
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 3,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: emerald,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'ĐIỂM DANH THÀNH CÔNG',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Thẻ Điểm Danh Điện Tử FPT University',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ─── Ticket Tear/Perforation Line ───
          Container(
            color: const Color(0xFFF0FDF4),
            child: Row(
              children: List.generate(
                60,
                (i) => Expanded(
                  child: Container(
                    height: 1.5,
                    color: i.isEven
                        ? const Color(0xFFA7F3D0)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),

          // ─── Ticket Body: Student Details ───
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              children: [
                _buildTicketInfoRow(
                  icon: Icons.person_rounded,
                  label: 'Sinh viên:',
                  value: student?.fullName ?? 'Sinh viên FPT',
                  isBold: true,
                  valueColor: deepBlue,
                ),
                _buildTicketDivider(),
                _buildTicketInfoRow(
                  icon: Icons.badge_rounded,
                  label: 'MSSV:',
                  value: student?.rollNo ?? 'N/A',
                  isBold: true,
                  valueColor: deepBlue,
                ),
                _buildTicketDivider(),
                _buildTicketInfoRow(
                  icon: Icons.email_rounded,
                  label: 'Email:',
                  value: student?.email ?? _emailController.text,
                  valueColor: deepBlue,
                ),
                _buildTicketDivider(),
                _buildTicketInfoRow(
                  icon: Icons.menu_book_rounded,
                  label: 'Môn học & Lớp:',
                  value: '${session.subjectCode} - Lớp ${session.classCode}',
                  valueColor: deepBlue,
                ),
                _buildTicketDivider(),
                _buildTicketInfoRow(
                  icon: Icons.format_list_numbered_rounded,
                  label: 'Buổi học:',
                  value:
                      'Buổi ${session.sessionNumber}/${session.totalSessions}',
                  valueColor: deepBlue,
                ),
                _buildTicketDivider(),
                _buildTicketInfoRow(
                  icon: Icons.access_time_filled_rounded,
                  label: 'Ca học (Slot):',
                  value: slotTimeRange,
                  valueColor: deepBlue,
                ),
                _buildTicketDivider(),
                _buildTicketInfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'Thời gian điểm danh:',
                  value: timeStr,
                  isBold: true,
                  valueColor: deepBlue,
                ),
                _buildTicketDivider(),
                _buildTicketInfoRow(
                  icon: Icons.verified_user_rounded,
                  label: 'Mã xác thực số:',
                  value: _digitalTicketHash ?? 'FAP-VERIFIED-2026',
                  isMonospace: true,
                  valueColor: const Color(0xFF0F766E),
                ),

                const SizedBox(height: 20),

                // ─── Sync Status Confirmation ───
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: emerald.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.cloud_done_rounded,
                          color: emerald,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Đã ghi nhận trên hệ thống điểm danh ASP.NET Core',
                          style: TextStyle(
                            color: emeraldDark,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ─── Reset / New Scan Button ───
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _resetForNewScan,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                    label: const Text(
                      'Điểm danh ca học khác / Đổi sinh viên',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Widgets for Ticket
  // ---------------------------------------------------------------------------
  Widget _buildTicketDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Divider(height: 1, color: Colors.grey.shade200),
    );
  }

  Widget _buildTicketInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isBold = false,
    bool isMonospace = false,
    Color valueColor = const Color(0xFF1B2A4A),
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Leading icon
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 8),
          // Fixed-width label for alignment
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Flexible right-aligned value
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                fontFamily: isMonospace ? 'monospace' : null,
                color: valueColor,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
