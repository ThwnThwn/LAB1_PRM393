import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/attendance_provider.dart';
import '../models/fap_class_slot.dart';
import '../dialogs/activity_detail_dialog.dart';
import '../dialogs/add_class_dialog.dart';

/// Modern Material 3 Weekly Timetable screen for FPT University Attendance Desktop App.
/// Provides a desktop-first 7-column x 8-slot schedule grid with week navigation,
/// subject tonal color theming, and quick access to class details and creation.
class FapTimetableScreen extends StatelessWidget {
  const FapTimetableScreen({super.key});

  static const Color _fptOrange = Color(0xFFF36F21);

  void _onSlotTapped(BuildContext context, FapClassSlot slot) {
    final provider = Provider.of<AttendanceProvider>(context, listen: false);
    if (!provider.selectTimetableSlot(slot)) return;

    showDialog(
      context: context,
      builder: (ctx) => ActivityDetailDialog(slot: slot),
    );
  }

  void _onAddNewClassTapped(BuildContext context) {
    showDialog(context: context, builder: (ctx) => const AddClassDialog());
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AttendanceProvider>(context);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Bar: Week navigation, labels, and Add Class action
          _buildTopBar(context, provider),
          const SizedBox(height: 12),
          _buildClassSelectionBar(context, provider),
          const SizedBox(height: 12),

          // Timetable Grid Container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildTimetableGrid(context, provider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassSelectionBar(
    BuildContext context,
    AttendanceProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = provider.selectedSlot;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _fptOrange.withValues(alpha: 0.25)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.filter_alt_outlined,
                size: 20,
                color: _fptOrange,
              ),
              const SizedBox(width: 8),
              Text(
                'Mã lớp điểm danh',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Container(
            height: 42,
            constraints: const BoxConstraints(minWidth: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('class-code-filter'),
                value: provider.classCodeFilter ?? '',
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Tất cả lớp')),
                  ...provider.availableClassCodes.map(
                    (classCode) => DropdownMenuItem(
                      value: classCode,
                      child: Text(
                        classCode,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
                onChanged: provider.isSessionOpen
                    ? null
                    : provider.setClassCodeFilter,
              ),
            ),
          ),
          SizedBox(
            width: 300,
            child: Text(
              selected == null
                  ? '1. Chọn mã lớp  •  2. Bấm ca học  •  3. Bắt đầu điểm danh'
                  : '${selected.subjectCode} • ${selected.classCode} • Slot ${selected.slot} • ${FapClassSlot.getDayName(selected.dayOfWeek)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: selected == null
                    ? colorScheme.onSurfaceVariant
                    : const Color(0xFF9A3412),
                fontWeight: selected == null
                    ? FontWeight.w500
                    : FontWeight.w700,
              ),
            ),
          ),
          if (selected != null)
            FilledButton.icon(
              onPressed: () => provider.selectSlotAndStartAttendance(selected),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Điểm danh lớp này'),
              style: FilledButton.styleFrom(
                backgroundColor: _fptOrange,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Bar Widget (Responsive with Wrap to prevent RenderFlex overflow)
  // ---------------------------------------------------------------------------
  Widget _buildTopBar(BuildContext context, AttendanceProvider provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          // Left: Title & Branding icon
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _fptOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: _fptOrange,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Thời khóa biểu tuần',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    'Lịch giảng dạy & điểm danh FAP',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Center: Week Navigation Pill & Current Week Button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      tooltip: 'Tuần trước',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => provider.previousWeek(),
                    ),
                    const SizedBox(width: 6),
                    // Clickable date range to open calendar picker
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showDatePickerDialog(context, provider),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.date_range_rounded,
                                size: 16,
                                color: _fptOrange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                provider.currentWeekLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      tooltip: 'Tuần sau',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => provider.nextWeek(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: provider.goToCurrentWeek,
                child: const Text('Tuần hiện tại'),
              ),
            ],
          ),

          // Right: FAB-style "+ Thêm lớp dạy mới" button
          FilledButton.icon(
            onPressed: () => _onAddNewClassTapped(context),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text(
              'Thêm lớp dạy mới',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _fptOrange,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Grid Layout
  // ---------------------------------------------------------------------------
  Widget _buildTimetableGrid(
    BuildContext context,
    AttendanceProvider provider,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minGridWidth = 1020.0;
        const double scrollHorizontalPadding = 16.0;
        final availableGridWidth =
            constraints.maxWidth - scrollHorizontalPadding;
        final gridWidth = availableGridWidth > minGridWidth
            ? availableGridWidth
            : minGridWidth;
        const double slotColWidth = 110.0;
        final double dayColWidth = (gridWidth - slotColWidth) / 7;

        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          padding: const EdgeInsets.all(8.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: gridWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Day headers row
                  _buildHeaderRow(context, provider, slotColWidth, dayColWidth),
                  const SizedBox(height: 6),

                  // FAP standard: Slot 1 to 8
                  for (int slot = 1; slot <= 8; slot++) ...[
                    _buildSlotRow(
                      context,
                      provider,
                      slot,
                      slotColWidth,
                      dayColWidth,
                    ),
                    if (slot < 8) const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Header row: Slot index column header + 7 Day headers (Mon - Sun)
  Widget _buildHeaderRow(
    BuildContext context,
    AttendanceProvider provider,
    double slotColWidth,
    double dayColWidth,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    return Row(
      children: [
        // Top-left corner cell: Slot & Time label
        SizedBox(
          key: const ValueKey('slot-header-cell'),
          width: slotColWidth,
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Slot / Giờ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 7 Day headers (Mon=1 ... Sun=7)
        for (int dayOfWeek = 1; dayOfWeek <= 7; dayOfWeek++) ...[
          _buildDayHeaderCell(context, provider, dayOfWeek, dayColWidth, now),
        ],
      ],
    );
  }

  Widget _buildDayHeaderCell(
    BuildContext context,
    AttendanceProvider provider,
    int dayOfWeek,
    double width,
    DateTime now,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final date = provider.getDateForDay(dayOfWeek);
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final dayName = FapClassSlot.getDayName(dayOfWeek);
    final dayShort = FapClassSlot.getDayShortName(dayOfWeek);
    final formattedDate =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

    return SizedBox(
      key: ValueKey('day-header-$dayOfWeek'),
      width: width,
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          decoration: BoxDecoration(
            color: isToday
                ? _fptOrange.withValues(alpha: 0.08)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isToday
                  ? _fptOrange
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: isToday ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayName,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: isToday ? _fptOrange : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '($dayShort)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isToday
                          ? _fptOrange.withValues(alpha: 0.85)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _fptOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$formattedDate • Hôm nay',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Row for a single slot (1 to 6)
  Widget _buildSlotRow(
    BuildContext context,
    AttendanceProvider provider,
    int slotNumber,
    double slotColWidth,
    double dayColWidth,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final slotTime = FapClassSlot.getSlotTimeRange(slotNumber);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Slot Header Cell (Left column)
          SizedBox(
            key: ValueKey('slot-row-cell-$slotNumber'),
            width: slotColWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                constraints: const BoxConstraints(minHeight: 98),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Slot $slotNumber',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              slotTime,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 7 Day Cells (for Mon=1 ... Sun=7)
          for (int dayOfWeek = 1; dayOfWeek <= 7; dayOfWeek++) ...[
            _buildDaySlotCell(
              context,
              provider,
              dayOfWeek,
              slotNumber,
              dayColWidth,
            ),
          ],
        ],
      ),
    );
  }

  // A single day x slot cell
  Widget _buildDaySlotCell(
    BuildContext context,
    AttendanceProvider provider,
    int dayOfWeek,
    int slotNumber,
    double width,
  ) {
    final slots = provider.getSlotsForCell(dayOfWeek, slotNumber);

    return SizedBox(
      key: ValueKey('day-slot-$dayOfWeek-$slotNumber'),
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: slots.isEmpty
            ? const _EmptySlotCell()
            : _TimetableSlotCard(
                slot: slots.first,
                isSelected: provider.selectedSlot?.id == slots.first.id,
                onTap: () => _onSlotTapped(context, slots.first),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Date Picker Dialog — shows a calendar for quick date navigation
  // ---------------------------------------------------------------------------
  Future<void> _showDatePickerDialog(
    BuildContext context,
    AttendanceProvider provider,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: _fptOrange,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.grey.shade800,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Colors.white,
              headerBackgroundColor: _fptOrange,
              headerForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              dayStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              todayBorder: const BorderSide(color: _fptOrange, width: 1.5),
              todayForegroundColor: WidgetStateProperty.all(_fptOrange),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return Colors.grey.shade400;
                }
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return Colors.grey.shade800;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _fptOrange;
                }
                return null;
              }),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDate != null) {
      provider.goToDate(selectedDate);
    }
  }
}

// =============================================================================
// Class Card Widget (with Hover Elevation & Tonal Color Scheme)
// =============================================================================
class _TimetableSlotCard extends StatefulWidget {
  final FapClassSlot slot;
  final bool isSelected;
  final VoidCallback onTap;

  const _TimetableSlotCard({
    required this.slot,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_TimetableSlotCard> createState() => _TimetableSlotCardState();
}

class _TimetableSlotCardState extends State<_TimetableSlotCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subjectColor = _getSubjectColorScheme(
      widget.slot.subjectCode,
      context,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2.0),
          constraints: const BoxConstraints(minHeight: 94),
          decoration: BoxDecoration(
            color: _isHovered
                ? subjectColor.container
                : subjectColor.container.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isSelected || _isHovered
                  ? subjectColor.primary
                  : subjectColor.border,
              width: widget.isSelected ? 2.0 : (_isHovered ? 1.5 : 1.0),
            ),
            boxShadow: widget.isSelected || _isHovered
                ? [
                    BoxShadow(
                      color: subjectColor.primary.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Card Content Body
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top Line: Subject Code & Online badge icon
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.slot.subjectCode,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                  letterSpacing: 0.3,
                                  color: subjectColor.onContainer,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.slot.isOnline)
                              Container(
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF0284C7,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.videocam_rounded,
                                  size: 13,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                          ],
                        ),

                        // Middle Line: Class Code Chip & Room Label
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: subjectColor.border,
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                widget.slot.classCode,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: subjectColor.onContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(
                                    widget.slot.isOnline
                                        ? Icons.link_rounded
                                        : Icons.meeting_room_outlined,
                                    size: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      widget.slot.room.isNotEmpty
                                          ? widget.slot.room
                                          : (widget.slot.isOnline
                                                ? 'Online'
                                                : '—'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Bottom Line: Slot Time Subtle Text
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 11,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.75,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.slot.slotTime.isNotEmpty
                                    ? widget.slot.slotTime
                                    : FapClassSlot.getSlotTimeRange(
                                        widget.slot.slot,
                                      ),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.normal,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Empty Slot Cell (Fixed Height, Dashed Border)
// =============================================================================
class _EmptySlotCell extends StatelessWidget {
  const _EmptySlotCell();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0),
      constraints: const BoxConstraints(minHeight: 94),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          radius: 10,
          strokeWidth: 1.0,
          dashLength: 5.0,
          gapLength: 4.0,
        ),
      ),
    );
  }
}

// =============================================================================
// Custom Painter for Rounded Dashed Border
// =============================================================================
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.radius = 10.0,
    this.dashLength = 5.0,
    this.gapLength = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = (distance + dashLength < metric.length)
            ? dashLength
            : metric.length - distance;
        final extractPath = metric.extractPath(distance, distance + length);
        canvas.drawPath(extractPath, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.gapLength != gapLength;
  }
}

// =============================================================================
// Material 3 Subject Tonal Palette System
// =============================================================================
class _SubjectColorScheme {
  final Color primary;
  final Color container;
  final Color onContainer;
  final Color border;

  const _SubjectColorScheme({
    required this.primary,
    required this.container,
    required this.onContainer,
    required this.border,
  });
}

const List<_SubjectColorScheme> _subjectPalettes = [
  _SubjectColorScheme(
    primary: Color(0xFFF36F21), // FPT Orange
    container: Color(0xFFFFF1EB),
    onContainer: Color(0xFF8A3000),
    border: Color(0xFFFFD0B8),
  ),
  _SubjectColorScheme(
    primary: Color(0xFF0284C7), // Sky Blue
    container: Color(0xFFF0F9FF),
    onContainer: Color(0xFF0369A1),
    border: Color(0xFFBAE6FD),
  ),
  _SubjectColorScheme(
    primary: Color(0xFF059669), // Emerald
    container: Color(0xFFECFDF5),
    onContainer: Color(0xFF047857),
    border: Color(0xFFA7F3D0),
  ),
  _SubjectColorScheme(
    primary: Color(0xFF7C3AED), // Purple
    container: Color(0xFFF5F3FF),
    onContainer: Color(0xFF6D28D9),
    border: Color(0xFFDDD6FE),
  ),
  _SubjectColorScheme(
    primary: Color(0xFFD97706), // Amber
    container: Color(0xFFFFFBEB),
    onContainer: Color(0xFFB45309),
    border: Color(0xFFFDE68A),
  ),
  _SubjectColorScheme(
    primary: Color(0xFF0D9488), // Teal
    container: Color(0xFFF0FDFA),
    onContainer: Color(0xFF0F766E),
    border: Color(0xFF99F6E4),
  ),
  _SubjectColorScheme(
    primary: Color(0xFFE11D48), // Rose
    container: Color(0xFFFFF1F2),
    onContainer: Color(0xFFBE123C),
    border: Color(0xFFFECDD3),
  ),
  _SubjectColorScheme(
    primary: Color(0xFF4F46E5), // Indigo
    container: Color(0xFFEEF2FF),
    onContainer: Color(0xFF4338CA),
    border: Color(0xFFC7D2FE),
  ),
];

_SubjectColorScheme _getSubjectColorScheme(
  String subjectCode,
  BuildContext context,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  int hash = 0;
  final code = subjectCode.trim().toUpperCase();
  for (int i = 0; i < code.length; i++) {
    hash = (31 * hash + code.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  final base = _subjectPalettes[hash % _subjectPalettes.length];

  if (isDark) {
    return _SubjectColorScheme(
      primary: base.primary,
      container: base.primary.withValues(alpha: 0.18),
      onContainer: Color.lerp(base.primary, Colors.white, 0.75) ?? Colors.white,
      border: base.primary.withValues(alpha: 0.35),
    );
  }
  return base;
}
