import 'package:flutter/material.dart';
import 'tokens.dart';

abstract final class StoreHeaderStyle {
  static const double actionsWidth = 320;
  static const double controlSize = 44;
  static const double iconSize = 20;
  static const double verticalPadding = 8;
  static const double greetingMaxWidth = 128;

  static double utilityPadding(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360 ? 2 : 4;

  static String greeting(String? name) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty
        ? 'Chào bạn'
        : 'Chào, ${trimmed.split(RegExp(r'\s+')).last}';
  }

  static TextStyle utilityText(BuildContext context) => T.body.copyWith(
    fontSize: MediaQuery.sizeOf(context).width < 360 ? 12 : 13,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static ButtonStyle utilityButton(BuildContext context) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(controlSize, controlSize)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: utilityPadding(context)),
    ),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.any(
            const {
              WidgetState.hovered,
              WidgetState.focused,
              WidgetState.pressed,
            }.contains,
          )
          ? T.accent
          : T.ink,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.focused) ? T.soft : Colors.transparent,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    textStyle: WidgetStatePropertyAll(utilityText(context)),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: T.radius),
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.focused)
            ? T.accent
            : Colors.transparent,
        width: 2,
      ),
    ),
  );
}
