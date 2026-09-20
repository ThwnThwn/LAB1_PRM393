import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/main.dart';

void main() {
  testWidgets('Selecting a timetable slot updates the active class', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FapAttendanceApp());

    expect(find.text('FAP ATTENDANCE'), findsOneWidget);
    expect(find.text('Chưa chọn ca dạy'), findsWidgets);

    final slotHeaderRect = tester.getRect(
      find.byKey(const ValueKey('slot-header-cell')),
    );
    final firstSlotRect = tester.getRect(
      find.byKey(const ValueKey('slot-row-cell-1')),
    );
    expect(firstSlotRect.left, closeTo(slotHeaderRect.left, 0.01));
    expect(firstSlotRect.right, closeTo(slotHeaderRect.right, 0.01));

    for (var day = 1; day <= 7; day++) {
      final headerRect = tester.getRect(
        find.byKey(ValueKey('day-header-$day')),
      );
      final cellRect = tester.getRect(find.byKey(ValueKey('day-slot-$day-1')));
      expect(cellRect.left, closeTo(headerRect.left, 0.01));
      expect(cellRect.right, closeTo(headerRect.right, 0.01));
    }

    await tester.tap(find.text('PRN232').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PRN232 - SE1917'), findsOneWidget);

    await tester.tap(find.text('Bắt đầu điểm danh QR (10s OTP)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MSSV'), findsOneWidget);

    await tester.tap(find.text('Danh sách sinh viên'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MSSV'), findsOneWidget);
  });
}
