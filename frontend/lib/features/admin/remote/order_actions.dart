import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

Future<void> settleCod(
  BuildContext context,
  WidgetRef ref,
  AdminRecord order,
  int total,
) async {
  final amount = TextEditingController(), reference = TextEditingController();
  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: 'Đối soát COD',
      message:
          'Chỉ xác nhận sau khi đã nhận đủ ${money(total)} cho đơn ${order['code'] ?? order['id']}. Mã đối soát dùng để tra cứu khoản thu.',
      reload: () => refreshAdmin(ref),
      onDisposed: () {
        amount.dispose();
        reference.dispose();
      },
      fields: [
        AppField(
          label: 'Số tiền đã thu (VND)',
          controller: amount,
          keyboardType: TextInputType.number,
          validator: (value) =>
              priceValidation(value) ??
              (int.tryParse(value ?? '') != total
                  ? 'Số tiền phải bằng tổng đơn ${money(total)}.'
                  : null),
        ),
        AppField(
          label: 'Mã đối soát',
          controller: reference,
          validator: (value) => (value ?? '').trim().length < 3
              ? 'Nhập mã đối soát từ 3 đến 100 ký tự.'
              : requiredText(value, max: 100),
        ),
      ],
      submit: () async {
        await repo.settleCod(
          order['id'],
          amount: amount.text,
          reference: reference.text.trim(),
          version: order['version'],
        );
      },
    ),
  );
  if (context.mounted && changed == true) {
    refreshAdmin(ref);
    toast(context, 'Đã ghi nhận tiền thu COD.');
  }
}
