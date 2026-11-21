part of 'style_page.dart';

// Product swatches describe the chosen color; UI states use the shared tokens.
const _styleColors = <String, Color>{
  'Trắng': Color(0xFFFAFAF8),
  'Đen': Color(0xFF252329),
  'Mận': Color(0xFF65394D),
  'Xanh': Color(0xFF526C80),
  'Nâu': Color(0xFF80634D),
  'Hồng đất': Color(0xFFBD8C85),
  'Tím': Color(0xFF84718E),
  'Đỏ': Color(0xFFAD303B),
};

class _StyleSection extends StatelessWidget {
  const _StyleSection({
    super.key,
    required this.number,
    required this.title,
    required this.description,
    required this.child,
  });
  final String number, title, description;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              number,
              style: T.small.copyWith(
                color: T.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              header: true,
              headingLevel: 3,
              child: Text(
                title,
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(description, style: T.small),
      const SizedBox(height: 16),
      child,
    ],
  );
}

class _StyleOptions extends StatelessWidget {
  const _StyleOptions({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final columns =
          constraints.maxWidth >=
              360 * MediaQuery.textScalerOf(context).scale(14) / 14
          ? 2
          : 1;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in children)
            SizedBox(
              width: (constraints.maxWidth - (columns - 1) * 8) / columns,
              child: child,
            ),
        ],
      );
    },
  );
}

class _StyleChoice extends StatelessWidget {
  const _StyleChoice({
    required this.label,
    required this.group,
    required this.selected,
    required this.onPressed,
    this.description,
    this.icon,
    this.swatch,
    this.trailingCheck = false,
  });
  final String label, group;
  final String? description;
  final bool selected, trailingCheck;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? swatch;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      visualDensity: VisualDensity.standard,
      minimumSize: const Size(48, 48),
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: description == null ? 12 : 14,
      ),
      alignment: Alignment.centerLeft,
      backgroundColor: selected ? T.soft : T.surface,
      foregroundColor: selected ? T.accent : T.ink,
      side: BorderSide(
        color: selected ? T.accent : T.controlLine,
        width: selected ? 1.5 : 1,
      ),
      shape: const RoundedRectangleBorder(borderRadius: T.radius),
    ),
    child: Semantics(
      selected: selected,
      label: '$group: $label',
      hint: description,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swatch != null) ...[
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: T.controlLine),
              ),
            ),
            const SizedBox(width: 8),
          ] else if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 10),
          ],
          Flexible(
            fit: trailingCheck ? FlexFit.tight : FlexFit.loose,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: T.body.copyWith(
                    color: selected ? T.accent : T.ink,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!, style: T.small),
                ],
              ],
            ),
          ),
          if (trailingCheck || description != null) ...[
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? T.accent : T.controlLine,
            ),
          ],
        ],
      ),
    ),
  );
}
