import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/remote_wishlist.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';

class RemoteWishlistPage extends ConsumerWidget {
  const RemoteWishlistPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlist = ref.watch(remoteWishlistProvider);
    Future<void> refresh() async {
      try {
        await wishlist.refresh();
      } catch (_) {
        /* Error rendered below. */
      }
    }

    final records = wishlist.items.entries.toList();
    final pages = math.max(1, (records.length / 12).ceil());
    final page =
        (int.tryParse(
                  GoRouterState.of(context).uri.queryParameters['page'] ?? '',
                ) ??
                1)
            .clamp(1, pages);
    final visible = records.skip((page - 1) * 12).take(12).toList();
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trang chủ / Yêu thích', style: T.small),
          const SizedBox(height: 28),
          Text(
            'Những món đồ bạn thích.',
            style: T.display(
              MediaQuery.sizeOf(context).width >= 1024 ? 48 : 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Lưu cảm hứng, trở lại khi bạn sẵn sàng.',
            style: T.body.copyWith(color: T.muted),
          ),
          const SizedBox(height: 24),
          if (wishlist.loading)
            const LoadingPanel()
          else if (!wishlist.loaded)
            StatePanel(
              title: 'Chưa tải được danh sách yêu thích',
              message: wishlist.error ?? 'Tải lại để xem sản phẩm đã lưu.',
              action: AppButton('Tải lại', onPressed: refresh),
            )
          else ...[
            Wrap(
              spacing: 24,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${records.length} sản phẩm đã lưu', style: T.small),
                TextButton.icon(
                  onPressed: wishlist.busy ? null : refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Tải lại'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (records.isEmpty)
              StatePanel(
                title: 'Tủ đồ yêu thích còn trống',
                message:
                    'Nhấn biểu tượng trái tim trên một sản phẩm để lưu lại.',
                action: AppButton(
                  'Khám phá cửa hàng',
                  onPressed: () => context.go('/shop'),
                ),
              )
            else ...[
              if (visible.any((e) => e.value != null))
                ProductGrid(
                  visible
                      .where((e) => e.value != null)
                      .map((e) => e.value!)
                      .toList(),
                  maxColumns: 4,
                ),
              for (final item in visible.where((e) => e.value == null))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(Icons.checkroom_outlined, color: T.muted),
                      const Text('Sản phẩm không còn mở bán', style: T.body),
                      TextButton(
                        onPressed: wishlist.busy
                            ? null
                            : () async {
                                try {
                                  await wishlist.toggle(item.key);
                                } catch (e) {
                                  if (context.mounted) {
                                    toast(context, wishlist.error ?? '$e');
                                  }
                                }
                              },
                        child: const Text('Bỏ yêu thích'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppButton(
                    'Trang trước',
                    outlined: true,
                    onPressed: page > 1
                        ? () => context.go('/wishlist?page=${page - 1}')
                        : null,
                  ),
                  Text('Trang $page / $pages', style: T.small),
                  AppButton(
                    'Trang sau',
                    outlined: true,
                    onPressed: page < pages
                        ? () => context.go('/wishlist?page=${page + 1}')
                        : null,
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
