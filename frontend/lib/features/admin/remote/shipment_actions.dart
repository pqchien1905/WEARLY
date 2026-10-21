import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/widgets/primitives.dart';
import '../../../domain/commerce.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

class ShipmentActions extends ConsumerWidget {
  const ShipmentActions({super.key, required this.data, required this.order});
  final AdminRecord data;
  final Order order;
  Future<void> update(
    BuildContext context,
    WidgetRef ref,
    String status,
    String label,
  ) async {
    final repo = ref.read(adminRepositoryProvider),
        note = TextEditingController();
    final eventKey = const Uuid().v4();
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminMutationDialog(
        title: label,
        message: status == 'RETURNED'
            ? 'Chỉ xác nhận khi đã nhận lại toàn bộ hàng. Tồn kho sẽ được cộng lại; tiền đã thu cần xử lý hoàn tiền riêng.'
            : 'Cập nhật mốc vận chuyển mô phỏng. Ghi chú bên dưới sẽ hiển thị cho khách.',
        reload: () => refreshAdmin(ref),
        onDisposed: note.dispose,
        fields: [
          TextFormField(
            controller: note,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Ghi chú cho khách (tùy chọn)',
            ),
            validator: (value) =>
                (value ?? '').trim().length > 300 ? 'Tối đa 300 ký tự.' : null,
          ),
        ],
        submit: () async {
          await repo.shipmentEvent(
            order.id,
            status: status,
            note: note.text.trim(),
            eventKey: eventKey,
            version: data['version'],
          );
        },
      ),
    );
    if (context.mounted && changed == true) refreshAdmin(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data['status'] != 'SHIPPED' || order.shipment == null) {
      return const SizedBox.shrink();
    }
    final state = order.shipment!.status;
    final options = [
      if (state == 'IN_TRANSIT') ('OUT_FOR_DELIVERY', 'Đang giao đến khách'),
      if (['IN_TRANSIT', 'OUT_FOR_DELIVERY'].contains(state))
        ('DELIVERY_FAILED', 'Giao thất bại'),
      if (state == 'DELIVERY_FAILED') ...[
        ('IN_TRANSIT', 'Giao lại'),
        ('RETURNED', 'Xác nhận hàng hoàn về kho'),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final option in options)
            AppButton(
              option.$2,
              outlined: true,
              onPressed: () => update(context, ref, option.$1, option.$2),
            ),
        ],
      ),
    );
  }
}
