import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';

class StudentCheckinScreen extends StatefulWidget {
  const StudentCheckinScreen({super.key});

  @override
  State<StudentCheckinScreen> createState() => _StudentCheckinScreenState();
}

class _StudentCheckinScreenState extends State<StudentCheckinScreen> {
  final _emailController = TextEditingController(
    text: 'minhnbse182173@fpt.edu.vn',
  );
  final _otpController = TextEditingController();
  Map<String, dynamic>? _checkinResult;

  void _submitAttendance() {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (email.isEmpty || otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập đầy đủ email và mã OTP!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final res = provider.checkinStudent(email: email, otp: otp);
    setState(() {
      _checkinResult = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);
    final session = provider.currentSession;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Logo
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF36F21).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.how_to_reg,
                    size: 44,
                    color: Color(0xFFF36F21),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'CỔNG ĐIỂM DANH SINH VIÊN',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1B2A4A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lớp: ${session.classCode} | Môn: ${session.subjectCode} | Buổi ${session.sessionNumber}/${session.totalSessions} | Slot ${session.slot}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Form Inputs
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email của sinh viên',
                    hintText: 'ví dụ: sinhvien@gmail.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Mã OTP (6 chữ số trên màn hình)',
                    hintText: '******',
                    prefixIcon: const Icon(Icons.lock_clock_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 20),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submitAttendance,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF36F21),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'XÁC NHẬN ĐIỂM DANH',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // Check-in Result Alert Card
                if (_checkinResult != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _checkinResult!['success']
                          ? Colors.green[50]
                          : Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _checkinResult!['success']
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _checkinResult!['success']
                              ? Icons.check_circle
                              : Icons.error_outline,
                          color: _checkinResult!['success']
                              ? Colors.green[700]
                              : Colors.red[700],
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _checkinResult!['message'],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _checkinResult!['success']
                                ? Colors.green[900]
                                : Colors.red[900],
                          ),
                        ),
                        if (_checkinResult!['student'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Thời gian: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
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
}
