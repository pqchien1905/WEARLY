import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';
import 'admin_column_row.dart';

/// Small groups of related operational cards; rows grow with enlarged text.
class OperationsGrid extends StatelessWidget {
  const OperationsGrid({
    super.key,
    required this.children,
    this.minWidth = 240,
    this.compactMinWidth,
    this.maxColumns = 4,
  });
  final List<Widget> children;
  final double minWidth;
  final double? compactMinWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final targetWidth = c.maxWidth < 600
          ? compactMinWidth ?? minWidth
          : minWidth;
      final columns = ((c.maxWidth + 16) / (targetWidth * scale + 16))
          .floor()
          .clamp(1, maxColumns);
      return Column(
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    Expanded(
                      child: start + i < children.length
                          ? children[start + i]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class OperationsPanel extends StatelessWidget {
  const OperationsPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: T.surface,
      border: Border.all(color: T.line),
      borderRadius: T.panelRadius,
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class OperationsMetric extends StatelessWidget {
  const OperationsMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.color = T.accent,
  });
  final String label, value;
  final String? caption;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => OperationsPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: T.small.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 12),
            Icon(icon, color: color, size: 20),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          value,
          style: T
              .display(28)
              .copyWith(
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: -.6,
              ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(caption!, style: T.small),
        ],
      ],
    ),
  );
}

class OperationsNotice extends StatelessWidget {
  const OperationsNotice({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.color = T.accent,
  });
  final String title, message;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .055),
      border: Border.all(color: color.withValues(alpha: .18)),
      borderRadius: T.radius,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: T.body.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(message, style: T.small),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Column widths are shared with the header; narrow screens show labelled cards.
class OperationsTable extends StatelessWidget {
  const OperationsTable({
    super.key,
    required this.headers,
    required this.widths,
    required this.rows,
    required this.cards,
    this.minWidth = 880,
  });
  final List<String> headers;
  final List<double> widths;
  final List<List<Widget>> rows;
  final List<Widget> cards;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide =
          c.maxWidth >= minWidth &&
          MediaQuery.textScalerOf(context).scale(14) <= 18;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            AdminColumnRow(
              widths: widths,
              header: true,
              children: headers.map(Text.new).toList(),
            ),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: T.line),
            Padding(
              padding: EdgeInsets.symmetric(vertical: wide ? 16 : 20),
              child: wide
                  ? AdminColumnRow(widths: widths, children: rows[i])
                  : cards[i],
            ),
          ],
        ],
      );
    },
  );
}

class OperationsEmpty extends StatelessWidget {
  const OperationsEmpty({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: T.canvas,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: T.muted, size: 28),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: T.body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: T.small),
      ],
    ),
  );
}

class OperationsIdentity extends StatelessWidget {
  const OperationsIdentity({
    super.key,
    required this.name,
    required this.email,
    this.caption,
  });
  final String name, email;
  final String? caption;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: T.soft,
        child: Text(
          name.trim().isEmpty
              ? '?'
              : name.trim().characters.first.toUpperCase(),
          style: T.body.copyWith(color: T.accent, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: T.body.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            SelectableText(email, style: T.small),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(caption!, style: T.small),
            ],
          ],
        ),
      ),
    ],
  );
}
