import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../app/providers.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'inventory_actions.dart';

String inventoryBack(String? value) {
  final uri = Uri.tryParse(value ?? '');
  return uri != null &&
          !uri.hasScheme &&
          !uri.hasAuthority &&
          uri.path == '/admin/inventory'
      ? uri.toString()
      : '/admin/inventory';
}

Widget stockStatus(int? quantity) => AdminStatus(
  quantity == null
      ? 'Chưa có kho'
      : quantity == 0
      ? 'Hết hàng'
      : quantity <= 5
      ? 'Sắp hết hàng'
      : 'Còn hàng',
  color: quantity == null
      ? T.muted
      : quantity == 0
      ? T.danger
      : quantity <= 5
      ? T.warning
      : T.success,
);
Widget inventoryPhoto(AdminRecord row) {
  final images = row['variant']['product']['images'] as List? ?? [];
  return SizedBox(
    width: 52,
    height: 64,
    child: images.isEmpty
        ? const Icon(Icons.image_outlined, color: T.muted)
        : FashionImage(
            images.first['url'],
            label: '${row['variant']['product']['name']}',
            fit: BoxFit.cover,
          ),
  );
}

class InventoryActions extends ConsumerWidget {
  const InventoryActions({super.key, required this.row, this.details});
  final AdminRecord row;
  final VoidCallback? details;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'Thao tác kho',
    onSelected: (value) async {
      if (value == 'detail') {
        details?.call();
        return;
      }
      if (value == 'initialize') {
        final repo = ref.read(adminRepositoryProvider);
        final changed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AdminMutationDialog(
            title: 'Khởi tạo bản ghi kho',
            message:
                '${row['variant']['sku']} sẽ có tồn kho bằng 0. Việc này không nhập thêm hàng.',
            reload: () => refreshAdmin(ref),
            submit: () async {
              await repo.initializeInventory(row['variantId']);
            },
          ),
        );
        if (context.mounted && changed == true) {
          refreshAdmin(ref);
          ref.read(catalogRevisionProvider.notifier).refresh();
          toast(context, 'Đã khởi tạo kho bằng 0.');
        }
        return;
      }
      await adjustInventory(
        context,
        ref,
        row,
        row['variant']['sku'],
        mode: value,
      );
    },
    itemBuilder: (_) => [
      if (details != null && row['id'] != null)
        const PopupMenuItem(value: 'detail', child: Text('Chi tiết & lịch sử')),
      if (canStaff(ref.watch(staffRoleProvider), 'inventory.write')) ...[
        if (row['id'] == null)
          const PopupMenuItem(
            value: 'initialize',
            child: Text('Khởi tạo kho 0'),
          )
        else ...[
          const PopupMenuItem(value: 'in', child: Text('Nhập kho')),
          const PopupMenuItem(value: 'out', child: Text('Xuất kho')),
          const PopupMenuItem(value: 'count', child: Text('Kiểm kê tồn kho')),
        ],
      ],
    ],
  );
}

class InventoryPager extends StatelessWidget {
  const InventoryPager({super.key, required this.page, required this.go});
  final AdminPage page;
  final void Function(int) go;
  @override
  Widget build(BuildContext context) => AdminPagination(page: page, onPage: go);
}
