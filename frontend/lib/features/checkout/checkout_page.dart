import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/commerce_state.dart';
import '../../app/account_state.dart';
import '../../app/account_details.dart';
import '../../app/config.dart';
import '../../app/payment_providers.dart';
import 'payment_panel.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
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
      address = TextEditingController();
  bool express = false, busy = false, confirmed = false;
  String payment = 'COD demo';
  String? error, addressId;
  @override
  void initState() {
    super.initState();
    final pending = ref.read(commerceProvider).pendingCheckout;
    if (ref.read(commerceProvider).remote) payment = 'COD';
    if (pending != null) {
      name.text = pending.draft.name;
      email.text = pending.draft.email;
      phone.text = pending.draft.phone;
      address.text = pending.draft.address;
      addressId = pending.draft.addressId;
      express = pending.draft.express;
      payment = pending.draft.payment;
      confirmed = true;
    }
  }

  @override
  void dispose() {
    for (final c in [name, email, phone, address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    final store = ref.read(commerceProvider);
    final retry = store.checkoutPending;
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
    if (!retry && !confirmed) {
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
              paymentMethod: payment == 'VNPay sandbox' ? 'vnpay' : 'cod',
            ),
          );
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

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(commerceProvider);
    if (cart.cartState.needsFeedback) {
      return CommerceFeedback(cart.cartState, onRetry: cart.refreshCart);
    }
    final remote = cart.remote;
    final methods = remote ? ref.watch(paymentMethodsProvider) : null;
    final locked = busy || cart.checkoutPending;
    final profile = ref.watch(accountProvider);
    final savedAddresses = profile == null
        ? null
        : ref.watch(accountDetailsProvider);
    if (cart.items.isEmpty) {
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
    final fields = Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DemoNotice(
            text: remote
                ? 'Chọn địa chỉ đã lưu và phương thức thanh toán. VNPay sandbox là thanh toán thử nghiệm.'
                : 'Đặt hàng demo. Không có thanh toán hoặc giao hàng thật. Bạn có thể dùng thông tin minh họa.',
          ),
          if (cart.checkoutPending)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: DemoNotice(
                text:
                    'Chưa xác định được kết quả đặt hàng. Bấm “Kiểm tra lại đơn vừa đặt” để xác nhận yêu cầu cũ, tránh tạo đơn trùng.',
              ),
            ),
          const SizedBox(height: 28),
          Text('Thông tin nhận hàng', style: T.display(26)),
          const SizedBox(height: 24),
          if (profile != null) ...[
            savedAddresses!.when(
              data: (details) => details.addresses.isEmpty
                  ? TextButton.icon(
                      onPressed: () => context.go('/account/addresses'),
                      icon: const Icon(
                        Icons.add_location_alt_outlined,
                        size: 18,
                      ),
                      label: const Text('Thêm địa chỉ vào sổ'),
                    )
                  : DropdownButtonFormField<String>(
                      key: ValueKey(
                        details.addresses
                            .map((a) => '${a.id}:${a.label}')
                            .join('|'),
                      ),
                      isExpanded: true,
                      initialValue:
                          details.addresses.any((a) => a.id == addressId)
                          ? addressId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Chọn địa chỉ đã lưu',
                      ),
                      items: details.addresses
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.label} — ${a.recipient}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: locked
                          ? null
                          : (id) {
                              final selected = details.addresses.firstWhere(
                                (a) => a.id == id,
                              );
                              name.text = selected.recipient;
                              addressId = selected.id;
                              phone.text = selected.phone;
                              address.text = selected.address;
                              if (email.text.isEmpty) {
                                email.text = profile.email;
                              }
                              setState(() {});
                            },
                    ),
              loading: () => const Text('Đang tải sổ địa chỉ…', style: T.small),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(accountDetailsProvider),
                child: const Text('Tải lại sổ địa chỉ'),
              ),
            ),
            const SizedBox(height: 20),
          ],
          AppField(
            label: 'Họ và tên',
            readOnly: remote || locked,
            controller: name,
            validator: requiredValue,
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'Email',
            readOnly: remote || locked,
            controller: email,
            validator: emailValidator,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'Số điện thoại',
            readOnly: remote || locked,
            controller: phone,
            keyboardType: TextInputType.phone,
            validator: (v) => RegExp(r'^0\d{9}$').hasMatch(v?.trim() ?? '')
                ? null
                : 'Nhập 10 chữ số, bắt đầu bằng 0.',
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'Địa chỉ đầy đủ',
            readOnly: remote || locked,
            controller: address,
            maxLines: 2,
            validator: (v) => (v?.trim().length ?? 0) >= 8
                ? null
                : 'Nhập số nhà, đường và tỉnh/thành.',
          ),
          const SizedBox(height: 24),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: express,
            onChanged: locked
                ? null
                : (v) => setState(() => express = v ?? false),
            title: const Text('Giao nhanh · 50.000đ'),
            subtitle: Text(
              remote
                  ? 'Cửa hàng sẽ xác nhận lịch giao sau khi tiếp nhận đơn.'
                  : 'Thời gian giao minh họa: 1–2 ngày',
              style: T.small,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: payment,
            decoration: const InputDecoration(
              labelText: 'Phương thức thanh toán',
            ),
            items:
                (remote
                        ? [
                            'COD',
                            if (methods?.asData?.value == true ||
                                payment == 'VNPay sandbox')
                              'VNPay sandbox',
                          ]
                        : ['COD demo', 'Thẻ / ví điện tử demo'])
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
            onChanged: locked ? null : (v) => setState(() => payment = v!),
          ),
          if (remote && methods?.asData?.value != true)
            Text(
              methods?.isLoading == true
                  ? 'Đang kiểm tra VNPay sandbox…'
                  : 'VNPay sandbox chưa sẵn sàng. Bạn vẫn có thể chọn COD.',
              style: T.small,
            ),
          const SizedBox(height: 20),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: confirmed,
            onChanged: locked
                ? null
                : (v) => setState(() => confirmed = v ?? false),
            title: Text(
              remote
                  ? 'Tôi xác nhận thông tin nhận hàng và phương thức thanh toán.'
                  : 'Tôi hiểu đây là đơn mô phỏng, không thanh toán thật.',
              style: T.body,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(error!, style: const TextStyle(color: T.danger)),
            ),
        ],
      ),
    );
    final summary = CartSummary(
      remote: remote,
      paymentMethod: payment == 'VNPay sandbox' ? 'vnpay' : 'cod',
      subtotal: subtotal,
      shipping: shipping,
      action: AppButton(
        cart.checkoutPending
            ? 'Kiểm tra lại đơn vừa đặt'
            : remote
            ? (payment == 'VNPay sandbox'
                  ? 'Đặt hàng với VNPay sandbox'
                  : 'Đặt hàng COD')
            : 'Tạo đơn hàng demo',
        busy: busy,
        onPressed: cart.cart.locked && !cart.checkoutPending ? null : submit,
      ),
    );
    return PageBody(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Một bước nữa thôi.', style: T.display(40)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/cart'),
                child: const Text('Trở về giỏ hàng'),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (_, c) => c.maxWidth < 850
                    ? Column(
                        children: [fields, const SizedBox(height: 32), summary],
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
                                child: fields,
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
    return PageBody(
      child: Column(
        children: [
          StatePanel(
            title: order == null
                ? (store.remote
                      ? 'Không tìm thấy đơn hàng'
                      : 'Không tìm thấy đơn trong phiên này')
                : (store.remote
                      ? 'Đã tiếp nhận đơn hàng'
                      : 'Đã tạo đơn demo $id'),
            message: order == null
                ? (store.remote
                      ? 'Kiểm tra lại mã đơn trong lịch sử tài khoản.'
                      : 'Dữ liệu demo được xóa khi tải lại trang.')
                : (store.remote
                      ? '$id · ${order.status}\n${order.draft.payment}'
                      : 'Đơn hàng mô phỏng – chưa thanh toán thật'),
            icon: Icons.check_circle_outline,
            action: AppButton(
              'Tiếp tục khám phá',
              onPressed: () => context.go('/shop'),
            ),
          ),
          if (order != null && store.remote)
            PaymentPanel(key: ValueKey(order.id), order: order),
          if (order != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: CartSummary(
                remote: store.remote,
                paymentMethod: order.paymentProvider,
                subtotal: order.subtotal,
                shipping: order.shipping,
                action: AppButton(
                  'Xem chi tiết đơn',
                  outlined: true,
                  onPressed: () => context.go('/account/orders/$id'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
