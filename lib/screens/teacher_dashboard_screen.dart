import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../dialogs/import_timetable_image_dialog.dart';
import '../providers/attendance_provider.dart';
import '../models/fap_class_slot.dart';
import '../models/student.dart';
import '../services/file_download_helper.dart';
import '../widgets/audit_log_widget.dart';
import '../widgets/device_security_panel.dart';
import '../widgets/qr_generator_widget.dart';
import '../widgets/roster_table_widget.dart';
import '../widgets/sheets_config_widget.dart';

// ── Stitch Design Tokens ──
class _DS {
  _DS._();
  static const Color primary = Color(0xFFA04100);
  static const Color primaryContainer = Color(0xFFF27023);
  static const Color secondary = Color(0xFF565E74);
  static const Color secondaryContainer = Color(0xFFDAE2FD);
  static const Color surface = Color(0xFFF8F9FF);
  static const Color surfaceBright = Color(0xFFF8F9FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFE5EEFF);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color onSurface = Color(0xFF0B1C30);
  static const Color outlineVariant = Color(0xFFE0C0B2);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color emerald50 = Color(0xFFECFDF5);
  static const Color emerald100 = Color(0xFFD1FAE5);
  static const Color emerald200 = Color(0xFFA7F3D0);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald700 = Color(0xFF047857);
  static const Color red50 = Color(0xFFFEF2F2);
  static const Color red600 = Color(0xFFDC2626);
  static const Color red700 = Color(0xFFB91C1C);
  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber100 = Color(0xFFFEF3C7);
  static const Color amber600 = Color(0xFFD97706);
  static const Color amber800 = Color(0xFF92400E);
  static const Color blue500 = Color(0xFF3B82F6);
  static const Color teal600 = Color(0xFF0D9488);
}

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  int _selectedTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _globalSearchQuery = '';
  DateTime _selectedDashboardDate = DateUtils.dateOnly(DateTime.now());
  DateTime _visibleCalendarMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _DS.red700 : null,
      ),
    );
  }

  Future<void> _exportCurrentCsv(AttendanceProvider provider) async {
    final url = provider.serverExportUrl;
    final slot = provider.selectedSlot;
    if (slot == null || provider.students.isEmpty) {
      _showMessage('Hãy chọn lớp có danh sách sinh viên trước khi xuất CSV.');
      return;
    }

    try {
      final saved = url != null
          ? await downloadFile(url)
          : await saveCsvFile(
              provider.exportFapCsv(),
              'attendance-${slot.subjectCode}-${slot.classCode}-slot${slot.slot}-${_fileDate(provider.currentSession.date)}.csv',
            );
      if (!mounted) return;
      _showMessage(
        saved
            ? 'Đã xuất file CSV. Bạn có thể mở file bằng Excel.'
            : 'Đã hủy lưu file CSV.',
      );
    } catch (error) {
      _showMessage('Không thể xuất CSV: $error', isError: true);
    }
  }

  Future<void> _exportCourseCsv(
    AttendanceProvider provider,
    FapClassSlot slot,
  ) async {
    final selected = await provider.selectTimetableSlotAndWait(slot);
    if (!mounted || !selected) return;
    await _exportCurrentCsv(provider);
  }

  Future<void> _importTimetableFromImage(AttendanceProvider provider) async {
    if (provider.isSessionOpen) {
      _showMessage(
        'Hãy đóng phiên điểm danh trước khi thay đổi thời khóa biểu.',
        isError: true,
      );
      return;
    }
    final selection = await showDialog<TimetableImageImportSelection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const TimetableImageImportDialog(),
    );
    if (!mounted || selection == null) return;

    try {
      final imported = await provider.importTimetableSlots(
        selection.slots,
        replaceExisting: selection.replaceExisting,
      );
      if (!mounted) return;
      setState(() {
        _selectedDashboardDate = DateUtils.dateOnly(DateTime.now());
        _visibleCalendarMonth = DateTime(
          DateTime.now().year,
          DateTime.now().month,
        );
      });
      _showMessage(
        imported == 0
            ? 'Các ca trong ảnh đã có sẵn trong thời khóa biểu.'
            : 'Đã nhập $imported ca và cập nhật thời khóa biểu.',
      );
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  void _openSlot(
    AttendanceProvider provider,
    FapClassSlot slot, {
    required int tabIndex,
    bool absentOnly = false,
  }) {
    if (!provider.selectTimetableSlot(slot)) return;
    if (_globalSearchQuery.isNotEmpty) {
      _searchController.clear();
      _globalSearchQuery = '';
      provider.setSearchQuery('');
    }
    provider.setFilterStatus(absentOnly ? AttendanceStatus.absent : null);
    setState(() => _selectedTabIndex = tabIndex);
  }

  void _openQuickQr(AttendanceProvider provider) {
    final today = DateTime.now().weekday;
    final target =
        provider.selectedSlot ??
        provider.classSlots.cast<FapClassSlot?>().firstWhere(
          (slot) => slot?.dayOfWeek == today,
          orElse: () =>
              provider.classSlots.isEmpty ? null : provider.classSlots.first,
        );
    if (target == null) {
      _showMessage('Thời khóa biểu chưa có ca dạy để chuẩn bị QR.');
      return;
    }
    _openSlot(provider, target, tabIndex: 1);
  }

  void _handleSearchChanged(AttendanceProvider provider, String value) {
    setState(() => _globalSearchQuery = value.trim());
    provider.setSearchQuery(value.trim());
  }

  void _submitGlobalSearch(AttendanceProvider provider, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return;

    final matchingSlots = provider.classSlots.where((slot) {
      return slot.subjectCode.toLowerCase().contains(query) ||
          slot.subjectName.toLowerCase().contains(query) ||
          slot.classCode.toLowerCase().contains(query) ||
          slot.room.toLowerCase().contains(query);
    }).toList();
    if (matchingSlots.isNotEmpty) {
      _openSlot(provider, matchingSlots.first, tabIndex: 2);
      return;
    }

    if (provider.filteredStudents.isNotEmpty) {
      setState(() => _selectedTabIndex = 2);
      return;
    }
    _showMessage('Không tìm thấy môn, lớp hoặc sinh viên phù hợp.');
  }

  void _selectDashboardDate(AttendanceProvider provider, DateTime date) {
    final expectedWeekStart = DateUtils.dateOnly(
      date.subtract(Duration(days: date.weekday - 1)),
    );
    provider.goToDate(date);
    if (!DateUtils.isSameDay(provider.currentWeekStart, expectedWeekStart)) {
      return;
    }
    setState(() {
      _selectedDashboardDate = DateUtils.dateOnly(date);
      _visibleCalendarMonth = DateTime(date.year, date.month);
    });
  }

  void _changeCalendarMonth(int delta) {
    setState(() {
      _visibleCalendarMonth = DateTime(
        _visibleCalendarMonth.year,
        _visibleCalendarMonth.month + delta,
      );
    });
  }

  Future<void> _copyAbsenceEmailDraft(AttendanceProvider provider) async {
    final absent = provider.students
        .where((student) => student.status == AttendanceStatus.absent)
        .toList();
    if (absent.isEmpty) {
      _showMessage('Phiên hiện tại không có sinh viên vắng.');
      return;
    }
    final session = provider.currentSession;
    final recipients = absent
        .map((student) => student.email.trim())
        .where((email) => email.isNotEmpty)
        .join('; ');
    final rollNumbers = absent.map((student) => student.rollNo).join(', ');
    final draft =
        'Người nhận: $recipients\n\n'
        'Tiêu đề: Cảnh báo chuyên cần ${session.subjectCode} - ${session.classCode}\n\n'
        'Nội dung:\nCác sinh viên sau đang được ghi nhận vắng ở Slot ${session.slot} ngày ${_displayDate(session.date)}: $rollNumbers. '
        'Vui lòng kiểm tra lại trạng thái chuyên cần trên FAP EduPulse.';
    await Clipboard.setData(ClipboardData(text: draft));
    _showMessage('Đã sao chép mẫu email cho ${absent.length} sinh viên vắng.');
  }

  static String _displayDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  static String _fileDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AttendanceProvider>(context, listen: false);
      provider.onNavigateToAttendance = () {
        if (mounted) setState(() => _selectedTabIndex = 1);
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final notification = provider.lastCheckinNotification;

    return Scaffold(
      backgroundColor: _DS.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1100;
          return Row(
            children: [
              _buildSidebar(context, compact: compact),
              Expanded(
                child: Column(
                  children: [
                    compact
                        ? _buildCompactHeader(context, provider)
                        : _buildHeader(context, provider),
                    if (notification != null)
                      _buildNotificationBanner(provider, notification),
                    Expanded(child: _buildActiveTabContent(provider)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // NOTIFICATION BANNER
  // ──────────────────────────────────────────────
  Widget _buildNotificationBanner(
    AttendanceProvider provider,
    String notification,
  ) {
    final isWarning = notification.startsWith('⚠️');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isWarning ? _DS.amber50 : _DS.emerald50,
        border: Border.all(color: isWarning ? _DS.amber600 : _DS.emerald500),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isWarning ? _DS.amber100 : _DS.emerald100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isWarning
                  ? Icons.warning_rounded
                  : Icons.notifications_active_rounded,
              color: isWarning ? _DS.amber800 : _DS.emerald700,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              notification,
              style: GoogleFonts.plusJakartaSans(
                color: isWarning ? _DS.amber800 : _DS.emerald700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: provider.clearLastCheckinNotification,
            tooltip: 'Đóng thông báo',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close_rounded,
              color: isWarning ? _DS.amber800 : _DS.emerald700,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // SIDEBAR
  // ──────────────────────────────────────────────
  Widget _buildSidebar(BuildContext context, {required bool compact}) {
    return Container(
      width: compact ? 76 : 260,
      decoration: const BoxDecoration(
        color: _DS.surfaceContainerLowest,
        border: Border(right: BorderSide(color: _DS.outlineVariant)),
      ),
      child: Column(
        children: [
          // Brand
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              20,
              compact ? 12 : 16,
              8,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _DS.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _DS.primaryContainer.withValues(alpha: 0.25),
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
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FPT EduPulse',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _DS.primary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Cổng Giảng Viên',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: _DS.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // CTA Button
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: 8,
            ),
            child: Consumer<AttendanceProvider>(
              builder: (context, prov, _) => Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openQuickQr(prov),
                  borderRadius: BorderRadius.circular(12),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: _DS.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _DS.primaryContainer.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Tạo phiên QR nhanh',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Nav items
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: 4,
              ),
              children: [
                _buildNavItem(
                  0,
                  'Bảng điều khiển',
                  Icons.dashboard_rounded,
                  compact: compact,
                ),
                _buildNavItem(
                  1,
                  'Điểm danh QR & OTP',
                  Icons.qr_code_scanner_rounded,
                  compact: compact,
                ),
                _buildNavItem(
                  2,
                  'Quản lý lớp học',
                  Icons.people_alt_rounded,
                  compact: compact,
                ),
                _buildNavItem(
                  3,
                  'Cấu hình Google Sheets',
                  Icons.cloud_outlined,
                  compact: compact,
                ),
                _buildNavItem(
                  4,
                  'Nhật ký chỉnh sửa',
                  Icons.history_rounded,
                  compact: compact,
                ),
              ],
            ),
          ),

          // Active slot info
          if (!compact)
            Consumer<AttendanceProvider>(
              builder: (context, prov, _) {
                final slot = prov.selectedSlot;
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _DS.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _DS.slate200),
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
                                  ? _DS.emerald500
                                  : slot != null
                                  ? _DS.primaryContainer
                                  : _DS.slate400,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Ca dạy đang chọn',
                            style: GoogleFonts.plusJakartaSans(
                              color: _DS.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        slot == null
                            ? 'Chưa chọn ca dạy'
                            : '${slot.subjectCode} - ${slot.classCode}',
                        style: GoogleFonts.plusJakartaSans(
                          color: _DS.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        slot == null
                            ? 'Bấm một ca trong thời khóa biểu'
                            : 'Slot ${slot.slot} • ${prov.getStudentCountForClass(slot.classCode)} sinh viên',
                        style: GoogleFonts.plusJakartaSans(
                          color: _DS.slate500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _DS.slate200)),
            ),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 6 : 8),
                  decoration: BoxDecoration(
                    color: _DS.surfaceBright,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _DS.slate200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _DS.slate200,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _DS.primaryContainer,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          size: 18,
                          color: _DS.slate500,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Giảng viên FPT',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _DS.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'FPT University',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: _DS.secondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 13,
                        color: _DS.primaryContainer.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'FPT University • Lab 1',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: _DS.slate400,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'v1.0',
                        style: GoogleFonts.jetBrainsMono(
                          color: _DS.slate400,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    String label,
    IconData icon, {
    required bool compact,
  }) {
    final isSelected = _selectedTabIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('nav-item-$index'),
          onTap: () => setState(() => _selectedTabIndex = index),
          borderRadius: BorderRadius.circular(8),
          hoverColor: _DS.surfaceContainerLow,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isSelected ? _DS.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? const Border(left: BorderSide(color: _DS.primary, width: 4))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: isSelected ? _DS.primary : _DS.secondary,
                  size: 20,
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        color: isSelected ? _DS.primary : _DS.secondary,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // HEADER / TOPBAR
  // ──────────────────────────────────────────────
  Widget _buildCompactHeader(
    BuildContext context,
    AttendanceProvider provider,
  ) {
    final canExport =
        provider.selectedSlot != null &&
        !provider.loadingSelectedSession &&
        provider.students.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: _DS.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: _DS.outlineVariant)),
      ),
      child: Row(
        children: [
          PopupMenuButton<FapClassSlot>(
            tooltip: 'Chọn ca dạy',
            onSelected: (slot) => provider.selectTimetableSlot(slot),
            itemBuilder: (context) => provider.classSlots
                .map(
                  (slot) => PopupMenuItem<FapClassSlot>(
                    value: slot,
                    child: Text(
                      '${FapClassSlot.getDayName(slot.dayOfWeek)} · Slot ${slot.slot} · ${slot.subjectCode} — ${slot.classCode}',
                    ),
                  ),
                )
                .toList(),
            icon: Icon(
              provider.selectedSlot == null
                  ? Icons.event_available_outlined
                  : Icons.event_available_rounded,
              color: _DS.primary,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                onChanged: (value) => _handleSearchChanged(provider, value),
                onSubmitted: (value) => _submitGlobalSearch(provider, value),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _DS.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Tìm môn, lớp, sinh viên...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 17),
                  suffixIcon: _globalSearchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            _handleSearchChanged(provider, '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 16),
                        ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildNotificationMenu(provider),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _openQuickQr(provider),
            tooltip: 'Mở trang QR',
            icon: const Icon(Icons.qr_code_2_rounded, size: 20),
            color: _DS.primaryContainer,
          ),
          IconButton(
            onPressed: canExport ? () => _exportCurrentCsv(provider) : null,
            tooltip: 'Tải CSV',
            icon: const Icon(Icons.file_download_rounded, size: 20),
            color: _DS.emerald600,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AttendanceProvider provider) {
    final selectedSlot = provider.selectedSlot;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: _DS.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: _DS.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left cluster
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Term badge
                  PopupMenuButton<FapClassSlot>(
                    key: const ValueKey('teaching-slot-picker'),
                    tooltip: 'Chọn ca dạy',
                    onSelected: (slot) => provider.selectTimetableSlot(slot),
                    itemBuilder: (context) => provider.classSlots
                        .map(
                          (slot) => PopupMenuItem<FapClassSlot>(
                            value: slot,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 58,
                                  child: Text(
                                    '${FapClassSlot.getDayName(slot.dayOfWeek)} · S${slot.slot}',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 11,
                                      color: _DS.slate500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${slot.subjectCode} — ${slot.classCode}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _DS.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _DS.slate200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: _DS.emerald500,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            selectedSlot == null
                                ? 'Chưa chọn ca'
                                : '${selectedSlot.subjectCode} - ${selectedSlot.classCode}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _DS.onSurface,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.expand_more,
                            size: 16,
                            color: _DS.secondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 20, color: _DS.slate200),
                  const SizedBox(width: 8),
                  // Metric badges
                  _metricBadge(
                    '${provider.countTotal}',
                    'SV',
                    _DS.surfaceBright,
                    _DS.onSurface,
                  ),
                  const SizedBox(width: 6),
                  _metricBadge(
                    '${provider.countPresent}',
                    'Có mặt',
                    _DS.emerald50,
                    _DS.emerald700,
                  ),
                  const SizedBox(width: 6),
                  _metricBadge(
                    '${provider.countAbsent}',
                    'Vắng',
                    _DS.red50,
                    _DS.red700,
                  ),
                  const SizedBox(width: 6),
                  _metricBadge(
                    '${provider.attendancePercentage.toStringAsFixed(1)}%',
                    'Chuyên cần',
                    _DS.emerald50,
                    _DS.emerald700,
                  ),
                  const SizedBox(width: 8),
                  // Session status pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: provider.isSessionOpen
                          ? _DS.emerald50
                          : _DS.slate100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: provider.isSessionOpen
                            ? _DS.emerald200
                            : _DS.slate200,
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
                                ? _DS.emerald500
                                : _DS.slate400,
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
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: provider.isSessionOpen
                                ? _DS.emerald700
                                : _DS.slate600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right cluster — search + bell + actions
          Row(
            children: [
              // Search bar
              Container(
                width: 220,
                height: 36,
                decoration: BoxDecoration(
                  color: _DS.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _DS.slate200),
                ),
                child: TextField(
                  key: const ValueKey('global-search-field'),
                  controller: _searchController,
                  onChanged: (value) => _handleSearchChanged(provider, value),
                  onSubmitted: (value) => _submitGlobalSearch(provider, value),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _DS.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tìm môn, mã lớp, sinh viên...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _DS.slate400,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: _DS.slate400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Notification bell
              _buildNotificationMenu(provider),
              const SizedBox(width: 8),

              // Separator
              Container(width: 1, height: 24, color: _DS.slate200),
              const SizedBox(width: 8),

              // Session open/close
              if (_selectedTabIndex == 1)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _actionBtn(
                    onPressed:
                        provider.sessionOperationInProgress ||
                            selectedSlot == null
                        ? null
                        : provider.isSessionOpen
                        ? provider.closeAttendanceSession
                        : provider.openAttendanceSession,
                    icon: provider.sessionOperationInProgress
                        ? null
                        : provider.isSessionOpen
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                    isLoading: provider.sessionOperationInProgress,
                    label: provider.isSessionOpen
                        ? 'Đóng điểm danh'
                        : provider.serverSessionId != null
                        ? 'Mở lại'
                        : 'Mở điểm danh',
                    bgColor: provider.isSessionOpen
                        ? _DS.red600
                        : _DS.emerald600,
                    fgColor: Colors.white,
                  ),
                ),

              // Quick QR
              if (_selectedTabIndex != 1)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _openQuickQr(provider),
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: const Text('Mở trang QR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _DS.primaryContainer,
                      side: const BorderSide(color: _DS.primaryContainer),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

              // Export CSV
              _actionBtn(
                onPressed:
                    selectedSlot == null ||
                        provider.loadingSelectedSession ||
                        provider.students.isEmpty
                    ? null
                    : () => _exportCurrentCsv(provider),
                icon: Icons.file_download_rounded,
                label: 'Tải CSV',
                bgColor: _DS.emerald600,
                fgColor: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricBadge(String value, String label, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _DS.slate200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: textColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _DS.slate600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationMenu(AttendanceProvider provider) {
    final notificationCount =
        (provider.lastCheckinNotification == null ? 0 : 1) +
        (provider.sheetsReachable ? 0 : 1) +
        (provider.deviceConflicts.isEmpty ? 0 : 1);

    return PopupMenuButton<int>(
      tooltip: 'Thông báo hệ thống',
      onSelected: (destination) {
        setState(() => _selectedTabIndex = destination);
      },
      itemBuilder: (context) => [
        if (provider.lastCheckinNotification != null)
          PopupMenuItem<int>(
            enabled: false,
            child: SizedBox(
              width: 300,
              child: Text(
                provider.lastCheckinNotification!,
                style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
              ),
            ),
          ),
        PopupMenuItem<int>(
          value: 3,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              provider.sheetsReachable
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: provider.sheetsReachable ? _DS.emerald600 : _DS.red600,
            ),
            title: Text(
              provider.sheetsReachable
                  ? 'Google Sheets đã kết nối'
                  : 'Google Sheets cần kiểm tra',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text('Mở cấu hình kết nối'),
          ),
        ),
        if (provider.deviceConflicts.isNotEmpty)
          PopupMenuItem<int>(
            value: 1,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(
                Icons.phonelink_lock_outlined,
                color: _DS.amber600,
              ),
              title: Text(
                '${provider.deviceConflicts.length} cảnh báo thiết bị',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text('Mở trang điểm danh để xử lý'),
            ),
          ),
        PopupMenuItem<int>(
          value: 4,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.history_rounded, color: _DS.slate600),
            title: Text(
              'Nhật ký chỉnh sửa',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text('${provider.auditLogs.length} hoạt động đã tải'),
          ),
        ),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _DS.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              size: 20,
              color: _DS.secondary,
            ),
          ),
          if (notificationCount > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: _DS.red600,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  notificationCount > 9 ? '9+' : '$notificationCount',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required VoidCallback? onPressed,
    required String label,
    required Color bgColor,
    required Color fgColor,
    IconData? icon,
    bool isLoading = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: fgColor),
            )
          : icon != null
          ? Icon(icon, size: 18)
          : const SizedBox.shrink(),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
      ),
    );
  }

  // ──────────────────────────────────────────────
  // TAB CONTENT ROUTER
  // ──────────────────────────────────────────────
  Widget _buildActiveTabContent(AttendanceProvider provider) {
    switch (_selectedTabIndex) {
      case 0:
        return _DashboardOverviewTab(
          searchQuery: _globalSearchQuery,
          selectedDate: _selectedDashboardDate,
          visibleMonth: _visibleCalendarMonth,
          onPreviousMonth: () => _changeCalendarMonth(-1),
          onNextMonth: () => _changeCalendarMonth(1),
          onSelectDate: (date) => _selectDashboardDate(provider, date),
          onOpenSlot: (slot) => _openSlot(provider, slot, tabIndex: 1),
          onOpenCourse: (slot) => _openSlot(provider, slot, tabIndex: 2),
          onExportCourse: (slot) => _exportCourseCsv(provider, slot),
          onImportTimetable: () => _importTimetableFromImage(provider),
          onCopyAbsenceEmail: () => _copyAbsenceEmailDraft(provider),
          onShowAbsences: () {
            provider.setFilterStatus(AttendanceStatus.absent);
            setState(() => _selectedTabIndex = 2);
          },
        );
      case 1:
        return _buildQrTab(provider);
      case 2:
        return const Padding(
          padding: EdgeInsets.all(20),
          child: RosterTableWidget(),
        );
      case 3:
        return const SheetsConfigWidget();
      case 4:
        return const AuditLogWidget();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Tab 1: QR Điểm danh ──
  Widget _buildQrTab(AttendanceProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const QrGeneratorWidget(),
                const SizedBox(height: 16),
                _buildStats(provider, compact: true),
                const SizedBox(height: 16),
                const DeviceSecurityPanel(),
                const SizedBox(height: 12),
                SizedBox(
                  height: 620,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: const SizedBox(
                      width: 920,
                      child: RosterTableWidget(),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: QrGeneratorWidget(),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    _buildStats(provider, compact: false),
                    const SizedBox(height: 20),
                    const DeviceSecurityPanel(),
                    const SizedBox(height: 12),
                    const Expanded(child: RosterTableWidget()),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStats(AttendanceProvider provider, {required bool compact}) {
    final cards = <Widget>[
      _buildStatCard(
        'Tổng sinh viên',
        '${provider.countTotal}',
        _DS.blue500,
        Icons.people_alt_rounded,
      ),
      _buildStatCard(
        'Có mặt',
        '${provider.countPresent}',
        _DS.emerald500,
        Icons.check_circle_rounded,
      ),
      _buildStatCard(
        'Vắng',
        '${provider.countAbsent}',
        _DS.red600,
        Icons.cancel_rounded,
      ),
      _buildStatCard(
        'Chuyên cần',
        '${provider.attendancePercentage.toStringAsFixed(1)}%',
        _DS.teal600,
        Icons.trending_up_rounded,
      ),
    ];
    if (!compact) {
      return Row(
        children: [
          cards[0],
          const SizedBox(width: 10),
          cards[1],
          const SizedBox(width: 10),
          cards[2],
          const SizedBox(width: 10),
          cards[3],
        ],
      );
    }
    return Column(
      children: [
        Row(children: [cards[0], const SizedBox(width: 10), cards[1]]),
        const SizedBox(height: 10),
        Row(children: [cards[2], const SizedBox(width: 10), cards[3]]),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: _DS.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _DS.slate200),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color, color.withValues(alpha: 0.3)],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
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
                              style: GoogleFonts.plusJakartaSans(
                                color: _DS.slate500,
                                fontSize: 12,
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
                        style: GoogleFonts.jetBrainsMono(
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
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// TAB 0 — DASHBOARD OVERVIEW (matching Stitch design exactly)
// ══════════════════════════════════════════════════════════════
class _DashboardOverviewTab extends StatelessWidget {
  final String searchQuery;
  final DateTime selectedDate;
  final DateTime visibleMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<FapClassSlot> onOpenSlot;
  final ValueChanged<FapClassSlot> onOpenCourse;
  final ValueChanged<FapClassSlot> onExportCourse;
  final VoidCallback onImportTimetable;
  final VoidCallback onCopyAbsenceEmail;
  final VoidCallback onShowAbsences;

  const _DashboardOverviewTab({
    required this.searchQuery,
    required this.selectedDate,
    required this.visibleMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelectDate,
    required this.onOpenSlot,
    required this.onOpenCourse,
    required this.onExportCourse,
    required this.onImportTimetable,
    required this.onCopyAbsenceEmail,
    required this.onShowAbsences,
  });

  static const Color _primary = Color(0xFFA04100);
  static const Color _container = Color(0xFFF27023);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _slate200 = Color(0xFFE2E8F0);
  static const Color _slate500 = Color(0xFF64748B);
  static const Color _slate600 = Color(0xFF475569);
  static const Color _slate700 = Color(0xFF334155);
  static const Color _slate900 = Color(0xFF0F172A);
  static const Color _emerald50 = Color(0xFFECFDF5);
  static const Color _emerald100 = Color(0xFFD1FAE5);
  static const Color _emerald200 = Color(0xFFA7F3D0);
  static const Color _emerald600 = Color(0xFF059669);
  static const Color _emerald700 = Color(0xFF047857);
  static const Color _red100 = Color(0xFFFEE2E2);
  static const Color _red700 = Color(0xFFB91C1C);
  static const Color _amber50 = Color(0xFFFFFBEB);
  static const Color _amber100 = Color(0xFFFEF3C7);
  static const Color _amber200 = Color(0xFFFDE68A);
  static const Color _amber600 = Color(0xFFD97706);
  static const Color _amber800 = Color(0xFF92400E);
  static const Color _amber950 = Color(0xFF451A03);
  static const Color _orange100 = Color(0xFFFFEDD5);
  static const Color _orange800 = Color(0xFF9A3412);

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, provider, _) {
        final dateSlots = _getDateSlots(provider, selectedDate);
        final uniqueSubjects = _getUniqueSubjectGroups(provider);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── SECTION 1: Absence Warning Banner ──
              _buildAbsenceWarningBanner(provider),
              const SizedBox(height: 20),

              // ── SECTION 2: Calendar + Today's Slots ──
              _buildCalendarAndSlots(
                context,
                provider,
                selectedDate,
                dateSlots,
              ),
              const SizedBox(height: 24),

              // ── SECTION 3: Class Cards Grid ──
              _buildClassCardsSection(context, provider, uniqueSubjects),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ──
  List<FapClassSlot> _getDateSlots(AttendanceProvider provider, DateTime date) {
    final dayOfWeek = date.weekday; // 1=Mon .. 7=Sun
    final query = searchQuery.trim().toLowerCase();
    return provider.classSlots.where((slot) {
      if (slot.dayOfWeek != dayOfWeek) return false;
      if (query.isEmpty) return true;
      return slot.subjectCode.toLowerCase().contains(query) ||
          slot.subjectName.toLowerCase().contains(query) ||
          slot.classCode.toLowerCase().contains(query) ||
          slot.room.toLowerCase().contains(query);
    }).toList()..sort((a, b) => a.slot.compareTo(b.slot));
  }

  // Deduplicated by subjectCode+classCode (unique courses)
  List<_CourseInfo> _getUniqueSubjectGroups(AttendanceProvider provider) {
    final seen = <String>{};
    final result = <_CourseInfo>[];
    final query = searchQuery.trim().toLowerCase();
    for (final slot in provider.classSlots) {
      final matchesQuery =
          query.isEmpty ||
          slot.subjectCode.toLowerCase().contains(query) ||
          slot.subjectName.toLowerCase().contains(query) ||
          slot.classCode.toLowerCase().contains(query) ||
          slot.room.toLowerCase().contains(query);
      if (!matchesQuery) continue;
      final key = '${slot.subjectCode}__${slot.classCode}';
      if (seen.add(key)) {
        result.add(
          _CourseInfo(
            classCode: slot.classCode,
            subjectCode: slot.subjectCode,
            subjectName: slot.subjectName,
            room: slot.room,
            studentCount: provider.getStudentCountForClass(slot.classCode),
            slotLabel: 'Slot ${slot.slot}',
            representativeSlot: slot,
          ),
        );
      }
    }
    return result;
  }

  // ── ABSENCE WARNING BANNER ──
  Widget _buildAbsenceWarningBanner(AttendanceProvider provider) {
    // Show warning if any absence data exists (based on current roster)
    final absentCount = provider.countAbsent;
    final hasWarning = provider.selectedSlot != null && absentCount > 0;

    if (!hasWarning) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _emerald50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _emerald200),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _emerald100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _emerald200),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: _emerald700,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tình hình chuyên cần tốt',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _emerald700,
                    ),
                  ),
                  Text(
                    provider.selectedSlot == null
                        ? 'Hãy chọn một ca dạy trong thời khóa biểu để xem thông tin lớp.'
                        : 'Không có sinh viên nào cần cảnh báo chuyên cần trong phiên hiện tại.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _emerald600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _amber200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 5, color: _container),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _amber100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _amber200),
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: _container,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Cảnh báo chuyên cần: Có $absentCount sinh viên vắng trong phiên hiện tại',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: _amber950,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _red100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Khẩn cấp',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: _red700,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Quy chế FPT: sinh viên vắng quá 20% tổng số giờ giảng dạy sẽ bị đình chỉ tư cách tham gia thi (FE).',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: _amber800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Action buttons
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: onCopyAbsenceEmail,
                            icon: const Icon(
                              Icons.content_copy_rounded,
                              size: 16,
                            ),
                            label: Text(
                              'Sao chép email cảnh báo',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _amber600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: onShowAbsences,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _amber950,
                              side: const BorderSide(color: _amber200),
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Xem danh sách',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── CALENDAR + TODAY'S SLOTS ──
  Widget _buildCalendarAndSlots(
    BuildContext context,
    AttendanceProvider provider,
    DateTime selectedDate,
    List<FapClassSlot> dateSlots,
  ) {
    final isToday = DateUtils.isSameDay(selectedDate, DateTime.now());
    final calendar = Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slate200),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar header
          Row(
            children: [
              Icon(Icons.event_rounded, color: _container, size: 20),
              const SizedBox(width: 8),
              Text(
                _monthLabel(visibleMonth),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _slate900,
                ),
              ),
              const Spacer(),
              _calNavBtn(Icons.chevron_left_rounded, onPreviousMonth),
              const SizedBox(width: 4),
              _calNavBtn(Icons.chevron_right_rounded, onNextMonth),
            ],
          ),
          const SizedBox(height: 14),
          // Weekday labels
          Row(
            children: ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: d == 'CN'
                              ? const Color(0xFFEF4444)
                              : _slate500,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          // Calendar days
          _buildCalendarDays(visibleMonth, selectedDate, provider),
          const SizedBox(height: 16),
          Divider(color: _slate200, height: 1),
          const SizedBox(height: 14),
          // Today summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isToday ? 'HÔM NAY' : 'NGÀY ĐÃ CHỌN',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                  letterSpacing: 1,
                ),
              ),
              Text(
                provider.currentWeekLabel,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  color: _slate500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _fullDateLabel(selectedDate),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _slate900,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: _container),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  dateSlots.isEmpty
                      ? 'Không có ca dạy trong ngày này'
                      : 'Tổng ${dateSlots.length} ca: ${dateSlots.map((s) => 'Slot ${s.slot}').join(', ')}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _slate600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final slots = Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slate200),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday
                          ? 'Tiết học hôm nay (Today\'s Slots)'
                          : 'Tiết học ngày đã chọn',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _slate900,
                      ),
                    ),
                    Text(
                      'Tiến trình giảng dạy ngày ${_shortDate(selectedDate)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: _slate500,
                      ),
                    ),
                  ],
                ),
              ),
              if (provider.isSessionOpen)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _amber50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _amber200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Đang mở phiên',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _amber800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (dateSlots.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _slate200),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.event_busy_rounded,
                      size: 36,
                      color: _slate500.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      searchQuery.isEmpty
                          ? 'Không có tiết dạy trong ngày này'
                          : 'Không có tiết dạy khớp từ khóa',
                      style: GoogleFonts.plusJakartaSans(
                        color: _slate500,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...dateSlots.map(
              (slot) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildTodaySlotRow(context, provider, slot),
              ),
            ),

          // Projector note
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.cast_connected_rounded, size: 15, color: _container),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Hỗ trợ kết nối không dây màn hình máy chiếu phòng học FPT EduCast',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _slate600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [calendar, const SizedBox(height: 20), slots],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: calendar),
            const SizedBox(width: 20),
            Expanded(flex: 8, child: slots),
          ],
        );
      },
    );
  }

  Widget _calNavBtn(IconData icon, VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      tooltip: icon == Icons.chevron_left_rounded ? 'Tháng trước' : 'Tháng sau',
      icon: Icon(icon, size: 18, color: _slate600),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFFF8FAFC),
        side: const BorderSide(color: _slate200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        fixedSize: const Size(28, 28),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildCalendarDays(
    DateTime month,
    DateTime selectedDate,
    AttendanceProvider provider,
  ) {
    final firstDay = DateTime(month.year, month.month, 1);
    final startOffset = (firstDay.weekday - 1) % 7; // Mon=0
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = <Widget>[];
    for (int i = 0; i < startOffset; i++) {
      cells.add(
        Expanded(
          child: Center(
            child: Text('', style: GoogleFonts.jetBrainsMono(fontSize: 12)),
          ),
        ),
      );
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final isSelected = DateUtils.isSameDay(date, selectedDate);
      final isToday = DateUtils.isSameDay(date, DateTime.now());
      final hasSlots = _getDateSlots(provider, date).isNotEmpty;
      cells.add(
        Expanded(
          child: Center(
            child: InkWell(
              key: ValueKey('calendar-day-${date.year}-${date.month}-$d'),
              onTap: () => onSelectDate(date),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 32,
                height: 34,
                decoration: BoxDecoration(
                  color: isSelected ? _container : null,
                  borderRadius: BorderRadius.circular(8),
                  border: isToday && !isSelected
                      ? Border.all(color: _container)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _container.withValues(alpha: 0.3),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$d',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: isSelected || isToday
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : isToday
                            ? _primary
                            : _slate700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (hasSlots)
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : _container,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    // Fill remaining cells to complete last row
    final totalCells = startOffset + daysInMonth;
    final remainder = (7 - totalCells % 7) % 7;
    for (int i = 0; i < remainder; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }

    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      rows.add(Row(children: cells.sublist(i, i + 7)));
      if (i + 7 < cells.length) rows.add(const SizedBox(height: 4));
    }
    return Column(children: rows);
  }

  Widget _buildTodaySlotRow(
    BuildContext context,
    AttendanceProvider provider,
    FapClassSlot slot,
  ) {
    final isActive =
        provider.isSessionOpen && provider.selectedSlot?.id == slot.id;
    final isSelected = provider.selectedSlot?.id == slot.id;
    final slotTime = FapClassSlot.getSlotTimeRange(slot.slot);
    final compact = MediaQuery.sizeOf(context).width < 1100;

    return AnimatedContainer(
      key: ValueKey('dashboard-slot-${slot.id}'),
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFFFFF7ED).withValues(alpha: 0.5)
            : _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? _container : _slate200,
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: _container.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Slot time badge
          Container(
            width: 60,
            height: 64,
            decoration: BoxDecoration(
              color: isActive ? _container : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(11),
              ),
              border: Border(
                right: BorderSide(
                  color: isActive
                      ? _container.withValues(alpha: 0.3)
                      : _slate200,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Slot ${slot.slot}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white70 : _slate500,
                  ),
                ),
                Text(
                  slotTime.split(' - ')[0],
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isActive ? Colors.white : _slate700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        slot.subjectCode,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _slate900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? _orange100
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'Lớp ${slot.classCode}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isActive ? _orange800 : _slate600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '• Phòng ${slot.room.isEmpty ? 'TBD' : slot.room}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: _slate500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    slot.subjectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _slate600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (isActive)
                        _slotStatusBadge(
                          Icons.radio_button_checked,
                          'Đang diễn ra: ${provider.countPresent}/${provider.countTotal} đã quét',
                          const Color(0xFFFFF7ED),
                          _orange800,
                          isLive: true,
                        )
                      else if (isSelected && provider.serverSessionId != null)
                        _slotStatusBadge(
                          Icons.check_circle_outline_rounded,
                          'Đã hoàn thành',
                          _emerald50,
                          _emerald700,
                        )
                      else
                        _slotStatusBadge(
                          Icons.timer_outlined,
                          slotTime,
                          const Color(0xFFF8FAFC),
                          _slate600,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(right: compact ? 6 : 14),
            child: compact
                ? IconButton(
                    key: ValueKey('open-slot-${slot.id}'),
                    onPressed: () => onOpenSlot(slot),
                    tooltip: isActive
                        ? 'Mở QR toàn màn hình'
                        : isSelected
                        ? 'Xem chi tiết'
                        : 'Chuẩn bị QR',
                    icon: Icon(
                      isActive
                          ? Icons.fullscreen_rounded
                          : isSelected
                          ? Icons.visibility_outlined
                          : Icons.qr_code_2_rounded,
                      size: 20,
                    ),
                    color: isActive ? _container : _slate700,
                  )
                : isActive
                ? ElevatedButton.icon(
                    key: ValueKey('open-slot-${slot.id}'),
                    onPressed: () => onOpenSlot(slot),
                    icon: const Icon(Icons.fullscreen_rounded, size: 16),
                    label: Text(
                      'Mở QR Fullscreen',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _container,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                  )
                : OutlinedButton.icon(
                    key: ValueKey('open-slot-${slot.id}'),
                    onPressed: () => onOpenSlot(slot),
                    icon: Icon(
                      isSelected
                          ? Icons.visibility_outlined
                          : Icons.qr_code_2_rounded,
                      size: 16,
                    ),
                    label: Text(
                      isSelected ? 'Xem chi tiết' : 'Chuẩn bị QR',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _slate700,
                      side: const BorderSide(color: _slate200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _slotStatusBadge(
    IconData icon,
    String text,
    Color bg,
    Color fg, {
    bool isLive = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive)
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _container,
                shape: BoxShape.circle,
              ),
            )
          else
            Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  // ── CLASS CARDS GRID ──
  Widget _buildClassCardsSection(
    BuildContext context,
    AttendanceProvider provider,
    List<_CourseInfo> courses,
  ) {
    final uniqueCodes = provider.availableClassCodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 760;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Danh sách lớp học phụ trách — Học kỳ hiện tại',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _slate900,
                  ),
                ),
                Text(
                  'Theo dõi tiến độ, quản lý sinh viên và xuất báo cáo điểm danh từng môn học',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: _slate500,
                  ),
                ),
              ],
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('import-timetable-image'),
                  onPressed: onImportTimetable,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _DS.primaryContainer,
                    side: const BorderSide(color: _DS.primaryContainer),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: const Text('Nhập ảnh TKB'),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _slate200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _filterChip('Tất cả (${uniqueCodes.length})', true),
                    ],
                  ),
                ),
              ],
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 12), actions],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                actions,
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        if (courses.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _slate200),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.search_off_rounded,
                  color: _slate500,
                  size: 30,
                ),
                const SizedBox(height: 8),
                Text(
                  'Không có lớp học khớp “$searchQuery”',
                  style: GoogleFonts.plusJakartaSans(
                    color: _slate600,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columnCount = constraints.maxWidth >= 1050
                  ? 3
                  : constraints.maxWidth >= 660
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnCount,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 280,
                ),
                itemCount: courses.length,
                itemBuilder: (context, i) =>
                    _buildClassCard(context, provider, courses[i]),
              );
            },
          ),
      ],
    );
  }

  Widget _filterChip(String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? _surface : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        boxShadow: active
            ? [const BoxShadow(color: Color(0x10000000), blurRadius: 4)]
            : null,
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? _primary : _slate500,
        ),
      ),
    );
  }

  Widget _buildClassCard(
    BuildContext context,
    AttendanceProvider provider,
    _CourseInfo course,
  ) {
    final absent = provider.selectedSlot?.classCode == course.classCode
        ? provider.countAbsent
        : 0;
    final hasAlert = absent >= 3;
    final hasWarn = absent >= 1 && absent < 3;

    return Container(
      key: ValueKey('course-card-${course.subjectCode}-${course.classCode}'),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slate200),
        boxShadow: [
          const BoxShadow(
            color: Color(0x05000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: const Color(0xFFFFF7ED).withValues(alpha: 0.4),
          onTap: () => onOpenCourse(course.representativeSlot),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: class badge + absence alert
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _orange100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        course.classCode,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _container,
                        ),
                      ),
                    ),
                    if (hasAlert)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _red100,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.report_rounded,
                              size: 12,
                              color: _red700,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$absent SV ≥3 buổi',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _red700,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (hasWarn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _amber100,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '$absent SV ≥1 buổi',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _amber800,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _emerald50,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'Ổn định',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _emerald700,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),
                Text(
                  course.subjectCode,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _slate900,
                  ),
                ),
                Text(
                  course.subjectName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: _slate500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 8),

                // Info rows
                _infoRow(
                  'Sĩ số:',
                  course.studentCount > 0
                      ? '${course.studentCount} Sinh viên'
                      : '— SV',
                ),
                const SizedBox(height: 3),
                _infoRow('Lịch học:', course.slotLabel),
                if (course.room.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  _infoRow('Phòng:', course.room),
                ],

                const Spacer(),
                // Action row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: ValueKey(
                          'open-course-${course.subjectCode}-${course.classCode}',
                        ),
                        onPressed: () =>
                            onOpenCourse(course.representativeSlot),
                        icon: const Icon(Icons.groups_rounded, size: 14),
                        label: Text(
                          'Danh sách lớp',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _slate700,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          backgroundColor: const Color(0xFFF8FAFC),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Xuất file CSV',
                      child: OutlinedButton(
                        key: ValueKey(
                          'export-course-${course.subjectCode}-${course.classCode}',
                        ),
                        onPressed: () =>
                            onExportCourse(course.representativeSlot),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _emerald700,
                          side: const BorderSide(color: _emerald200),
                          backgroundColor: _emerald50,
                          padding: const EdgeInsets.symmetric(
                            vertical: 7,
                            horizontal: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          minimumSize: const Size(0, 0),
                        ),
                        child: const Icon(Icons.description_outlined, size: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _slate500),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _slate700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── Date helpers ──
  String _monthLabel(DateTime d) {
    const months = [
      '',
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12',
    ];
    return '${months[d.month]}, ${d.year}';
  }

  String _fullDateLabel(DateTime d) {
    const days = [
      '',
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];
    return '${days[d.weekday]}, ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// Simple data model for course card
class _CourseInfo {
  final String classCode;
  final String subjectCode;
  final String subjectName;
  final String room;
  final int studentCount;
  final String slotLabel;
  final FapClassSlot representativeSlot;
  const _CourseInfo({
    required this.classCode,
    required this.subjectCode,
    required this.subjectName,
    required this.room,
    required this.studentCount,
    required this.slotLabel,
    required this.representativeSlot,
  });
}
