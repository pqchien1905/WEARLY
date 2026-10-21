import 'package:flutter/material.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/commerce.dart';
import '../../data/commerce_json.dart';

String trackingTime(DateTime time) =>
    '${time.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 19).replaceFirst('T', ' ')} (UTC+7)';

class OrderTracking extends StatelessWidget {
  const OrderTracking({super.key, required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) {
    final shipment = order.shipment;
    Widget events(List<OrderEvent> rows, Map<String, String> names) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final event in rows)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${names[event.status]} · ${trackingTime(event.createdAt)}',
                  style: T.small,
                ),
                if (event.note.isNotEmpty) Text(event.note, style: T.body),
              ],
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (order.status == 'Đã hủy') ...[
          const StatePanel(
            title: 'Đơn đã hủy',
            message:
                'Đơn hàng đã được hủy. Số lượng sản phẩm đã được trả lại kho.',
            icon: Icons.cancel_outlined,
          ),
          const SizedBox(height: 24),
          if (order.paymentStatus == 'PAID' && order.total > 0)
            const Text(
              'Đơn đã hủy, khoản đã thu cần xử lý hoàn tiền riêng.',
              style: T.small,
            ),
        ],
        Text('Theo dõi vận chuyển', style: T.display(26)),
        const SizedBox(height: 12),
        if (shipment == null)
          const Text(
            'Chưa có vận đơn được ghi nhận cho đơn này.',
            style: T.small,
          )
        else ...[
          const Text('Mô phỏng vận chuyển local', style: T.body),
          const Text(
            'Các mốc do cửa hàng cập nhật để kiểm thử.',
            style: T.small,
          ),
          const SizedBox(height: 8),
          SelectableText(
            shipment.trackingCode,
            semanticsLabel: shipment.trackingCode,
            style: T.body,
          ),
          Text(
            'Hiện tại: ${shipmentStatusNames[shipment.status]}',
            style: T.body,
          ),
          events(shipment.events, shipmentStatusNames),
          if (shipment.status == 'RETURNED' &&
              order.paymentStatus == 'PAID' &&
              order.total > 0)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Đơn đã thu tiền; yêu cầu hoàn tiền cần được xử lý riêng.',
                style: T.small,
              ),
            ),
        ],
        const SizedBox(height: 24),
        Text('Lịch sử xử lý đơn', style: T.display(22)),
        if (order.history.isEmpty)
          const Text('Chưa có mốc xử lý được ghi nhận.', style: T.small),
        events(order.history, orderStatusNames),
        const SizedBox(height: 24),
      ],
    );
  }
}
