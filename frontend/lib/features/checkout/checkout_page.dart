import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/commerce_state.dart';
import '../../app/account_state.dart';
import '../../app/account_details.dart';
import '../../app/config.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/commerce.dart';
import '../cart/cart_page.dart';

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
  String? error;
  @override
  void dispose() {
    for (final c in [name, email, phone, address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) {
      return;
    }
    if (!confirmed) {
      setState(
        () => error = 'Xác nhận đây là đơn hàng mô phỏng trước khi tiếp tục.',
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
              express: express,
              payment: payment,
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
    final subtotal = cart.cart.subtotal;
    final shipping = express
        ? BrandConfig.expressFee
        : subtotal >= BrandConfig.freeShippingAt
        ? 0
        : BrandConfig.shippingFee;
    final fields = Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DemoNotice(
            text:
                'Đặt hàng demo. Không có thanh toán hoặc giao hàng thật. Bạn có thể dùng thông tin minh họa.',
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
                      onChanged: busy
                          ? null
                          : (id) {
                              final selected = details.addresses.firstWhere(
                                (a) => a.id == id,
                              );
                              name.text = selected.recipient;
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
            controller: name,
            validator: requiredValue,
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'Email',
            controller: email,
            validator: emailValidator,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'Số điện thoại',
            controller: phone,
            keyboardType: TextInputType.phone,
            validator: (v) => RegExp(r'^0\d{9}$').hasMatch(v?.trim() ?? '')
                ? null
                : 'Nhập 10 chữ số, bắt đầu bằng 0.',
          ),
          const SizedBox(height: 16),
          AppField(
            label: 'Địa chỉ đầy đủ',
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
            onChanged: busy
                ? null
                : (v) => setState(() => express = v ?? false),
            title: const Text('Giao nhanh · 50.000đ'),
            subtitle: const Text(
              'Thời gian giao minh họa: 1–2 ngày',
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
            items: [
              'COD demo',
              'Thẻ / ví điện tử demo',
            ].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: busy ? null : (v) => setState(() => payment = v!),
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: confirmed,
            onChanged: busy
                ? null
                : (v) => setState(() => confirmed = v ?? false),
            title: const Text(
              'Tôi hiểu đây là đơn mô phỏng, không thanh toán thật.',
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
      subtotal: subtotal,
      shipping: shipping,
      action: AppButton('Tạo đơn hàng demo', busy: busy, onPressed: submit),
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

class OrderSuccessPage extends ConsumerWidget {
  const OrderSuccessPage({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref
        .watch(commerceProvider)
        .orders
        .where((o) => o.id == id)
        .firstOrNull;
    return PageBody(
      child: Column(
        children: [
          StatePanel(
            title: order == null
                ? 'Không tìm thấy đơn trong phiên này'
                : 'Đã tạo đơn demo $id',
            message: order == null
                ? 'Dữ liệu demo được xóa khi tải lại trang.'
                : 'Đơn hàng mô phỏng – chưa thanh toán thật',
            icon: Icons.check_circle_outline,
            action: AppButton(
              'Tiếp tục khám phá',
              onPressed: () => context.go('/shop'),
            ),
          ),
          if (order != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: CartSummary(
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
