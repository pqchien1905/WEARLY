import 'dart:async';
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
import 'account_components.dart';

part 'review_list.dart';
part 'review_filters.dart';

class CustomerReviewsPage extends ConsumerWidget {
  const CustomerReviewsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteApiProvider);
    final account = ref.watch(accountProvider);
    final repository = ref.watch(ownerReviewRepositoryProvider);
    if (remote && account != null && repository != null) {
      return _ReviewHistory(key: ValueKey((account.id, repository.generation)));
    }
    return AccountFrame(
      title: 'Đánh giá của tôi',
      current: '/account/reviews',
      child: !remote
          ? const StatePanel(
              title: 'Đánh giá cần cửa hàng trực tuyến',
              message:
                  'Đăng nhập trong cửa hàng trực tuyến để xem các đánh giá bạn đã viết.',
            )
          : const LoginRequired(next: '/account/reviews'),
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
  int? rating;
  String query = '';
  final search = TextEditingController();
  Timer? debounce;
  OwnedReviewPage? snapshot;
  OwnedReviewKey? snapshotKey;
  String? notice;
  bool dialogOpen = false;
  OwnedReviewKey get requestKey => (page: page, query: query, rating: rating);
  bool get filtered => query.isNotEmpty || rating != null;

  void reload() {
    setState(() => notice = null);
    ref.invalidate(ownedReviewsProvider(requestKey));
  }

  void applySearch() {
    debounce?.cancel();
    if (query == search.text.trim()) return;
    setState(() {
      query = search.text.trim();
      page = 1;
      notice = null;
    });
  }

  void clearFilters() {
    debounce?.cancel();
    search.clear();
    setState(() {
      query = '';
      rating = null;
      page = 1;
      notice = null;
    });
  }

  Future<void> edit(OwnedReview review, {bool deleting = false}) async {
    final repository = ref.read(ownerReviewRepositoryProvider);
    if (repository == null || dialogOpen) return;
    setState(() => dialogOpen = true);
    final result = await showDialog<ReviewEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReviewEditor(
        productId: review.productId,
        repository: repository,
        previous: review,
        deleting: deleting,
        productName: review.product?.name ?? 'Sản phẩm không còn mở bán',
      ),
    );
    if (!mounted) return;
    setState(() {
      dialogOpen = false;
      notice = switch (result) {
        ReviewEditorResult.saved => 'Đã lưu thay đổi đánh giá.',
        ReviewEditorResult.deleted => 'Đã xóa đánh giá.',
        _ => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = requestKey;
    final result = ref.watch(ownedReviewsProvider(key));
    if (result is AsyncData<OwnedReviewPage?> && !result.isLoading) {
      snapshot = result.value;
      snapshotKey = key;
    }
    final data = snapshotKey == key ? snapshot : null;
    final busy = result.isLoading;
    final current = !busy && !result.hasError;
    final pages = data == null || data.total == 0
        ? 1
        : (data.total / data.limit).ceil();
    // Deleting the last row (or changing its rating) can remove the last page.
    if (current && data != null && page > pages) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && requestKey == key) setState(() => page = pages);
      });
    }
    return AccountFrame(
      title: 'Đánh giá của tôi',
      current: '/account/reviews',
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReviewFilters(
              search: search,
              rating: rating,
              onChanged: () {
                setState(() {});
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 350),
                  applySearch,
                );
              },
              onSubmitted: applySearch,
              onRating: (value) {
                debounce?.cancel();
                setState(() {
                  rating = value;
                  query = search.text.trim();
                  page = 1;
                  notice = null;
                });
              },
              onClear: clearFilters,
            ),
            const SizedBox(height: 20),
            if (notice != null) ...[
              Semantics(
                liveRegion: true,
                child: AccountNotice(
                  text: notice!,
                  icon: Icons.check_circle_outline,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (data != null) ...[
              AccountToolbar(
                label: '${data.total} đánh giá${filtered ? ' phù hợp' : ''}',
                actions: [
                  TextButton.icon(
                    onPressed: () => context.go('/account/orders'),
                    icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                    label: const Text('Xem đơn hàng'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : reload,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(busy ? 'Đang tải lại…' : 'Tải lại'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (busy && data == null)
              const AccountLoading(label: 'Đang tải đánh giá…')
            else if (busy) ...[
              const LinearProgressIndicator(
                semanticsLabel: 'Đang tải lại đánh giá',
              ),
              const SizedBox(height: 16),
            ],
            if (result.hasError) ...[
              AccountCard(
                title: data == null
                    ? 'Chưa tải được đánh giá'
                    : 'Chưa cập nhật được danh sách',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(accountError(result.error!), style: T.body),
                    ),
                    if (data != null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Đang hiển thị dữ liệu đã tải. Tải lại để tiếp tục sửa hoặc xóa.',
                        style: T.small,
                      ),
                    ],
                    const SizedBox(height: 16),
                    AppButton(
                      data == null ? 'Tải lại' : 'Thử lại',
                      onPressed: reload,
                      outlined: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (data != null) ...[
              if (data.total == 0)
                AccountEmptyState(
                  title: filtered
                      ? 'Không có đánh giá phù hợp'
                      : 'Bạn chưa viết đánh giá nào',
                  icon: filtered
                      ? Icons.search_off_outlined
                      : Icons.rate_review_outlined,
                  message: filtered
                      ? 'Thử từ khóa khác hoặc bỏ bộ lọc số sao để xem thêm đánh giá.'
                      : 'Mở sản phẩm trong đơn đã giao để chia sẻ trải nghiệm của bạn.',
                  action: filtered
                      ? AppButton(
                          'Bỏ bộ lọc',
                          onPressed: clearFilters,
                          outlined: true,
                        )
                      : null,
                )
              else if (data.items.isEmpty)
                StatePanel(
                  title: 'Trang này không còn đánh giá',
                  message:
                      'Danh sách vừa thay đổi. Tải lại để xem đánh giá hiện có.',
                  action: AppButton(
                    'Tải lại danh sách',
                    onPressed: busy ? null : reload,
                  ),
                )
              else
                _ReviewList(
                  reviews: data.items,
                  onEdit: current && !dialogOpen
                      ? (review) => edit(review)
                      : null,
                  onDelete: current && !dialogOpen
                      ? (review) => edit(review, deleting: true)
                      : null,
                ),
            ],
            if (page > 1 || (data?.hasNext ?? false)) ...[
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton(
                    'Trang trước',
                    outlined: true,
                    onPressed: page > 1 && !busy
                        ? () => setState(() {
                            page--;
                            notice = null;
                          })
                        : null,
                  ),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      data == null ? 'Trang $page' : 'Trang $page / $pages',
                      style: T.small,
                    ),
                  ),
                  AppButton(
                    'Trang sau',
                    outlined: true,
                    onPressed: current && (data?.hasNext ?? false)
                        ? () => setState(() {
                            page++;
                            notice = null;
                          })
                        : null,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }
}
