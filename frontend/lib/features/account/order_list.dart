part of 'orders_page.dart';

class _OrderList extends StatelessWidget {
  const _OrderList({required this.orders});
  final List<Order> orders;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (c.maxWidth < 1000 * scale) {
        return Column(
          children: [for (final order in orders) _OrderCard(order: order)],
        );
      }
      Widget cell(Widget child, {bool end = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Align(
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      );
      return Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: T.surface,
          border: Border.all(color: T.line),
          borderRadius: T.radius,
        ),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: FlexColumnWidth(1.7),
            1: FlexColumnWidth(3.5),
            2: FlexColumnWidth(2.1),
            3: FlexColumnWidth(2),
            4: FlexColumnWidth(1.8),
          },
          border: const TableBorder(
            horizontalInside: BorderSide(color: T.line),
          ),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: T.canvas),
              children: [
                for (final label in [
                  'Đơn hàng',
                  'Sản phẩm',
                  'Trạng thái',
                  'Tổng tiền',
                  'Thao tác',
                ])
                  cell(
                    Text(
                      label,
                      style: T.small.copyWith(fontWeight: FontWeight.w600),
                    ),
                    end: label == 'Tổng tiền' || label == 'Thao tác',
                  ),
              ],
            ),
            for (final order in orders)
              TableRow(
                children: [
                  cell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          order.displayCode,
                          semanticsLabel: order.displayCode,
                          style: T.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: T.accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(orderDate(order.createdAt), style: T.small),
                      ],
                    ),
                  ),
                  cell(_OrderPreview(order: order)),
                  cell(OrderStatusLabel(order.status)),
                  cell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          money(order.total),
                          style: T.body.copyWith(fontWeight: FontWeight.w600),
                          textAlign: TextAlign.end,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          orderPaymentLabel(order),
                          style: T.small,
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                    end: true,
                  ),
                  cell(_OrderLink(order: order), end: true),
                ],
              ),
          ],
        ),
      );
    },
  );
}

class _OrderPreview extends StatelessWidget {
  const _OrderPreview({required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (order.items.isNotEmpty) ...[
        ClipRRect(
          borderRadius: T.radius,
          child: SizedBox(
            width: 52,
            height: 68,
            child: FashionImage(
              order.items.first.image,
              label: order.items.first.name,
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.items.isEmpty ? 'Đơn hàng' : order.items.first.name,
              style: T.body.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            if (order.items.isNotEmpty) ...[
              Text(
                '${order.items.first.color} · Size ${order.items.first.size}${order.items.length > 1 ? ' · +${order.items.length - 1} mẫu khác' : ''}',
                style: T.small,
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '${order.items.fold(0, (sum, item) => sum + item.quantity)} sản phẩm · ${order.paymentProvider == 'cod'
                  ? 'COD'
                  : order.paymentProvider == 'free'
                  ? 'Không cần thanh toán'
                  : paymentProviderName(order.paymentProvider)}',
              style: T.small,
            ),
          ],
        ),
      ),
    ],
  );
}

class _OrderLink extends StatelessWidget {
  const _OrderLink({required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    onPressed: () => context.go('/account/orders/${order.id}'),
    child: const Text('Xem chi tiết'),
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelectableText(
                order.displayCode,
                semanticsLabel: order.displayCode,
                style: T.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: T.accent,
                ),
              ),
              OrderStatusLabel(order.status),
            ],
          ),
          const SizedBox(height: 8),
          Text('Đặt ngày ${orderDate(order.createdAt)}', style: T.small),
          const Divider(height: 32),
          _OrderPreview(order: order),
          const Divider(height: 32),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tổng tiền', style: T.small),
                  Text(
                    money(order.total),
                    style: T.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(orderPaymentLabel(order), style: T.small),
                ],
              ),
              _OrderLink(order: order),
            ],
          ),
        ],
      ),
    ),
  );
}
