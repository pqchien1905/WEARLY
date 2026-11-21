import '../../../app/providers.dart' show catalogRevisionProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

String promotionsBack(String? from) {
  final uri = Uri.tryParse(from ?? '');
  return uri != null &&
          !uri.hasScheme &&
          !uri.hasAuthority &&
          !uri.hasFragment &&
          uri.path == '/admin/promotions'
      ? uri.toString()
      : '/admin/promotions';
}

Future<bool> changePromotion(
  BuildContext context,
  WidgetRef ref,
  AdminRecord row, {
  bool remove = false,
}) async {
  final repo = ref.read(adminRepositoryProvider);
  void refresh({bool detail = true}) {
    if (!context.mounted) return;
    ref.read(catalogRevisionProvider.notifier).refresh();
    ref.invalidate(adminPromotionsProvider);
    ref.invalidate(adminPromotionSummaryProvider);
    ref.invalidate(adminSummaryProvider);
    if (detail) {
      ref.invalidate(adminPromotionHistoryProvider);
      ref.invalidate(
        adminDetailProvider((kind: 'promotions', id: '${row['id']}')),
      );
    }
  }

  final active = row['active'] != true;
  final automatic = row['application'] == 'AUTOMATIC';
  final label = automatic ? 'khuyến mãi' : 'mã khuyến mãi';
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title:
          '${remove
              ? 'Xóa'
              : active
              ? 'Bật'
              : 'Tắt'} $label',
      message: remove
          ? 'Xóa vĩnh viễn ${automatic ? row['name'] : row['code']}? Chỉ khuyến mãi chưa từng gắn với đơn hàng mới được xóa. Thao tác này không thể hoàn tác.'
          : row['application'] == 'AUTOMATIC'
          ? '${active ? 'Bật' : 'Tắt'} chương trình ${row['name']}? Giá hiển thị trên cửa hàng sẽ cập nhật theo thời hạn; đơn đã đặt giữ nguyên giá.'
          : active
          ? 'Bật mã ${row['code']}? Khách chỉ sử dụng được khi đúng thời hạn, đủ giá trị đơn và còn lượt.'
          : 'Ngừng áp dụng mã ${row['code']} cho đơn mới? Giá trị giảm của đơn đã đặt được giữ nguyên.',
      destructive: remove,
      submitLabel: remove ? 'Xác nhận xóa' : 'Xác nhận',
      reload: refresh,
      submit: () async {
        try {
          if (remove) {
            await repo.deletePromotion(
              '${row['id']}',
              row['version'] as int,
              onLateCompletion: refresh,
            );
          } else {
            await repo.savePromotion('${row['id']}', {
              'active': active,
              'expectedVersion': row['version'],
            }, onLateCompletion: refresh);
          }
          refresh(detail: !remove);
        } catch (_) {
          refresh();
          rethrow;
        }
      },
    ),
  );
  if (context.mounted && changed == true) {
    toast(
      context,
      'Đã ${remove
          ? 'xóa'
          : active
          ? 'bật'
          : 'tắt'} $label.',
    );
  }
  return changed == true;
}
