import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/motion_widgets.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/store_content.dart';
import '../../domain/catalog.dart';

/// Text remains legible independently of the campaign image selected in CMS.
class HomeHero extends StatelessWidget {
  const HomeHero({super.key, required this.remote, this.product});
  final bool remote;
  final Product? product;

  @override
  Widget build(BuildContext context) => PageBody(
    vertical: MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 800;
        final words = Padding(
          padding: EdgeInsets.all(compact ? 28 : 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Tủ đồ đương đại', style: T.body.copyWith(color: T.soft)),
              const SizedBox(height: 24),
              StoreContentText(
                field: 'banner',
                fallback: 'Mặc theo\ncách bạn.',
                style: T
                    .display(
                      compact ? 46 : (constraints.maxWidth * .05).clamp(52, 80),
                    )
                    .copyWith(color: T.surface),
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  'Phom dáng giản dị. Sắc màu có chiều sâu. Những thiết kế để bạn thoải mái là chính mình.',
                  style: T.body.copyWith(color: T.soft, height: 1.8),
                ),
              ),
              const SizedBox(height: 32),
              AppButton(
                'Khám phá bộ sưu tập',
                light: true,
                icon: Icons.arrow_outward_rounded,
                onPressed: () => context.go('/shop'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: T.surface,
                  overlayColor: T.surface.withValues(alpha: .12),
                ),
                onPressed: () => context.go('/ai-stylist'),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Tìm phong cách cùng AI'),
              ),
              if (!compact) ...[
                const SizedBox(height: 48),
                Text(
                  'Thiết kế mới từ WEARLY',
                  style: T.small.copyWith(color: T.soft),
                ),
              ],
            ],
          ),
        );
        final photo = Stack(
          fit: StackFit.expand,
          children: [
            InteractivePhoto(
              onTap: () => context.go(
                product != null
                    ? '/products/${product!.slug}'
                    : remote
                    ? '/shop'
                    : '/products/nep-2',
              ),
              child: remote && product == null
                  ? const Center(
                      child: Icon(
                        Icons.checkroom_outlined,
                        color: T.muted,
                        size: 48,
                      ),
                    )
                  : FashionImage(
                      product?.image ?? 'assets/images/black-dress.jpg',
                      label:
                          product?.name ?? 'Thiết kế trong bộ sưu tập WEARLY',
                      fit: BoxFit.contain,
                    ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: T.surface.withValues(alpha: .96),
                    borderRadius: T.radius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            product?.name ?? 'Khám phá thiết kế',
                            style: T.body.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.arrow_outward_rounded,
                          color: T.accent,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        return ClipRRect(
          borderRadius: T.heroRadius,
          child: ColoredBox(
            color: T.accentDeep,
            child: compact
                ? Column(
                    children: [
                      SizedBox(width: double.infinity, child: words),
                      AspectRatio(aspectRatio: 4 / 5, child: photo),
                    ],
                  )
                : Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: (constraints.maxWidth * .46).clamp(
                                  560,
                                  700,
                                ),
                              ),
                              child: words,
                            ),
                          ),
                          const Spacer(flex: 6),
                        ],
                      ),
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: constraints.maxWidth * 5 / 11,
                        right: 0,
                        child: photo,
                      ),
                    ],
                  ),
          ),
        );
      },
    ),
  );
}
