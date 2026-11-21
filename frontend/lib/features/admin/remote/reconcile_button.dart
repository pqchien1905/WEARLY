import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/api_providers.dart';
import '../../../core/widgets/primitives.dart';
import '../../../core/design/tokens.dart';
import 'admin_providers.dart';

class ReconcilePaymentButton extends ConsumerStatefulWidget {
  const ReconcilePaymentButton({
    super.key,
    required this.orderId,
    required this.attemptId,
  });
  final String orderId, attemptId;
  @override
  ConsumerState<ReconcilePaymentButton> createState() =>
      _ReconcilePaymentButtonState();
}

class _ReconcilePaymentButtonState
    extends ConsumerState<ReconcilePaymentButton> {
  bool busy = false;
  String? message;
  Future<void> reconcile() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ref
          .read(adminApiClientProvider)
          .request(
            'POST',
            'admin/payments/orders/${widget.orderId}/reconcile',
            body: {'attemptId': widget.attemptId},
          );
      if (mounted) {
        refreshAdmin(ref);
        setState(() => message = 'Đã cập nhật kết quả xác minh.');
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppButton(
        'Xác minh giao dịch',
        outlined: true,
        busy: busy,
        onPressed: busy ? null : reconcile,
      ),
      if (message != null) Text(message!, style: T.small),
    ],
  );
}
