import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../providers/attendance_provider.dart';
import '../models/student.dart';

class RosterTableWidget extends StatelessWidget {
  const RosterTableWidget({super.key});

  static const double _statusColumnWidth = 146;

  void _handlePickCsvFile(
    BuildContext context,
    AttendanceProvider provider,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String content = '';
        if (file.bytes != null) {
          content = utf8.decode(file.bytes!);
        }
        if (content.isEmpty) {
          throw const FormatException('File CSV không có dữ liệu.');
        }
        if (context.mounted) {
          final importResult = await provider.importCsvContent(content);
          if (!context.mounted) return;
          final warningParts = <String>[
            if (importResult.skippedRows > 0)
              '${importResult.skippedRows} dòng thiếu dữ liệu',
            if (importResult.duplicateRows > 0)
              '${importResult.duplicateRows} dòng trùng',
          ];
          final warning = warningParts.isEmpty
              ? ''
              : ' Bỏ qua ${warningParts.join(' và ')}.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đã lưu ${importResult.importedCount} sinh viên vào database.$warning',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is FormatException ? e.message : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể import CSV: $message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final students = provider.filteredStudents;

    return Column(
      children: [
        if (provider.serverSessionId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 17,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Có thể sửa nhiều dòng trước khi mở phiên QR. Bấm Lưu để ghi một lần lên Google Sheets.',
                    style: TextStyle(color: Color(0xFF334155), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        // Controls Row — Modern Search & Filters
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              // Search Field
              Expanded(
                child: TextField(
                  onChanged: (val) => provider.setSearchQuery(val),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm MSSV, Họ tên hoặc Email...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFFF36F21),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Filter Chips with Count Badges
              _buildFilterChip(
                'Tất cả',
                provider.filterStatus == null,
                null,
                '${provider.countTotal}',
                () => provider.setFilterStatus(null),
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                'Có mặt',
                provider.filterStatus == AttendanceStatus.present,
                const Color(0xFF22C55E),
                '${provider.countPresent}',
                () => provider.setFilterStatus(AttendanceStatus.present),
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                'Vắng',
                provider.filterStatus == AttendanceStatus.absent,
                const Color(0xFFEF4444),
                '${provider.countAbsent}',
                () => provider.setFilterStatus(AttendanceStatus.absent),
              ),
              const SizedBox(width: 14),

              // Import CSV File Button
              ElevatedButton.icon(
                onPressed: () => _handlePickCsvFile(context, provider),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('Import CSV'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B2A4A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Student Data Table
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            clipBehavior: Clip.antiAlias,
            child: students.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_search_outlined,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          provider.loadingSelectedSession
                              ? 'Đang tải phiên và danh sách từ Google Sheets...'
                              : provider.lastCheckinNotification?.startsWith(
                                      'Không thể đồng bộ phiên',
                                    ) ==
                                    true
                              ? 'Không tải được dữ liệu từ Google Sheets. Hãy kiểm tra kết nối rồi chọn lại ca.'
                              : provider.students.isEmpty
                              ? 'Google Sheets chưa có danh sách sinh viên cho lớp này.'
                              : 'Không tìm thấy sinh viên phù hợp.',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Sticky Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFB),
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 48), // Avatar space
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 100,
                              child: Text('MSSV', style: _headerStyle),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('Họ và tên', style: _headerStyle),
                            ),
                            SizedBox(
                              width: 200,
                              child: Text('Email', style: _headerStyle),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text('Check-in', style: _headerStyle),
                            ),
                            SizedBox(
                              width: _statusColumnWidth,
                              child: Text('Trạng thái', style: _headerStyle),
                            ),
                          ],
                        ),
                      ),
                      // Scrollable rows
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: students.length,
                          itemBuilder: (context, index) {
                            final student = students[index];
                            final isEven = index.isEven;
                            return _buildStudentRow(
                              context,
                              student,
                              isEven,
                              provider,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (provider.hasUnsavedAttendanceChanges)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF5C09C)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: Color(0xFFC45A16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${provider.unsavedAttendanceCount} dòng chưa lưu lên Google Sheets',
                    style: const TextStyle(
                      color: Color(0xFF7C3E15),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: provider.savingAttendanceDraft
                      ? null
                      : provider.discardAttendanceDraft,
                  child: const Text('Hủy thay đổi'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: provider.savingAttendanceDraft
                      ? null
                      : () => provider.saveAttendanceDraft(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF36F21),
                    foregroundColor: Colors.white,
                  ),
                  icon: provider.savingAttendanceDraft
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(
                    provider.savingAttendanceDraft
                        ? 'Đang lưu…'
                        : 'Lưu ${provider.unsavedAttendanceCount} dòng',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static final TextStyle _headerStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Colors.grey.shade500,
    letterSpacing: 0.5,
  );

  Widget _buildFilterChip(
    String label,
    bool isSelected,
    Color? color,
    String count,
    VoidCallback onTap,
  ) {
    final chipColor = color ?? Colors.grey.shade600;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? chipColor.withValues(alpha: 0.3)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? chipColor : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? chipColor.withValues(alpha: 0.15)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? chipColor : Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentRow(
    BuildContext context,
    Student student,
    bool isEven,
    AttendanceProvider provider,
  ) {
    final statusColor = _getStatusColor(student.status);
    final isDrafted = provider.isAttendanceDrafted(student.rollNo);
    final isConflicted = provider.isAttendanceDraftConflicted(student.rollNo);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFFCFCFD),
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // Status avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getStatusIcon(student.status),
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // MSSV
          SizedBox(
            width: 100,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    student.rollNo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isDrafted)
                  Tooltip(
                    message: isConflicted
                        ? 'Dòng này đã thay đổi trên Sheet; hãy kiểm tra trước khi lưu'
                        : 'Thay đổi chưa lưu',
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        isConflicted
                            ? Icons.warning_amber_rounded
                            : Icons.circle,
                        size: isConflicted ? 15 : 7,
                        color: isConflicted
                            ? const Color(0xFFDC2626)
                            : const Color(0xFFF36F21),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Full name
          Expanded(
            child: Text(
              student.fullName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Email
          SizedBox(
            width: 200,
            child: Text(
              student.email,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Check-in time
          SizedBox(
            width: 100,
            child: student.checkinTime != null
                ? Text(
                    _formatTime(student.checkinTime!),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  )
                : Text('—', style: TextStyle(color: Colors.grey.shade300)),
          ),
          // Status dropdown as pill badge
          SizedBox(
            width: _statusColumnWidth,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AttendanceStatus>(
                value: student.status,
                isDense: true,
                isExpanded: true,
                borderRadius: BorderRadius.circular(10),
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
                selectedItemBuilder: (context) {
                  return AttendanceStatus.values.map((st) {
                    final c = _getStatusColor(st);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              st.toLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c,
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
                items: AttendanceStatus.values.map((st) {
                  return DropdownMenuItem(
                    value: st,
                    child: Text(
                      st.toLabel(),
                      style: TextStyle(
                        color: _getStatusColor(st),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  );
                }).toList(),
                onChanged:
                    provider.loadingSelectedSession ||
                        provider.savingAttendanceDraft ||
                        provider.isStatusUpdatePending(student.rollNo)
                    ? null
                    : (newStatus) {
                        if (newStatus != null) {
                          provider.toggleStudentStatus(student, newStatus);
                        }
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return const Color(0xFF22C55E);
      case AttendanceStatus.absent:
        return const Color(0xFFEF4444);
    }
  }

  IconData _getStatusIcon(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Icons.check_circle_rounded;
      case AttendanceStatus.absent:
        return Icons.cancel_rounded;
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
