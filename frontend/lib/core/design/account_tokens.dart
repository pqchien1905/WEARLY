import 'package:flutter/material.dart';
import 'tokens.dart';

/// Account component tokens inherit Wearly's semantic palette.
abstract final class AccountTokens {
  static const background = T.canvas;
  static const panel = T.surface;
  static const border = T.line;
  static const selected = T.soft;
  static const selectedText = T.accent;
  static const radius = T.panelRadius;
  static const double sidebarWidth = 256;
  static const double gap = 32;
  static const double padding = 24;
  static const double compactPadding = 20;
  static const double sectionGap = 24;
  static const double emptyHeight = 360;
  static const double controlHeight = 48;
  static TextStyle display(double size) =>
      T.display(size).copyWith(letterSpacing: size >= 32 ? -.9 : -.5);
  static const heading = TextStyle(
    fontFamily: 'BeVietnamPro',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: T.ink,
  );
}
