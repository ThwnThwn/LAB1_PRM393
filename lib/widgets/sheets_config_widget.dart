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

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    _urlController.text = provider.sheetsService.webAppUrl ?? '';
  }

  @override

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final isConfigured = provider.sheetsService.isConfigured;

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
                    colors: isConfigured
                        ? [const Color(0xFFF0FDF4), const Color(0xFFECFDF5)]
                        : [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isConfigured
                        ? const Color(0xFF22C55E).withValues(alpha: 0.3)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isConfigured
                            ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isConfigured ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                        color: isConfigured ? const Color(0xFF16A34A) : const Color(0xFFD97706),
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
                                isConfigured
                                    ? 'Đã kết nối với Google Sheets!'
                                    : 'Chế độ Nội bộ (Local DB Mode)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: isConfigured
                                      ? const Color(0xFF166534)
                                      : const Color(0xFF92400E),
                                ),
                              ),
                              if (isConfigured) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF22C55E).withValues(alpha: 0.4),
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
                            isConfigured
                                ? 'Mọi lượt điểm danh sẽ được đồng bộ trực tiếp lên Google Sheet.'
                                : 'Dữ liệu lưu trong bộ nhớ ứng dụng. Nhập URL bên dưới để kết nối.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isConfigured
                                  ? const Color(0xFF166534).withValues(alpha: 0.7)
                                  : const Color(0xFF92400E).withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isConfigured)
                      ElevatedButton.icon(
                        onPressed: () => provider.syncWithGoogleSheets(),
                        icon: const Icon(Icons.sync, size: 18),
                        label: const Text('Đồng bộ ngay'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                        ),
                      ),
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
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1B2A4A)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Dán đường dẫn Web App URL sau khi deploy Google Apps Script:',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              hintText: 'https://script.google.com/macros/s/.../exec',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        ElevatedButton(
                          onPressed: () {
                            provider.setGoogleSheetsUrl(_urlController.text.trim());
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đã cập nhật Google Sheets Web App URL!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF36F21),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Lưu cấu hình'),
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
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1B2A4A)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: GoogleSheetsService.sampleAppsScriptCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đã sao chép mã Apps Script vào bộ nhớ tạm!'),
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
                        'Hướng dẫn thiết lập 3 bước:\n'
                        '1. Mở file Google Sheets → chọn Extensions → Apps Script.\n'
                        '2. Xóa toàn bộ code cũ, dán đoạn mã bên dưới vào và lưu lại.\n'
                        '3. Bấm Deploy → New deployment → Web app → Execute as: Me → Anyone → Deploy & Copy URL.',
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
