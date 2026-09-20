import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/attendance_provider.dart';
import 'screens/teacher_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FapAttendanceApp());
}
class FapAttendanceApp extends StatelessWidget {
  const FapAttendanceApp({super.key});

  static const Color _fptOrange = Color(0xFFF36F21);
  static const Color _deepBlue = Color(0xFF1B2A4A);

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.interTextTheme();

    return ChangeNotifierProvider(
      create: (_) => AttendanceProvider(),
      child: MaterialApp(
        title: 'FAP Smart Attendance Assistant',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          textTheme: baseTextTheme,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _fptOrange,
            primary: _fptOrange,
            secondary: _deepBlue,
            tertiary: const Color(0xFF059669),
            surface: Colors.white,
            surfaceContainerLowest: const Color(0xFFF8FAFB),
          ),
          scaffoldBackgroundColor: const Color(0xFFF4F6F9),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
          ),
          chipTheme: ChipThemeData(
            shape: const StadiumBorder(),
            side: BorderSide.none,
            labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF8FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _fptOrange, width: 1.8),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            labelStyle: GoogleFonts.inter(fontSize: 13),
            hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400),
          ),
          dividerTheme: DividerThemeData(
            color: Colors.grey.shade200,
            thickness: 1,
            space: 1,
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 8,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        home: const TeacherDashboardScreen(),
      ),
    );
  }
}
