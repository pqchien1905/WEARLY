import 'package:flutter/material.dart';
import '../../core/widgets/promotion_price.dart';
import 'order_tracking.dart';
import 'returns_panel.dart';
import 'refund_panel.dart';
import '../checkout/payment_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/commerce_state.dart';
import '../../app/account_state.dart';
import '../../core/network/api_client.dart';
import '../../domain/commerce.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import 'account_navigation.dart';
import 'account_components.dart';
import '../../data/remote_payments.dart';

part 'order_list.dart';
part 'order_detail.dart';
part 'order_history.dart';
part 'order_filters.dart';

const orderStages = [
  'Chờ xác nhận',
  'Đã xác nhận',
  'Đang đóng gói',
  'Đang giao',
  'Đã giao',
];

class OrderStatusLabel extends StatelessWidget {
  const OrderStatusLabel(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: const BoxDecoration(color: T.canvas, borderRadius: T.radius),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          switch (status) {
            'Đã giao' => Icons.check_circle_outline,
            'Đã hủy' => Icons.cancel_outlined,
            'Đang giao' => Icons.local_shipping_outlined,
            'Đã hoàn về kho' => Icons.assignment_return_outlined,
            'Chờ xác nhận' => Icons.schedule,
            _ => Icons.inventory_2_outlined,
          },
          size: 16,
          color: status == 'Đã hủy'
              ? T.danger
              : status == 'Đã giao'
              ? T.success
              : T.accent,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            status,
            style: T.small.copyWith(
              fontWeight: FontWeight.w500,
              color: status == 'Đã hủy'
                  ? T.danger
                  : status == 'Đã giao'
                  ? T.success
                  : T.accent,
            ),
          ),
        ),
      ],
    ),
  );
}

class OrderProgress extends StatelessWidget {
  const OrderProgress({super.key, required this.status, this.remote = false});
  final String status;
  final bool remote;
  @override
  Widget build(BuildContext context) {
    final stages = orderStages
        .where((s) => !remote || s != 'Đang đóng gói')
        .toList();
    final current = stages.indexOf(status);
    if (status == 'Đã hủy') {
      return StatePanel(
        title: 'Đơn đã hủy',
        message: remote
            ? 'Đơn hàng đã được hủy. Số lượng sản phẩm đã được trả lại kho.'
            : 'Đây là thay đổi trạng thái mô phỏng; không thực hiện hoàn tiền hoặc vận chuyển thật.',
        icon: Icons.cancel_outlined,
      );
    }
    if (current < 0) {
      return DemoNotice(
        text: 'Trạng thái hiện tại: $status. Chưa có tiến trình tương ứng.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tiến trình đơn hàng', style: T.display(26)),
        const SizedBox(height: 12),
        Text(
          remote
              ? 'Trạng thái do cửa hàng cập nhật. Chưa có thông tin vận đơn.'
              : 'Minh họa theo trạng thái hiện tại; chưa có vận đơn hay mốc giao hàng thực tế.',
          style: T.small,
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (_, c) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (var i = 0; i < stages.length; i++)
                SizedBox(
                  width: c.maxWidth < 700 ? c.maxWidth : (c.maxWidth - 64) / 5,
                  child: Semantics(
                    selected: i == current,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          i == current
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: i == current ? T.accent : T.controlLine,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            stages[i],
                            style: T.small.copyWith(
                              color: i == current ? T.accent : T.muted,
                              fontWeight: i == current
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
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

String orderDate(DateTime date) {
  final local = date.toUtc().add(const Duration(hours: 7));
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class _CancelOrder extends ConsumerStatefulWidget {
  const _CancelOrder(
    this.id, {
    super.key,
    required this.code,
    this.paid = false,
    this.enabled = true,
  });
  final String id, code;
  final bool paid, enabled;
  @override
  ConsumerState<_CancelOrder> createState() => _CancelOrderState();
}

class _CancelOrderState extends ConsumerState<_CancelOrder> {
  bool busy = false;
  String? error;
  Future<void> cancel() async {
    if (busy || !widget.enabled) return;
    setState(() {
      busy = true;
      error = null;
    });
    final store = ref.read(commerceProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hủy đơn hàng này?'),
        content: Text(
          widget.paid
              ? 'Hủy đơn ${widget.code}? Khoản đã thanh toán cần được cửa hàng xử lý hoàn tiền riêng.'
              : 'Đơn ${widget.code} sẽ được hủy. Bạn có thể đặt đơn mới nếu thay đổi ý định.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ đơn'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận hủy'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => busy = false);
      return;
    }
    try {
      await store.setStatus(widget.id, 'Đã hủy');
      if (mounted) toast(context, 'Đã hủy đơn ${widget.code}.');
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
      // Reconcile a state conflict or a response lost after cancellation.
      await store.loadOrder(widget.id);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: busy || !widget.enabled ? null : cancel,
          icon: const Icon(Icons.close, size: 18),
          label: Text(busy ? 'Đang xử lý…' : 'Hủy đơn hàng'),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(error!, style: T.small.copyWith(color: T.danger)),
            ),
          ),
      ],
    ),
  );
}
