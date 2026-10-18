import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/review_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import 'review_editor.dart';

class ProductReviews extends ConsumerStatefulWidget {
  const ProductReviews({
    super.key,
    required this.productId,
    required this.slug,
  });
  final String productId, slug;
  @override
  ConsumerState<ProductReviews> createState() => _ProductReviewsState();
}

class _ProductReviewsState extends ConsumerState<ProductReviews> {
  int page = 1;
  void reload() {
    setState(() => page = 1);
    ref.read(reviewRevisionProvider.notifier).refresh(widget.productId);
  }

  Future<void> edit({ProductReview? previous, bool deleting = false}) async {
    final repository = ref.read(ownerReviewRepositoryProvider);
    if (repository == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReviewEditor(
        productId: widget.productId,
        repository: repository,
        previous: previous,
        deleting: deleting,
      ),
    );
    if (mounted) setState(() => page = 1);
  }

  @override
  Widget build(BuildContext context) {
    final public = ref.watch(
      publicReviewsProvider((productId: widget.productId, page: page)),
    );
    final account = ref.watch(accountProvider);
    final mine = ref.watch(myReviewProvider(widget.productId));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: T.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Đánh giá từ người mua', style: T.display(28)),
          const SizedBox(height: 12),
          const Text(
            'Trải nghiệm thực tế về chất liệu và độ vừa vặn.',
            style: T.body,
          ),
          const SizedBox(height: 24),
          if (account == null)
            AppButton(
              'Đăng nhập để đánh giá',
              outlined: true,
              onPressed: () => context.go(
                Uri(
                  path: '/login',
                  queryParameters: {'next': '/products/${widget.slug}'},
                ).toString(),
              ),
            )
          else
            mine.when(
              skipLoadingOnReload: false,
              skipLoadingOnRefresh: false,
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => TextButton(
                onPressed: () =>
                    ref.invalidate(myReviewProvider(widget.productId)),
                child: const Text('Kiểm tra lại quyền đánh giá'),
              ),
              data: (data) => data == null
                  ? const SizedBox.shrink()
                  : Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (data.review != null) ...[
                          Text(
                            'Đánh giá của bạn: ${data.review!.rating} sao',
                            style: T.small,
                          ),
                          if (data.canReview)
                            AppButton(
                              'Sửa đánh giá',
                              outlined: true,
                              onPressed: () => edit(previous: data.review),
                            ),
                          TextButton(
                            onPressed: () =>
                                edit(previous: data.review, deleting: true),
                            child: const Text('Xóa đánh giá'),
                          ),
                        ] else if (data.canReview)
                          AppButton(
                            'Viết đánh giá',
                            icon: Icons.edit_outlined,
                            onPressed: edit,
                          )
                        else
                          const Text(
                            'Bạn có thể đánh giá sau khi đơn hàng được giao.',
                            style: T.small,
                          ),
                      ],
                    ),
            ),
          const SizedBox(height: 24),
          public.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chưa tải được đánh giá.', style: T.body),
                TextButton(
                  onPressed: reload,
                  child: const Text('Tải lại đánh giá'),
                ),
              ],
            ),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (data.average != null) ...[
                      Text(
                        '${data.average!.toStringAsFixed(1).replaceAll('.', ',')} / 5',
                        style: T.display(36),
                      ),
                      const SizedBox(width: 20),
                    ],
                    Expanded(
                      child: Text('${data.total} đánh giá', style: T.body),
                    ),
                    IconButton(
                      tooltip: 'Tải lại đánh giá',
                      onPressed: reload,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (data.total == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Chưa có đánh giá', style: T.body),
                  ),
                if (data.total > 0 && data.items.isEmpty)
                  const Text(
                    'Trang này không còn đánh giá. Hãy quay lại trang trước.',
                    style: T.body,
                  ),
                for (final review in data.items)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              const Text('Khách đã mua hàng', style: T.body),
                              Text(
                                '${review.createdAt.day}/${review.createdAt.month}/${review.createdAt.year}',
                                style: T.small,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            label: '${review.rating} trên 5 sao',
                            child: ExcludeSemantics(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 1; i <= 5; i++)
                                    Icon(
                                      i <= review.rating
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: T.accent,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(review.comment, style: T.body),
                          const Divider(height: 32),
                        ],
                      ),
                    ),
                  ),
                if (page > 1 || data.hasNext)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppButton(
                        'Đánh giá trước',
                        outlined: true,
                        onPressed: page > 1
                            ? () => setState(() => page--)
                            : null,
                      ),
                      Text('Trang $page', style: T.small),
                      AppButton(
                        'Đánh giá tiếp',
                        outlined: true,
                        onPressed: data.hasNext
                            ? () => setState(() => page++)
                            : null,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
