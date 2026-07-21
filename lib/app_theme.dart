import 'package:flutter/material.dart';

class AppColors extends InheritedWidget {
  final bool isDarkMode;

  const AppColors({
    super.key,
    required this.isDarkMode,
    required super.child,
  });

  static AppColors of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AppColors>();
    assert(result != null, 'No AppColors found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(AppColors oldWidget) => isDarkMode != oldWidget.isDarkMode;

  Color get background => isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0);
  Color get surface => isDarkMode ? const Color(0xFF252526) : const Color(0xFFFFFFFF);
  Color get primary => isDarkMode ? const Color(0xFF569CD6) : const Color(0xFF007ACC);
  Color get text => isDarkMode ? const Color(0xFFD4D4D4) : const Color(0xFF333333);
  Color get textSecondary => isDarkMode ? const Color(0xFF858585) : const Color(0xFF666666);
  Color get receive => isDarkMode ? const Color(0xFF4EC9B0) : const Color(0xFF1AAB8A);
  Color get send => isDarkMode ? const Color(0xFFCE9178) : const Color(0xFFC97B4A);
  Color get error => isDarkMode ? const Color(0xFFF48771) : const Color(0xFFE06C5C);
  Color get hexBackground => isDarkMode ? const Color(0xFF334D4A) : const Color(0xFFD4EDDA);
  Color get scaffoldBackground => isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0);
  Color get navRailBackground => isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8);
  Color get cardBorder => isDarkMode ? const Color(0xFF569CD6) : const Color(0xFF007ACC);
  Color get appBarBackground => isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0);
  Color get divider => isDarkMode ? const Color(0xFF858585).withOpacity(0.3) : const Color(0xFFCCCCCC);
  Color get inputFill => isDarkMode ? const Color(0xFF252526) : const Color(0xFFF9F9F9);

  ThemeData get themeData {
    if (isDarkMode) {
      return ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        primaryColor: const Color(0xFF569CD6),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF569CD6),
          secondary: Color(0xFFCE9178),
          surface: Color(0xFF252526),
        ),
      );
    } else {
      return ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF0F0F0),
        primaryColor: const Color(0xFF007ACC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF007ACC),
          secondary: Color(0xFFC97B4A),
          surface: Color(0xFFFFFFFF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE0E0E0),
          foregroundColor: Color(0xFF333333),
          elevation: 0,
        ),
      );
    }
  }

  Color navigationRailColor(int selectedIndex, int index) {
    if (selectedIndex == index) {
      return primary;
    }
    return isDarkMode ? const Color(0xFF858585) : const Color(0xFF999999);
  }
}
