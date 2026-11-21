import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/api_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_pagination.dart';
import 'admin_presentation.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

typedef AdminReviewQuery = ({
  int page,
  String visibility,
  int? rating,
  String q,
});

class AdminReviewPage extends AdminPage {
  AdminReviewPage(super.json)
    : counts = Map<String, int>.from(json['counts'] as Map? ?? const {});
  final Map<String, int> counts;
}

final adminReviewsProvider = FutureProvider.autoDispose
    .family<AdminReviewPage, AdminReviewQuery>((ref, q) async {
      final value = await ref
          .watch(adminApiClientProvider)
          .get(
            'admin/reviews',
            query: {
              'page': '${q.page}',
              'limit': '20',
              'visibility': q.visibility,
              if (q.rating != null) 'rating': '${q.rating}',
              if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
            },
          );
      return AdminReviewPage(Map<String, dynamic>.from(value as Map));
    });

const _visibility = {
  'all': 'Tất cả',
  'visible': 'Đang hiển thị',
  'hidden': 'Đã ẩn',
};

class RemoteReviewsPage extends ConsumerStatefulWidget {
  const RemoteReviewsPage({super.key});
  @override
  ConsumerState<RemoteReviewsPage> createState() => _RemoteReviewsPageState();
}

class _RemoteReviewsPageState extends ConsumerState<RemoteReviewsPage> {
  final search = TextEditingController();
  int page = 1;
  String visibility = 'all', q = '';
  int? rating;

  AdminReviewQuery get query =>
      (page: page, visibility: visibility, rating: rating, q: q);
  void reload() => ref.invalidate(adminReviewsProvider);
  void filter(VoidCallback change) => setState(() {
    change();
    page = 1;
  });

  Future<void> moderate(AdminRecord review, {required bool hide}) async {
    final reason = TextEditingController(
      text: hide ? '${review['hiddenReason'] ?? ''}' : '',
    );
    await showDialog<bool>(
      context: context,
      builder: (_) => AdminMutationDialog(
        title: hide ? 'Ẩn đánh giá' : 'Hiện lại đánh giá',
        message: hide
            ? 'Đánh giá sẽ không còn trên trang sản phẩm và không tính vào điểm trung bình. Khách vẫn thấy đánh giá của mình kèm lý do.'
            : 'Đánh giá sẽ hiển thị lại trên trang sản phẩm nếu khách vẫn đủ điều kiện (đã nhận hàng).',
        submitLabel: hide ? 'Ẩn đánh giá' : 'Hiện lại',
        destructive: hide,
        reload: reload,
        onDisposed: reason.dispose,
        fields: [
          if (hide)
            TextFormField(
              controller: reason,
              maxLength: 120,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Lý do (khách sẽ thấy)',
                helperText: 'Ví dụ: Ngôn từ không phù hợp, quảng cáo, spam.',
              ),
              validator: (v) => requiredText(v, max: 120),
            ),
        ],
        submit: () async {
          await ref
              .read(adminApiClientProvider)
              .request(
                'PATCH',
                'admin/reviews/${Uri.encodeComponent('${review['id']}')}/visibility',
                body: {
                  'hidden': hide,
                  if (hide) 'reason': reason.text.trim(),
                  'expectedUpdatedAt': review['updatedAt'],
                },
              );
          reload();
        },
      ),
    );
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminReviewsProvider(query));
    final counts = value.value?.counts ?? const <String, int>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Đánh giá sản phẩm',
          'Kiểm duyệt đánh giá của khách. Đánh giá bị ẩn không hiện trên trang sản phẩm và không tính vào điểm trung bình.',
          actions: [AppButton('Tải lại', outlined: true, onPressed: reload)],
        ),
        AdminCard(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final e in _visibility.entries)
                    ButtonSegment(
                      value: e.key,
                      label: Text(
                        counts[e.key] == null
                            ? e.value
                            : '${e.value} (${adminNumber(counts[e.key])})',
                      ),
                    ),
                ],
                selected: {visibility},
                onSelectionChanged: (s) => filter(() => visibility = s.first),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<int?>(
                  initialValue: rating,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Số sao',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tất cả')),
                    for (var i = 5; i >= 1; i--)
                      DropdownMenuItem(value: i, child: Text('$i sao')),
                  ],
                  onChanged: (v) => filter(() => rating = v),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: search,
                  maxLength: 100,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Tìm nội dung, sản phẩm, khách hàng',
                    isDense: true,
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: 'Tìm',
                      icon: const Icon(Icons.search),
                      onPressed: () => filter(() => q = search.text),
                    ),
                  ),
                  onSubmitted: (v) => filter(() => q = v),
                ),
              ),
            ],
          ),
        ),
        AdminAsync(
          value: value,
          reload: reload,
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.items.isEmpty)
                const AdminCard(
                  child: Text('Không có đánh giá phù hợp.', style: T.body),
                ),
              for (final review in data.items)
                _ReviewCard(
                  review: review,
                  onHide: () => moderate(review, hide: true),
                  onRestore: () => moderate(review, hide: false),
                ),
              if (data.total > 0 || page > 1)
                AdminPagination(
                  page: data,
                  loading: value.isLoading,
                  onPage: (n) => setState(() => page = n),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({
    required this.review,
    required this.onHide,
    required this.onRestore,
  });
  final AdminRecord review;
  final VoidCallback onHide, onRestore;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = review['hiddenAt'] != null;
    final product = review['product'] as Map? ?? const {};
    final user = review['user'] as Map? ?? const {};
    final rating = review['rating'] as int? ?? 0;
    final productPath = '/admin/products/${product['id']}';
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                label: '$rating trên 5 sao',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 1; i <= 5; i++)
                        Icon(
                          i <= rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: T.accent,
                          size: 18,
                        ),
                    ],
                  ),
                ),
              ),
              hidden
                  ? const AdminStatus('Đã ẩn', color: T.danger)
                  : const AdminStatus('Đang hiển thị', color: T.success),
              Text(adminDate(review['createdAt']), style: T.small),
            ],
          ),
          const SizedBox(height: 12),
          Text('${review['comment']}', style: T.body),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canVisitAdmin(ref.watch(staffRoleProvider), productPath))
                TextButton(
                  onPressed: () => context.go(productPath),
                  child: Text('Sản phẩm: ${product['name']}'),
                )
              else
                Text('Sản phẩm: ${product['name']}', style: T.small),
              Text(
                'Khách: ${user['name'] ?? ''} · ${user['email'] ?? ''}',
                style: T.small,
              ),
            ],
          ),
          if (hidden)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Ẩn lúc ${adminDate(review['hiddenAt'])} · Lý do: ${review['hiddenReason'] ?? '—'}',
                style: T.small.copyWith(color: T.danger),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              if (hidden) ...[
                AppButton('Hiện lại', outlined: true, onPressed: onRestore),
                TextButton(onPressed: onHide, child: const Text('Sửa lý do')),
              ] else
                AppButton(
                  'Ẩn đánh giá',
                  outlined: true,
                  icon: Icons.visibility_off_outlined,
                  onPressed: onHide,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
