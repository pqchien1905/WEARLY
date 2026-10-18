import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';

const _collections = {
  'everyday': (
    'Everyday, theo cách bạn.',
    'Phom dáng đơn giản để kết hợp mỗi ngày. Chọn một món làm điểm bắt đầu cho tủ đồ của bạn.',
    'assets/images/shirt.jpg',
    'Tối giản',
    ['nep-1', 'nep-3', 'nep-4', 'nep-8'],
  ),
  'weekend': (
    'Một cuối tuần thảnh thơi.',
    'Chất liệu nhẹ, phom rộng và những lựa chọn thoải mái cho ngày không vội.',
    'assets/images/trousers.jpg',
    'Thư giãn',
    ['nep-3', 'nep-1', 'nep-4', 'nep-7'],
  ),
  'occasion': (
    'Dành cho một dịp riêng.',
    'Sắc mận, đường nét mềm và một chút chỉn chu cho những cuộc hẹn.',
    'assets/images/black-dress.jpg',
    'Thanh lịch',
    ['nep-2', 'nep-6', 'nep-7', 'nep-8'],
  ),
};

class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key, this.slug});
  final String? slug;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = _collections[slug];
    if (slug != null && collection == null) {
      return PageBody(
        child: StatePanel(
          title: 'Chưa tìm thấy bộ sưu tập',
          message: 'Khám phá các lựa chọn đang có tại Wearly.',
          action: AppButton(
            'Xem bộ sưu tập',
            onPressed: () => context.go('/collections'),
          ),
        ),
      );
    }
    if (collection == null) {
      return PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Một tủ đồ, nhiều cảm hứng.',
              style: T.display(
                MediaQuery.sizeOf(context).width < 600 ? 36 : 52,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ba cách bắt đầu. Những thiết kế được chọn từ catalog minh họa.',
            ),
            const SizedBox(height: 32),
            LayoutBuilder(
              builder: (_, c) => Wrap(
                spacing: 24,
                runSpacing: 40,
                children: [
                  for (final entry in _collections.entries)
                    SizedBox(
                      width: c.maxWidth < 700
                          ? c.maxWidth
                          : (c.maxWidth - 48) / 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () =>
                                context.go('/collections/${entry.key}'),
                            child: AspectRatio(
                              aspectRatio: 4 / 5,
                              child: FashionImage(
                                entry.value.$3,
                                label: entry.value.$1,
                                alignment: Alignment.topCenter,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(entry.value.$1, style: T.display(26)),
                          const SizedBox(height: 12),
                          Text(entry.value.$2),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () =>
                                context.go('/collections/${entry.key}'),
                            child: const Text('Khám phá bộ sưu tập'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      );
    }
    final query = Uri(queryParameters: {'style': collection.$4}).query;
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton(
            onPressed: () => context.go('/collections'),
            child: const Text('Tất cả bộ sưu tập'),
          ),
          const SizedBox(height: 20),
          Text(
            collection.$1,
            style: T.display(MediaQuery.sizeOf(context).width < 600 ? 36 : 52),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(collection.$2),
          ),
          const SizedBox(height: 32),
          ref
              .watch(allProductsProvider)
              .when(
                loading: () => const LoadingPanel(),
                error: (_, _) => StatePanel(
                  title: 'Chưa tải được bộ sưu tập',
                  message: 'Thử lại để xem các thiết kế.',
                  action: AppButton(
                    'Thử lại',
                    onPressed: () => ref.invalidate(allProductsProvider),
                  ),
                ),
                data: (page) =>
                    !page.items.any((p) => collection.$5.contains(p.slug))
                    ? const StatePanel(
                        title: 'Bộ sưu tập đang được cập nhật',
                        message: 'Quay lại sau để xem những thiết kế mới.',
                      )
                    : ProductGrid([
                        for (final slug in collection.$5)
                          ...page.items.where((p) => p.slug == slug),
                      ]),
              ),
          const SizedBox(height: 32),
          AppButton(
            'Xem tất cả thiết kế cùng phong cách',
            outlined: true,
            onPressed: () => context.go('/shop?$query'),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
