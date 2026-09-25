import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/attendance_provider.dart';
import '../models/fap_class_slot.dart';

/// Material 3 Dialog for adding a new class/slot to the lecturer's timetable.
/// Enforces inserting students via CSV, XLSX or Google Sheets as required.
class AddClassDialog extends StatefulWidget {
  const AddClassDialog({super.key});

  /// Static helper to display the dialog easily from any screen
  static Future<FapClassSlot?> show(BuildContext context) {
    return showDialog<FapClassSlot>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddClassDialog(),
    );
  }

  @override
  State<AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends State<AddClassDialog> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for text fields
  final _subjectCodeController = TextEditingController();
  final _subjectNameController = TextEditingController();
  final _classCodeController = TextEditingController();
  final _roomController = TextEditingController();
  final _instructorController = TextEditingController();
  final _googleSheetsUrlController = TextEditingController();

  // State variables
  int _selectedSlot = 1;
  int _selectedDayOfWeek = 1; // 1 = Thứ 2, ..., 7 = CN
  bool _isOnline = false;

  // Import mode: 0 = CSV/XLSX file, 1 = Google Sheets DB
  int _importMethodIndex = 0;

  // Import file & sheet state
  String? _pickedFileName;
  int? _importedStudentCount;
  Uint8List? _cachedStudentFileBytes;
  String? _cachedStudentFileName;
  bool _isLoading = false;

  @override
  void dispose() {
    _subjectCodeController.dispose();
    _subjectNameController.dispose();
    _classCodeController.dispose();
    _roomController.dispose();
    _instructorController.dispose();
    _googleSheetsUrlController.dispose();
    super.dispose();
  }

  /// Pick a CSV or XLSX file and validate its student roster.
  Future<void> _pickAndImportFile() async {
    setState(() => _isLoading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final file = result.files.single;
      if (file.bytes == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể đọc dữ liệu file. Vui lòng thử lại.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final classCode = _classCodeController.text.trim();
      if (!mounted) return;
      final provider = Provider.of<AttendanceProvider>(context, listen: false);

      final importResult = provider.parseStudentFile(
        file.bytes!,
        file.name,
        classCode,
      );
      _cachedStudentFileBytes = file.bytes;
      _cachedStudentFileName = file.name;
      _pickedFileName = file.name;
      setState(() {
        _importedStudentCount = importResult.importedCount;
        _isLoading = false;
      });

      final warningParts = <String>[
        if (importResult.skippedRows > 0)
          '${importResult.skippedRows} dòng thiếu dữ liệu',
        if (importResult.duplicateRows > 0)
          '${importResult.duplicateRows} dòng trùng',
      ];
      final warning = warningParts.isEmpty
          ? ''
          : ' Bỏ qua ${warningParts.join(' và ')}.';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Đã import "${file.name}" (${importResult.importedCount} sinh viên).$warning',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final message = e is FormatException ? e.message : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red[800],
            content: Text('Không thể import danh sách sinh viên: $message'),
          ),
        );
      }
    }
  }

  /// Import students directly from Google Sheets URL
  Future<void> _importFromGoogleSheets() async {
    final sheetUrl = _googleSheetsUrlController.text.trim();
    final classCode = _classCodeController.text.trim().toUpperCase();

    if (sheetUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vui lòng nhập đường dẫn Google Sheets hoặc Web App URL!',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    final count = await provider.importStudentsFromGoogleSheets(
      classCode.isNotEmpty ? classCode : 'SE1801',
      sheetUrl,
    );

    setState(() {
      _isLoading = false;
      if (count > 0) {
        _importedStudentCount = count;
        _cachedStudentFileBytes = null;
        _cachedStudentFileName = null;
        _pickedFileName = 'Google Sheets ($count sinh viên)';
      }
    });

    if (mounted) {
      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Text(
              'Đã nạp thành công $count sinh viên từ Google Sheets!',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              'Không thể tải sinh viên từ Google Sheet. Vui lòng kiểm tra quyền chia sẻ hoặc Web App URL.',
            ),
          ),
        );
      }
    }
  }

  /// Handle Save Action
  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Strict validation: Lecturer must insert students via file or Google Sheets
    if (_importedStudentCount == null || _importedStudentCount! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFC53030),
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bắt buộc: Giảng viên phải nạp danh sách học viên bằng file CSV, XLSX hoặc Google Sheets!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    final subjectCode = _subjectCodeController.text.trim().toUpperCase();
    final subjectName = _subjectNameController.text.trim();
    final classCode = _classCodeController.text.trim().toUpperCase();
    final room = _roomController.text.trim();
    final instructor = _instructorController.text.trim();

    // Import the selected local roster after all class fields are validated.
    if (_cachedStudentFileBytes != null && _cachedStudentFileName != null) {
      setState(() => _isLoading = true);
      try {
        await provider.importStudentFileForClass(
          classCode,
          _cachedStudentFileBytes!,
          _cachedStudentFileName!,
        );
      } catch (error) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red[800],
              content: Text('Không thể lưu danh sách vào database: $error'),
            ),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final newSlot = FapClassSlot(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      subjectCode: subjectCode,
      subjectName: subjectName,
      classCode: classCode,
      slot: _selectedSlot,
      dayOfWeek: _selectedDayOfWeek,
      room: room.isNotEmpty ? room : (_isOnline ? 'Online' : 'NVH TBA'),
      slotTime: FapClassSlot.getSlotTimeRange(_selectedSlot),
      sessionNumber: 1,
      instructor: instructor.isNotEmpty ? instructor : 'Giảng viên',
      campus: 'FUHCM',
      isOnline: _isOnline,
    );

    provider.addClassSlot(newSlot);
    Navigator.of(context).pop(newSlot);
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    String? hintText,
    IconData? prefixIcon,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon != null
          ? Icon(
              prefixIcon,
              size: 20,
              color: const Color(0xFF1B2A4A).withValues(alpha: 0.7),
            )
          : null,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.35,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFF36F21), width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    const fptOrange = Color(0xFFF36F21);
    const deepBlue = Color(0xFF1B2A4A);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dialog Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: fptOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_business_rounded,
                      color: fptOrange,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thêm lớp / ca dạy mới',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: deepBlue,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Thiết lập thông tin môn học và import danh sách sinh viên (CSV / XLSX / Google Sheets)',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Đóng',
                    splashRadius: 20,
                  ),
                ],
              ),
            ),

            // Dialog Scrollable Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Form Section 1: Thông tin môn học & lớp
                      const Text(
                        '1. Thông tin môn & lớp học',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: deepBlue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Row 1: Mã môn học & Tên môn học
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _subjectCodeController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: _buildInputDecoration(
                                labelText: 'Mã môn học *',
                                hintText: 'VD: PRN231, SWP391',
                                prefixIcon: Icons.bookmark_border_rounded,
                              ),
                              validator: (val) =>
                                  (val == null || val.trim().isEmpty)
                                  ? 'Vui lòng nhập mã môn học'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _subjectNameController,
                              decoration: _buildInputDecoration(
                                labelText: 'Tên môn học *',
                                hintText:
                                    'VD: Building Cross-Platform Back-End...',
                                prefixIcon: Icons.menu_book_rounded,
                              ),
                              validator: (val) =>
                                  (val == null || val.trim().isEmpty)
                                  ? 'Vui lòng nhập tên môn học'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Row 2: Mã lớp / Nhóm SV & Phòng học
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _classCodeController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: _buildInputDecoration(
                                labelText: 'Mã lớp / Nhóm SV *',
                                hintText: 'VD: SE1917, IA1802',
                                prefixIcon: Icons.groups_outlined,
                              ),
                              validator: (val) =>
                                  (val == null || val.trim().isEmpty)
                                  ? 'Vui lòng nhập mã lớp / nhóm SV'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _roomController,
                              decoration: _buildInputDecoration(
                                labelText: 'Phòng học',
                                hintText: 'VD: NVH 602, Alpha 305',
                                prefixIcon: Icons.meeting_room_outlined,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Form Section 2: Thời khóa biểu & Giảng viên
                      const Text(
                        '2. Thời khóa biểu & Giảng viên',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: deepBlue,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Row 3: Slot & Thứ (Day of Week)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Slot Dropdown (1-6)
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedSlot,
                              decoration: _buildInputDecoration(
                                labelText: 'Slot học *',
                                prefixIcon: Icons.access_time_rounded,
                              ),
                              items: List.generate(6, (index) {
                                final slotNum = index + 1;
                                return DropdownMenuItem<int>(
                                  value: slotNum,
                                  child: Text(
                                    'Slot $slotNum (${FapClassSlot.getSlotTimeRange(slotNum)})',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedSlot = val);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Day of Week Dropdown (1-7)
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedDayOfWeek,
                              decoration: _buildInputDecoration(
                                labelText: 'Thứ (Day of Week) *',
                                prefixIcon: Icons.calendar_today_rounded,
                              ),
                              items: List.generate(7, (index) {
                                final day = index + 1;
                                return DropdownMenuItem<int>(
                                  value: day,
                                  child: Text(
                                    '${FapClassSlot.getDayName(day)} (${FapClassSlot.getDayShortName(day)})',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedDayOfWeek = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Row 4: Giảng viên & Online Switch
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _instructorController,
                              decoration: _buildInputDecoration(
                                labelText: 'Giảng viên phụ trách',
                                hintText: 'VD: PhuongLHK, SonNT5',
                                prefixIcon: Icons.person_outline_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Online Switch Toggle Box
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _isOnline
                                            ? Icons.videocam_rounded
                                            : Icons.videocam_off_outlined,
                                        color: _isOnline
                                            ? fptOrange
                                            : Colors.grey[600],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Học Online',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: deepBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Switch(
                                    value: _isOnline,
                                    activeThumbColor: fptOrange,
                                    onChanged: (val) {
                                      setState(() => _isOnline = val);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Form Section 3: Bắt buộc Insert học viên
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '3. Nạp danh sách sinh viên (Bắt buộc)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: deepBlue,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  _importedStudentCount != null &&
                                      _importedStudentCount! > 0
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _importedStudentCount != null &&
                                      _importedStudentCount! > 0
                                  ? 'Đã nạp: $_importedStudentCount SV'
                                  : 'Chưa có SV',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color:
                                    _importedStudentCount != null &&
                                        _importedStudentCount! > 0
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Method Selector: local file vs Google Sheets
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment<int>(
                            value: 0,
                            icon: Icon(Icons.file_present_rounded),
                            label: Text('CSV / XLSX'),
                          ),
                          ButtonSegment<int>(
                            value: 1,
                            icon: Icon(Icons.cloud_download_outlined),
                            label: Text('Google Sheets DB'),
                          ),
                        ],
                        selected: {_importMethodIndex},
                        onSelectionChanged: (set) {
                          setState(() => _importMethodIndex = set.first);
                        },
                      ),
                      const SizedBox(height: 14),

                      // Upload Area based on Selected Method
                      if (_importMethodIndex == 0) ...[
                        // CSV/XLSX file picker card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: _pickedFileName != null
                                  ? Colors.green.shade400
                                  : fptOrange.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          color: _pickedFileName != null
                              ? const Color(0xFFF1F8F4)
                              : const Color(0xFFFFF8F3),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _pickedFileName != null
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : fptOrange.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.upload_file_rounded,
                                    size: 30,
                                    color: _pickedFileName != null
                                        ? Colors.green.shade700
                                        : fptOrange,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Import file CSV hoặc XLSX',
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: deepBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _pickedFileName ??
                                            'Hỗ trợ .csv, .xlsx với StudentCode/FullName hoặc RollNo/FullName/Email',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : _pickAndImportFile,
                                  icon: _isLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.file_open_outlined,
                                          size: 18,
                                        ),
                                  label: const Text('Chọn file'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: deepBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else ...[
                        // Google Sheets URL Input Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color:
                                  _importedStudentCount != null &&
                                      _importedStudentCount! > 0
                                  ? Colors.green.shade400
                                  : deepBlue.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          color: const Color(0xFFF8FAFC),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Đường dẫn Google Sheets / Web App URL:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _googleSheetsUrlController,
                                        decoration: InputDecoration(
                                          hintText:
                                              'https://docs.google.com/spreadsheets/d/... hoặc Apps Script URL',
                                          prefixIcon: const Icon(
                                            Icons.link_rounded,
                                          ),
                                          isDense: true,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton.icon(
                                      onPressed: _isLoading
                                          ? null
                                          : _importFromGoogleSheets,
                                      icon: _isLoading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.cloud_download,
                                              size: 18,
                                            ),
                                      label: const Text('Tải từ Sheet'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0F9D58,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Dialog Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFA),
                border: Border(
                  top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Cancel Button
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Hủy bỏ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Save Button with FPT Orange
                  FilledButton.icon(
                    onPressed: _onSave,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'Lưu lớp học',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: fptOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
