import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_presentation.dart';
import 'admin_widgets.dart';
import 'inventory_actions.dart';
import 'inventory_widgets.dart';
import 'order_presentation.dart';

class InventoryOverview extends ConsumerWidget {
  const InventoryOverview({super.key, required this.row});
  final AdminRecord row;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = row['variant'], p = v['product'];
    final role = ref.watch(staffRoleProvider);
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: inventoryPhoto(row),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p['name']}',
                    style: T.display(23).copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SelectableText('${v['sku']}', style: T.body),
                ],
              ),
            ),
            InventoryActions(row: row),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AdminStatus('Màu ${v['color']}'),
            AdminStatus('Cỡ ${v['size']}'),
            AdminStatus('${p['category']?['name'] ?? 'Chưa có danh mục'}'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Cập nhật ${adminOrderDate(row['updatedAt'])} (UTC+7)',
          style: T.small,
        ),
        if (v['active'] != true || p['active'] != true) ...[
          const SizedBox(height: 12),
          const Text(
            'Sản phẩm hoặc SKU đang ẩn. Nhập kho không tự bật bán.',
            style: T.small,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => context.go(
                Uri(
                  path: '/admin/inventory',
                  queryParameters: {'productId': '${p['id']}'},
                ).toString(),
              ),
              icon: const Icon(Icons.view_list_outlined, size: 18),
              label: const Text('Các SKU cùng sản phẩm'),
            ),
            if (canStaff(role, 'catalog.read'))
              TextButton.icon(
                onPressed: () => context.go('/admin/products/${p['id']}'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Xem sản phẩm'),
              ),
          ],
        ),
      ],
    );
    final balance = Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: T.canvas, borderRadius: T.radius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sẵn sàng bán', style: T.small),
          const SizedBox(height: 10),
          Text(
            '${adminNumber(row['quantity'])} đơn vị khả dụng',
            style: T.display(28).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: stockStatus(row['quantity']),
          ),
          const SizedBox(height: 16),
          if (canStaff(role, 'inventory.write')) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (mode, label, icon) in [
                  ('in', 'Nhập kho', Icons.add),
                  ('out', 'Xuất kho', Icons.remove),
                  ('count', 'Kiểm kê tồn kho', Icons.fact_check_outlined),
                ])
                  AppButton(
                    label,
                    icon: icon,
                    outlined: mode != 'in',
                    onPressed: () => adjustInventory(
                      context,
                      ref,
                      row,
                      '${v['sku']}',
                      mode: mode,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Đã trừ hàng dành cho đơn đặt thành công. Giỏ hàng không giữ hàng. Mọi điều chỉnh đều lưu vào lịch sử.',
            style: T.small,
          ),
        ],
      ),
    );
    return AdminCard(
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth >= 850 &&
              MediaQuery.textScalerOf(context).scale(14) <= 17) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: identity),
                const SizedBox(width: 32),
                Expanded(flex: 4, child: balance),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [identity, const SizedBox(height: 20), balance],
          );
        },
      ),
    );
  }
}
