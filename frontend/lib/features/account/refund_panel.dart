import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/refund_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_refunds.dart';
import 'order_tracking.dart';
import '../../data/remote_payments.dart';

class RefundHistory extends StatelessWidget {
  const RefundHistory({super.key, required this.refund});
  final RefundRecord refund;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        refundStatusNames[refund.status]!,
        style: T.body.copyWith(fontWeight: FontWeight.w600),
      ),
      Text(
        '${money(refund.amount)} · ${refund.provider == 'cod' ? 'COD' : '${paymentProviderName(refund.provider)} sandbox'}',
        style: T.body,
      ),
      Text(
        trackingTime(refund.completedAt ?? refund.createdAt),
        style: T.small,
      ),
      if (refund.reference != null)
        Text('Biên nhận: ${refund.reference}', style: T.small),
      if (refund.transactionNo != null)
        Text('Giao dịch hoàn: ${refund.transactionNo}', style: T.small),
      if (['REVIEW', 'PROCESSING'].contains(refund.status))
        const Text(
          'Chưa xác nhận tiền đã được hoàn. Cửa hàng đang kiểm tra kết quả.',
          style: T.small,
        ),
    ],
  );
}

class RefundPanel extends ConsumerWidget {
  const RefundPanel({super.key, required this.orderId});
  final String orderId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hoàn tiền', style: T.display(26)),
        const SizedBox(height: 12),
        ref
            .watch(refundStateProvider(orderId))
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (state) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tổng tiền đã hoàn: ${money(state.refunded)}',
                    style: T.body,
                  ),
                  if (state.refunds.isEmpty)
                    const Text(
                      'Chưa có khoản hoàn tiền được ghi nhận.',
                      style: T.small,
                    ),
                  for (final r in state.refunds)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: RefundHistory(refund: r),
                    ),
                ],
              ),
            ),
        AppButton(
          'Cập nhật hoàn tiền',
          outlined: true,
          onPressed: () => ref.invalidate(refundStateProvider(orderId)),
        ),
      ],
    ),
  );
}
