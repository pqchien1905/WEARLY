import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/account_tokens.dart';
import '../../core/design/tokens.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.child,
    this.title,
    this.description,
    this.icon,
    this.padding,
  });
  final Widget child;
  final String? title, description;
  final IconData? icon;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding:
        padding ??
        EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600
              ? AccountTokens.compactPadding
              : AccountTokens.padding,
        ),
    decoration: BoxDecoration(
      color: AccountTokens.panel,
      borderRadius: AccountTokens.radius,
      border: Border.all(color: AccountTokens.border),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: T.accent),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    headingLevel: 2,
                    child: Text(title!, style: AccountTokens.heading),
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description!, style: T.body.copyWith(color: T.muted)),
            ],
            const SizedBox(height: 24),
          ],
          child,
        ],
      ),
    ),
  );
}

class AccountNotice extends StatelessWidget {
  const AccountNotice({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
  });
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(color: T.soft, borderRadius: T.radius),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: T.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: T.small.copyWith(color: T.accent, height: 1.7),
          ),
        ),
      ],
    ),
  );
}

class AccountEmptyState extends StatelessWidget {
  const AccountEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.search_off_outlined,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => AccountCard(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AccountTokens.emptyHeight - AccountTokens.padding * 2,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: T.soft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: T.accent, size: 30),
                ),
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  headingLevel: 2,
                  child: Text(
                    title,
                    style: AccountTokens.display(24),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: T.body.copyWith(color: T.muted),
                  textAlign: TextAlign.center,
                ),
                if (action != null) ...[const SizedBox(height: 24), action!],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AccountLink extends StatelessWidget {
  const AccountLink({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.path,
    this.enabled = true,
  });
  final String title, description, path;
  final IconData icon;
  final bool enabled;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    minLeadingWidth: 24,
    leading: Icon(icon, color: T.accent, size: 22),
    title: Text(title, style: T.body.copyWith(fontWeight: FontWeight.w500)),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(description, style: T.small),
    ),
    trailing: const Icon(Icons.arrow_forward, size: 18, color: T.muted),
    enabled: enabled,
    onTap: enabled ? () => context.go(path) : null,
  );
}

/// Equal columns that always occupy the complete account content width.
/// Collapse the entire row together, avoiding orphan half-width panels.
class AccountGrid extends StatelessWidget {
  const AccountGrid({
    super.key,
    required this.children,
    this.columns = 2,
    this.minColumnWidth = 320,
    this.equalHeight = false,
  });
  final List<Widget> children;
  final int columns;
  final double minColumnWidth;
  final bool equalHeight;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final count =
          c.maxWidth >=
              columns * minColumnWidth * scale +
                  (columns - 1) * AccountTokens.sectionGap
          ? columns
          : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < children.length; start += count) ...[
            if (start > 0) const SizedBox(height: AccountTokens.sectionGap),
            if (count == 1)
              children[start]
            else
              Builder(
                builder: (_) {
                  if (equalHeight) {
                    final cells = children.skip(start).take(count).toList();
                    return Table(
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.intrinsicHeight,
                      columnWidths: {
                        for (var i = 1; i < cells.length * 2 - 1; i += 2)
                          i: const FixedColumnWidth(AccountTokens.sectionGap),
                      },
                      children: [
                        TableRow(
                          children: [
                            for (var i = 0; i < cells.length; i++) ...[
                              if (i > 0) const SizedBox.shrink(),
                              cells[i],
                            ],
                          ],
                        ),
                      ],
                    );
                  }
                  final row = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (
                        var i = start;
                        i < (start + count).clamp(0, children.length);
                        i++
                      ) ...[
                        if (i > start)
                          const SizedBox(width: AccountTokens.sectionGap),
                        Expanded(child: children[i]),
                      ],
                    ],
                  );
                  return row;
                },
              ),
          ],
        ],
      );
    },
  );
}

class AccountToolbar extends StatelessWidget {
  const AccountToolbar({super.key, required this.label, required this.actions});
  final String label;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final stacked =
          c.maxWidth < 560 * MediaQuery.textScalerOf(context).scale(14) / 14;
      final action = Wrap(
        alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
        spacing: 12,
        runSpacing: 8,
        children: actions,
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: T.body.copyWith(color: T.muted)),
            const SizedBox(height: 12),
            action,
          ],
        );
      }
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: T.body.copyWith(color: T.muted)),
            ),
            const SizedBox(width: 24),
            Expanded(child: action),
          ],
        ),
      );
    },
  );
}

class AccountLoading extends StatelessWidget {
  const AccountLoading({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => AccountCard(
    child: Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 20),
            Text(label, style: T.small),
          ],
        ),
      ),
    ),
  );
}
