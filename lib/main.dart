import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/otp_provider.dart';
import 'screens/teacher_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FapAttendanceApp());
}

class FapAttendanceApp extends StatelessWidget {
  const FapAttendanceApp({super.key});

  // ── Stitch Design Tokens ──
  static const Color primary = Color(0xFFA04100);
  static const Color primaryContainer = Color(0xFFF27023);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF531E00);
  static const Color secondary = Color(0xFF565E74);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFDAE2FD);
  static const Color tertiary = Color(0xFFA73A00);
  static const Color tertiaryContainer = Color(0xFFFE661E);
  static const Color surface = Color(0xFFF8F9FF);
  static const Color surfaceBright = Color(0xFFF8F9FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainer = Color(0xFFE5EEFF);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color onSurface = Color(0xFF0B1C30);
  static const Color onSurfaceVariant = Color(0xFF584238);
  static const Color outline = Color(0xFF8C7166);
  static const Color outlineVariant = Color(0xFFE0C0B2);
  static const Color error = Color(0xFFBA1A1A);

  static const _buttonTextStyle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    // Fix 1: MultiProvider — OTP timer isolated from attendance state.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => OtpProvider()),
        ChangeNotifierProxyProvider<OtpProvider, AttendanceProvider>(
          create: (_) => AttendanceProvider(),
          update: (_, otp, prev) => prev!..otpProvider = otp,
        ),
      ],
      child: MaterialApp(
        title: 'FPT EduPulse — Cổng Giảng Viên',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          textTheme: GoogleFonts.plusJakartaSansTextTheme(),
          colorScheme: const ColorScheme(
            brightness: Brightness.light,
            primary: primary,
            onPrimary: onPrimary,
            primaryContainer: primaryContainer,
            onPrimaryContainer: onPrimaryContainer,
            secondary: secondary,
            onSecondary: onSecondary,
            secondaryContainer: secondaryContainer,
            tertiary: tertiary,
            tertiaryContainer: tertiaryContainer,
            error: error,
            onError: onPrimary,
            surface: surface,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            outline: outline,
            outlineVariant: outlineVariant,
            surfaceBright: surfaceBright,
            surfaceContainer: surfaceContainer,
            surfaceContainerLow: surfaceContainerLow,
            surfaceContainerLowest: surfaceContainerLowest,
          ),
          scaffoldBackgroundColor: surface,
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            color: surfaceContainerLowest,
            surfaceTintColor: Colors.transparent,
          ),
          chipTheme: const ChipThemeData(
            shape: StadiumBorder(),
            side: BorderSide.none,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: _buttonTextStyle,
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: _buttonTextStyle,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: _buttonTextStyle,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: primaryContainer, width: 1.8),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            labelStyle: const TextStyle(fontSize: 13),
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          ),
          dividerTheme: const DividerThemeData(
            color: Color(0xFFE2E8F0),
            thickness: 1,
            space: 1,
          ),
          dialogTheme: DialogThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
