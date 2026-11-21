import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';

/// Shared column sizing keeps each list header aligned with its data rows.
class AdminColumnRow extends StatelessWidget {
  const AdminColumnRow({
    super.key,
    required this.widths,
    required this.children,
    this.header = false,
  });
  final List<double> widths;
  final List<Widget> children;
  final bool header;

  @override
  Widget build(BuildContext context) {
    assert(widths.length == children.length);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: header ? 14 : 0),
      decoration: header
          ? const BoxDecoration(
              color: T.canvas,
              border: Border(
                top: BorderSide(color: T.line),
                bottom: BorderSide(color: T.line),
              ),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth - (children.length - 1) * 16;
          final total = widths.reduce((a, b) => a + b);
          // Share extra space across the table; never let the name column
          // consume the entire surplus on a wide monitor.
          final first = (available * widths.first / total).clamp(0.0, 360.0);
          final last = (available * widths.last / total).clamp(0.0, 244.0);
          final remaining = available - first - last;
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                SizedBox(
                  width: i == 0
                      ? first
                      : i == children.length - 1
                      ? last
                      : remaining *
                            widths[i] /
                            (total - widths.first - widths.last),
                  child: cell(children[i]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget cell(Widget child) => header
      ? Semantics(
          header: true,
          child: DefaultTextStyle(
            style: T.small.copyWith(color: T.ink, fontWeight: FontWeight.w600),
            child: child,
          ),
        )
      : child;
}

class AdminRowActions extends StatelessWidget {
  const AdminRowActions({
    super.key,
    required this.onOpen,
    required this.edit,
    required this.menu,
  });
  final VoidCallback onOpen;
  final Widget edit, menu;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 244),
      child: TextButtonTheme(
        data: TextButtonThemeData(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(44, 44),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: onOpen,
                child: const Text('Xem chi tiết'),
              ),
            ),
            Expanded(child: edit),
            menu,
          ],
        ),
      ),
    ),
  );
}
