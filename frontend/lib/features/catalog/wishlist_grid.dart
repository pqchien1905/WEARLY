part of 'remote_wishlist_page.dart';

class _WishlistGrid extends StatelessWidget {
  const _WishlistGrid({
    required this.records,
    required this.enabled,
    required this.onRemove,
  });
  final List<MapEntry<String, Product?>> records;
  final bool enabled;
  final ValueChanged<String> onRemove;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final effectiveWidth =
          c.maxWidth / MediaQuery.textScalerOf(context).scale(1);
      final columns = effectiveWidth < 400
          ? 1
          : effectiveWidth < 700
          ? 2
          : effectiveWidth < 1100
          ? 3
          : 4;
      const gap = 24.0;
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: 32,
        children: [
          for (final entry in records)
            SizedBox(
              key: ValueKey(entry.key),
              width: width,
              child: entry.value != null
                  ? ProductCard(
                      entry.value!,
                      actionsEnabled: enabled,
                      showQuickAddLabel: true,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 3 / 4,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: T.soft,
                              borderRadius: T.radius,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.checkroom_outlined,
                                size: 48,
                                color: T.muted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Sản phẩm không còn mở bán',
                          style: T.body.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Bạn có thể bỏ sản phẩm này khỏi danh sách đã lưu.',
                          style: T.small,
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: enabled ? () => onRemove(entry.key) : null,
                          icon: const Icon(Icons.favorite_border, size: 18),
                          label: const Text('Bỏ yêu thích'),
                        ),
                      ],
                    ),
            ),
        ],
      );
    },
  );
}
