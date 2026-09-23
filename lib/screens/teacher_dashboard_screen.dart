import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../services/file_download_helper.dart';
import '../widgets/audit_log_widget.dart';
import '../widgets/device_security_panel.dart';
import '../widgets/qr_generator_widget.dart';
import '../widgets/roster_table_widget.dart';
import '../widgets/sheets_config_widget.dart';
import 'fap_timetable_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  int _selectedTabIndex = 0;

  Future<void> _exportSessionCsv(AttendanceProvider provider) async {
    final url = provider.serverExportUrl;
    if (url == null) return;

    try {
      final saved = await downloadFile(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'Đã xuất file CSV. Bạn có thể mở file bằng Excel.'
                : 'Đã hủy lưu file CSV.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể xuất CSV: $error')));
    }
  }

  @override
  void initState() {
    super.initState();
    // Register navigation callback so timetable slot click can navigate to QR tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AttendanceProvider>(context, listen: false);
      provider.onNavigateToAttendance = () {
        if (mounted) {
          setState(() {
            _selectedTabIndex = 1; // Switch to Điểm danh QR & OTP tab
          });
        }
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final notification = provider.lastCheckinNotification;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Row(
        children: [
          // Sidebar Navigation
          _buildSidebar(context),

          // Main Content Area
          Expanded(
            child: Column(
              children: [
                // Top Header Bar
                _buildHeader(context, provider),

                // Live Notification Banner
                if (notification != null)
                  _buildNotificationBanner(notification),

                // Active View Body
                Expanded(child: _buildActiveTabContent(provider)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBanner(String notification) {
    final isWarning = notification.startsWith('⚠️');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isWarning
              ? [const Color(0xFFB45309), const Color(0xFFD97706)]
              : [Colors.green.shade700, Colors.green.shade600],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isWarning
                  ? Icons.gpp_maybe_rounded
                  : Icons.notifications_active_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notification,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SIDEBAR — Gradient Dark Navigation with Animated Indicators
  // ============================================================
  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 264,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E3259), Color(0xFF152242), Color(0xFF0F1A35)],
        ),
      ),
      child: Column(
        children: [
          // App Title Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF36F21), Color(0xFFFF8A4C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF36F21).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FAP ATTENDANCE',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 0.8,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Smart Desktop Assistant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 14),
              children: [
                _buildNavItem(
                  0,
                  'Thời khóa biểu tuần',
                  Icons.calendar_month_rounded,
                ),
                _buildNavItem(
                  1,
                  'Điểm danh QR & OTP 10s',
                  Icons.qr_code_scanner_rounded,
                ),
                _buildNavItem(
                  2,
                  'Danh sách sinh viên',
                  Icons.people_alt_outlined,
                ),
                _buildNavItem(
                  3,
                  'Cấu hình Google Sheets',
                  Icons.cloud_outlined,
                ),
                _buildNavItem(4, 'Nhật ký chỉnh sửa', Icons.history_rounded),
              ],
            ),
          ),

          // Active Slot Quick Tag — Glassmorphism Card
          Consumer<AttendanceProvider>(
            builder: (context, prov, _) {
              final selectedSlot = prov.selectedSlot;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: prov.isSessionOpen
                                ? const Color(0xFF22C55E)
                                : selectedSlot != null
                                ? const Color(0xFFF36F21)
                                : Colors.white38,
                            shape: BoxShape.circle,
                            boxShadow: prov.isSessionOpen
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF22C55E,
                                      ).withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Ca dạy đang chọn',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedSlot == null
                          ? 'Chưa chọn ca dạy'
                          : '${selectedSlot.subjectCode} - ${selectedSlot.classCode}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedSlot == null
                          ? 'Bấm một ca trong thời khóa biểu'
                          : 'Slot ${selectedSlot.slot} • ${prov.getStudentCountForClass(selectedSlot.classCode)} sinh viên',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Footer info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF36F21).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFFF36F21),
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'FPT University • Lab 1',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'v1.0',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Sidebar Nav Item with animated left indicator
  Widget _buildNavItem(int index, String label, IconData icon) {
    final isSelected = _selectedTabIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedTabIndex = index;
            });
          },
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          splashColor: const Color(0xFFF36F21).withValues(alpha: 0.12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFF36F21).withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // Animated left indicator bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 3,
                  height: isSelected ? 22 : 0,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF36F21),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFFF36F21,
                              ).withValues(alpha: 0.4),
                              blurRadius: 6,
                            ),
                          ]
                        : [],
                  ),
                ),
                SizedBox(width: isSelected ? 10 : 4),
                Icon(
                  icon,
                  color: isSelected
                      ? const Color(0xFFF36F21)
                      : Colors.white.withValues(alpha: 0.5),
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.65),
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER — Clean Layout with Better Spacing
  // ============================================================
  Widget _buildHeader(BuildContext context, AttendanceProvider provider) {
    final selectedSlot = provider.selectedSlot;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Class / Subject active badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2A4A).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.class_outlined,
                  color: Color(0xFF1B2A4A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                selectedSlot == null
                    ? 'Chưa chọn ca dạy'
                    : '${selectedSlot.subjectCode} - Lớp ${selectedSlot.classCode}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B2A4A),
                ),
              ),
              if (selectedSlot != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF36F21).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFF36F21).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Slot ${selectedSlot.slot}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF36F21),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: provider.isSessionOpen
                      ? const Color(0xFF22C55E).withValues(alpha: 0.08)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: provider.isSessionOpen
                        ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: provider.isSessionOpen
                            ? const Color(0xFF22C55E)
                            : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      selectedSlot == null
                          ? 'CHƯA CHỌN'
                          : provider.isSessionOpen
                          ? 'ĐANG MỞ'
                          : provider.serverSessionId != null
                          ? 'ĐÃ ĐÓNG'
                          : 'CHƯA CÓ PHIÊN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: provider.isSessionOpen
                            ? const Color(0xFF16A34A)
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Action Buttons
          Row(
            children: [
              if (_selectedTabIndex == 1)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ElevatedButton.icon(
                    onPressed:
                        provider.sessionOperationInProgress ||
                            selectedSlot == null
                        ? null
                        : provider.isSessionOpen
                        ? provider.closeAttendanceSession
                        : provider.openAttendanceSession,
                    icon: provider.sessionOperationInProgress
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            provider.isSessionOpen
                                ? Icons.stop_circle_outlined
                                : Icons.play_circle_outline,
                          ),
                    label: Text(
                      provider.isSessionOpen
                          ? 'Đóng điểm danh'
                          : provider.serverSessionId != null
                          ? 'Mở lại điểm danh'
                          : 'Mở điểm danh',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: provider.isSessionOpen
                          ? Colors.red[700]
                          : Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              if (_selectedTabIndex != 1)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: OutlinedButton.icon(
                    onPressed: selectedSlot == null
                        ? null
                        : () {
                            setState(() {
                              _selectedTabIndex = 1;
                            });
                          },
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: const Text('Mở trang QR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF36F21),
                      side: const BorderSide(color: Color(0xFFF36F21)),
                    ),
                  ),
                ),

              // Export FAP Report Button
              ElevatedButton.icon(
                onPressed: provider.serverSessionId == null
                    ? null
                    : () => _exportSessionCsv(provider),
                icon: const Icon(Icons.file_download, size: 18),
                label: const Text('Tải CSV phiên này'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TAB CONTENT
  // ============================================================
  Widget _buildActiveTabContent(AttendanceProvider provider) {
    switch (_selectedTabIndex) {
      case 0:
        return const FapTimetableScreen();
      case 1:
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Pane: Dynamic QR & OTP Widget (scrollable to guarantee no clipping)
              const SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: QrGeneratorWidget(),
                ),
              ),
              const SizedBox(width: 20),

              // Right Pane: Summary Statistics & Quick Roster Overview
              Expanded(
                child: Column(
                  children: [
                    // Stat Cards Grid — Premium Redesigned
                    Row(
                      children: [
                        _buildStatCard(
                          'Tổng sinh viên',
                          '${provider.countTotal}',
                          const Color(0xFF3B82F6),
                          Icons.people_alt_rounded,
                        ),
                        const SizedBox(width: 10),
                        _buildStatCard(
                          'Có mặt',
                          '${provider.countPresent}',
                          const Color(0xFF22C55E),
                          Icons.check_circle_rounded,
                        ),
                        const SizedBox(width: 10),
                        _buildStatCard(
                          'Vắng',
                          '${provider.countAbsent}',
                          const Color(0xFFEF4444),
                          Icons.cancel_rounded,
                        ),
                        const SizedBox(width: 10),
                        _buildStatCard(
                          'Chuyên cần',
                          '${provider.attendancePercentage.toStringAsFixed(1)}%',
                          const Color(0xFF0D9488),
                          Icons.trending_up_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Device-level anti proxy-attendance protection.
                    const DeviceSecurityPanel(),
                    const SizedBox(height: 12),

                    // Quick Roster Table
                    const Expanded(child: RosterTableWidget()),
                  ],
                ),
              ),
            ],
          ),
        );
      case 2:
        return const Padding(
          padding: EdgeInsets.all(20.0),
          child: RosterTableWidget(),
        );
      case 3:
        return const SheetsConfigWidget();
      case 4:
        return const AuditLogWidget();
      default:
        return const FapTimetableScreen();
    }
  }

  // ============================================================
  // STAT CARD — Premium with Icon, Gradient Accent & Border
  // ============================================================
  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Left accent bar
            Container(
              width: 4,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color, color.withValues(alpha: 0.4)],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, size: 16, color: color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
