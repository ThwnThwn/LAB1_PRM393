import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/student.dart';
import '../providers/attendance_provider.dart';
import '../services/fap_demo_sync_service.dart';

class FapAttendanceDemoScreen extends StatefulWidget {
  const FapAttendanceDemoScreen({super.key});

  @override
  State<FapAttendanceDemoScreen> createState() =>
      _FapAttendanceDemoScreenState();
}

class _FapAttendanceDemoScreenState extends State<FapAttendanceDemoScreen> {
  final Map<String, FapDemoMark> _marks = {};
  List<Student> _sourceRecords = [];
  bool? _sourceIsOpen;
  String _sourceLabel = 'Chưa nạp dữ liệu';
  String? _sessionKey;
  String? _syncMessage;
  DateTime? _savedAt;
  bool _isLoading = false;

  void _ensureSession(AttendanceProvider provider) {
    final session = provider.currentSession;
    final key =
        '${session.classCode}|${session.subjectCode}|${session.slot}|${session.date}';
    if (_sessionKey == key) return;
    _sessionKey = key;
    _marks
      ..clear()
      ..addEntries(
        provider.students.map(
          (student) => MapEntry(
            FapDemoSyncService.normalizeRollNo(student.rollNo),
            FapDemoMark.unmarked,
          ),
        ),
      );
    _sourceRecords = [];
    _sourceIsOpen = null;
    _sourceLabel = 'Chưa nạp dữ liệu';
    _syncMessage = null;
    _savedAt = null;
  }

  void _showMessage(String message, {bool warning = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: warning
            ? const Color(0xFFB45309)
            : const Color(0xFF166534),
      ),
    );
  }

  Future<void> _loadFromSheets(AttendanceProvider provider) async {
    if (provider.selectedSlot == null) {
      _showMessage(
        'Hãy chọn một ca học trong Lịch dạy FAP trước.',
        warning: true,
      );
      return;
    }
    if (!provider.sheetsService.isConfigured) {
      _showMessage(
        'Chưa có Web App URL. Hãy cấu hình ở mục Google Sheets.',
        warning: true,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final session = provider.currentSession;
      final result = await provider.sheetsService.fetchAttendanceFromSheet(
        classCode: session.classCode,
        subjectCode: session.subjectCode,
        slot: session.slot,
      );
      if (!mounted) return;
      setState(() {
        _sourceRecords = result.students;
        _sourceIsOpen = result.isOpen;
        _sourceLabel = result.source;
        _syncMessage = result.students.isEmpty
            ? 'Không tìm thấy bản ghi đúng lớp/môn/slot trong Google Sheet.'
            : 'Đã nạp ${result.students.length} bản ghi. Bấm “Tự động tích P/A” để đối chiếu.';
        _savedAt = null;
      });
    } catch (error) {
      _showMessage('Không thể đọc Google Sheet: $error', warning: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadCurrentSession(AttendanceProvider provider) {
    if (provider.selectedSlot == null) {
      _showMessage('Hãy chọn một ca học trước.', warning: true);
      return;
    }
    setState(() {
      _sourceRecords = provider.students
          .map(
            (student) => Student(
              rollNo: student.rollNo,
              fullName: student.fullName,
              email: student.email,
              group: student.group,
              status: student.status,
              checkinTime: student.checkinTime,
              notes: student.notes,
            ),
          )
          .toList();
      _sourceIsOpen = provider.isSessionOpen;
      _sourceLabel = 'Cache phiên hiện tại';
      _syncMessage =
          'Đã nạp ${_sourceRecords.length} bản ghi từ cache runtime.';
      _savedAt = null;
    });
  }

  void _autoFill(AttendanceProvider provider) {
    if (_sourceRecords.isEmpty) {
      _showMessage('Hãy nạp dữ liệu điểm danh trước.', warning: true);
      return;
    }
    if (_sourceIsOpen == true) {
      _showMessage(
        'Phiên vẫn đang mở. Hãy đóng phiên để tránh đánh vắng sinh viên chưa kịp check-in.',
        warning: true,
      );
      return;
    }

    final result = FapDemoSyncService.matchClosedSession(
      roster: provider.students,
      attendanceRecords: _sourceRecords,
    );
    setState(() {
      _marks
        ..clear()
        ..addAll(result.marksByRollNo);
      _syncMessage = result.unmatchedRollNos.isEmpty
          ? 'Đối chiếu xong: ${result.matchedCount}/${provider.students.length} sinh viên đã được tích P/A.'
          : 'Đã khớp ${result.matchedCount}/${provider.students.length}; còn ${result.unmatchedRollNos.length} MSSV chưa có trong nguồn.';
      _savedAt = null;
    });
  }

  Future<void> _saveDemo(AttendanceProvider provider) async {
    final pending = provider.students.where((student) {
      final key = FapDemoSyncService.normalizeRollNo(student.rollNo);
      return (_marks[key] ?? FapDemoMark.unmarked) == FapDemoMark.unmarked;
    }).length;
    if (pending > 0) {
      _showMessage(
        'Còn $pending sinh viên chưa chọn Present/Absent.',
        warning: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lưu điểm danh mô phỏng?'),
        content: const Text(
          'Thao tác này chỉ mô phỏng bước Save trên FAP để phục vụ demo, '
          'không gửi dữ liệu vào hệ thống FAP thật.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận lưu Demo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savedAt = DateTime.now());
    _showMessage('Đã lưu trạng thái trên màn hình FAP Demo.');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AttendanceProvider>();
    _ensureSession(provider);
    final roster = provider.students;
    final presentCount = _marks.values
        .where((mark) => mark == FapDemoMark.present)
        .length;
    final absentCount = _marks.values
        .where((mark) => mark == FapDemoMark.absent)
        .length;
    final pendingCount = roster.length - presentCount - absentCount;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildHeader(provider),
          const SizedBox(height: 14),
          _buildSessionBar(
            provider,
            presentCount: presentCount,
            absentCount: absentCount,
            pendingCount: pendingCount,
          ),
          const SizedBox(height: 14),
          if (_syncMessage != null) ...[
            _buildSyncBanner(),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: roster.isEmpty
                ? _buildEmptyState(provider)
                : _buildAttendanceTable(provider),
          ),
          const SizedBox(height: 14),
          _buildFooter(provider),
        ],
      ),
    );
  }

  Widget _buildHeader(AttendanceProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF36F21),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text(
              'FPT',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FAP Attendance — Demo',
                  style: TextStyle(
                    color: Color(0xFF1B2A4A),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Mô phỏng màn hình giảng viên, không kết nối FAP thật',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ],
            ),
          ),
          _sourceChip(),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _isLoading ? null : () => _loadFromSheets(provider),
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_rounded, size: 18),
            label: const Text('Nạp Google Sheet'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1B2A4A),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _loadCurrentSession(provider),
            icon: const Icon(Icons.storage_rounded, size: 18),
            label: const Text('Dùng dữ liệu phiên'),
          ),
        ],
      ),
    );
  }

  Widget _sourceChip() {
    final color = _sourceIsOpen == true
        ? const Color(0xFFD97706)
        : _sourceRecords.isNotEmpty
        ? const Color(0xFF16A34A)
        : const Color(0xFF64748B);
    final label = _sourceIsOpen == true
        ? 'Nguồn đang mở'
        : _sourceIsOpen == false
        ? 'Nguồn đã đóng'
        : _sourceLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSessionBar(
    AttendanceProvider provider, {
    required int presentCount,
    required int absentCount,
    required int pendingCount,
  }) {
    final session = provider.currentSession;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.menu_book_rounded, color: Color(0xFFF36F21)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              provider.selectedSlot == null
                  ? 'Chưa chọn ca học'
                  : '${session.subjectCode} • ${session.classCode} • Slot ${session.slot}',
              style: const TextStyle(
                color: Color(0xFF1B2A4A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _countPill('Present', presentCount, const Color(0xFF16A34A)),
          const SizedBox(width: 8),
          _countPill('Absent', absentCount, const Color(0xFFDC2626)),
          const SizedBox(width: 8),
          _countPill('Chưa chọn', pendingCount, const Color(0xFF64748B)),
        ],
      ),
    );
  }

  Widget _countPill(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSyncBanner() {
    final warning =
        _sourceIsOpen == true ||
        (_syncMessage?.contains('Không') ?? false) ||
        (_syncMessage?.contains('còn') ?? false);
    final color = warning ? const Color(0xFFD97706) : const Color(0xFF167A4A);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            warning ? Icons.info_outline_rounded : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(_syncMessage!, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AttendanceProvider provider) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.fact_check_outlined,
            size: 54,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(height: 14),
          Text(
            provider.selectedSlot == null
                ? 'Chọn một ca trong “Lịch dạy FAP” để bắt đầu.'
                : 'Ca học này chưa có danh sách sinh viên.',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTable(AttendanceProvider provider) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              dividerThickness: 0.6,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('MSSV')),
                DataColumn(label: Text('Họ và tên')),
                DataColumn(label: Text('Present')),
                DataColumn(label: Text('Absent')),
                DataColumn(label: Text('Dữ liệu nguồn')),
                DataColumn(label: Text('Check-in')),
              ],
              rows: [
                for (var index = 0; index < provider.students.length; index++)
                  _studentRow(provider.students[index], index),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataRow _studentRow(Student student, int index) {
    final key = FapDemoSyncService.normalizeRollNo(student.rollNo);
    final mark = _marks[key] ?? FapDemoMark.unmarked;
    final source = _sourceRecords.cast<Student?>().firstWhere(
      (item) =>
          item != null &&
          FapDemoSyncService.normalizeRollNo(item.rollNo) == key,
      orElse: () => null,
    );
    return DataRow(
      cells: [
        DataCell(Text('${index + 1}')),
        DataCell(
          Text(
            student.rollNo,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        DataCell(SizedBox(width: 240, child: Text(student.fullName))),
        DataCell(
          _markChoice(
            key,
            FapDemoMark.present,
            mark == FapDemoMark.present,
            const Color(0xFF16A34A),
          ),
        ),
        DataCell(
          _markChoice(
            key,
            FapDemoMark.absent,
            mark == FapDemoMark.absent,
            const Color(0xFFDC2626),
          ),
        ),
        DataCell(_sourceStatus(source)),
        DataCell(Text(_formatTime(source?.checkinTime))),
      ],
    );
  }

  Widget _markChoice(
    String rollNo,
    FapDemoMark value,
    bool selected,
    Color color,
  ) {
    return Semantics(
      button: true,
      selected: selected,
      label: value == FapDemoMark.present ? 'Present' : 'Absent',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          _marks[rollNo] = value;
          _savedAt = null;
        }),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? color : const Color(0xFF94A3B8),
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _sourceStatus(Student? student) {
    if (student == null) {
      return const Text(
        'Không khớp',
        style: TextStyle(color: Color(0xFFD97706)),
      );
    }
    final color = switch (student.status) {
      AttendanceStatus.present => const Color(0xFF16A34A),
      AttendanceStatus.late => const Color(0xFFD97706),
      AttendanceStatus.absent => const Color(0xFFDC2626),
      AttendanceStatus.notChecked => const Color(0xFF64748B),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        student.status.toLabel(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }

  Widget _buildFooter(AttendanceProvider provider) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _savedAt == null
                ? 'Quy tắc: PRESENT/LATE → Present; ABSENT/NOT CHECKED → Absent sau khi đóng phiên.'
                : 'Đã lưu Demo lúc ${_formatTime(_savedAt)} • Không gửi sang FAP thật.',
            style: TextStyle(
              color: _savedAt == null
                  ? const Color(0xFF64748B)
                  : const Color(0xFF16A34A),
              fontSize: 12,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            for (final key in _marks.keys.toList()) {
              _marks[key] = FapDemoMark.unmarked;
            }
            _savedAt = null;
          }),
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('Bỏ chọn'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _autoFill(provider),
          icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
          label: const Text('Tự động tích P/A'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF36F21),
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _saveDemo(provider),
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Lưu điểm danh (Demo)'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF167A4A),
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
