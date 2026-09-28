import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/fap_class_slot.dart';
import '../services/attendance_api_service.dart';

class TimetableImageImportSelection {
  final List<FapClassSlot> slots;
  final bool replaceExisting;

  const TimetableImageImportSelection({
    required this.slots,
    required this.replaceExisting,
  });
}

class TimetableImageImportDialog extends StatefulWidget {
  final AttendanceApiService? api;

  const TimetableImageImportDialog({super.key, this.api});

  @override
  State<TimetableImageImportDialog> createState() =>
      _TimetableImageImportDialogState();
}

class _TimetableImageImportDialogState
    extends State<TimetableImageImportDialog> {
  late final AttendanceApiService _api = widget.api ?? AttendanceApiService();
  final List<_EditableCandidate> _candidates = [];
  Uint8List? _imageBytes;
  String? _fileName;
  TimetableOcrResult? _result;
  String? _error;
  bool _analyzing = false;
  bool _replaceExisting = true;

  @override
  void dispose() {
    for (final candidate in _candidates) {
      candidate.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAndAnalyze() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'png',
        'jpg',
        'jpeg',
        'bmp',
        'tif',
        'tiff',
        'webp',
      ],
      allowMultiple: false,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Không đọc được dữ liệu ảnh đã chọn.');
      return;
    }

    setState(() {
      _imageBytes = bytes;
      _fileName = file.name;
      _error = null;
      _analyzing = true;
      _result = null;
      for (final candidate in _candidates) {
        candidate.dispose();
      }
      _candidates.clear();
    });

    try {
      final result = await _api.importTimetableImage(
        bytes: bytes,
        fileName: file.name,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _candidates.addAll(
          result.candidates.map(_EditableCandidate.fromOcrCandidate),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _addManualCandidate() {
    setState(() => _candidates.add(_EditableCandidate.empty()));
  }

  void _removeCandidate(int index) {
    setState(() {
      final candidate = _candidates.removeAt(index);
      candidate.dispose();
    });
  }

  void _submit() {
    final selected = _candidates
        .where((candidate) => candidate.selected)
        .toList();
    if (selected.isEmpty) {
      setState(() => _error = 'Hãy chọn ít nhất một ca học để nhập.');
      return;
    }
    final invalid = selected.where((candidate) => !candidate.isValid).toList();
    if (invalid.isNotEmpty) {
      setState(
        () => _error =
            'Còn ${invalid.length} ca thiếu mã môn, mã lớp, thứ hoặc slot.',
      );
      return;
    }

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final slots = selected.indexed.map((entry) {
      final index = entry.$1;
      final candidate = entry.$2;
      final subjectCode = candidate.subjectCode.text.trim().toUpperCase();
      final classCode = candidate.classCode.text.trim().toUpperCase();
      final room = candidate.room.text.trim();
      return FapClassSlot(
        id: 'ocr-$stamp-$index-${subjectCode.toLowerCase()}-${classCode.toLowerCase()}',
        subjectCode: subjectCode,
        subjectName: candidate.subjectName.text.trim().isEmpty
            ? subjectCode
            : candidate.subjectName.text.trim(),
        classCode: classCode,
        slot: candidate.slot!,
        dayOfWeek: candidate.dayOfWeek!,
        room: room,
        slotTime: FapClassSlot.getSlotTimeRange(candidate.slot!),
        instructor: candidate.instructor.text.trim(),
        campus: 'FUHCM',
        isOnline:
            room.toLowerCase().contains('online') ||
            room.toLowerCase().contains('trực tuyến'),
      );
    }).toList();

    Navigator.of(context).pop(
      TimetableImageImportSelection(
        slots: slots,
        replaceExisting: _replaceExisting,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: media.height - 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1E8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.document_scanner_outlined,
                      color: Color(0xFFF27023),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nhập thời khóa biểu từ ảnh',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'OCR chạy trên máy • kiểm tra lại trước khi lưu',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: _analyzing ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_imageBytes == null)
                      _buildEmptyPicker(theme)
                    else
                      _buildFileHeader(),
                    if (_analyzing) ...[
                      const SizedBox(height: 22),
                      const LinearProgressIndicator(color: Color(0xFFF27023)),
                      const SizedBox(height: 10),
                      Text(
                        'Đang đọc mã môn, lớp, thứ, slot và phòng học…',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _buildMessage(
                        Icons.error_outline_rounded,
                        _error!,
                        const Color(0xFFB91C1C),
                        const Color(0xFFFEF2F2),
                      ),
                    ],
                    if (_result != null && !_analyzing) ...[
                      const SizedBox(height: 20),
                      _buildRecognitionSummary(),
                      const SizedBox(height: 16),
                      _buildCandidateList(),
                    ],
                  ],
                ),
              ),
            ),
            if (_result != null && !_analyzing) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _replaceExisting,
                        onChanged: (value) =>
                            setState(() => _replaceExisting = value ?? true),
                        title: const Text('Thay thế thời khóa biểu hiện tại'),
                        subtitle: const Text('Tắt để gộp với các ca đang có'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF27023),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      onPressed: _submit,
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(
                        'Nhập ${_candidates.where((item) => item.selected).length} ca',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPicker(ThemeData theme) {
    return InkWell(
      onTap: _pickAndAnalyze,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAF7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF7B88D), width: 1.5),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.add_photo_alternate_outlined,
              size: 46,
              color: Color(0xFFF27023),
            ),
            const SizedBox(height: 12),
            Text(
              'Chọn ảnh chụp thời khóa biểu',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ảnh càng thẳng và rõ chữ thì kết quả càng chính xác • tối đa 12 MB',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF27023),
              ),
              onPressed: _pickAndAnalyze,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Chọn ảnh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _imageBytes!,
              width: 72,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 72,
                height: 54,
                child: Icon(Icons.image_outlined),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fileName ?? 'Ảnh thời khóa biểu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${(_imageBytes!.length / 1024).toStringAsFixed(0)} KB',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _analyzing ? null : _pickAndAnalyze,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Chọn ảnh khác'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecognitionSummary() {
    final result = _result!;
    final percent = (result.confidence * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMessage(
          result.candidates.isEmpty
              ? Icons.info_outline_rounded
              : Icons.check_circle_outline_rounded,
          result.candidates.isEmpty
              ? 'OCR đã đọc ảnh nhưng chưa tách được ca học. Hãy thêm ca thủ công hoặc thử ảnh rõ hơn.'
              : 'Đã nhận diện ${result.candidates.length} ca học • độ tin cậy tổng thể $percent%.',
          result.candidates.isEmpty
              ? const Color(0xFFB45309)
              : const Color(0xFF047857),
          result.candidates.isEmpty
              ? const Color(0xFFFFFBEB)
              : const Color(0xFFECFDF5),
        ),
        if (result.rawText.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Xem văn bản OCR gốc',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            children: [
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    result.rawText,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCandidateList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Kiểm tra các ca trước khi nhập',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: _addManualCandidate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Thêm ca'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < _candidates.length; index++) ...[
          _buildCandidateCard(_candidates[index], index),
          if (index != _candidates.length - 1) const SizedBox(height: 10),
        ],
        if (_candidates.isEmpty)
          OutlinedButton.icon(
            onPressed: _addManualCandidate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Thêm ca học thủ công'),
          ),
      ],
    );
  }

  Widget _buildCandidateCard(_EditableCandidate candidate, int index) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: candidate.selected ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: candidate.isValid
              ? const Color(0xFFE2E8F0)
              : const Color(0xFFF59E0B),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: candidate.selected,
                activeColor: const Color(0xFFF27023),
                onChanged: (value) =>
                    setState(() => candidate.selected = value ?? false),
              ),
              Expanded(
                child: Text(
                  'Ca ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (candidate.confidence > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'OCR ${(candidate.confidence * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Xóa ca này',
                visualDensity: VisualDensity.compact,
                onPressed: () => _removeCandidate(index),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 650;
              final fields = [
                _textField(candidate.subjectCode, 'Mã môn *', 'PRN232'),
                _textField(candidate.classCode, 'Mã lớp *', 'SE1917'),
                _textField(candidate.room, 'Phòng', 'NVH 602'),
                _dayDropdown(candidate),
                _slotDropdown(candidate),
              ];
              if (narrow) {
                return Column(
                  children: [
                    for (final field in fields) ...[
                      field,
                      if (field != fields.last) const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    var fieldIndex = 0;
                    fieldIndex < fields.length;
                    fieldIndex++
                  ) ...[
                    Expanded(child: fields[fieldIndex]),
                    if (fieldIndex != fields.length - 1)
                      const SizedBox(width: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
    return TextField(
      controller: controller,
      enabled: true,
      textCapitalization: TextCapitalization.characters,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _dayDropdown(_EditableCandidate candidate) {
    return DropdownButtonFormField<int>(
      initialValue: candidate.dayOfWeek,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Thứ *',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: List.generate(
        7,
        (index) => DropdownMenuItem(
          value: index + 1,
          child: Text(FapClassSlot.getDayName(index + 1)),
        ),
      ),
      onChanged: (value) => setState(() => candidate.dayOfWeek = value),
    );
  }

  Widget _slotDropdown(_EditableCandidate candidate) {
    return DropdownButtonFormField<int>(
      initialValue: candidate.slot,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Slot *',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: List.generate(
        8,
        (index) => DropdownMenuItem(
          value: index + 1,
          child: Text(
            'Slot ${index + 1} • ${FapClassSlot.getSlotTimeRange(index + 1)}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      onChanged: (value) => setState(() => candidate.slot = value),
    );
  }

  Widget _buildMessage(
    IconData icon,
    String text,
    Color color,
    Color background,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

class _EditableCandidate {
  final TextEditingController subjectCode;
  final TextEditingController subjectName;
  final TextEditingController instructor;
  final TextEditingController classCode;
  final TextEditingController room;
  final double confidence;
  int? dayOfWeek;
  int? slot;
  bool selected = true;

  _EditableCandidate({
    required String subjectCode,
    required String subjectName,
    required String instructor,
    required String classCode,
    required String room,
    required this.dayOfWeek,
    required this.slot,
    required this.confidence,
  }) : subjectCode = TextEditingController(text: subjectCode),
       subjectName = TextEditingController(text: subjectName),
       instructor = TextEditingController(text: instructor),
       classCode = TextEditingController(text: classCode),
       room = TextEditingController(text: room);

  factory _EditableCandidate.fromOcrCandidate(TimetableOcrCandidate candidate) {
    return _EditableCandidate(
      subjectCode: candidate.subjectCode,
      subjectName: candidate.subjectName,
      instructor: candidate.instructor,
      classCode: candidate.classCode,
      room: candidate.room,
      dayOfWeek: candidate.dayOfWeek,
      slot: candidate.slot,
      confidence: candidate.confidence,
    );
  }

  factory _EditableCandidate.empty() {
    return _EditableCandidate(
      subjectCode: '',
      subjectName: '',
      instructor: '',
      classCode: '',
      room: '',
      dayOfWeek: null,
      slot: null,
      confidence: 0,
    );
  }

  bool get isValid =>
      subjectCode.text.trim().isNotEmpty &&
      classCode.text.trim().isNotEmpty &&
      dayOfWeek != null &&
      slot != null;

  void dispose() {
    subjectCode.dispose();
    subjectName.dispose();
    instructor.dispose();
    classCode.dispose();
    room.dispose();
  }
}
