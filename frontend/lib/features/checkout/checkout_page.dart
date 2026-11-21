import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/commerce_state.dart';
import '../../app/account_state.dart';
import '../../app/account_details.dart';
import '../../app/config.dart';
import '../../app/payment_providers.dart';
import '../../app/promotion_providers.dart';
import '../../data/remote_payments.dart';
import '../../data/remote_promotions.dart';
import 'payment_panel.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/purchase_progress.dart';
import '../../domain/commerce.dart';
import '../cart/cart_page.dart';
import '../cart/commerce_feedback.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});
  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      address = TextEditingController(),
      coupon = TextEditingController();
  bool express = false, busy = false, confirmed = false;
  String payment = 'COD demo';
  String? error, addressId;
  PromotionQuote? quote;
  bool quoting = false;
  @override
  void initState() {
    super.initState();
    final pending = ref.read(commerceProvider).pendingCheckout;
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
    if (ref.read(commerceProvider).remote) payment = 'COD';
    if (pending != null) {
      name.text = pending.draft.name;
      email.text = pending.draft.email;
      phone.text = pending.draft.phone;
      address.text = pending.draft.address;
      addressId = pending.draft.addressId;
      express = pending.draft.express;
      payment = pending.draft.payment;
      coupon.text = pending.draft.couponCode ?? '';
      confirmed = true;
    }
  }

  @override
  void dispose() {
    for (final c in [name, email, phone, address, coupon]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    final store = ref.read(commerceProvider);
    final retry = store.checkoutPending;
    final applied =
        quote?.cartVersion == store.cartVersion &&
            quote?.subtotal == store.cart.subtotal
        ? quote
        : null;
    if (!retry &&
        store.remote &&
        coupon.text.trim().isNotEmpty &&
        applied == null) {
      setState(
        () => error =
            'Hãy áp dụng lại hoặc xóa mã khuyến mãi trước khi đặt hàng.',
      );
      return;
    }
    if (!retry && !form.currentState!.validate()) {
      return;
    }
    if (!retry &&
        store.remote &&
        !(ref
                .read(accountDetailsProvider)
                .asData
                ?.value
                .addresses
                .any((a) => a.id == addressId) ??
            false)) {
      setState(() => error = 'Hãy chọn một địa chỉ đã lưu trước khi đặt hàng.');
      return;
    }
    if (!retry && !store.remote && !confirmed) {
      setState(
        () => error = store.remote
            ? 'Vui lòng xác nhận thông tin nhận hàng và phương thức thanh toán.'
            : 'Xác nhận đây là đơn hàng mô phỏng trước khi tiếp tục.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final order = await ref
          .read(commerceProvider)
          .checkout(
            CheckoutDraft(
              name: name.text.trim(),
              email: email.text.trim(),
              phone: phone.text.trim(),
              address: address.text.trim(),
              addressId: addressId,
              express: express,
              payment: payment,
              paymentMethod: paymentMethodFor(payment),
              couponCode: applied?.code,
              discount: applied?.discount ?? 0,
            ),
          );
      // Online methods open the gateway in a new tab; this tab moves to the
      // order page, which watches the payment until it is confirmed.
      if (store.remote &&
          onlinePaymentProviders.contains(paymentMethodFor(payment))) {
        try {
          final state = await ref
              .read(paymentRepositoryProvider)
              .start(order.id);
          final url = state.checkoutUrl;
          if (url != null && mounted) {
            // Gateway in a new tab; this tab shows the order and watches it.
            ref.read(paymentLauncherProvider)(url);
          }
        } catch (_) {
          // The order exists; its page offers "Thanh toán ngay" to retry.
        }
      }
      if (mounted) {
        context.go('/checkout/success/${order.id}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void selectAddress(DeliveryAddress selected) {
    final profile = ref.read(accountProvider);
    setState(() {
      addressId = selected.id;
      name.text = selected.recipient;
      phone.text = selected.phone;
      address.text = selected.address;
      if (email.text.isEmpty && profile != null) email.text = profile.email;
    });
  }

  Future<void> applyCoupon() async {
    if (quoting) return;
    final store = ref.read(commerceProvider),
        version = ref.read(commerceProvider).cartVersion;
    if (version == null || coupon.text.trim().isEmpty) return;
    setState(() {
      quoting = true;
      error = null;
      quote = null;
    });
    try {
      final result = await ref
          .read(promotionRepositoryProvider)
          .preview(coupon.text, express: express, cartVersion: version);
      if (!mounted) return;
      if (store.cartVersion != version ||
          result.subtotal != store.cart.subtotal) {
        setState(
          () => error = 'Giỏ hàng đã thay đổi. Vui lòng áp dụng lại mã.',
        );
      } else {
        setState(() => quote = result);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => quoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(commerceProvider);
    if (cart.cartState.needsFeedback) {
      return CommerceFeedback(cart.cartState, onRetry: cart.refreshCart);
    }
    final remote = cart.remote;
    final methods = remote ? ref.watch(paymentMethodsProvider) : null;
    final onlineChoices = checkoutPaymentMethods.values
        .where(
          (m) => m != 'cod' && (methods?.asData?.value.enabled(m) ?? false),
        )
        .length;
    final locked = busy || cart.checkoutPending || quoting;
    final applied =
        quote?.cartVersion == cart.cartVersion &&
            quote?.subtotal == cart.cart.subtotal
        ? quote
        : null;
    final discount =
        cart.pendingCheckout?.draft.discount ?? applied?.discount ?? 0;
    final couponCode = cart.pendingCheckout?.draft.couponCode ?? applied?.code;
    final profile = ref.watch(accountProvider);
    final savedAddresses = profile == null
        ? null
        : ref.watch(accountDetailsProvider);
    // An unresolved checkout stays re-checkable even after the server emptied
    // the cart into the (possibly committed) order.
    if (cart.items.isEmpty && !cart.checkoutPending) {
      return StatePanel(
        title: 'Giỏ hàng chưa có sản phẩm',
        message: 'Thêm một sản phẩm để bắt đầu đặt hàng.',
        action: AppButton('Về cửa hàng', onPressed: () => context.go('/shop')),
      );
    }
    final subtotal = cart.pendingCheckout?.subtotal ?? cart.cart.subtotal;
    final shipping =
        cart.pendingCheckout?.shipping ??
        (express
            ? BrandConfig.expressFee
            : subtotal >= BrandConfig.freeShippingAt
            ? 0
            : BrandConfig.shippingFee);
    final paymentChoices = remote
        ? [
            for (final entry in checkoutPaymentMethods.entries)
              if (entry.value == 'cod' ||
                  payment == entry.key ||
                  (methods?.asData?.value.enabled(entry.value) ?? false))
                entry.key,
          ]
        : ['COD demo', 'Thẻ / ví điện tử demo'];
    final standardFee = subtotal >= BrandConfig.freeShippingAt
        ? 0
        : BrandConfig.shippingFee;
    final fields = Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!remote)
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: DemoNotice(
                text:
                    'Đặt hàng demo. Không có thanh toán hoặc giao hàng thật. Bạn có thể dùng thông tin minh họa.',
              ),
            ),
          if (cart.checkoutPending)
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: DemoNotice(
                text:
                    'Chưa xác định được kết quả đặt hàng. Bấm “Kiểm tra lại đơn vừa đặt” để xác nhận yêu cầu cũ, tránh tạo đơn trùng.',
              ),
            ),
          _SectionTitle(
            'Địa chỉ nhận hàng',
            trailing: remote && profile != null
                ? TextButton(
                    onPressed: locked
                        ? null
                        : () => context.go('/account/addresses'),
                    child: const Text('Quản lý sổ địa chỉ'),
                  )
                : null,
          ),
          if (profile != null)
            savedAddresses!.when(
              data: (details) {
                if (details.addresses.isEmpty) {
                  return remote
                      ? _EmptyAddress(
                          onAdd: () => context.go('/account/addresses'),
                        )
                      : const SizedBox.shrink();
                }
                // The live store ships only to saved addresses, so pick one;
                // the demo keeps free-form fields and waits for a choice.
                if (remote &&
                    !locked &&
                    !details.addresses.any((a) => a.id == addressId)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) selectAddress(details.addresses.first);
                  });
                }
                return Column(
                  children: [
                    for (final a in details.addresses)
                      _ChoiceTile(
                        selected: a.id == addressId,
                        onTap: locked ? null : () => selectAddress(a),
                        icon: Icons.location_on_outlined,
                        title: '${a.recipient} · ${a.phone}',
                        subtitle: a.address,
                        badge: a.label,
                      ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Đang tải sổ địa chỉ…', style: T.small),
              ),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(accountDetailsProvider),
                child: const Text('Tải lại sổ địa chỉ'),
              ),
            ),
          if (!remote) ...[
            if (profile != null) const SizedBox(height: 8),
            AppField(
              label: 'Họ và tên',
              readOnly: locked,
              controller: name,
              validator: requiredValue,
            ),
            const SizedBox(height: 16),
            AppField(
              label: 'Email',
              readOnly: locked,
              controller: email,
              validator: emailValidator,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            AppField(
              label: 'Số điện thoại',
              readOnly: locked,
              controller: phone,
              keyboardType: TextInputType.phone,
              validator: (v) => RegExp(r'^0\d{9}$').hasMatch(v?.trim() ?? '')
                  ? null
                  : 'Nhập 10 chữ số, bắt đầu bằng 0.',
            ),
            const SizedBox(height: 16),
            AppField(
              label: 'Địa chỉ đầy đủ',
              readOnly: locked,
              controller: address,
              maxLines: 2,
              validator: (v) => (v?.trim().length ?? 0) >= 8
                  ? null
                  : 'Nhập số nhà, đường và tỉnh/thành.',
            ),
          ],
          const SizedBox(height: 32),
          const _SectionTitle('Hình thức giao hàng'),
          _ChoiceTile(
            selected: !express,
            onTap: locked
                ? null
                : () => setState(() {
                    express = false;
                    quote = null;
                  }),
            icon: Icons.local_shipping_outlined,
            title: 'Giao tiêu chuẩn',
            subtitle: standardFee == 0
                ? 'Đơn của bạn được miễn phí giao hàng'
                : 'Miễn phí cho đơn từ ${money(BrandConfig.freeShippingAt)}',
            trailing: standardFee == 0 ? 'Miễn phí' : money(standardFee),
          ),
          _ChoiceTile(
            selected: express,
            onTap: locked
                ? null
                : () => setState(() {
                    express = true;
                    quote = null;
                  }),
            icon: Icons.bolt_rounded,
            title: 'Giao nhanh',
            subtitle: remote
                ? 'Ưu tiên xử lý; cửa hàng xác nhận lịch giao khi tiếp nhận đơn'
                : 'Thời gian giao minh họa: 1–2 ngày',
            trailing: money(BrandConfig.expressFee),
          ),
          const SizedBox(height: 32),
          const _SectionTitle('Phương thức thanh toán'),
          for (final p in paymentChoices)
            _ChoiceTile(
              selected: payment == p,
              onTap: locked ? null : () => setState(() => payment = p),
              icon: _paymentIcon(paymentMethodFor(p)),
              title: _paymentTitle(p, remote),
              subtitle: _paymentSubtitle(paymentMethodFor(p), remote),
            ),
          if (remote && onlineChoices == 0 && methods?.isLoading == true)
            const Text('Đang kiểm tra thanh toán trực tuyến…', style: T.small),
          if (remote) ...[
            const SizedBox(height: 32),
            const _SectionTitle('Ưu đãi'),
            TextFormField(
              controller: coupon,
              readOnly: locked,
              maxLength: 32,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() => quote = null),
              onFieldSubmitted: (_) => locked ? null : applyCoupon(),
              decoration: InputDecoration(
                labelText: 'Mã khuyến mãi',
                hintText: 'Nhập mã nếu có',
                counterText: '',
                helperText: couponCode != null
                    ? 'Đã áp dụng mã $couponCode'
                    : null,
                suffixIcon: coupon.text.trim().isEmpty
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (couponCode == null)
                              TextButton(
                                onPressed: locked || quoting
                                    ? null
                                    : applyCoupon,
                                child: quoting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Áp dụng'),
                              ),
                            IconButton(
                              tooltip: 'Xóa mã',
                              onPressed: locked
                                  ? null
                                  : () => setState(() {
                                      coupon.clear();
                                      quote = null;
                                    }),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
          if (!remote) ...[
            const SizedBox(height: 20),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: locked
                  ? null
                  : (v) => setState(() => confirmed = v ?? false),
              title: const Text(
                'Tôi hiểu đây là đơn mô phỏng, không thanh toán thật.',
                style: T.body,
              ),
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(error!, style: const TextStyle(color: T.danger)),
            ),
        ],
      ),
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
      remote: remote,
      paymentMethod: paymentMethodFor(payment),
      discount: discount,
      couponCode: couponCode,
      subtotal: subtotal,
      shipping: shipping,
      action: AppButton(
        cart.checkoutPending
            ? 'Kiểm tra lại đơn vừa đặt'
            : remote
            ? (paymentMethodFor(payment) == 'cod'
                  ? 'Đặt hàng'
                  : 'Thanh toán với ${paymentProviderName(paymentMethodFor(payment))}')
            : 'Tạo đơn hàng demo',
        busy: busy,
        onPressed: quoting || (cart.cart.locked && !cart.checkoutPending)
            ? null
            : submit,
      ),
    );
    return PageBody(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PurchaseProgress(current: 1),
              Text(
                'Một bước nữa thôi.',
                style: T.display(
                  MediaQuery.sizeOf(context).width < 600 ? 32 : 40,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/cart'),
                child: const Text('Trở về giỏ hàng'),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (_, c) => c.maxWidth < 850
                    ? Column(
                        children: [
                          SurfacePanel(child: fields),
                          const SizedBox(height: 32),
                          summary,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 760,
                                ),
                                child: SurfacePanel(child: fields),
                              ),
                            ),
                          ),
                          const SizedBox(width: 64),
                          Expanded(
                            flex: 4,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 480,
                                ),
                                child: summary,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderSuccessPage extends ConsumerStatefulWidget {
  const OrderSuccessPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<OrderSuccessPage> createState() => _OrderSuccessPageState();
}

class _OrderSuccessPageState extends ConsumerState<OrderSuccessPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(commerceProvider).loadOrder(widget.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(commerceProvider);
    final id = widget.id;
    final loadState = store.detailState(id);
    if (loadState.needsFeedback) {
      return CommerceFeedback(loadState, onRetry: () => store.loadOrder(id));
    }
    final order = store.orders.where((o) => o.id == id).firstOrNull;
    final online =
        order != null &&
        store.remote &&
        onlinePaymentProviders.contains(order.paymentProvider);
    final awaitingPayment =
        online &&
        !const [
          'PAID',
          'PARTIALLY_REFUNDED',
          'REFUNDED',
        ].contains(order.paymentStatus);
    final links = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        if (order != null && store.remote)
          AppButton(
            'Xem đơn hàng',
            outlined: awaitingPayment,
            onPressed: () => context.go('/account/orders/$id'),
          ),
        AppButton(
          'Tiếp tục mua sắm',
          outlined: true,
          onPressed: () => context.go('/shop'),
        ),
      ],
    );
    return PageBody(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              StatePanel(
                title: order == null
                    ? (store.remote
                          ? 'Không tìm thấy đơn hàng'
                          : 'Không tìm thấy đơn trong phiên này')
                    : !store.remote
                    ? 'Đã tạo đơn demo $id'
                    : awaitingPayment
                    ? 'Đơn hàng ${order.displayCode} đã được tạo'
                    : 'Đặt hàng thành công',
                message: order == null
                    ? (store.remote
                          ? 'Kiểm tra lại mã đơn trong lịch sử tài khoản.'
                          : 'Dữ liệu demo được xóa khi tải lại trang.')
                    : !store.remote
                    ? 'Đơn hàng mô phỏng – chưa thanh toán thật'
                    : awaitingPayment
                    ? 'Hoàn tất thanh toán để cửa hàng xác nhận và chuẩn bị giao hàng.'
                    : online
                    ? 'Mã đơn ${order.displayCode}. Đã nhận thanh toán, cửa hàng sẽ sớm xác nhận đơn.'
                    : 'Mã đơn ${order.displayCode}. Bạn sẽ thanh toán khi nhận hàng; cửa hàng sẽ liên hệ xác nhận.',
                icon: awaitingPayment
                    ? Icons.receipt_long_outlined
                    : Icons.check_circle_outline,
                action: awaitingPayment ? null : links,
              ),
              if (online) PaymentPanel(key: ValueKey(order.id), order: order),
              if (awaitingPayment) links,
              if (order != null) ...[
                const SizedBox(height: 24),
                CartSummary(
                  automaticSavings: order.items.fold<int>(
                    0,
                    (sum, i) =>
                        sum +
                        (i.discounted
                            ? (i.originalUnitPrice! - i.unitPrice) * i.quantity
                            : 0),
                  ),
                  remote: store.remote,
                  paymentMethod: order.paymentProvider,
                  discount: order.discount,
                  couponCode: order.couponCode,
                  subtotal: order.subtotal,
                  shipping: order.shipping,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

IconData _paymentIcon(String method) => switch (method) {
  'cod' => Icons.payments_outlined,
  'vnpay' => Icons.qr_code_2_rounded,
  _ => Icons.account_balance_wallet_outlined,
};

String _paymentTitle(String label, bool remote) {
  if (!remote) return label;
  return switch (paymentMethodFor(label)) {
    'cod' => 'Thanh toán khi nhận hàng (COD)',
    'zalopay' => 'Ví ZaloPay',
    'momo' => 'Ví MoMo',
    'vnpay' => 'VNPay',
    _ => label,
  };
}

String? _paymentSubtitle(String method, bool remote) {
  if (!remote) return null;
  return method == 'cod'
      ? 'Trả tiền mặt cho nhân viên giao hàng'
      : 'Chuyển sang ${paymentProviderName(method)} để thanh toán · môi trường thử nghiệm';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: T.body.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Selectable card used for address, delivery and payment choices.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.badge,
  });
  final bool selected;
  final VoidCallback? onTap;
  final IconData icon;
  final String title;
  final String? subtitle, trailing, badge;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? T.soft : T.surface,
        shape: RoundedRectangleBorder(
          borderRadius: T.radius,
          side: BorderSide(
            color: selected ? T.accent : T.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? T.accent : T.controlLine,
                ),
                const SizedBox(width: 14),
                Icon(icon, size: 20, color: T.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: T.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (badge != null && badge!.isNotEmpty)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: T.canvas,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(999),
                                ),
                                border: Border.all(color: T.line),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                child: Text(badge!, style: T.small),
                              ),
                            ),
                        ],
                      ),
                      if (subtitle != null) Text(subtitle!, style: T.small),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    trailing!,
                    style: T.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _EmptyAddress extends StatelessWidget {
  const _EmptyAddress({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: T.radius,
      border: Border.all(color: T.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Bạn chưa có địa chỉ nhận hàng.', style: T.body),
        const SizedBox(height: 12),
        AppButton(
          'Thêm địa chỉ',
          icon: Icons.add_location_alt_outlined,
          outlined: true,
          onPressed: onAdd,
        ),
      ],
    ),
  );
}
