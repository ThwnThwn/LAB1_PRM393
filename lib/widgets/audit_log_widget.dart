import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/attendance_provider.dart';

class AuditLogWidget extends StatelessWidget {
  const AuditLogWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final logs = provider.auditLogs;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFB),
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF36F21).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.history_rounded, color: Color(0xFFF36F21), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nhật ký phiên điểm danh',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1B2A4A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Lịch sử thay đổi trạng thái sinh viên',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: provider.serverSessionId == null
                        ? null
                        : provider.loadAuditLogs,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Làm mới'),
                  ),
                ],
              ),
            ),
            // Log List
            Expanded(
              child: provider.serverSessionId == null
                  ? _buildEmptyState('Chưa có phiên điểm danh nào được mở.', Icons.lock_clock_outlined)
                  : logs.isEmpty
                  ? _buildEmptyState('Phiên này chưa có thay đổi.', Icons.note_alt_outlined)
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final time = DateTime.tryParse(
                          log['createdAt']?.toString() ?? '',
                        )?.toLocal();
                        final isEven = index.isEven;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isEven ? Colors.white : const Color(0xFFFCFCFD),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF36F21).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.edit_note_rounded,
                                  color: Color(0xFFF36F21),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${log['action'] ?? 'UPDATE'}${(log['rollNo']?.toString().isNotEmpty ?? false) ? ' • ${log['rollNo']}' : ''}',
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${log['previousStatus'] ?? ''}${(log['previousStatus']?.toString().isNotEmpty ?? false) ? ' → ' : ''}${log['newStatus'] ?? ''}'
                                      '${(log['reason']?.toString().isNotEmpty ?? false) ? ' • ${log['reason']}' : ''}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    log['actor']?.toString() ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  if (time != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatTime(time),
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)} ${two(value.day)}/${two(value.month)}/${value.year}';
  }
}
