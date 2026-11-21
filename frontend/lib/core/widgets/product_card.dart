import 'promotion_price.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'wishlist_button.dart';
import '../../domain/catalog.dart';
import '../design/tokens.dart';
import 'primitives.dart';
import 'motion_widgets.dart';
import '../../features/catalog/quick_add_sheet.dart';

class ProductCard extends ConsumerWidget {
  const ProductCard(
    this.product, {
    super.key,
    this.actionsEnabled = true,
    this.showQuickAddLabel = false,
  });
  final Product product;
  final bool actionsEnabled, showQuickAddLabel;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InteractivePhoto(
                onTap: () => context.go('/products/${product.slug}'),
                child: FashionImage(
                  product.image,
                  label: product.media.isNotEmpty
                      ? product.media.first.label
                      : product.name,
                  fit: BoxFit.contain,
                ),
              ),
              if (!product.variants.any((variant) => variant.stock > 0))
                Positioned(
                  top: 12,
                  left: 12,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: T.surface,
                      borderRadius: T.radius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        'Hết hàng',
                        style: T.small.copyWith(color: T.ink),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                right: 8,
                child: WishlistButton(
                  product,
                  card: true,
                  enabled: actionsEnabled,
                ),
              ),
              if (!showQuickAddLabel)
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: IconButton.filledTonal(
                    tooltip: 'Chọn size ${product.name}',
                    onPressed:
                        actionsEnabled &&
                            product.variants.any((variant) => variant.stock > 0)
                        ? () => showQuickAdd(context, product.slug)
                        : null,
                    style: IconButton.styleFrom(backgroundColor: T.surface),
                    icon: const Icon(Icons.add, size: 20),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () => context.go('/products/${product.slug}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.body.copyWith(fontWeight: FontWeight.w600, height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 4),
        PromotionPrice(
          price: product.price,
          original: product.cheapestVariant.originalPrice,
          name: product.cheapestVariant.promotionName,
          prefix: product.variants.any((v) => v.price != product.price)
              ? 'Từ '
              : '',
        ),
        const SizedBox(height: 8),
        Wrap(
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final color in product.colors.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: color,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: Color(
                        product.variants
                            .firstWhere((v) => v.color == color)
                            .colorHex,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: T.line),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Text('${product.colors.length} màu', style: T.small),
          ],
        ),
        if (showQuickAddLabel) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  actionsEnabled && product.variants.any((v) => v.stock > 0)
                  ? () => showQuickAdd(context, product.slug)
                  : null,
              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: Text(
                product.variants.any((v) => v.stock > 0)
                    ? 'Chọn size'
                    : 'Tạm hết hàng',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ProductGrid extends StatelessWidget {
  const ProductGrid(this.products, {super.key, this.maxColumns = 4});
  final List<Product> products;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final count =
          (c.maxWidth < 330
                  ? 1
                  : c.maxWidth < 650
                  ? 2
                  : c.maxWidth < 1000
                  ? 3
                  : 4)
              .clamp(1, maxColumns);
      final gap = c.maxWidth < 600 ? 14.0 : 24.0;
      final width = (c.maxWidth - gap * (count - 1)) / count;
      return Wrap(
        spacing: gap,
        runSpacing: 32,
        children: products
            .map((p) => SizedBox(width: width, child: ProductCard(p)))
            .toList(),
      );
    },
  );
}

class SizeSelector extends StatelessWidget {
  const SizeSelector({
    super.key,
    required this.variants,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });
  final List<ProductVariant> variants;
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: variants
        .map(
          (v) => Semantics(
            selected: v.size == selected,
            label: 'Size ${v.size}${v.stock == 0 ? ", hết hàng" : ""}',
            child: SizedBox(
              width: v.size.length > 4 ? 96 : 58,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: selected == v.size ? T.ink : T.surface,
                  foregroundColor: selected == v.size ? T.surface : T.ink,
                  side: BorderSide(color: selected == v.size ? T.ink : T.line),
                ),
                onPressed: !enabled || v.stock == 0
                    ? null
                    : () => onSelected(v.size),
                child: Text(
                  v.size,
                  style: TextStyle(
                    decoration: v.stock == 0
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
            ),
          ),
        )
        .toList(),
  );
}

class QuantitySelector extends StatelessWidget {
  const QuantitySelector({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });
  final int value, max;
  final bool enabled;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: T.line),
      borderRadius: T.radius,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Giảm số lượng',
          onPressed: enabled && value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove, size: 16),
        ),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
          tooltip: 'Tăng số lượng',
          onPressed: enabled && value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add, size: 16),
        ),
      ],
    ),
  );
}
