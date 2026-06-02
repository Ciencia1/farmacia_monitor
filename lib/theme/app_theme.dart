import 'package:flutter/material.dart';

class AppTheme {
  // Colores principales
  static const Color bgDark = Color(0xFF0F1117);
  static const Color bgCard = Color(0xFF161B27);
  static const Color bgCardAlt = Color(0xFF12202E);
  static const Color border = Color(0xFF2A3040);

  static const Color tempOk = Color(0xFF4ADE9F);
  static const Color tempWarn = Color(0xFFFBBF24);
  static const Color tempDanger = Color(0xFFF87171);
  static const Color tempCold = Color(0xFF60A5FA);

  static const Color textPrimary = Color(0xFFE8E8E8);
  static const Color textSecondary = Color(0xFF8A9BB0);
  static const Color textMuted = Color(0xFF556070);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgDark,
        colorScheme: const ColorScheme.dark(
          primary: tempOk,
          secondary: tempWarn,
          error: tempDanger,
          surface: bgCard,
        ),
        cardColor: bgCard,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: bgDark,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          iconTheme: IconThemeData(color: textSecondary),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w300),
          headlineMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
          bodyMedium: TextStyle(color: textSecondary, fontSize: 13),
          labelSmall: TextStyle(color: textMuted, fontSize: 11, letterSpacing: 0.08),
        ),
        dividerColor: border,
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bgCard,
          selectedItemColor: tempOk,
          unselectedItemColor: textMuted,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
      );

  // Color de temperatura según valor
  static Color tempColor(double temp) {
    if (temp < 2.0) return tempCold;
    if (temp <= 7.5) return tempOk;
    if (temp <= 8.0) return tempWarn;
    return tempDanger;
  }

  // Texto de estado según temperatura
  static String tempStatus(double temp) {
    if (temp < 2.0) return 'TEMPERATURA BAJA — ALERTA';
    if (temp <= 7.5) return 'TEMPERATURA ÓPTIMA';
    if (temp <= 8.0) return 'PRÓXIMO AL LÍMITE';
    return 'TEMPERATURA ALTA — ALERTA';
  }

  // Ícono de estado
  static IconData tempIcon(double temp) {
    if (temp < 2.0) return Icons.ac_unit_rounded;
    if (temp <= 7.5) return Icons.check_circle_rounded;
    if (temp <= 8.0) return Icons.warning_rounded;
    return Icons.local_fire_department_rounded;
  }
}
