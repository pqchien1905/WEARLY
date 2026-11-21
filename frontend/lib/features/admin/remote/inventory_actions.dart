import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/primitives.dart';
import '../../../core/design/tokens.dart';
import '../../../app/providers.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

Future<void> adjustInventory(
  BuildContext context,
  WidgetRef ref,
  AdminRecord inventory,
  String sku, {
  String mode = 'delta',
}) async {
  final delta = TextEditingController(), reason = TextEditingController();
  final before = inventory['quantity'] as int;
  int? change() {
    final text = delta.text.trim();
    final n = RegExp(r'^[+-]?\d+$').hasMatch(text) ? int.tryParse(text) : null;
    return n == null
        ? null
        : mode == 'in'
        ? n
        : mode == 'out'
        ? -n
        : mode == 'count'
        ? n - before
        : n;
  }

  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: switch (mode) {
        'in' => 'Nhập kho',
        'out' => 'Xuất kho',
        'count' => 'Kiểm kê tồn kho',
        _ => 'Điều chỉnh kho',
      },
      message:
          '$sku · Tồn kho hiện tại: $before. ${mode == 'delta'
              ? 'Nhập số dương để thêm hoặc số âm để giảm.'
              : mode == 'count'
              ? 'Chỉ nhập số lượng còn có thể bán, đã trừ hàng dành cho các đơn hiện có.'
              : 'Kiểm tra số lượng trước khi xác nhận lưu.'}',
      reload: () => refreshAdmin(ref),
      onDisposed: () {
        delta.dispose();
        reason.dispose();
      },
      fields: [
        AppField(
          label: switch (mode) {
            'in' => 'Số lượng nhập',
            'out' => 'Số lượng xuất',
            'count' => 'Số lượng kiểm kê',
            _ => 'Số lượng thay đổi',
          },
          controller: delta,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          validator: (s) {
            final input = int.tryParse(s?.trim() ?? ''), n = change();
            if (mode != 'delta' &&
                (input == null ||
                    input < 0 ||
                    (mode != 'count' && input == 0))) {
              return 'Nhập số nguyên ${mode == 'count' ? 'không âm' : 'lớn hơn 0'}.';
            }
            if (mode == 'count' && n == 0) {
              return 'Số lượng trùng với tồn kho hiện tại. Không cần điều chỉnh.';
            }
            return n == null || n == 0 || n.abs() > 1000000
                ? 'Nhập số nguyên khác 0, tối đa ±1.000.000.'
                : n + before < 0
                ? 'Tồn kho không thể âm.'
                : n + before > 2147483647
                ? 'Số lượng vượt giới hạn lưu trữ.'
                : null;
          },
        ),
        ValueListenableBuilder(
          valueListenable: delta,
          builder: (_, value, _) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: T.canvas,
              borderRadius: T.radius,
            ),
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Trước: $before → Sau: ${change() == null ? '—' : before + change()!} đơn vị',
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        AppField(
          label: 'Lý do',
          controller: reason,
          validator: (s) => (s ?? '').trim().length < 3
              ? 'Nhập ít nhất 3 ký tự.'
              : requiredText(s),
        ),
      ],
      submit: () async {
        await repo.adjust(
          inventory['id'],
          delta: change()!,
          version: inventory['version'],
          reason: reason.text.trim(),
          operation: mode,
        );
      },
    ),
  );
  // Dialog routes can outlive the originating account/page.
  if (context.mounted && changed == true) {
    refreshAdmin(ref);
    ref.read(catalogRevisionProvider.notifier).refresh();
    toast(context, 'Đã cập nhật tồn kho.');
  }
}
