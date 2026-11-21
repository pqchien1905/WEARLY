import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/refund_providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/format.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/remote_refunds.dart';
import '../../account/refund_panel.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../../data/remote_payments.dart';

class AdminRefundActions extends ConsumerStatefulWidget {
  const AdminRefundActions({super.key, required this.orderId});
  final String orderId;
  @override
  ConsumerState<AdminRefundActions> createState() => _AdminRefundActionsState();
}

class _AdminRefundActionsState extends ConsumerState<AdminRefundActions> {
  bool busy = false;
  String? error;
  void refresh() {
    ref.invalidate(adminRefundStateProvider(widget.orderId));
    refreshAdmin(ref);
  }

  Future<void> retry() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(adminRefundRepositoryProvider).retry(widget.orderId);
      if (mounted) refresh();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(
    RefundState state, {
    RefundSource? source,
    RefundRecord? refund,
  }) async {
    final repo = ref.read(adminRefundRepositoryProvider),
        controller = TextEditingController(text: refund?.transactionNo);
    final query = refund != null, cod = state.provider == 'cod';
    // VNPay refunds are queried by a refund number; wallets by the stored request.
    final vnpay = state.provider == 'vnpay',
        gateway = paymentProviderName(state.provider);
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RefundDialog(
        title: query
            ? 'Kiểm tra kết quả hoàn'
            : cod
            ? 'Ghi nhận hoàn COD'
            : 'Hoàn qua $gateway sandbox',
        label: query
            ? 'Truy vấn $gateway'
            : cod
            ? 'Xác nhận đã hoàn COD'
            : 'Gửi yêu cầu hoàn sandbox',
        message: query
            ? (vnpay
                  ? 'Dùng mã giao dịch hoàn từ VNPay sandbox. Mã thanh toán ban đầu không xác nhận được khoản hoàn.'
                  : 'Hệ thống truy vấn $gateway bằng mã yêu cầu hoàn đã lưu.')
            : cod
            ? 'Chỉ xác nhận khi đã trả tiền cho khách: ${money(source!.available)}. Thao tác này ghi biên nhận hoàn tiền.'
            : 'Gửi yêu cầu hoàn ${money(source!.available)} qua $gateway thử nghiệm. Nếu chưa rõ kết quả, hệ thống sẽ giữ khoản này để xác minh.',
        controller: controller,
        fieldLabel: query
            ? (vnpay ? 'Mã giao dịch hoàn VNPay' : null)
            : cod
            ? 'Mã biên nhận hoàn tiền'
            : null,
        readOnly: query && refund.transactionNo != null,
        submit: () async {
          if (query) {
            await repo.query(
              widget.orderId,
              refund.id,
              transactionNo: vnpay ? controller.text.trim() : null,
            );
          } else {
            await repo.create(
              widget.orderId,
              source: source!,
              version: state.version,
              reference: cod ? controller.text.trim() : null,
            );
          }
        },
      ),
    );
    if (mounted) {
      setState(() {});
      refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminRefundStateProvider(widget.orderId)),
        repo = ref.watch(adminRefundRepositoryProvider),
        pending = repo.pendingDraft(widget.orderId);
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hoàn tiền', style: T.display(26)),
          const SizedBox(height: 12),
          if (pending != null) ...[
            Text(
              'Chưa rõ kết quả yêu cầu ${money(pending.amount)}${pending.reference == null ? '' : ' · ${pending.reference}'}. Thử lại giữ nguyên yêu cầu gốc.',
              style: T.small,
            ),
            AppButton(
              'Thử lại yêu cầu hoàn gốc',
              busy: busy,
              onPressed: busy ? null : retry,
            ),
          ],
          if (error != null)
            Text(error!, style: const TextStyle(color: T.danger)),
          AdminAsync(
            value: value,
            reload: refresh,
            builder: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tổng tiền đã hoàn: ${money(state.refunded)}',
                  style: T.body,
                ),
                for (final source in state.sources)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.primary
                              ? 'Khoản thu của đơn'
                              : 'Khoản thanh toán thu thêm',
                          style: T.body,
                        ),
                        if (source.attemptId != null)
                          SelectableText(
                            'Lần thanh toán: ${source.attemptId}',
                            style: T.small,
                          ),
                        Text(
                          'Đã thu ${money(source.collected)} · Được hoàn ${money(source.entitled)}',
                          style: T.small,
                        ),
                        Text(
                          'Có thể hoàn tiếp: ${money(source.available)}',
                          style: T.body,
                        ),
                        if (source.pending)
                          const Text(
                            'Khoản hoàn trước đang chờ xác minh. Kiểm tra kết quả trước khi hoàn tiếp.',
                            style: T.small,
                          ),
                        if (source.available > 0 &&
                            pending == null &&
                            !source.pending)
                          AppButton(
                            state.provider == 'cod'
                                ? 'Ghi nhận hoàn COD'
                                : 'Hoàn qua ${paymentProviderName(state.provider)} sandbox',
                            onPressed: () => act(state, source: source),
                          ),
                      ],
                    ),
                  ),
                if (state.sources.isEmpty)
                  const Text(
                    'Chưa có nguồn tiền đủ điều kiện hoàn. Kiểm tra biên nhận thu, tình trạng hủy hoặc nhận hàng trả.',
                    style: T.small,
                  ),
                for (final refund in state.refunds)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RefundHistory(refund: refund),
                        if (refund.provider != 'cod' &&
                            refund.providerRequestId != null)
                          SelectableText(
                            'Mã yêu cầu ${paymentProviderName(refund.provider)}: ${refund.providerRequestId}',
                            style: T.small,
                          ),
                        if (refund.attemptId != null)
                          SelectableText(
                            'Lần thanh toán: ${refund.attemptId}',
                            style: T.small,
                          ),
                        if (refund.provider != 'cod' &&
                            ['REVIEW', 'PROCESSING'].contains(refund.status))
                          AppButton(
                            'Kiểm tra kết quả hoàn',
                            outlined: true,
                            onPressed: () => act(state, refund: refund),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : refresh,
            child: const Text('Tải lại hoàn tiền'),
          ),
        ],
      ),
    );
  }
}

class _RefundDialog extends StatefulWidget {
  const _RefundDialog({
    required this.title,
    required this.label,
    required this.message,
    required this.controller,
    required this.submit,
    this.fieldLabel,
    this.readOnly = false,
  });
  final String title, label, message;
  final String? fieldLabel;
  final bool readOnly;
  final TextEditingController controller;
  final Future<void> Function() submit;
  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  final form = GlobalKey<FormState>();
  bool busy = false, failed = false;
  String? error;
  Future<void> save() async {
    if (busy || failed || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.submit();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.message),
                const SizedBox(height: 16),
                if (widget.fieldLabel != null)
                  TextFormField(
                    controller: widget.controller,
                    readOnly: widget.readOnly,
                    enabled: !busy && !failed,
                    decoration: InputDecoration(labelText: widget.fieldLabel),
                    validator: (v) =>
                        widget.fieldLabel == 'Mã giao dịch hoàn VNPay'
                        ? !RegExp(r'^[1-9]\d{0,14}$').hasMatch(v ?? '')
                              ? 'Nhập mã giao dịch hoàn hợp lệ.'
                              : null
                        : (v ?? '').trim().length < 3 ||
                              (v ?? '').trim().length > 100
                        ? 'Nhập mã từ 3 đến 100 ký tự.'
                        : null,
                  ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: T.danger)),
                if (failed)
                  const Text(
                    'Đóng để tải lại kết quả trước khi thao tác tiếp. Yêu cầu chưa rõ kết quả sẽ được giữ nguyên mã.',
                    style: T.small,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        if (!failed) AppButton(widget.label, busy: busy, onPressed: save),
      ],
    ),
  );
}
