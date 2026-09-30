import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized Design System for Crsis_Link
class AppColors {
  AppColors._();

  static const Color emergencyRed = Color(0xFFE50914);
  static const Color pitchBlack = Color(0xFF080808);
  static const Color cleanBackground = Color(0xFFF8F9FA);
  static const Color surfaceCards = Color(0xFFFFFFFF);
  static const Color surfaceBorder = Color(0xFFEDEDED);
}

class AppTypography {
  AppTypography._();

  static TextStyle get primaryHeader => GoogleFonts.archivoBlack(
        color: AppColors.pitchBlack,
      );

  static TextStyle get subtitle => GoogleFonts.inter(
        color: AppColors.pitchBlack,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get body => GoogleFonts.inter(
        color: AppColors.pitchBlack,
        fontWeight: FontWeight.w500,
      );
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.cleanBackground,
      primaryColor: AppColors.emergencyRed,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.emergencyRed,
        primary: AppColors.emergencyRed,
        secondary: AppColors.pitchBlack,
        surface: AppColors.cleanBackground,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceCards,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.surfaceBorder, width: 1),
        ),
      ),
      textTheme: TextTheme(
        displayLarge: AppTypography.primaryHeader,
        displayMedium: AppTypography.primaryHeader,
        displaySmall: AppTypography.primaryHeader,
        headlineLarge: AppTypography.primaryHeader,
        headlineMedium: AppTypography.primaryHeader,
        headlineSmall: AppTypography.primaryHeader,
        titleLarge: AppTypography.subtitle,
        titleMedium: AppTypography.subtitle,
        titleSmall: AppTypography.subtitle,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.body,
        bodySmall: AppTypography.body,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.pitchBlack,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
        ),
      ),
    );
  }
}
