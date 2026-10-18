import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../virtual_tryon/tryon_results.dart';
import 'account_navigation.dart';

class TryOnHistoryPage extends ConsumerWidget {
  const TryOnHistoryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref
        .watch(tryOnResultsProvider)
        .values
        .toList()
        .reversed
        .toList();
    final catalog = ref.watch(allProductsProvider).asData?.value.items;
    return AccountFrame(
      title: 'Những lần thử đồ.',
      current: '/account/try-ons',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DemoNotice(
            text:
                'Lịch sử của tab này chỉ giữ mã phiên và trang phục, tối đa 20 kết quả. Không lưu ảnh cá nhân hay ảnh AI. Tải lại trang sẽ xóa lịch sử.',
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              AppButton(
                'Thử trang phục mới',
                onPressed: () => context.go('/virtual-try-on'),
              ),
              if (results.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    if (await confirmAction(
                          context,
                          'Xóa lịch sử thử đồ?',
                          'Các đường dẫn kết quả trong tab này sẽ không còn mở được.',
                        ) &&
                        context.mounted) {
                      ref.read(tryOnResultsProvider.notifier).clear();
                      toast(context, 'Đã xóa lịch sử thử đồ.');
                    }
                  },
                  child: const Text('Xóa toàn bộ lịch sử'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (results.isEmpty)
            const StatePanel(
              title: 'Chưa có lần thử đồ nào',
              message:
                  'Hoàn tất một phiên thử đồ demo để xem lại thông tin trang phục tại đây.',
              icon: Icons.checkroom_outlined,
            ),
          for (final result in results)
            Builder(
              builder: (context) {
                final product = catalog
                    ?.where((p) => p.slug == result.slug)
                    .firstOrNull;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border.all(color: T.line),
                    borderRadius: T.radius,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        height: 86,
                        child: product == null
                            ? const ColoredBox(
                                color: T.canvas,
                                child: Icon(
                                  Icons.checkroom_outlined,
                                  color: T.muted,
                                ),
                              )
                            : FashionImage(
                                product.image,
                                label: '${product.name}, ảnh catalog minh họa',
                              ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product?.name ??
                                  'Trang phục chưa có trong catalog',
                              style: T.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('Biến thể: ${result.sku}', style: T.small),
                            Text(
                              'Phiên ${result.id} · Kết quả mô phỏng',
                              style: T.small,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                  onPressed: () => context.go(
                                    '/virtual-try-on/${result.id}',
                                  ),
                                  child: const Text('Xem kết quả'),
                                ),
                                if (product != null)
                                  TextButton(
                                    onPressed: () =>
                                        context.go('/products/${result.slug}'),
                                    child: const Text('Xem trang phục'),
                                  ),
                                TextButton(
                                  onPressed: () async {
                                    if (await confirmAction(
                                          context,
                                          'Xóa phiên thử đồ?',
                                          'Chỉ xóa thông tin kết quả của phiên này.',
                                        ) &&
                                        context.mounted) {
                                      ref
                                          .read(tryOnResultsProvider.notifier)
                                          .remove(result.id);
                                    }
                                  },
                                  child: const Text(
                                    'Xóa phiên',
                                    style: TextStyle(color: T.danger),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
