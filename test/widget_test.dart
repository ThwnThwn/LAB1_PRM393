import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance_app/main.dart';

void main() {
  void configureDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  BoxDecoration calendarDayDecoration(WidgetTester tester, Finder dayFinder) {
    final container = find
        .descendant(of: dayFinder, matching: find.byType(Container))
        .first;
    return tester.widget<Container>(container).decoration! as BoxDecoration;
  }

  testWidgets('calendar lets the lecturer select a different teaching date', (
    tester,
  ) async {
    configureDesktopViewport(tester);
    await tester.pumpWidget(const FapAttendanceApp());

    final now = DateTime.now();
    final anotherDay = now.day == 1 ? 2 : 1;
    final todayFinder = find.byKey(
      ValueKey('calendar-day-${now.year}-${now.month}-${now.day}'),
    );
    final anotherDayFinder = find.byKey(
      ValueKey('calendar-day-${now.year}-${now.month}-$anotherDay'),
    );

    expect(todayFinder, findsOneWidget);
    expect(
      calendarDayDecoration(tester, todayFinder).color,
      const Color(0xFFF27023),
    );

    await tester.tap(anotherDayFinder);
    await tester.pump();

    expect(
      calendarDayDecoration(tester, anotherDayFinder).color,
      const Color(0xFFF27023),
    );
    expect(find.text('NGÀY ĐÃ CHỌN'), findsOneWidget);
  });

  testWidgets('opening a course selects its timetable slot and roster tab', (
    tester,
  ) async {
    configureDesktopViewport(tester);
    await tester.pumpWidget(const FapAttendanceApp());

    expect(find.text('FPT EduPulse'), findsOneWidget);
    expect(find.text('Chưa chọn ca dạy'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-course-PRN232-SE1917')));
    await tester.pump();

    expect(find.text('PRN232 - SE1917'), findsWidgets);
    expect(find.textContaining('Buổi 3/20'), findsWidgets);
    expect(
      find.text(
        'Có thể sửa nhiều dòng trước khi mở phiên QR. Bấm Lưu để ghi một lần lên Google Sheets.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('global search filters the dashboard course list', (
    tester,
  ) async {
    configureDesktopViewport(tester);
    await tester.pumpWidget(const FapAttendanceApp());

    await tester.enterText(
      find.byKey(const ValueKey('global-search-field')),
      'EXE201',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('course-card-EXE201-SE1919')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('course-card-PRN232-SE1917')),
      findsNothing,
    );
  });

  testWidgets('teaching slot dropdown fits long course labels', (tester) async {
    configureDesktopViewport(tester);
    await tester.pumpWidget(const FapAttendanceApp());

    await tester.tap(find.byKey(const ValueKey('teaching-slot-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('teaching-slot-option-hcm202-tue-1')),
      findsOneWidget,
    );
    expect(find.text('HCM202 — SE1920'), findsWidgets);
    final hcmOption = find.byKey(
      const ValueKey('teaching-slot-option-hcm202-tue-1'),
    );
    expect(
      find.descendant(of: hcmOption, matching: find.textContaining('Buổi')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
