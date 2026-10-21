import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/return_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_returns.dart';
import '../../domain/commerce.dart';
import 'order_tracking.dart';

class ReturnHistory extends StatelessWidget {
  const ReturnHistory({super.key, required this.request, required this.order});
  final ReturnCase request;
  final Order order;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        returnStatusNames[request.status]!,
        style: T.body.copyWith(fontWeight: FontWeight.w600),
      ),
      Text(trackingTime(request.createdAt), style: T.small),
      Text(request.reason, style: T.body),
      for (final item in request.items)
        Text(
          '${order.items.where((i) => i.id == item.id).firstOrNull?.name ?? 'Sản phẩm trong đơn'} × ${item.quantity} · ${money(item.amount)}',
          style: T.small,
        ),
      Text('Tiền hàng dự kiến hoàn: ${money(request.amount)}', style: T.body),
      const Text(
        'Nhận hàng và hoàn tiền được xác nhận riêng. Phí giao hàng được giữ lại.',
        style: T.small,
      ),
      if (request.decisionNote.isNotEmpty)
        Text('Phản hồi: ${request.decisionNote}', style: T.small),
      if (request.receiptNote.isNotEmpty)
        Text('Nhận hàng: ${request.receiptNote}', style: T.small),
    ],
  );
}

class ReturnsPanel extends ConsumerStatefulWidget {
  const ReturnsPanel({super.key, required this.order});
  final Order order;
  @override
  ConsumerState<ReturnsPanel> createState() => _ReturnsPanelState();
}

class _ReturnsPanelState extends ConsumerState<ReturnsPanel> {
  final reason = TextEditingController(), form = GlobalKey<FormState>();
  final quantities = <String, TextEditingController>{};
  bool busy = false;
  String? error;
  ReturnQuote? quote;
  @override
  void initState() {
    super.initState();
    final draft = ref
        .read(returnRepositoryProvider)
        .pendingDraft(widget.order.id);
    if (draft != null) {
      reason.text = draft.reason;
      for (final item in draft.quantities.entries) {
        quantities[item.key] = TextEditingController(text: '${item.value}');
      }
    }
  }

  List<Map<String, Object?>> get selected => [
    for (final entry in quantities.entries)
      if ((int.tryParse(entry.value.text) ?? 0) > 0)
        {'orderItemId': entry.key, 'quantity': int.parse(entry.value.text)},
  ];
  Future<void> run(bool submit) async {
    if (busy) return;
    final repo = ref.read(returnRepositoryProvider);
    if (!repo.hasPending(widget.order.id) &&
        !(form.currentState?.validate() ?? false)) {
      return;
    }
    if (selected.isEmpty && !repo.hasPending(widget.order.id)) {
      setState(() => error = 'Chọn ít nhất một sản phẩm để trả.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (submit) {
        await repo.submit(
          widget.order.id,
          reason: reason.text.trim(),
          items: selected,
          expectedAmount: quote?.amount ?? 0,
        );
        if (!mounted) return;
        quote = null;
        reason.clear();
        for (final c in quantities.values) {
          c.text = '0';
        }
        ref.invalidate(returnStateProvider(widget.order.id));
      } else {
        final value = await repo.preview(widget.order.id, selected);
        if (!mounted) return;
        quote = value;
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    reason.dispose();
    for (final c in quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(returnStateProvider(widget.order.id)),
        draft = ref
            .watch(returnRepositoryProvider)
            .pendingDraft(widget.order.id),
        pending = draft != null,
        amount = draft?.amount ?? quote?.amount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Trả hàng', style: T.display(26)),
          const SizedBox(height: 12),
          value.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$e'),
                AppButton(
                  'Tải lại yêu cầu trả hàng',
                  outlined: true,
                  onPressed: () =>
                      ref.invalidate(returnStateProvider(widget.order.id)),
                ),
              ],
            ),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(returnEligibilityMessages[data.reason]!, style: T.small),
                if (data.deadline != null && data.canRequest)
                  Text(
                    'Hạn gửi: ${trackingTime(data.deadline!)}',
                    style: T.small,
                  ),
                for (final request in data.requests)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: ReturnHistory(request: request, order: widget.order),
                  ),
                if (data.canRequest || pending)
                  Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        for (final item in widget.order.items)
                          if ((data.remaining[item.id] ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextFormField(
                                key: ValueKey('return-quantity-${item.id}'),
                                controller: quantities.putIfAbsent(
                                  item.id,
                                  () => TextEditingController(text: '0'),
                                ),
                                enabled: !busy && !pending,
                                decoration: InputDecoration(
                                  labelText: 'Số lượng trả: ${item.name}',
                                  helperText:
                                      'Từ 0 đến ${data.remaining[item.id]} · ${item.color} / ${item.size}',
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() => quote = null),
                                validator: (v) {
                                  final n = int.tryParse(v ?? '');
                                  return n == null ||
                                          n < 0 ||
                                          n > (data.remaining[item.id] ?? 0)
                                      ? 'Nhập số lượng hợp lệ.'
                                      : null;
                                },
                              ),
                            ),
                        TextFormField(
                          controller: reason,
                          enabled: !busy && !pending,
                          decoration: const InputDecoration(
                            labelText: 'Lý do trả hàng',
                          ),
                          maxLines: 3,
                          validator: (v) =>
                              (v ?? '').trim().length < 3 ||
                                  v!.trim().length > 300
                              ? 'Nhập lý do từ 3 đến 300 ký tự.'
                              : null,
                        ),
                        if (amount != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Tiền hàng dự kiến hoàn: ${money(amount)}. Phí giao hàng được giữ lại.',
                              style: T.body,
                            ),
                          ),
                        if (pending)
                          const Text(
                            'Chưa rõ kết quả gửi. Thử lại sẽ dùng đúng yêu cầu ban đầu.',
                            style: T.small,
                          ),
                        if (error != null)
                          Text(error!, style: T.body.copyWith(color: T.danger)),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (!pending)
                              AppButton(
                                'Tính tiền hàng dự kiến hoàn',
                                outlined: true,
                                busy: busy,
                                onPressed: busy ? null : () => run(false),
                              ),
                            if (quote != null || pending)
                              AppButton(
                                pending
                                    ? 'Thử gửi lại yêu cầu gốc'
                                    : 'Gửi yêu cầu trả hàng',
                                busy: busy,
                                onPressed: busy ? null : () => run(true),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => ref.invalidate(
                          returnStateProvider(widget.order.id),
                        ),
                  child: const Text('Cập nhật yêu cầu trả hàng'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
