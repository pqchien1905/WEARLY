import 'package:flutter/material.dart';
import '../../core/design/tokens.dart';
import '../../domain/commerce.dart';
import '../../data/commerce_json.dart';

String trackingTime(DateTime time) {
  final local = time.toUtc().add(const Duration(hours: 7));
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} · ${pad(local.hour)}:${pad(local.minute)}';
}

class OrderTracking extends StatelessWidget {
  const OrderTracking({super.key, required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) {
    final shipment = order.shipment;
    Widget title(String value, IconData icon) => Row(
      children: [
        Icon(icon, size: 22, color: T.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            header: true,
            headingLevel: 2,
            child: Text(
              value,
              style: T.body.copyWith(fontWeight: FontWeight.w600, fontSize: 18),
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title('Theo dõi vận chuyển', Icons.local_shipping_outlined),
        const SizedBox(height: 20),
        if (shipment == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: T.canvas,
              borderRadius: T.radius,
            ),
            child: Text(
              order.status == 'Đã hủy'
                  ? 'Đơn đã hủy'
                  : 'Thông tin vận chuyển sẽ được cập nhật khi đơn hàng được bàn giao.',
              style: T.body.copyWith(color: T.muted),
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: T.canvas,
              borderRadius: T.radius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shipmentStatusNames[shipment.status]!,
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text('Mã vận đơn', style: T.small),
                const SizedBox(height: 4),
                SelectableText(
                  shipment.trackingCode,
                  semanticsLabel: shipment.trackingCode,
                  style: T.small,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _Timeline(events: shipment.events, names: shipmentStatusNames),
        ],
        const Divider(height: 40),
        title('Lịch sử xử lý đơn', Icons.history_outlined),
        const SizedBox(height: 20),
        if (order.history.isEmpty)
          const Text('Chưa có mốc xử lý được ghi nhận.', style: T.small)
        else
          _Timeline(events: order.history, names: orderStatusNames),
        if (['Đã hủy', 'Đã hoàn về kho'].contains(order.status) &&
            order.paymentStatus == 'PAID' &&
            order.total > 0) ...[
          const SizedBox(height: 16),
          const Text(
            'Khoản đã thanh toán cần được cửa hàng xử lý hoàn tiền riêng.',
            style: T.small,
          ),
        ],
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events, required this.names});
  final List<OrderEvent> events;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context) {
    final rows = events.reversed.toList();
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      const SizedBox(height: 5),
                      Icon(
                        i == 0 ? Icons.check_circle : Icons.circle_outlined,
                        size: 16,
                        color: i == 0 ? T.accent : T.controlLine,
                      ),
                      if (i < rows.length - 1)
                        Expanded(
                          child: Container(
                            width: 1,
                            margin: const EdgeInsets.only(top: 6),
                            color: T.line,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < rows.length - 1 ? 24 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              names[rows[i].status]!,
                              style: T.body.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              trackingTime(rows[i].createdAt),
                              style: T.small,
                            ),
                          ],
                        ),
                        if (rows[i].note.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(rows[i].note, style: T.small),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
