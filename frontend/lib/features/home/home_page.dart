import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../app/api_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../../core/widgets/category_choices.dart';
import 'home_hero.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider(''));
    final remote = ref.watch(remoteApiProvider);
    final campaign = remote
        ? ref.watch(catalogProvider('category=dam')).value?.items.firstOrNull
        : null;
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Column(
      children: [
        HomeHero(
          remote: remote,
          product: campaign ?? catalog.value?.items.firstOrNull,
        ),
        PageBody(
          vertical: 24,
          child: Row(
            children: [
              if (!mobile) ...[
                Text(
                  'Bạn đang tìm gì?',
                  style: T.body.copyWith(color: T.muted),
                ),
                const SizedBox(width: 32),
              ],
              Expanded(
                child: CategoryChoices(
                  home: true,
                  onSelected: (slug) => context.go(
                    Uri(
                      path: '/shop',
                      queryParameters: {'category': slug},
                    ).toString(),
                  ),
                ),
              ),
            ],
          ),
        ),
        PageBody(
          vertical: mobile ? 32 : 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                'Mới trong tủ đồ',
                subtitle: 'Những lựa chọn dễ mặc, dễ yêu.',
                action: 'Xem tất cả',
                onAction: () => context.go('/shop'),
              ),
              const SizedBox(height: 32),
              catalog.when(
                data: (p) => p.items.isEmpty
                    ? const StatePanel(
                        title: 'Bộ sưu tập đang được cập nhật',
                        message: 'Những thiết kế mới sẽ xuất hiện tại đây.',
                      )
                    : ProductGrid(p.items.take(4).toList()),
                error: (_, _) => StatePanel(
                  title: 'Chưa tải được bộ sưu tập',
                  message: 'Thử kết nối lại để xem sản phẩm.',
                  action: AppButton(
                    'Thử lại',
                    onPressed: () => ref.invalidate(catalogProvider),
                  ),
                ),
                loading: () => const LoadingPanel(),
              ),
            ],
          ),
        ),
        PageBody(
          vertical: mobile ? 24 : 48,
          child: LayoutBuilder(
            builder: (_, c) {
              final content = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: EdgeInsets.all(mobile ? 28 : 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.auto_awesome_outlined,
                          color: T.accent,
                          size: 28,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Một góc nhìn mới\ncho tủ đồ quen.',
                          style: T.display(mobile ? 32 : 42),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Đi làm, hẹn hò hay một ngày thật thong thả. Hãy để stylist gợi ý những món đồ hợp với kế hoạch của bạn.',
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['Đi làm thanh lịch', 'Cuối tuần nhẹ nhàng']
                              .map(
                                (s) => ActionChip(
                                  label: Text(s),
                                  onPressed: () => context.go(
                                    Uri(
                                      path: '/ai-stylist',
                                      queryParameters: {'prompt': s},
                                    ).toString(),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 24),
                        AppButton(
                          'Trò chuyện với AI Stylist',
                          onPressed: () => context.go('/ai-stylist'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          ref.watch(remoteApiProvider)
                              ? 'Xem trạng thái dịch vụ và nhận gợi ý trong AI Stylist.'
                              : 'Trải nghiệm mô phỏng – chưa kết nối AI',
                          style: T.small,
                        ),
                      ],
                    ),
                  ),
                ),
              );
              final photo = SizedBox(
                height: c.maxWidth < 800
                    ? c.maxWidth
                    : (c.maxWidth * .44).clamp(480, 640),
                width: double.infinity,
                child: remote && catalog.value?.items.firstOrNull == null
                    ? const ColoredBox(color: T.photo)
                    : FashionImage(
                        remote
                            ? catalog.value!.items.first.image
                            : 'assets/images/shirt.jpg',
                        label: remote
                            ? catalog.value!.items.first.name
                            : 'Gợi ý phối áo trắng cùng denim, ảnh minh họa',
                        fit: BoxFit.contain,
                        alignment: Alignment(0, -.65),
                      ),
              );
              return Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: T.canvas,
                  borderRadius: T.heroRadius,
                ),
                child: c.maxWidth < 800
                    ? Column(children: [content, photo])
                    : Row(
                        children: [
                          Expanded(child: content),
                          Expanded(child: photo),
                        ],
                      ),
              );
            },
          ),
        ),
        PageBody(
          vertical: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                'Phòng thử, theo cách mới.',
                subtitle: remote
                    ? 'Chọn trang phục, thêm ảnh và xem trạng thái xử lý trong phòng thử.'
                    : 'Khám phá trải nghiệm trước khi công nghệ AI được kết nối.',
                action: 'Vào phòng thử',
                onAction: () => context.go('/virtual-try-on'),
              ),
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (_, c) => Wrap(
                  spacing: 32,
                  runSpacing: 24,
                  children: [
                    for (final item in [
                      (
                        Icons.checkroom_outlined,
                        'Chọn món đồ',
                        'Bắt đầu với thiết kế bạn yêu thích.',
                      ),
                      (
                        Icons.add_photo_alternate_outlined,
                        'Chọn ảnh của bạn',
                        remote
                            ? 'Bạn quyết định khi nào tải ảnh lên và có thể xóa ảnh.'
                            : 'Ảnh chỉ ở trong phiên trình duyệt.',
                      ),
                      (
                        Icons.compare_outlined,
                        remote ? 'Theo dõi kết quả' : 'Xem trải nghiệm mẫu',
                        remote
                            ? 'Kết quả được lưu riêng trong tài khoản của bạn.'
                            : 'Bản demo không biến đổi ảnh thực.',
                      ),
                    ])
                      SizedBox(
                        width: c.maxWidth < 700
                            ? c.maxWidth
                            : (c.maxWidth - 64) / 3,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(item.$1, color: T.accent, size: 28),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.$2,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(item.$3, style: T.small),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PageBody(
          vertical: 40,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(mobile ? 28 : 48),
            decoration: const BoxDecoration(
              color: T.soft,
              borderRadius: T.heroRadius,
            ),
            child: LayoutBuilder(
              builder: (_, c) {
                final heading = Text(
                  'Một món đồ đẹp.\nNhiều cách là chính mình.',
                  style: T.display(mobile ? 32 : 48),
                );
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: const Text(
                        'Everyday là câu chuyện về những thiết kế có thể cùng bạn đi qua nhiều dịp. Khám phá cách phối lại chiếc áo quen với một phom quần mới.',
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      'Đọc câu chuyện bộ sưu tập',
                      outlined: true,
                      onPressed: () => context.go('/collections'),
                    ),
                  ],
                );
                return c.maxWidth < 850
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading,
                          const SizedBox(height: 24),
                          details,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: heading),
                          const SizedBox(width: 64),
                          Expanded(child: details),
                        ],
                      );
              },
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.action,
    this.onAction,
  });
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) => SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 20,
        runSpacing: 12,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.display(c.maxWidth < 600 ? 28 : 36)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      subtitle!,
                      style: T.body.copyWith(color: T.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (action != null)
            TextButton.icon(
              onPressed: onAction,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.north_east, size: 16),
              label: Text(action!),
            ),
        ],
      ),
    ),
  );
}
