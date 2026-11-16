import 'package:flutter/material.dart';

/// Familia Anymyst: Plan usa coral con violeta sobre fondo oscuro.
class Tema {
  static const fondo = Color(0xFF101416);
  static const superficie = Color(0xFF1A2023);
  static const superficieAlta = Color(0xFF232B2F);
  static const borde = Color(0xFF33403F);
  static const texto = Color(0xFFE6EEEC);
  static const textoSuave = Color(0xFF9AACAA);

  static const coral = Color(0xFFFF8A5B);
  static const coralOscuro = Color(0xFF8A3A1E);
  static const violeta = Color(0xFF2A1458);
  static const violetaOscuro = Color(0xFF1A0B3A);
  static const dorado = Color(0xFFE8B84A);

  static ThemeData get tema {
    final esquema = ColorScheme.fromSeed(
      seedColor: coral,
      brightness: Brightness.dark,
    ).copyWith(
      primary: coral,
      onPrimary: violetaOscuro,
      secondary: dorado,
      surface: superficie,
      onSurface: texto,
      outline: borde,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: fondo,
      dividerColor: borde,
      appBarTheme: const AppBarTheme(
        backgroundColor: fondo,
        foregroundColor: texto,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
            color: texto,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2),
      ),
      cardTheme: const CardThemeData(color: superficie, elevation: 0),
      dialogTheme: const DialogThemeData(backgroundColor: superficieAlta),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: coral, foregroundColor: violetaOscuro),
    );
  }
}
