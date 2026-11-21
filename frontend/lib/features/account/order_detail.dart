part of 'orders_page.dart';

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({
    required this.order,
    this.remote = false,
    this.actionsEnabled = true,
  });
  final Order order;
  final bool remote, actionsEnabled;
  @override
  Widget build(BuildContext context) {
    final products = AccountCard(
      title: 'Sản phẩm trong đơn',
      icon: Icons.shopping_bag_outlined,
      child: Column(
        children: [
          for (var i = 0; i < order.items.length; i++) ...[
            if (i > 0) const Divider(height: 32),
            _OrderItemLine(item: order.items[i]),
          ],
        ],
      ),
    );
    final recipient = AccountCard(
      title: 'Thông tin nhận hàng',
      icon: Icons.location_on_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AccountGrid(
            columns: 2,
            minColumnWidth: 130,
            children: [
              _OrderInfo(label: 'Người nhận', value: order.draft.name),
              _OrderInfo(label: 'Số điện thoại', value: order.draft.phone),
            ],
          ),
          const SizedBox(height: 20),
          _OrderInfo(label: 'Địa chỉ', value: order.draft.address),
          if (order.pinned)
            PinMapLink(
              latitude: order.pinLatitude!,
              longitude: order.pinLongitude!,
            ),
          const SizedBox(height: 20),
          _OrderInfo(label: 'Email liên hệ', value: order.draft.email),
          const Divider(height: 32),
          _OrderInfo(
            label: 'Hình thức giao hàng',
            value: order.draft.express ? 'Giao nhanh' : 'Giao tiêu chuẩn',
          ),
          if (remote && order.status == 'Chờ xác nhận')
            _ChangeAddress(
              key: ValueKey('address-${order.id}'),
              order: order,
              enabled: actionsEnabled,
            ),
        ],
      ),
    );
    final online = onlinePaymentProviders.contains(order.paymentProvider);
    final paid = const [
      'PAID',
      'PARTIALLY_REFUNDED',
      'REFUNDED',
    ].contains(order.paymentStatus);
    // An unpaid wallet order's next step is paying: show it first, full width.
    final awaitingPayment =
        remote && online && !paid && order.status == 'Chờ xác nhận';
    final (payLabel, payColor) = _paymentState(order, online, paid);
    final payment = AccountCard(
      title: 'Thanh toán',
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              _OrderInfo(
                label: 'Phương thức',
                value: online
                    ? 'Ví ${paymentProviderName(order.paymentProvider)}'
                    : order.paymentProvider == 'free'
                    ? 'Miễn thanh toán'
                    : 'Thanh toán khi nhận hàng (COD)',
              ),
              _Pill(label: payLabel, color: payColor),
            ],
          ),
          if (remote &&
              order.status == 'Chờ xác nhận' &&
              !paid &&
              order.paymentProvider != 'free' &&
              order.total > 0)
            _ChangePayment(
              key: ValueKey('payment-${order.id}-${order.paymentProvider}'),
              order: order,
              enabled: actionsEnabled,
            ),
          const Divider(height: 32),
          _AmountLine(label: 'Tạm tính', value: money(order.subtotal)),
          const SizedBox(height: 12),
          _AmountLine(
            label: 'Phí giao hàng',
            value: order.shipping == 0 ? 'Miễn phí' : money(order.shipping),
          ),
          if (order.couponCode != null) ...[
            const SizedBox(height: 12),
            _AmountLine(
              label: 'Khuyến mãi ${order.couponCode}',
              value: '-${money(order.discount)}',
            ),
          ],
          const Divider(height: 32),
          _AmountLine(
            label: 'Tổng thanh toán',
            value: money(order.total),
            strong: true,
          ),
          // Paid/refunded wallet orders keep their verification controls here;
          // unpaid ones show the payment block at the top instead.
          if (remote && online && !awaitingPayment)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: PaymentPanel(
                key: ValueKey(order.id),
                order: order,
                enabled: actionsEnabled,
                framed: false,
              ),
            ),
          if (remote && order.status == 'Chờ xác nhận')
            _CancelOrder(
              order.id,
              key: ValueKey('cancel-${order.id}'),
              code: order.displayCode,
              enabled: actionsEnabled,
              paid:
                  [
                    'PAID',
                    'PARTIALLY_REFUNDED',
                  ].contains(order.paymentStatus) &&
                  order.total > 0,
            ),
        ],
      ),
    );
    final tracking = AccountCard(
      child: remote
          ? OrderTracking(order: order)
          : OrderProgress(status: order.status),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountCard(
          child: LayoutBuilder(
            builder: (_, constraints) => AccountGrid(
              columns:
                  constraints.maxWidth >=
                      520 * MediaQuery.textScalerOf(context).scale(14) / 14 + 72
                  ? 4
                  : 2,
              minColumnWidth: 130,
              children: [
                _OrderInfo(
                  label: 'Mã đơn hàng',
                  value: order.displayCode,
                  strong: true,
                ),
                _OrderInfo(
                  label: 'Ngày đặt hàng',
                  value: orderDate(order.createdAt),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Trạng thái', style: T.small),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OrderStatusLabel(order.status),
                        if (remote) _Pill(label: payLabel, color: payColor),
                      ],
                    ),
                  ],
                ),
                _OrderInfo(
                  label: 'Tổng thanh toán',
                  value: money(order.total),
                  strong: true,
                ),
              ],
            ),
          ),
        ),
        if (awaitingPayment)
          PaymentPanel(
            key: ValueKey(order.id),
            order: order,
            enabled: actionsEnabled,
          )
        else
          const SizedBox(height: 24),
        LayoutBuilder(
          builder: (_, c) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (c.maxWidth < 900 * scale) {
              return Column(
                children: [
                  products,
                  const SizedBox(height: 24),
                  payment,
                  const SizedBox(height: 24),
                  recipient,
                  const SizedBox(height: 24),
                  tracking,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [products, const SizedBox(height: 24), tracking],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [payment, const SizedBox(height: 24), recipient],
                  ),
                ),
              ],
            );
          },
        ),
        if (remote && ['Đã giao', 'Đã hoàn về kho'].contains(order.status)) ...[
          const SizedBox(height: 24),
          AccountCard(
            child: ReturnsPanel(
              key: ValueKey('returns-${order.id}'),
              order: order,
            ),
          ),
        ],
        if (remote &&
            order.total > 0 &&
            (order.hasOnlineCollection ||
                [
                  'PAID',
                  'PARTIALLY_REFUNDED',
                  'REFUNDED',
                ].contains(order.paymentStatus))) ...[
          const SizedBox(height: 24),
          AccountCard(
            child: RefundPanel(
              key: ValueKey('refunds-${order.id}'),
              orderId: order.id,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton('Tiếp tục mua sắm', onPressed: () => context.go('/shop')),
            AppButton(
              'Cần hỗ trợ đơn hàng',
              outlined: true,
              onPressed: () => context.go('/contact'),
            ),
          ],
        ),
      ],
    );
  }
}

(String, Color) _paymentState(Order order, bool online, bool paid) {
  if (order.paymentProvider == 'free') {
    return ('Không cần thanh toán', T.success);
  }
  return switch (order.paymentStatus) {
    'PAID' => ('Đã thanh toán', T.success),
    'PARTIALLY_REFUNDED' => ('Đã hoàn một phần', T.warning),
    'REFUNDED' => ('Đã hoàn tiền', T.muted),
    'FAILED' => ('Thanh toán chưa thành công', T.danger),
    'CANCELLED' => ('Đã hủy thanh toán', T.muted),
    _ when !online => ('Thu tiền khi giao', T.muted),
    _ => ('Chờ thanh toán', T.warning),
  };
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: T.radius,
    ),
    child: Text(
      label,
      style: T.small.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class _OrderInfo extends StatelessWidget {
  const _OrderInfo({
    required this.label,
    required this.value,
    this.strong = false,
  });
  final String label, value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: T.small),
      const SizedBox(height: 8),
      SelectableText(
        value,
        semanticsLabel: value,
        style: T.body.copyWith(
          fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
          fontSize: strong ? 18 : 14,
          color: strong ? T.accent : T.ink,
        ),
      ),
    ],
  );
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.value,
    this.strong = false,
  });
  final String label, value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: T.body.copyWith(
            color: strong ? T.ink : T.muted,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
      const SizedBox(width: 16),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: T.body.copyWith(
            fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
            fontSize: strong ? 18 : 14,
          ),
        ),
      ),
    ],
  );
}

class _OrderItemLine extends StatelessWidget {
  const _OrderItemLine({required this.item});
  final CartItem item;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: T.radius,
        child: SizedBox(
          width: 64,
          height: 88,
          child: FashionImage(item.image, label: item.name),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: LayoutBuilder(
          builder: (_, c) {
            final description = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text('${item.color} / ${item.size}', style: T.small),
                const SizedBox(height: 4),
                Text('Số lượng: ${item.quantity}', style: T.small),
              ],
            );
            final price = Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(item.total),
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (item.quantity > 1)
                  Text('${money(item.unitPrice)} / sản phẩm', style: T.small),
                if (item.discounted)
                  PromotionPrice(
                    price: item.unitPrice,
                    original: item.originalUnitPrice,
                    name: item.promotionName,
                  ),
              ],
            );
            if (c.maxWidth <
                380 * MediaQuery.textScalerOf(context).scale(14) / 14) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [description, const SizedBox(height: 12), price],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: description),
                const SizedBox(width: 24),
                price,
              ],
            );
          },
        ),
      ),
    ],
  );
}

String _orderEditError(Object error) {
  if (error is! ApiException) return accountError(error);
  return switch (error.code) {
    'ORDER_STATE_CONFLICT' =>
      'Cửa hàng đã xác nhận đơn nên không thể thay đổi nữa. Liên hệ hỗ trợ nếu cần.',
    'PAYMENT_ALREADY_SETTLED' =>
      'Đơn đã được thanh toán nên không thể đổi phương thức.',
    'PAYMENT_VERIFICATION_UNAVAILABLE' =>
      'Chưa kiểm tra được giao dịch đang mở. Thử lại sau ít phút.',
    'PAYMENT_UNAVAILABLE' => 'Phương thức này đang tạm ngưng.',
    'NOT_FOUND' => 'Không tìm thấy địa chỉ này. Tải lại trang rồi thử lại.',
    _ => error.message,
  };
}

typedef _Option = ({String value, String title, String? subtitle});

/// Shared shell for the two order edit dialogs: a radio list and one action.
Future<String?> _pickOption(
  BuildContext context, {
  required String title,
  String? note,
  required List<_Option> options,
  required String? initial,
  required String confirm,
}) => showDialog<String>(
  context: context,
  builder: (context) {
    var selected = initial;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(note, style: T.small),
                  ),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v),
                  child: Column(
                    children: [
                      for (final o in options)
                        RadioListTile<String>(
                          value: o.value,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            o.title,
                            style: T.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: o.subtitle == null
                              ? null
                              : Text(o.subtitle!, style: T.small),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: selected == null || selected == initial
                ? null
                : () => Navigator.pop(context, selected),
            child: Text(confirm),
          ),
        ],
      ),
    );
  },
);

class _ChangeAddress extends ConsumerStatefulWidget {
  const _ChangeAddress({super.key, required this.order, required this.enabled});
  final Order order;
  final bool enabled;
  @override
  ConsumerState<_ChangeAddress> createState() => _ChangeAddressState();
}

class _ChangeAddressState extends ConsumerState<_ChangeAddress> {
  bool busy = false;
  Future<void> open() async {
    setState(() => busy = true);
    try {
      final details = await ref.read(accountDetailsProvider.future);
      if (!mounted) return;
      if (details.addresses.isEmpty) {
        toast(context, 'Thêm địa chỉ vào sổ địa chỉ trước.');
        context.go('/account/addresses');
        return;
      }
      final d = widget.order.draft;
      final current = details.addresses
          .where(
            (a) =>
                a.recipient == d.name &&
                a.phone == d.phone &&
                a.address == d.address,
          )
          .firstOrNull;
      final picked = await _pickOption(
        context,
        title: 'Đổi địa chỉ nhận hàng',
        note: 'Chọn một địa chỉ trong sổ địa chỉ. Phí giao hàng không đổi.',
        options: [
          for (final a in details.addresses)
            (
              value: a.id,
              title: '${a.recipient} · ${a.phone}',
              subtitle: a.label.isEmpty
                  ? a.address
                  : '${a.label} — ${a.address}',
            ),
        ],
        initial: current?.id,
        confirm: 'Lưu địa chỉ',
      );
      if (picked == null || !mounted) return;
      await ref
          .read(commerceProvider)
          .changeOrderAddress(widget.order.id, picked);
      if (mounted) toast(context, 'Đã cập nhật địa chỉ nhận hàng.');
    } catch (e) {
      if (mounted) toast(context, _orderEditError(e));
      try {
        await ref.read(commerceProvider).loadOrder(widget.order.id);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: OutlinedButton.icon(
      onPressed: busy || !widget.enabled ? null : open,
      icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
      label: Text(busy ? 'Đang xử lý…' : 'Đổi địa chỉ'),
    ),
  );
}

class _ChangePayment extends ConsumerStatefulWidget {
  const _ChangePayment({super.key, required this.order, required this.enabled});
  final Order order;
  final bool enabled;
  @override
  ConsumerState<_ChangePayment> createState() => _ChangePaymentState();
}

class _ChangePaymentState extends ConsumerState<_ChangePayment> {
  bool busy = false;
  Future<void> open() async {
    setState(() => busy = true);
    try {
      final methods = await ref.read(paymentRepositoryProvider).available();
      if (!mounted) return;
      final current = widget.order.paymentProvider;
      final picked = await _pickOption(
        context,
        title: 'Đổi phương thức thanh toán',
        note: onlinePaymentProviders.contains(current)
            ? 'Nếu bạn vừa mở trang thanh toán, hãy hoàn tất hoặc đợi giao dịch đó hết hạn trước khi đổi.'
            : null,
        options: [
          (
            value: 'cod',
            title: 'Thanh toán khi nhận hàng (COD)',
            subtitle: 'Trả tiền mặt cho nhân viên giao hàng',
          ),
          for (final m in const ['zalopay', 'momo', 'vnpay'])
            if (methods.enabled(m) || m == current)
              (
                value: m,
                title: m == 'vnpay' ? 'VNPay' : 'Ví ${paymentProviderName(m)}',
                subtitle: 'Thanh toán trực tuyến · môi trường thử nghiệm',
              ),
        ],
        initial: current,
        confirm: 'Đổi phương thức',
      );
      if (picked == null || !mounted) return;
      await ref
          .read(commerceProvider)
          .changeOrderPayment(widget.order.id, picked);
      if (mounted) {
        toast(
          context,
          picked == 'cod'
              ? 'Đã chuyển sang thanh toán khi nhận hàng.'
              : 'Đã chuyển sang ${paymentProviderName(picked)}. Bấm “Thanh toán ngay” để thanh toán.',
        );
      }
    } catch (e) {
      if (mounted) toast(context, _orderEditError(e));
      try {
        await ref.read(commerceProvider).loadOrder(widget.order.id);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: OutlinedButton.icon(
      onPressed: busy || !widget.enabled ? null : open,
      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
      label: Text(busy ? 'Đang xử lý…' : 'Đổi phương thức thanh toán'),
    ),
  );
}
