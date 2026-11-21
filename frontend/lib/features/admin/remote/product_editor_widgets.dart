import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_presentation.dart';
import 'product_widgets.dart';

class ProductEditorSection extends StatelessWidget {
  const ProductEditorSection({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.actions = const [],
  });
  final String title, description;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 24),
    decoration: BoxDecoration(
      color: T.surface,
      border: Border.all(color: T.line),
      borderRadius: T.radius,
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 20,
              runSpacing: 16,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: T.body.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(description, style: T.small),
                    ],
                  ],
                ),
                if (actions.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(24), child: child),
        ],
      ),
    ),
  );
}

class ProductEditorPreview extends StatelessWidget {
  const ProductEditorPreview({
    super.key,
    required this.product,
    required this.category,
    required this.brand,
  });
  final AdminRecord product;
  final String category, brand;
  @override
  Widget build(BuildContext context) {
    final images = product['images'] as List? ?? [],
        facts = ProductFacts(product);
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: T.surface,
        border: Border.all(color: T.line),
        borderRadius: T.radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 18, color: T.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Xem trước sản phẩm',
                    style: T.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: T.canvas,
              child: images.isNotEmpty && '${images.first['url']}'.isNotEmpty
                  ? FashionImage(
                      '${images.first['url']}',
                      label: '${images.first['alt'] ?? product['name']}',
                      fit: BoxFit.contain,
                    )
                  : const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: T.muted,
                        size: 48,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [brand, category].where((v) => v.isNotEmpty).join(' / '),
                  style: T.small,
                ),
                const SizedBox(height: 8),
                Text(
                  '${product['name']}'.trim().isEmpty
                      ? 'Tên sản phẩm'
                      : '${product['name']}',
                  style: T.body.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  facts.price,
                  style: T.body.copyWith(
                    fontSize: 17,
                    color: T.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    productStatus(product),
                    Text(
                      '${facts.selling.length} biến thể đang bán',
                      style: T.small,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Bản xem trước theo nội dung đang chỉnh sửa.',
                  style: T.small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProductEditorCheck extends StatelessWidget {
  const ProductEditorCheck(this.label, {super.key, required this.complete});
  final String label;
  final bool complete;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          complete ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 18,
          color: complete ? T.success : T.muted,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: T.small)),
      ],
    ),
  );
}

Widget variantStock(int quantity) => AdminStatus(
  quantity == 0
      ? 'Hết hàng'
      : quantity <= 5
      ? '$quantity · Sắp hết'
      : '$quantity có sẵn',
  color: quantity == 0
      ? T.danger
      : quantity <= 5
      ? T.warning
      : T.success,
);
