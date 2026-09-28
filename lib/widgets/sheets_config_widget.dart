import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../services/google_sheets_service.dart';

class SheetsConfigWidget extends StatefulWidget {
  const SheetsConfigWidget({super.key});

  @override
  State<SheetsConfigWidget> createState() => _SheetsConfigWidgetState();
}

class _SheetsConfigWidgetState extends State<SheetsConfigWidget> {
  final _urlController = TextEditingController();
  bool _loadedConfiguration = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = Provider.of<AttendanceProvider>(context, listen: false);
      await provider.loadGoogleSheetsConfiguration(verify: true);
      if (!mounted) return;
      _urlController.text = provider.sheetsService.webAppUrl ?? '';
      setState(() => _loadedConfiguration = true);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndSeed(AttendanceProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tạo dữ liệu demo?'),
        content: const Text(
          'Ứng dụng sẽ tạo một roster chung gồm 35 sinh viên cho 4 lớp '
          '(SE1917–SE1920), 7 ca học theo lịch tuần 21/09–27/09/2026, '
          '2 phiên lịch sử và một sinh viên vắng 4/20 buổi để thử cảnh báo. '
          'Tổng cộng 315 bản ghi điểm danh. Các dòng demo cũ và roster của 4 lớp này '
          'sẽ được thay thế; dữ liệu khác trong Sheet vẫn được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Tạo dữ liệu'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final success = await provider.seedGoogleSheetsDemo();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          provider.sheetsConfigurationMessage ??
              (success
                  ? 'Đã tạo dữ liệu demo trên Google Sheets.'
                  : 'Không thể tạo dữ liệu demo.'),
        ),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final isConfigured = provider.sheetsService.isConfigured;
    final isReady = isConfigured && provider.sheetsReachable;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection Status Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isReady
                        ? [const Color(0xFFF0FDF4), const Color(0xFFECFDF5)]
                        : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isReady
                        ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isReady
                            ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isReady
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded,
                        color: isReady
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFD97706),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isReady
                                    ? 'Google Sheets đang là database chính'
                                    : 'Google Sheets chưa sẵn sàng',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: isReady
                                      ? const Color(0xFF166534)
                                      : const Color(0xFF92400E),
                                ),
                              ),
                              if (isReady) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF22C55E,
                                        ).withValues(alpha: 0.4),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isReady
                                ? 'Roster, phiên, điểm danh, thiết bị và audit log đều được đọc và ghi trực tiếp trên Sheet.'
                                : (provider.sheetsConfigurationMessage ??
                                      'Hãy deploy Apps Script và lưu Web App URL để mở khóa chức năng điểm danh.'),
                            style: TextStyle(
                              fontSize: 13,
                              color: isReady
                                  ? const Color(
                                      0xFF166534,
                                    ).withValues(alpha: 0.7)
                                  : const Color(
                                      0xFF92400E,
                                    ).withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isReady) ...[
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FilledButton.icon(
                            onPressed: provider.demoSeedInProgress
                                ? null
                                : () => _confirmAndSeed(provider),
                            icon: provider.demoSeedInProgress
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              provider.demoSeedInProgress
                                  ? 'Đang tạo...'
                                  : 'Tạo dữ liệu demo',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: provider.serverSessionId == null
                                ? null
                                : () => provider.syncWithGoogleSheets(),
                            icon: const Icon(Icons.sync, size: 17),
                            label: const Text('Đồng bộ phiên hiện tại'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Google Apps Script Web App URL Input
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cấu hình Web App URL của Google Sheets',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B2A4A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Dán đường dẫn Web App URL sau khi deploy Google Apps Script:',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              hintText:
                                  'https://script.google.com/macros/s/.../exec',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        ElevatedButton(
                          onPressed: provider.sheetsConfigurationInProgress
                              ? null
                              : () async {
                                  final success = await provider
                                      .setGoogleSheetsUrl(
                                        _urlController.text.trim(),
                                      );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        provider.sheetsConfigurationMessage ??
                                            (success
                                                ? 'Đã cấu hình Google Sheets.'
                                                : 'Không thể cấu hình Google Sheets.'),
                                      ),
                                      backgroundColor: success
                                          ? Colors.green
                                          : Colors.red.shade700,
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF36F21),
                            foregroundColor: Colors.white,
                          ),
                          child: provider.sheetsConfigurationInProgress
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _loadedConfiguration
                                      ? 'Kiểm tra & lưu'
                                      : 'Đang tải...',
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Instructions & Code Snippet
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Mã nguồn Google Apps Script',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1B2A4A),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: GoogleSheetsService.sampleAppsScriptCode,
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã sao chép mã Apps Script vào bộ nhớ tạm!',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Sao chép Code'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Steps
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Text(
                        'Hướng dẫn thiết lập & seed demo:\n'
                        '1. Mở file Google Sheets → chọn Extensions → Apps Script.\n'
                        '2. Xóa toàn bộ code cũ, dán đoạn mã bên dưới vào và lưu lại.\n'
                        '3. Bấm Deploy → New deployment → Web app → Execute as: Me → Anyone → Deploy & Copy URL.\n'
                        '4. Dán URL, bấm Kiểm tra & lưu, sau đó bấm Tạo dữ liệu demo ở khung trạng thái.',
                        style: TextStyle(fontSize: 13, height: 1.6),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Code block with syntax-like styling
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          GoogleSheetsService.sampleAppsScriptCode,
                          style: const TextStyle(
                            color: Color(0xFFCDD6F4),
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
