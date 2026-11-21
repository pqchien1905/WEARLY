part of 'reviews_page.dart';

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.reviews,
    required this.onEdit,
    required this.onDelete,
  });
  final List<OwnedReview> reviews;
  final ValueChanged<OwnedReview>? onEdit, onDelete;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final wide = constraints.maxWidth >= 1000 * scale;
      final rows = [
        for (final review in reviews)
          _HistoryRow(
            key: ValueKey('review-${review.id}'),
            review: review,
            wide: wide,
            onEdit: onEdit == null ? null : () => onEdit!(review),
            onDelete: onDelete == null ? null : () => onDelete!(review),
          ),
      ];
      if (!wide) {
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              AccountCard(child: rows[i]),
            ],
          ],
        );
      }
      return Container(
        key: const ValueKey('reviews-table'),
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: T.surface,
          border: Border.all(color: T.line),
          borderRadius: T.radius,
        ),
        child: Column(
          children: [
            ColoredBox(
              color: T.canvas,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: _ReviewColumns(
                  children: [
                    for (final title in [
                      'Sản phẩm',
                      'Đánh giá',
                      'Nội dung',
                      'Thao tác',
                    ])
                      Text(
                        title,
                        style: T.small.copyWith(fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
            ),
            for (final row in rows) ...[
              const Divider(height: 1),
              Padding(padding: const EdgeInsets.all(24), child: row),
            ],
          ],
        ),
      );
    },
  );
}

/// Shared column widths keep every header and row on the same grid.
class _ReviewColumns extends StatelessWidget {
  const _ReviewColumns({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: children[0]),
        const SizedBox(width: 24),
        SizedBox(width: 152 * scale, child: children[1]),
        const SizedBox(width: 24),
        Expanded(flex: 5, child: children[2]),
        const SizedBox(width: 24),
        SizedBox(width: 160 * scale, child: children[3]),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    super.key,
    required this.review,
    required this.wide,
    required this.onEdit,
    required this.onDelete,
  });
  final OwnedReview review;
  final bool wide;
  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final product = _ReviewedProduct(review: review);
    final rating = _ReviewRating(review: review, wide: wide);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!wide) ...[
          Text(
            'Nội dung đánh giá',
            style: T.small.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
        ],
        Text(review.comment, style: T.body),
        if (!review.canEdit) ...[
          const SizedBox(height: 12),
          const Text(
            'Hiện chưa thể sửa đánh giá này. Bạn vẫn có thể xóa.',
            style: T.small,
          ),
        ],
      ],
    );
    final actions = Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (review.canEdit)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              textStyle: T.small.copyWith(fontWeight: FontWeight.w500),
            ),
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Sửa đánh giá'),
          ),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: T.danger,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            textStyle: T.small.copyWith(fontWeight: FontWeight.w500),
          ),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Xóa đánh giá'),
        ),
      ],
    );
    if (wide) {
      return _ReviewColumns(children: [product, rating, content, actions]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        product,
        const SizedBox(height: 20),
        rating,
        const Divider(height: 32),
        content,
        const SizedBox(height: 20),
        actions,
      ],
    );
  }
}

class _ReviewedProduct extends StatelessWidget {
  const _ReviewedProduct({required this.review});
  final OwnedReview review;

  @override
  Widget build(BuildContext context) {
    final product = review.product;
    final name = product?.name ?? 'Sản phẩm không còn mở bán';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: T.radius,
            child: SizedBox(
              width: 64,
              height: 84,
              child: product?.image?.isNotEmpty == true
                  ? FashionImage(product!.image!, label: name)
                  : const ColoredBox(
                      color: T.canvas,
                      child: Icon(
                        Icons.checkroom_outlined,
                        color: T.muted,
                        size: 24,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: T.body.copyWith(fontWeight: FontWeight.w600)),
              if (product != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: T.accent,
                    padding: EdgeInsets.zero,
                    textStyle: T.small.copyWith(fontWeight: FontWeight.w500),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () => context.go(
                    '/products/${Uri.encodeComponent(product.slug)}',
                  ),
                  child: const Text('Xem sản phẩm'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewRating extends StatelessWidget {
  const _ReviewRating({required this.review, required this.wide});
  final OwnedReview review;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final date = review.createdAt.toUtc().add(const Duration(hours: 7));
    String two(int value) => value.toString().padLeft(2, '0');
    final stars = Semantics(
      label: '${review.rating} trên 5 sao',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var star = 1; star <= 5; star++)
              Icon(
                star <= review.rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: T.accent,
                size: 18,
              ),
            const SizedBox(width: 8),
            Text(
              '${review.rating}/5',
              style: T.small.copyWith(
                color: T.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
    final created = Text(
      'Ngày ${two(date.day)}/${two(date.month)}/${date.year}',
      style: T.small,
    );
    final updatedAt = DateTime.parse(review.updatedAt);
    final updated =
        updatedAt.isAfter(review.createdAt.add(const Duration(seconds: 1)))
        ? Text('Đã chỉnh sửa', style: T.small.copyWith(color: T.accent))
        : null;
    return wide
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stars,
              const SizedBox(height: 12),
              created,
              if (updated != null) ...[const SizedBox(height: 4), updated],
            ],
          )
        : Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [stars, created, ?updated],
          );
  }
}
