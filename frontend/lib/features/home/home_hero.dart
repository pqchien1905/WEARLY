import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/motion.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/store_content.dart';
import '../../domain/catalog.dart';

/// Campaign hero. Text stays legible independently of the CMS image; every
/// effect is finite or pointer-driven, and all of it is skipped when the
/// platform asks for reduced motion.
class HomeHero extends StatefulWidget {
  const HomeHero({super.key, required this.remote, this.product});
  final bool remote;
  final Product? product;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero>
    with SingleTickerProviderStateMixin {
  late final entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// Pointer position over the image panel, -1..1 on both axes.
  Offset tilt = Offset.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      entrance.value = 1;
    } else if (entrance.isDismissed) {
      entrance.forward();
    }
  }

  @override
  void dispose() {
    entrance.dispose();
    super.dispose();
  }

  String get productPath => widget.product != null
      ? '/products/${widget.product!.slug}'
      : widget.remote
      ? '/shop'
      : '/products/nep-2';

  /// Fade + rise for the [index]-th element of the staggered entrance.
  Widget reveal(int index, Widget child, {double rise = 24}) {
    final start = (index * .09).clamp(0.0, .6);
    final curve = CurvedAnimation(
      parent: entrance,
      curve: Interval(
        start,
        math.min(start + .5, 1),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, rise * (1 - curve.value)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageBody(
    vertical: MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 800;
        final words = _words(context, constraints, compact);
        final photo = _photo(context, compact);
        return ClipRRect(
          borderRadius: T.heroRadius,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF52293D), T.accentDeep, Color(0xFF2E1622)],
              ),
            ),
            child: Stack(
              children: [
                // Soft glows give the flat plum depth without competing with text.
                const Positioned(
                  left: -160,
                  top: -200,
                  child: _Glow(size: 520, color: Color(0x40B97A98)),
                ),
                const Positioned(
                  left: 120,
                  bottom: -260,
                  child: _Glow(size: 480, color: Color(0x2EE4B8CC)),
                ),
                if (compact)
                  Column(
                    children: [
                      SizedBox(width: double.infinity, child: words),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: AspectRatio(aspectRatio: 4 / 5, child: photo),
                      ),
                    ],
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: (constraints.maxWidth * .46).clamp(
                              580,
                              720,
                            ),
                          ),
                          child: words,
                        ),
                      ),
                      const Spacer(flex: 6),
                    ],
                  ),
                  Positioned(
                    top: 14,
                    bottom: 14,
                    left: constraints.maxWidth * 5 / 11,
                    right: 14,
                    child: photo,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _words(
    BuildContext context,
    BoxConstraints constraints,
    bool compact,
  ) {
    const onDark = Color(0xFFD9C3CE);
    // The largest size; longer admin-written banners step down from here.
    final maxSize = compact
        ? (constraints.maxWidth * .11).clamp(34.0, 46.0)
        : (constraints.maxWidth * .048).clamp(48.0, 72.0);
    final headline = T
        .display(maxSize)
        .copyWith(
          color: T.surface,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 28 : 56,
        compact ? 36 : 56,
        compact ? 28 : 40,
        compact ? 28 : 48,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          reveal(0, const _Eyebrow('Bộ sưu tập mới')),
          SizedBox(height: compact ? 24 : 32),
          reveal(
            1,
            StoreContentText(
              field: 'banner',
              fallback: 'Mặc theo\ncách bạn.',
              style: headline,
              builder: (text) => BalancedHeadline(
                text,
                style: headline,
                minSize: compact ? 30 : 40,
              ),
            ),
            rise: 36,
          ),
          const SizedBox(height: 20),
          reveal(2, _AccentRule(progress: entrance, width: compact ? 56 : 72)),
          const SizedBox(height: 22),
          reveal(
            3,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Text(
                'Phom dáng giản dị. Sắc màu có chiều sâu. Những thiết kế để bạn thoải mái là chính mình.',
                style: T.body.copyWith(
                  color: onDark,
                  height: 1.8,
                  fontSize: compact ? 14 : 15,
                ),
              ),
            ),
          ),
          SizedBox(height: compact ? 28 : 36),
          reveal(
            4,
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppButton(
                  'Khám phá bộ sưu tập',
                  light: true,
                  icon: Icons.arrow_outward_rounded,
                  onPressed: () => context.go('/shop'),
                ),
                _GhostButton(
                  label: 'Tìm phong cách cùng AI',
                  icon: Icons.auto_awesome_outlined,
                  onPressed: () => context.go('/ai-stylist'),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 56),
            reveal(
              5,
              const Wrap(
                spacing: 28,
                runSpacing: 12,
                children: [
                  _Feature(Icons.auto_awesome_outlined, 'AI Stylist'),
                  _Feature(Icons.photo_camera_outlined, 'Phòng thử ảo'),
                  _Feature(
                    Icons.local_shipping_outlined,
                    'Thanh toán khi nhận',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _photo(BuildContext context, bool compact) {
    final product = widget.product;
    final reduced = Motion.reduced(context);
    final image = widget.remote && product == null
        ? const Center(
            child: Icon(Icons.checkroom_outlined, color: T.muted, size: 48),
          )
        : FashionImage(
            product?.image ?? 'assets/images/black-dress.jpg',
            label: product?.name ?? 'Thiết kế trong bộ sưu tập WEARLY',
            fit: BoxFit.contain,
            alignment: Alignment.center,
          );
    // Pointer parallax: the garment and the watermark drift in opposite
    // directions, which reads as depth. Settles immediately on exit.
    final drift = reduced ? Offset.zero : tilt;
    return reveal(
      2,
      rise: 0,
      ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        child: LayoutBuilder(
          builder: (context, panel) => MouseRegion(
            onHover: (event) {
              if (reduced ||
                  !panel.hasBoundedWidth ||
                  !panel.hasBoundedHeight) {
                return;
              }
              final size = panel.biggest;
              final local = event.localPosition;
              setState(
                () => tilt = Offset(
                  (local.dx / size.width * 2 - 1).clamp(-1, 1),
                  (local.dy / size.height * 2 - 1).clamp(-1, 1),
                ),
              );
            },
            onExit: (_) => setState(() => tilt = Offset.zero),
            child: Material(
              color: T.photo,
              child: InkWell(
                onTap: () => context.go(productPath),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, -.15),
                          radius: .95,
                          colors: [Color(0xFFFFFFFF), Color(0xFFEDE6EA)],
                        ),
                      ),
                    ),
                    _Drift(
                      offset: drift * -10,
                      child: Center(
                        child: FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              'WEARLY',
                              style: T
                                  .display(160)
                                  .copyWith(
                                    color: T.accent.withValues(alpha: .06),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 8,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        compact ? 48 : 56,
                        24,
                        compact ? 96 : 104,
                      ),
                      child: _Drift(
                        offset: drift * 14,
                        scale: drift == Offset.zero ? 1 : 1.03,
                        child: ScaleTransition(
                          scale: Tween(begin: 1.06, end: 1.0).animate(
                            CurvedAnimation(
                              parent: entrance,
                              curve: const Interval(
                                .1,
                                .85,
                                curve: Curves.easeOutCubic,
                              ),
                            ),
                          ),
                          child: RepaintBoundary(child: image),
                        ),
                      ),
                    ),
                    const Positioned(left: 20, top: 20, child: _Badge('Mới')),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: reveal(
                        6,
                        IgnorePointer(
                          child: _ProductCard(
                            product: product,
                            hovered: drift != Offset.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Drift extends StatelessWidget {
  const _Drift({required this.offset, required this.child, this.scale = 1});
  final Offset offset;
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Offset>(
    tween: Tween(end: offset),
    duration: Motion.duration(context, const Duration(milliseconds: 420)),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, value, child) => Transform.translate(
      offset: value,
      child: AnimatedScale(
        scale: scale,
        duration: Motion.duration(context, Motion.image),
        curve: Motion.curve,
        child: child,
      ),
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: T.surface.withValues(alpha: .08),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      border: Border.all(color: T.surface.withValues(alpha: .18)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 16, 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFE9B9CE),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: T.small.copyWith(
                color: T.surface,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Thin rule that draws itself left-to-right during the entrance.
class _AccentRule extends StatelessWidget {
  const _AccentRule({required this.progress, required this.width});
  final Animation<double> progress;
  final double width;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    builder: (context, _) => Container(
      width:
          width *
          Curves.easeOutCubic.transform(
            ((progress.value - .25) / .5).clamp(0.0, 1.0),
          ),
      height: 2,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(2)),
        gradient: LinearGradient(
          colors: [Color(0xFFE9B9CE), Color(0x00E9B9CE)],
        ),
      ),
    ),
  );
}

class _GhostButton extends StatefulWidget {
  const _GhostButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_GhostButton> createState() => _GhostButtonState();
}

class _GhostButtonState extends State<_GhostButton> {
  bool active = false;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: widget.onPressed,
    onHover: (value) => setState(() => active = value),
    onFocusChange: (value) => setState(() => active = value),
    style: OutlinedButton.styleFrom(
      foregroundColor: T.surface,
      backgroundColor: T.surface.withValues(alpha: active ? .12 : 0),
      side: BorderSide(color: T.surface.withValues(alpha: active ? .7 : .35)),
      overlayColor: T.surface.withValues(alpha: .08),
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: const RoundedRectangleBorder(borderRadius: T.radius),
    ),
    icon: AnimatedRotation(
      turns: active && !Motion.reduced(context) ? .08 : 0,
      duration: Motion.duration(context),
      child: Icon(widget.icon, size: 18),
    ),
    label: Text(widget.label),
  );
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: T.surface.withValues(alpha: .08),
          border: Border.all(color: T.surface.withValues(alpha: .14)),
        ),
        child: Icon(icon, size: 15, color: const Color(0xFFE9B9CE)),
      ),
      const SizedBox(width: 10),
      Text(
        label,
        style: T.small.copyWith(
          color: const Color(0xFFD9C3CE),
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: T.accentDeep,
      borderRadius: BorderRadius.all(Radius.circular(999)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: T.small.copyWith(
          color: T.surface,
          fontWeight: FontWeight.w600,
          letterSpacing: .6,
        ),
      ),
    ),
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.hovered});
  final Product? product;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final product = this.product;
    final duration = Motion.duration(context);
    return AnimatedContainer(
      duration: duration,
      curve: Motion.curve,
      decoration: BoxDecoration(
        color: T.surface.withValues(alpha: .94),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: T.surface),
        boxShadow: [
          BoxShadow(
            color: T.accentDeep.withValues(alpha: hovered ? .18 : .10),
            blurRadius: hovered ? 32 : 20,
            offset: Offset(0, hovered ? 14 : 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'THIẾT KẾ NỔI BẬT',
                  style: T.small.copyWith(
                    color: T.accent,
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product?.name ?? 'Khám phá thiết kế',
                  style: T.body.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (product != null && product.variants.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    money(product.price),
                    style: T.small.copyWith(color: T.muted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          AnimatedContainer(
            duration: duration,
            curve: Motion.curve,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: hovered ? T.accent : T.soft,
              shape: BoxShape.circle,
            ),
            child: AnimatedRotation(
              turns: hovered ? .125 : 0,
              duration: duration,
              curve: Motion.curve,
              child: Icon(
                Icons.arrow_outward_rounded,
                color: hovered ? T.surface : T.accent,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A headline that steps its size down until it fits in [maxLines], then
/// narrows to the tightest width with the same line count so the last line
/// is not left with a single word.
class BalancedHeadline extends StatelessWidget {
  const BalancedHeadline(
    this.text, {
    super.key,
    required this.style,
    this.minSize = 36,
    this.maxLines = 3,
  });
  final String text;
  final TextStyle style;
  final double minSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      final maxWidth = constraints.maxWidth;
      int lines(TextStyle s, double width) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: s),
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: width);
        final count = painter.computeLineMetrics().length;
        painter.dispose();
        return count;
      }

      var fitted = style;
      if (maxWidth.isFinite) {
        for (var size = style.fontSize ?? 48; size >= minSize; size -= 2) {
          fitted = style.copyWith(fontSize: size);
          if (lines(fitted, maxWidth) <= maxLines) break;
        }
      }
      var width = maxWidth;
      if (maxWidth.isFinite) {
        final target = lines(fitted, maxWidth);
        if (target > 1) {
          var low = maxWidth * .55, high = maxWidth;
          for (var i = 0; i < 12; i++) {
            final mid = (low + high) / 2;
            if (lines(fitted, mid) > target) {
              low = mid;
            } else {
              high = mid;
            }
          }
          width = (high + 1).clamp(0, maxWidth);
        }
      }
      // Align loosens a tight parent width so the narrowed box applies.
      return Align(
        alignment: AlignmentDirectional.topStart,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Text(text, style: fitted),
        ),
      );
    },
  );
}
