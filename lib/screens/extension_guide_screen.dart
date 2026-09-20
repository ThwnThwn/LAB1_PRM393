import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';

class ExtensionGuideScreen extends StatelessWidget {
  const ExtensionGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const fptOrange = Color(0xFFF36F21);
    const deepBlue = Color(0xFF1B2A4A);
    final provider = Provider.of<AttendanceProvider>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Banner — with subtle pattern overlay
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3259), Color(0xFF2E4374), Color(0xFF1B2A4A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: deepBlue.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [fptOrange, Color(0xFFFF8A4C)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: fptOrange.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.extension_rounded, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'CHROME & EDGE EXTENSION',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'FAP Auto Attendance Assistant',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tiện ích mở rộng tự động tích điểm danh sinh viên trên trang web FAP (fap.fpt.edu.vn) cho giảng viên.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Installation Steps Card — Stepper Style
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
                      'Hướng dẫn cài đặt trong 3 bước',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: deepBlue,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildStepItem(
                      number: '1',
                      title: 'Mở trang quản lý tiện ích trình duyệt',
                      description: 'Trên Chrome hoặc Edge, mở tab mới và truy cập: chrome://extensions/ rồi gạt bật "Developer mode" (Chế độ cho nhà phát triển) ở góc phải.',
                      copyText: 'chrome://extensions/',
                      context: context,
                      isLast: false,
                    ),
                    _buildStepItem(
                      number: '2',
                      title: 'Tải tiện ích đã giải nén (Load unpacked)',
                      description: 'Nhấn nút "Load unpacked" (Tải tiện ích đã giải nén) và chọn thư mục mã nguồn extension bên dưới:',
                      copyText: r'C:\Users\minhn\.gemini\antigravity\scratch\fap_attendance_app\extension',
                      context: context,
                      isLast: false,
                    ),
                    _buildStepItem(
                      number: '3',
                      title: 'Truy cập FAP và điểm danh tự động 1-Click',
                      description: 'Mở trang điểm danh lớp học trên https://fap.fpt.edu.vn/ → Widget trợ lý sẽ tự động xuất hiện ở góc dưới màn hình. Bấm "Tự động tích điểm danh" để hệ thống tự động tick P / A cho sinh viên!',
                      copyText: 'https://fap.fpt.edu.vn/',
                      context: context,
                      isLast: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Live Simulation & Test Card
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mô phỏng dữ liệu đồng bộ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: deepBlue,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Dữ liệu ca dạy hiện tại được Extension đọc để tích điểm danh',
                                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Color(0xFF2E7D32),
                                content: Text('⚡ Dữ liệu điểm danh đã sẵn sàng cho Extension trên FAP!'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.sync_rounded, size: 18),
                          label: const Text('Kiểm tra kết nối'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: fptOrange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Lớp hiện tại: ${provider.currentSession.classCode} (${provider.currentSession.subjectCode})',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Tổng SV: ${provider.countTotal}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF3B82F6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildMiniStat('Có mặt (P)', '${provider.countPresent}', const Color(0xFF22C55E)),
                              const SizedBox(width: 10),
                              _buildMiniStat('Vắng (A)', '${provider.countAbsent}', const Color(0xFFEF4444)),
                              const SizedBox(width: 10),
                              _buildMiniStat('Chưa điểm danh', '${provider.countNotChecked}', const Color(0xFF9CA3AF)),
                            ],
                          ),
                        ],
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

  Widget _buildMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ),
            Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem({
    required String number,
    required String title,
    required String description,
    required String copyText,
    required BuildContext context,
    required bool isLast,
  }) {
    const fptOrange = Color(0xFFF36F21);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number + connecting line
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [fptOrange, Color(0xFFFF8A4C)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: fptOrange.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.grey.shade200,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: Color(0xFF1B2A4A)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            copyText,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Color(0xFF1B2A4A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: copyText));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đã sao chép vào bộ nhớ tạm!')),
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: fptOrange.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.copy_rounded, size: 14, color: fptOrange),
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
        ],
      ),
    );
  }
}
