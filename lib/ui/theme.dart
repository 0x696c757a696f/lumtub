import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF101419);
  static const surface = Color(0xFF1B222A);
  static const sidebar = Color(0xFF151B22);
  static const accent = Color(0xFF55D4BA);
  static const activeNav = Color(0xFF253A38);
  static const errorBackground = Color(0xFF3F292D);
  static const errorText = Color(0xFFFFBCC2);
}

ThemeData buildAppTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: Brightness.dark, surface: AppColors.surface),
      appBarTheme: const AppBarTheme(backgroundColor: AppColors.background, surfaceTintColor: Colors.transparent),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: AppColors.accent)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
    );
