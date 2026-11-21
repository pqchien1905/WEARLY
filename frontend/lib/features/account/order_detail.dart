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
          const SizedBox(height: 20),
          _OrderInfo(label: 'Email liên hệ', value: order.draft.email),
          const Divider(height: 32),
          _OrderInfo(
            label: 'Hình thức giao hàng',
            value: order.draft.express ? 'Giao nhanh' : 'Giao tiêu chuẩn',
          ),
        ],
      ),
    );
    final payment = AccountCard(
      title: 'Thông tin thanh toán',
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _OrderInfo(label: 'Phương thức', value: order.draft.payment),
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
          if (remote)
            PaymentPanel(
              key: ValueKey(order.id),
              order: order,
              enabled: actionsEnabled,
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
                    OrderStatusLabel(order.status),
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
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (_, c) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (c.maxWidth < 900 * scale) {
              return Column(
                children: [
                  products,
                  const SizedBox(height: 24),
                  recipient,
                  const SizedBox(height: 24),
                  payment,
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
                    children: [recipient, const SizedBox(height: 24), payment],
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
            [
              'PAID',
              'PARTIALLY_REFUNDED',
              'REFUNDED',
            ].contains(order.paymentStatus)) ...[
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
