import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/commerce_state.dart';
import '../../app/payment_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_payments.dart';
import '../../domain/commerce.dart';

class PaymentPanel extends ConsumerStatefulWidget {
  const PaymentPanel({super.key, required this.order, this.onRefresh});
  final Order order;
  final Future<void> Function()? onRefresh;
  @override
  ConsumerState<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends ConsumerState<PaymentPanel> {
  PaymentState? result;
  bool busy = false;
  String? error;
  Future<void> run(bool query) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(paymentRepositoryProvider);
      final state = await (query
          ? repo.reconcile(widget.order.id)
          : repo.start(widget.order.id));
      if (!mounted) return;
      setState(() => result = state);
      await (widget.onRefresh?.call() ??
          ref.read(commerceProvider).refreshPaymentOrder(widget.order.id));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.order.paymentProvider != 'vnpay') return const SizedBox.shrink();
    final status = result?.status ?? widget.order.paymentStatus;
    final paid = ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'].contains(status);
    final label = switch (status) {
      'PAID' => 'Đã thanh toán',
      'PARTIALLY_REFUNDED' => 'Đã hoàn một phần',
      'REFUNDED' => 'Đã hoàn tiền',
      'FAILED' => 'Thanh toán thất bại',
      'CANCELLED' => 'Đã hủy thanh toán',
      _ => 'Chờ thanh toán',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VNPay sandbox', style: T.display(24)),
          const SizedBox(height: 12),
          Text(label, style: T.body),
          const Text(
            'Thanh toán thử nghiệm. Giữ tab cửa hàng này để kiểm tra kết quả sau khi hoàn tất trên VNPay.',
            style: T.small,
          ),
          if (result?.reviewRequired == true)
            const Text(
              'Có khoản thanh toán cần cửa hàng kiểm tra. Vui lòng liên hệ hỗ trợ.',
              style: TextStyle(color: T.danger),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!, style: const TextStyle(color: T.danger)),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (!paid && widget.order.status == 'Chờ xác nhận')
                AppButton(
                  'Chuẩn bị thanh toán',
                  onPressed: busy ? null : () => run(false),
                  busy: busy,
                ),
              if (!paid && result?.checkoutUrl != null)
                AppButton(
                  'Mở VNPay sandbox (tab mới)',
                  onPressed: busy
                      ? null
                      : () {
                          try {
                            ref.read(paymentLauncherProvider)(
                              result!.checkoutUrl!,
                            );
                          } catch (e) {
                            setState(() => error = '$e');
                          }
                        },
                ),
              AppButton(
                'Kiểm tra kết quả',
                outlined: true,
                onPressed: busy ? null : () => run(true),
              ),
            ],
          ),
          if (!paid)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Nếu đường dẫn hết hạn, hãy kiểm tra kết quả trước khi tạo lại thanh toán hoặc hủy đơn.',
                style: T.small,
              ),
            ),
        ],
      ),
    );
  }
}

class PaymentReturnPage extends StatelessWidget {
  const PaymentReturnPage({super.key});
  @override
  Widget build(BuildContext context) => const PageBody(child: _ReturnContent());
}

class _ReturnContent extends StatelessWidget {
  const _ReturnContent();
  @override
  Widget build(BuildContext context) => StatePanel(
    title: 'Đã quay lại từ VNPay sandbox',
    message:
        'Trở về tab cửa hàng ban đầu và bấm “Kiểm tra kết quả” trong đơn hàng. Nếu đã đóng tab đó, đăng nhập lại và mở lịch sử đơn hàng để kiểm tra.',
    icon: Icons.receipt_long_outlined,
    action: AppButton(
      'Lịch sử đơn hàng',
      onPressed: () => context.go('/account/orders'),
    ),
  );
}
