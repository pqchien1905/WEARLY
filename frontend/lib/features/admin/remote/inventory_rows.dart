import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_presentation.dart';
import 'inventory_actions.dart';
import 'inventory_widgets.dart';
import 'order_presentation.dart';
import 'admin_column_row.dart';

const _columns = [240.0, 160.0, 140.0, 115.0, 140.0, 200.0];

/// Flexible rows keep identifiers readable without forcing a horizontal table
/// on a small screen or when the user enlarges text.
class InventoryRows extends ConsumerWidget {
  const InventoryRows({super.key, required this.rows, required this.open});
  final List<AdminRecord> rows;
  final void Function(AdminRecord) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, c) {
      final wide =
          c.maxWidth >= 1100 &&
          MediaQuery.textScalerOf(context).scale(14) <= 17;
      final writable = canStaff(
        ref.watch(staffRoleProvider),
        'inventory.write',
      );
      return Material(
        color: T.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: T.radius,
          side: BorderSide(color: T.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            if (wide)
              const AdminColumnRow(
                widths: _columns,
                header: true,
                children: [
                  Text('Sản phẩm', style: T.small),
                  Text('Mã SKU', style: T.small),
                  Text('Màu / Kích cỡ', style: T.small),
                  Text('Tồn kho khả dụng', style: T.small),
                  Text('Cập nhật (UTC+7)', style: T.small),
                  Text('Thao tác', style: T.small),
                ],
              ),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0 || wide) const Divider(height: 1, color: T.line),
              _row(context, ref, rows[i], wide, writable),
            ],
          ],
        ),
      );
    },
  );

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    AdminRecord row,
    bool wide,
    bool writable,
  ) {
    final v = row['variant'], p = v['product'];
    final quantity = row['quantity'] as int?;
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: inventoryPhoto(row),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row['id'] != null)
                TextButton(
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 48),
                    foregroundColor: T.ink,
                  ),
                  onPressed: () => open(row),
                  child: Text(
                    '${p['name']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                )
              else
                Text(
                  '${p['name']}',
                  style: T.body.copyWith(fontWeight: FontWeight.w600),
                ),
              if (!wide)
                Tooltip(
                  message: '${v['sku']}',
                  child: Text(
                    '${v['sku']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.small,
                  ),
                ),
              if (!wide) const SizedBox(height: 4),
              Text(
                wide
                    ? '${p['category']?['name'] ?? '—'}'
                    : '${v['color']} / ${v['size']} · ${p['category']?['name'] ?? '—'}',
                style: T.small,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (v['active'] != true || p['active'] != true)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Đã ngừng bán / ẩn', style: T.small),
                ),
            ],
          ),
        ),
      ],
    );
    final balance = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          quantity == null ? '—' : adminNumber(quantity),
          style: T
              .display(20)
              .copyWith(
                fontWeight: FontWeight.w600,
                color: quantity == 0 ? T.danger : T.ink,
              ),
        ),
        const SizedBox(height: 6),
        stockStatus(quantity),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (writable && row['id'] != null)
          AppButton(
            'Nhập kho',
            outlined: true,
            icon: Icons.add,
            onPressed: () =>
                adjustInventory(context, ref, row, '${v['sku']}', mode: 'in'),
          ),
        InventoryActions(row: row, details: () => open(row)),
      ],
    );
    return Padding(
      padding: wide
          ? const EdgeInsets.symmetric(vertical: 12)
          : const EdgeInsets.all(16),
      child: wide
          ? AdminColumnRow(
              widths: _columns,
              children: [
                identity,
                SelectableText('${v['sku']}', style: T.small),
                Text('${v['color']} / ${v['size']}', style: T.body),
                balance,
                Text(adminOrderDate(row['updatedAt']), style: T.small),
                actions,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 16),
                Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [balance, actions],
                ),
                const SizedBox(height: 14),
                Text(
                  'Cập nhật ${adminOrderDate(row['updatedAt'])} (UTC+7)',
                  style: T.small,
                ),
                if (row['id'] != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => open(row),
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('Chi tiết & lịch sử'),
                    ),
                  ),
              ],
            ),
    );
  }
}
