import '../../core/widgets/promotion_price.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/purchase_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/commerce_state.dart';
import '../../app/remote_route_gate.dart';
import 'commerce_feedback.dart';
import '../../app/config.dart';
import '../../app/providers.dart';
import '../../app/remote_wishlist.dart';
import '../../core/design/tokens.dart';
import '../../core/design/motion.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../../data/remote_payments.dart';

class CartPage extends ConsumerStatefulWidget {
  const CartPage({super.key, this.compact = false});
  final bool compact;
  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  bool get compact => widget.compact;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = ref.read(commerceProvider);
      if (store.remote &&
          store.signedIn &&
          store.cartState.loaded &&
          store.cartState.pending == 0 &&
          !store.cart.locked) {
        store.refreshCart();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(commerceProvider);
    if (cart.requiresLogin) {
      return LoginRequired(
        next: '/cart',
        beforeNavigate: compact ? () => Navigator.pop(context) : null,
      );
    }
    if (cart.cartState.needsFeedback) {
      return CommerceFeedback(cart.cartState, onRetry: cart.refreshCart);
    }
    final total = cart.cart.subtotal;
    // The server may already have turned the cart into the unresolved order.
    if (cart.items.isEmpty && cart.checkoutPending) {
      return StatePanel(
        title: 'Đơn vừa đặt đang chờ xác nhận',
        message:
            'Chưa nhận được kết quả của lần đặt hàng trước. Kiểm tra lại đơn đó trước khi mua tiếp để tránh tạo đơn trùng.',
        icon: Icons.receipt_long_outlined,
        action: AppButton(
          'Kiểm tra đơn vừa đặt',
          onPressed: () {
            if (compact) Navigator.pop(context);
            context.go('/checkout');
          },
        ),
      );
    }
    if (cart.items.isEmpty) {
      return StatePanel(
        title: 'Tủ đồ đang chờ bạn.',
        message:
            'Giỏ hàng chưa có sản phẩm. Bắt đầu với một thiết kế bạn yêu thích.',
        icon: Icons.shopping_bag_outlined,
        action: AppButton(
          'Khám phá cửa hàng',
          onPressed: () {
            if (compact) {
              Navigator.pop(context);
            }
            context.go('/shop');
          },
        ),
      );
    }
    final lines = Column(
      children: [
        for (final item in cart.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: compact ? 70 : 90,
                      height: compact ? 95 : 120,
                      child: FashionImage(item.image, label: item.name),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              if (compact) {
                                Navigator.pop(context);
                              }
                              context.go('/products/${item.slug}');
                            },
                            child: Text(
                              item.name,
                              style: T.body.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('${item.color} / ${item.size}', style: T.small),
                          const SizedBox(height: 8),
                          PromotionPrice(
                            price: item.unitPrice,
                            original: item.originalUnitPrice,
                            name: item.promotionName,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Xóa ${item.name}',
                      onPressed: cart.cart.locked
                          ? null
                          : () async {
                              try {
                                await cart.remove(item.sku);
                              } catch (e) {
                                if (context.mounted) toast(context, '$e');
                              }
                            },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    QuantitySelector(
                      enabled: !cart.cart.locked,
                      value: item.quantity,
                      max: item.stock,
                      onChanged: (v) async {
                        try {
                          await cart.update(item.sku, v);
                        } catch (e) {
                          if (context.mounted) {
                            toast(context, '$e');
                          }
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () async {
                        if (cart.remote) {
                          final wishlist = ref.read(remoteWishlistProvider);
                          try {
                            final product = await ref
                                .read(productRepositoryProvider)
                                .bySlug(item.slug);
                            if (product == null) {
                              throw StateError('Sản phẩm không còn mở bán.');
                            }
                            await wishlist.save(product.id);
                            if (context.mounted) {
                              toast(context, 'Đã lưu vào danh sách yêu thích.');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              toast(context, wishlist.error ?? '$e');
                            }
                          }
                          return;
                        }
                        ref
                            .read(wishlistProvider.notifier)
                            .toggle(item.slug.replaceFirst('nep-', 'p'));
                        toast(context, 'Đã cập nhật danh sách yêu thích.');
                      },
                      child: const Text('Lưu yêu thích'),
                    ),
                    Text(
                      money(item.total),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const Divider(),
              ],
            ),
          ),
      ],
    );
    final summary = CartSummary(
      automaticSavings: cart.items.fold<int>(
        0,
        (sum, i) =>
            sum +
            (i.discounted
                ? (i.originalUnitPrice! - i.unitPrice) * i.quantity
                : 0),
      ),
      remote: cart.remote,
      subtotal: total,
      shipping: total >= BrandConfig.freeShippingAt
          ? 0
          : BrandConfig.shippingFee,
      action: AppButton(
        'Tiến hành đặt hàng',
        onPressed: () {
          if (compact) {
            Navigator.pop(context);
          }
          context.go('/checkout');
        },
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) const PurchaseProgress(current: 0),
        Text('Giỏ hàng của bạn', style: T.display(compact ? 28 : 40)),
        const SizedBox(height: 12),
        Text(
          '${cart.count} sản phẩm · ${cart.remote ? 'Đã lưu vào tài khoản' : 'Dữ liệu trong phiên demo'}',
          style: T.small,
        ),
        const SizedBox(height: 32),
        if (cart.remote)
          TextButton.icon(
            onPressed: cart.cart.locked ? null : cart.refreshCart,
            icon: const Icon(Icons.refresh),
            label: const Text('Cập nhật giỏ hàng'),
          ),
        if (cart.checkoutPending)
          const DemoNotice(
            text:
                'Đơn vừa đặt đang chờ xác nhận kết quả. Tiếp tục đặt hàng để kiểm tra lại, tránh tạo thêm đơn.',
          ),
        LayoutBuilder(
          builder: (_, c) => c.maxWidth < 850
              ? Column(children: [lines, const SizedBox(height: 24), summary])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: lines),
                    const SizedBox(width: 64),
                    Expanded(flex: 4, child: summary),
                  ],
                ),
        ),
      ],
    );
    return compact
        ? Padding(padding: const EdgeInsets.all(24), child: content)
        : PageBody(child: content);
  }
}

class CartSummary extends StatelessWidget {
  const CartSummary({
    super.key,
    required this.subtotal,
    required this.shipping,
    this.action,
    this.remote = false,
    this.paymentMethod = 'cod',
    this.discount = 0,
    this.couponCode,
    this.automaticSavings = 0,
  });
  final int subtotal, shipping;
  final Widget? action;
  final bool remote;
  final String paymentMethod;
  final int discount;
  final int automaticSavings;
  final String? couponCode;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: T.canvas,
      border: Border.all(color: T.line),
      borderRadius: T.panelRadius,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tóm tắt đơn hàng', style: T.display(24)),
        const SizedBox(height: 24),
        _line('Tạm tính', money(subtotal)),
        if (automaticSavings > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Đã bao gồm ưu đãi tự động: tiết kiệm ${money(automaticSavings)}',
              style: T.small.copyWith(color: T.accent),
            ),
          ),
        const SizedBox(height: 16),
        _line('Giao hàng', shipping == 0 ? 'Miễn phí' : money(shipping)),
        const Divider(),
        if (couponCode != null) ...[
          _line('Khuyến mãi $couponCode', '-${money(discount)}'),
          const SizedBox(height: 16),
        ],
        _line('Tổng cộng', money(subtotal + shipping - discount), strong: true),
        const SizedBox(height: 12),
        Text(
          remote
              ? (paymentMethod == 'free'
                    ? 'Không cần thanh toán.'
                    : onlinePaymentProviders.contains(paymentMethod)
                    ? '${paymentProviderName(paymentMethod)} sandbox: thanh toán thử nghiệm. Kiểm tra kết quả trong chi tiết đơn hàng.'
                    : 'Thanh toán COD khi nhận hàng. Tổng tiền được xác nhận khi tạo đơn.')
              : 'Giá và phí vận chuyển mô phỏng, không thu tiền.',
          style: T.small,
        ),
        if (action != null) ...[
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: action!),
        ],
      ],
    ),
  );
  Widget _line(String label, String value, {bool strong = false}) => Row(
    children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            fontSize: strong ? 18 : 14,
          ),
        ),
      ),
    ],
  );
}

void showCartDrawer(BuildContext context) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Đóng giỏ hàng',
  transitionDuration: Motion.duration(context),
  transitionBuilder: (c, animation, secondaryAnimation, child) =>
      SlideTransition(
        position: animation.drive(
          Tween(
            begin: const Offset(.12, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Motion.curve)),
        ),
        child: FadeTransition(opacity: animation, child: child),
      ),
  pageBuilder: (c, _, _) => Align(
    alignment: Alignment.centerRight,
    child: Material(
      color: T.surface,
      child: SizedBox(
        width: MediaQuery.sizeOf(c).width.clamp(320, 520),
        height: double.infinity,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Đóng giỏ hàng',
                  onPressed: () => Navigator.pop(c),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Expanded(
                child: SingleChildScrollView(child: CartPage(compact: true)),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
