import 'package:flutter/material.dart';
import '../design/tokens.dart';
import '../format.dart';

/// Amounts come from the API; the storefront never calculates payable discounts.
class PromotionPrice extends StatelessWidget {
  const PromotionPrice({
    super.key,
    required this.price,
    this.original,
    this.name,
    this.prefix = '',
    this.large = false,
  });
  final int price;
  final int? original;
  final String? name;
  final String prefix;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final discounted = original != null && original! > price;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '$prefix${money(price)}',
              style: T.body.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: large ? 24 : null,
                color: discounted ? T.accent : T.ink,
              ),
            ),
            if (discounted)
              Text(
                money(original!),
                style: T.small.copyWith(decoration: TextDecoration.lineThrough),
              ),
          ],
        ),
        if (discounted)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              name == null || name!.isEmpty ? 'Ưu đãi tự động' : name!,
              style: T.small.copyWith(color: T.accent),
            ),
          ),
      ],
    );
  }
}
