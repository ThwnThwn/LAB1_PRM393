import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/attendance_provider.dart';

class DeviceSecurityPanel extends StatelessWidget {
  const DeviceSecurityPanel({super.key});

  static const _ink = Color(0xFF1B2A4A);
  static const _success = Color(0xFF15803D);
  static const _warning = Color(0xFFD97706);

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final conflicts = provider.deviceConflicts;

    if (conflicts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: const Row(
          children: [
            Icon(Icons.shield_outlined, color: _success, size: 19),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Chống điểm danh hộ đang bật • Mỗi thiết bị chỉ được dùng cho một MSSV trong phiên',
                style: TextStyle(
                  color: Color(0xFF166534),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final visibleConflicts = conflicts.take(3).toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.gpp_maybe_outlined,
                    color: _warning,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${conflicts.length} cảnh báo điểm danh hộ',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Thiết bị đã thử điểm danh cho MSSV khác trong cùng phiên.',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFFDE68A)),
          ...visibleConflicts.map(
            (binding) => _buildConflictRow(context, provider, binding),
          ),
          if (conflicts.length > visibleConflicts.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Còn ${conflicts.length - visibleConflicts.length} cảnh báo khác trong nhật ký.',
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConflictRow(
    BuildContext context,
    AttendanceProvider provider,
    Map<String, dynamic> binding,
  ) {
    final bindingId = (binding['id'] as num?)?.toInt();
    final deviceCode = binding['deviceCode']?.toString() ?? '--------';
    final assignedRollNo = binding['rollNo']?.toString() ?? '---';
    final attemptedRollNo = binding['lastBlockedRollNo']?.toString() ?? '---';
    final attempts = (binding['blockedAttempts'] as num? ?? 0).toInt();
    final blockedAt = DateTime.tryParse(
      binding['lastBlockedAt']?.toString() ?? '',
    )?.toLocal();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              'TB $deviceCode',
              style: const TextStyle(
                color: _ink,
                fontFamily: 'monospace',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: Color(0xFF78350F), fontSize: 12),
                children: [
                  const TextSpan(text: 'Đã gắn '),
                  TextSpan(
                    text: assignedRollNo,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(text: ' • thử '),
                  TextSpan(
                    text: attemptedRollNo,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: ' • $attempts lần'),
                  if (blockedAt != null)
                    TextSpan(text: ' • ${_formatTime(blockedAt)}'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: bindingId == null || provider.deviceReleaseInProgress
                ? null
                : () => _confirmRelease(context, provider, bindingId),
            icon: provider.deviceReleaseInProgress
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.lock_open_rounded, size: 16),
            label: const Text('Mở khóa'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFB45309),
              side: const BorderSide(color: Color(0xFFF59E0B)),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRelease(
    BuildContext context,
    AttendanceProvider provider,
    int bindingId,
  ) async {
    final controller = TextEditingController();
    var reasonIsValid = false;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock_open_rounded, color: _warning, size: 22),
                  SizedBox(width: 10),
                  Text('Mở khóa thiết bị'),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sau khi mở khóa, điện thoại này có thể điểm danh cho một MSSV khác trong phiên hiện tại. Thao tác sẽ được lưu vào nhật ký.',
                      style: TextStyle(fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: 160,
                      onChanged: (value) {
                        final valid = value.trim().length >= 3;
                        if (valid != reasonIsValid) {
                          setDialogState(() => reasonIsValid = valid);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Lý do mở khóa',
                        hintText: 'Ví dụ: Sinh viên hết pin và mượn điện thoại',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                FilledButton.icon(
                  onPressed: reasonIsValid
                      ? () =>
                            Navigator.pop(dialogContext, controller.text.trim())
                      : null,
                  icon: const Icon(Icons.lock_open_rounded, size: 17),
                  label: const Text('Xác nhận mở khóa'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB45309),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

    if (reason == null || !context.mounted) return;
    final success = await provider.releaseDeviceBinding(bindingId, reason);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Đã mở khóa thiết bị và lưu lý do vào nhật ký.'
              : provider.lastCheckinNotification ??
                    'Không thể mở khóa thiết bị.',
        ),
        backgroundColor: success ? _success : Colors.red.shade700,
      ),
    );
  }

  static String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }
}
