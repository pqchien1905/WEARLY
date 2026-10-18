import 'package:flutter/material.dart';
import 'motion.dart';

abstract final class T {
  static const canvas = Color(0xFFF7F8F7),
      surface = Color(0xFFFFFFFF),
      ink = Color(0xFF252329),
      muted = Color(0xFF67636A),
      line = Color(0xFFDFDCE0),
      controlLine = Color(0xFF8E8A91),
      accent = Color(0xFF65394D),
      soft = Color(0xFFECE5E9),
      photo = Color(0xFFE9EAE7),
      success = Color(0xFF286047),
      danger = Color(0xFFAD303B),
      warning = Color(0xFF805A16);
  // Page shell follows the viewport; reading/form widths stay local to pages.
  static const double maxWidth = double.infinity;
  static const radius = BorderRadius.all(Radius.circular(6));
  static double gutter(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600
      ? 20
      : MediaQuery.sizeOf(context).width < 1024
      ? 32
      : 56;
  static TextStyle display(double size) => TextStyle(
    fontFamily: 'Manrope',
    fontSize: size,
    fontWeight: FontWeight.w500,
    letterSpacing: -1.5,
    height: 1.12,
    color: ink,
  );
  static const body = TextStyle(
    fontFamily: 'BeVietnamPro',
    fontSize: 14,
    height: 1.65,
    color: ink,
  );
  static const small = TextStyle(
    fontFamily: 'BeVietnamPro',
    fontSize: 12,
    height: 1.5,
    color: muted,
  );
}

ThemeData buildTheme({bool reduceMotion = false}) {
  final duration = reduceMotion ? Duration.zero : Motion.fast;
  final scheme = ColorScheme.fromSeed(seedColor: T.accent, surface: T.surface)
      .copyWith(
        primary: T.accent,
        onPrimary: T.surface,
        error: T.danger,
        onSurface: T.ink,
        onSurfaceVariant: T.muted,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: T.surface,
        surfaceContainerLow: T.canvas,
        surfaceContainer: T.canvas,
        surfaceContainerHigh: T.soft,
        surfaceContainerHighest: T.soft,
        outline: T.line,
        secondaryContainer: T.soft,
        onSecondaryContainer: T.accent,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: T.surface,
    fontFamily: 'BeVietnamPro',
    splashFactory: NoSplash.splashFactory,
    hoverColor: T.soft.withValues(alpha: .45),
    focusColor: T.accent.withValues(alpha: .12),
    textTheme: const TextTheme(
      bodyMedium: T.body,
      bodyLarge: T.body,
      bodySmall: T.small,
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(
      color: T.line,
      thickness: 1,
      space: 32,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: T.surface,
      labelStyle: T.body.copyWith(color: T.muted),
      floatingLabelStyle: T.small.copyWith(color: T.accent),
      hintStyle: T.body.copyWith(color: T.muted),
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: const OutlineInputBorder(
        borderRadius: T.radius,
        borderSide: BorderSide(color: T.controlLine),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: T.radius,
        borderSide: BorderSide(color: T.controlLine),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: T.radius,
        borderSide: BorderSide(color: T.accent, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: T.ink,
            foregroundColor: T.surface,
            minimumSize: const Size(48, 50),
            shape: const RoundedRectangleBorder(borderRadius: T.radius),
            textStyle: const TextStyle(
              fontFamily: 'BeVietnamPro',
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ).copyWith(
            animationDuration: duration,
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return T.line;
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return T.accent;
              }
              return T.ink;
            }),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.disabled) ? T.muted : T.surface,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: T.ink, width: 2)
                  : const BorderSide(color: Colors.transparent, width: 2),
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: T.ink,
            minimumSize: const Size(48, 50),
            side: const BorderSide(color: T.controlLine),
            shape: const RoundedRectangleBorder(borderRadius: T.radius),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ).copyWith(
            animationDuration: duration,
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? T.line
                    : states.contains(WidgetState.focused)
                    ? T.accent
                    : T.controlLine,
                width: states.contains(WidgetState.focused) ? 2 : 1,
              ),
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: T.ink,
        minimumSize: const Size(44, 44),
      ).copyWith(animationDuration: duration),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: T.ink,
        minimumSize: const Size(44, 44),
      ).copyWith(animationDuration: duration),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: T.canvas,
      selectedColor: T.soft,
      side: const BorderSide(color: T.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      labelStyle: T.small.copyWith(color: T.ink),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: T.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: T.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(),
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: T.accent,
      selectedTileColor: T.soft,
      iconColor: T.muted,
      titleTextStyle: T.body,
      subtitleTextStyle: T.small,
      minVerticalPadding: 12,
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: const WidgetStatePropertyAll(T.canvas),
      headingTextStyle: T.small.copyWith(fontWeight: FontWeight.w600),
      dataTextStyle: T.body,
      dividerThickness: 1,
      horizontalMargin: 20,
      columnSpacing: 28,
      dataRowMinHeight: 64,
      dataRowMaxHeight: 88,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: T.ink,
      contentTextStyle: TextStyle(fontFamily: 'BeVietnamPro', color: T.surface),
      actionTextColor: T.surface,
      shape: RoundedRectangleBorder(borderRadius: T.radius),
      elevation: 2,
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: T.accent,
      textColor: T.surface,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: T.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: T.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: T.radius),
    ),
  );
}
