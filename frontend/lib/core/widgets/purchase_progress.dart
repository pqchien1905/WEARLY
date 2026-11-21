import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// Read-only orientation: future steps are not presented as actionable links.
class PurchaseProgress extends StatelessWidget {
  const PurchaseProgress({super.key, required this.current});
  final int current;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Wrap(
      spacing: 20,
      runSpacing: 12,
      children: [
        for (final (index, label) in [
          'Giỏ hàng',
          'Đặt hàng',
          'Hoàn tất',
        ].indexed)
          Semantics(
            label:
                'Bước ${index + 1}: $label${index == current ? ', hiện tại' : ''}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == current ? T.accent : T.canvas,
                    border: Border.all(
                      color: index == current ? T.accent : T.line,
                    ),
                  ),
                  child: index < current
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: T.accent,
                        )
                      : Text(
                          '${index + 1}',
                          style: T.small.copyWith(
                            color: index == current ? T.surface : T.muted,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: T.small.copyWith(
                    color: index == current ? T.accent : T.muted,
                    fontWeight: index == current
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
