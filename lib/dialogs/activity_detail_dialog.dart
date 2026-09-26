import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../models/fap_class_slot.dart';

/// Material 3 dialog showing activity/class details for the FAP Attendance Desktop App,
/// modeled after the FPT Academic Portal Activity Detail page.
class ActivityDetailDialog extends StatelessWidget {
  final FapClassSlot slot;

  const ActivityDetailDialog({super.key, required this.slot});

  static const Color fptOrange = Color(0xFFF36F21);
  static const Color fapNavy = Color(0xFF1B2A4A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      backgroundColor: colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Bar
            _buildHeader(context),

            const Divider(height: 1, thickness: 1),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject Highlight Card
                    _buildSubjectBanner(context),
                    const SizedBox(height: 16),

                    // Details Card / Table
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.35,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            context: context,
                            icon: Icons.book_outlined,
                            label: 'Môn học',
                            content: SelectableText(
                              '${slot.subjectCode} - ${slot.subjectName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          _buildDivider(),
                          _buildDetailRow(
                            context: context,
                            icon: Icons.groups_outlined,
                            label: 'Nhóm sinh viên',
                            content: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: fptOrange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: fptOrange.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    slot.classCode,
                                    style: const TextStyle(
                                      color: fptOrange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildDivider(),
                          _buildDetailRow(
                            context: context,
                            icon: Icons.access_time_rounded,
                            label: 'Slot',
                            content: Text(
                              'Slot ${slot.slot} (${slot.slotTime.isNotEmpty ? slot.slotTime : FapClassSlot.getSlotTimeRange(slot.slot)})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          _buildDivider(),
                          _buildDetailRow(
                            context: context,
                            icon: Icons.calendar_today_outlined,
                            label: 'Ngày',
                            content: Text(
                              FapClassSlot.getDayName(slot.dayOfWeek),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          _buildDivider(),
                          _buildDetailRow(
                            context: context,
                            icon: Icons.meeting_room_outlined,
                            label: 'Phòng',
                            content: Row(
                              children: [
                                Text(
                                  slot.room.isNotEmpty
                                      ? slot.room
                                      : (slot.isOnline ? 'Online' : 'N/A'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                                if (slot.isOnline) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.green.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        const Text(
                                          'Online',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _buildDivider(),
                          _buildDetailRow(
                            context: context,
                            icon: Icons.person_outline,
                            label: 'Giảng viên',
                            content: Text(
                              slot.instructor.isNotEmpty
                                  ? slot.instructor
                                  : 'Chưa phân công',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          _buildDivider(),
                          _buildDetailRow(
                            context: context,
                            icon: Icons.location_city_outlined,
                            label: 'Cơ sở',
                            content: Text(
                              slot.campus.isNotEmpty ? slot.campus : 'FUHCM',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          _buildDivider(),
                          _buildDetailRow(
                            context: context,
                            icon: Icons.bookmark_outline,
                            label: 'Buổi học (Session)',
                            content: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Buổi ${slot.sessionNumber}/${slot.totalSessions}',
                                style: TextStyle(
                                  color: colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                          if (slot.meetUrl != null &&
                              slot.meetUrl!.isNotEmpty) ...[
                            _buildDivider(),
                            _buildDetailRow(
                              context: context,
                              icon: Icons.video_call_outlined,
                              label: 'Meet URL',
                              content: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      slot.meetUrl!,
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Sao chép link',
                                    icon: const Icon(Icons.copy, size: 16),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: slot.meetUrl!),
                                      );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Đã sao chép đường dẫn Meet!',
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
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
              ),
            ),

            const Divider(height: 1, thickness: 1),

            // Action Buttons Footer
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: fptOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: fptOrange,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chi tiết ca dạy',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: fapNavy,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'FPT Academic Portal (FAP)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Đóng',
            style: IconButton.styleFrom(
              hoverColor: Colors.black.withValues(alpha: 0.05),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [fapNavy, fapNavy.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: fapNavy.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: fptOrange,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              slot.subjectCode,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.subjectName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lớp: ${slot.classCode} • Buổi: ${slot.sessionNumber}/${slot.totalSessions}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Widget content,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.black.withValues(alpha: 0.05),
      indent: 16,
      endIndent: 16,
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Đóng'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text(
                'Bắt đầu điểm danh QR (10s OTP)',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: fptOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: () {
                final provider = Provider.of<AttendanceProvider>(
                  context,
                  listen: false,
                );
                provider.selectSlotAndStartAttendance(slot);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}
