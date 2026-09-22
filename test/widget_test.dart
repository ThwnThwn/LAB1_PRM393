import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/main.dart';
import 'package:fap_attendance_app/models/student.dart';

void main() {
  testWidgets(
    'Only today keeps the orange day header after selecting another day',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const FapAttendanceApp());
      final today = DateTime.now().weekday;
      final otherDay = today == 4 ? 1 : 4;

      Color headerBorderColor(int day) {
        final header = find.byKey(ValueKey('day-header-$day'));
        final container = find
            .descendant(of: header, matching: find.byType(Container))
            .first;
        final decoration =
            tester.widget<Container>(container).decoration! as BoxDecoration;
        return (decoration.border! as Border).top.color;
      }

      const orange = Color(0xFFF36F21);
      expect(headerBorderColor(today), orange);
      expect(headerBorderColor(otherDay), isNot(orange));

      final classCell = find.byKey(ValueKey('day-slot-$otherDay-1'));
      await tester.tap(
        find.descendant(of: classCell, matching: find.text('PRN232')),
      );
      await tester.pump();

      expect(headerBorderColor(today), orange);
      expect(headerBorderColor(otherDay), isNot(orange));
    },
  );

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
    expect(find.byKey(const ValueKey('slot-row-cell-8')), findsOneWidget);

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
    expect(
      find.text(
        'Không tải được dữ liệu từ Google Sheets. Hãy kiểm tra kết nối rồi chọn lại ca.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Danh sách sinh viên'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(
        'Không tải được dữ liệu từ Google Sheets. Hãy kiểm tra kết nối rồi chọn lại ca.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Có thể sửa nhiều dòng trước khi mở phiên QR. Bấm Lưu để ghi một lần lên Google Sheets.',
      ),
      findsOneWidget,
    );
    final statusControls = tester.widgetList<DropdownButton<AttendanceStatus>>(
      find.byType(DropdownButton<AttendanceStatus>),
    );
    expect(statusControls, isEmpty);
  });

  testWidgets('Class code filter keeps only the selected teaching group', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FapAttendanceApp());
    expect(find.text('PRN232'), findsWidgets);
    expect(find.text('EXE201'), findsOneWidget);
    expect(find.text('SWP391'), findsNothing);
    expect(find.text('MLN111'), findsNothing);
    expect(find.text('ITE302c'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('day-slot-2-1')),
        matching: find.text('HCM202'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('day-slot-5-1')),
        matching: find.text('HCM202'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('day-slot-1-4')),
        matching: find.text('HCM202'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('class-code-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SE1919').last);
    await tester.pumpAndSettle();

    expect(find.text('EXE201'), findsOneWidget);
    expect(find.text('PRN232'), findsNothing);
  });
}
