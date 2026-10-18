import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../app/remote_route_gate.dart';
import '../../app/review_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../product_detail/review_editor.dart';
import 'account_navigation.dart';

class CustomerReviewsPage extends ConsumerWidget {
  const CustomerReviewsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteApiProvider);
    final account = ref.watch(accountProvider);
    final repository = ref.watch(ownerReviewRepositoryProvider);
    return AccountFrame(
      title: 'Đánh giá của tôi',
      current: '/account/reviews',
      child: !remote
          ? const StatePanel(
              title: 'Đánh giá cần cửa hàng trực tuyến',
              message:
                  'Đăng nhập trong cửa hàng trực tuyến để xem các đánh giá bạn đã viết.',
            )
          : account == null || repository == null
          ? const LoginRequired(next: '/account/reviews')
          : _ReviewHistory(key: ValueKey((account.id, repository.generation))),
    );
  }
}

class _ReviewHistory extends ConsumerStatefulWidget {
  const _ReviewHistory({super.key});
  @override
  ConsumerState<_ReviewHistory> createState() => _ReviewHistoryState();
}

class _ReviewHistoryState extends ConsumerState<_ReviewHistory> {
  int page = 1;
  void reload() {
    ref.invalidate(ownedReviewsProvider);
    setState(() => page = 1);
  }

  Future<void> edit(OwnedReview review, {bool deleting = false}) async {
    final repository = ref.read(ownerReviewRepositoryProvider);
    if (repository == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReviewEditor(
        productId: review.productId,
        repository: repository,
        previous: review,
        deleting: deleting,
      ),
    );
    if (mounted) setState(() => page = 1);
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 840),
      child: SizedBox(
        width: double.infinity,
        child: ref
            .watch(ownedReviewsProvider(page))
            .when(
              skipLoadingOnRefresh: false,
              skipLoadingOnReload: false,
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('Đang tải đánh giá…', style: T.body),
              ),
              error: (error, _) => StatePanel(
                title: 'Chưa tải được đánh giá',
                message: accountError(error),
                action: AppButton('Tải lại', onPressed: reload),
              ),
              data: (data) {
                if (data == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Những trải nghiệm bạn đã chia sẻ sau khi nhận hàng.',
                      style: T.body,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${data.total} đánh giá', style: T.small),
                        TextButton.icon(
                          onPressed: reload,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Tải lại'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    if (data.total == 0)
                      StatePanel(
                        title: 'Bạn chưa viết đánh giá nào',
                        message:
                            'Mở sản phẩm trong đơn đã giao để chia sẻ trải nghiệm của bạn.',
                        action: AppButton(
                          'Xem đơn hàng',
                          onPressed: () => context.go('/account/orders'),
                        ),
                      )
                    else if (data.items.isEmpty)
                      StatePanel(
                        title: 'Trang này không còn đánh giá',
                        message:
                            'Danh sách vừa thay đổi. Trở lại trang đầu để xem đánh giá hiện có.',
                        action: AppButton('Về trang đầu', onPressed: reload),
                      )
                    else
                      for (final review in data.items) ...[
                        _HistoryRow(
                          key: ValueKey('review-${review.id}'),
                          review: review,
                          onEdit: () => edit(review),
                          onDelete: () => edit(review, deleting: true),
                        ),
                        const Divider(height: 40),
                      ],
                    if (page > 1 || data.hasNext)
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          AppButton(
                            'Trang trước',
                            outlined: true,
                            onPressed: page > 1
                                ? () => setState(() => page--)
                                : null,
                          ),
                          Text('Trang $page', style: T.small),
                          AppButton(
                            'Trang sau',
                            outlined: true,
                            onPressed: data.hasNext
                                ? () => setState(() => page++)
                                : null,
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
      ),
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    super.key,
    required this.review,
    required this.onEdit,
    required this.onDelete,
  });
  final OwnedReview review;
  final VoidCallback onEdit, onDelete;
  @override
  Widget build(BuildContext context) {
    final date = review.createdAt.toLocal();
    final product = review.product;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          product?.name ?? 'Sản phẩm không còn mở bán',
          style: T.display(22),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
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
                        size: 22,
                      ),
                  ],
                ),
              ),
            ),
            Text('${date.day}/${date.month}/${date.year}', style: T.small),
          ],
        ),
        const SizedBox(height: 16),
        Text(review.comment, style: T.body),
        if (!review.canEdit) ...[
          const SizedBox(height: 12),
          const Text(
            'Hiện chưa thể sửa đánh giá này. Bạn vẫn có thể xóa.',
            style: T.small,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (product != null)
              TextButton(
                onPressed: () => context.go(
                  '/products/${Uri.encodeComponent(product.slug)}',
                ),
                child: const Text('Xem sản phẩm'),
              ),
            if (review.canEdit)
              TextButton(onPressed: onEdit, child: const Text('Sửa đánh giá')),
            TextButton(onPressed: onDelete, child: const Text('Xóa đánh giá')),
          ],
        ),
      ],
    );
  }
}
