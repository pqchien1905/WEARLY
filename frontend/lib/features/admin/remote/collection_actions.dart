import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

String collectionsBack(String? from) {
  final uri = Uri.tryParse(from ?? '');
  return uri != null &&
          !uri.hasScheme &&
          !uri.hasAuthority &&
          !uri.hasFragment &&
          uri.path == '/admin/collections'
      ? uri.toString()
      : '/admin/collections';
}

String collectionProducts(AdminRecord row, {String? visibility}) => Uri(
  path: '/admin/products',
  queryParameters: {'style': '${row['style']}', 'visibility': ?visibility},
).toString();
bool collectionPublished(AdminRecord row) =>
    row['active'] == true && (row['productCount'] as num? ?? 0) > 0;

Future<bool> changeCollection(
  BuildContext context,
  WidgetRef ref,
  AdminRecord row, {
  bool remove = false,
}) async {
  final repo = ref.read(adminRepositoryProvider);
  final revision = ref.read(catalogRevisionProvider.notifier);
  void refresh({bool detail = true}) {
    revision.refresh();
    if (!context.mounted) return;
    ref.invalidate(adminCollectionsProvider);
    ref.invalidate(adminCollectionSummaryProvider);
    ref.invalidate(adminCollectionStylesProvider);
    if (detail) {
      ref.invalidate(
        adminDetailProvider((kind: 'collections', id: '${row['id']}')),
      );
    }
  }

  final active = row['active'] != true;
  final action = remove
      ? 'Xóa bộ sưu tập'
      : active
      ? 'Hiện bộ sưu tập'
      : 'Ẩn bộ sưu tập';
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: action,
      submitLabel: remove ? 'Xác nhận xóa' : 'Xác nhận',
      destructive: remove,
      message: remove
          ? 'Xóa vĩnh viễn “${row['title']}” và đường dẫn /collections/${row['slug']}? Sản phẩm và tồn kho được giữ nguyên. Thao tác này không thể hoàn tác.'
          : active
          ? 'Hiện “${row['title']}” tại cửa hàng khi có sản phẩm công khai cùng phong cách. Bộ chưa đủ điều kiện sẽ ở trạng thái chờ.'
          : 'Ẩn “${row['title']}” và trang chi tiết của bộ tại cửa hàng. Sản phẩm vẫn giữ nguyên trạng thái bán.',
      reload: refresh,
      submit: () async {
        try {
          if (remove) {
            await repo.deleteCollection(
              '${row['id']}',
              row['version'] as int,
              onLateCompletion: refresh,
            );
          } else {
            await repo.saveCollection('${row['id']}', {
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
      remove
          ? 'Đã xóa bộ sưu tập.'
          : active
          ? 'Đã bật bộ sưu tập.'
          : 'Đã ẩn bộ sưu tập.',
    );
  }
  return changed == true;
}
