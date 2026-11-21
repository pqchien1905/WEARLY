import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/format.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/commerce_json.dart';
import 'inventory_actions.dart' show adjustInventory;
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'product_editor_widgets.dart';

class ProductVariantSection extends ConsumerWidget {
  const ProductVariantSection({
    super.key,
    required this.product,
    this.locked = false,
    this.tableOnWide = false,
    this.lockedReason,
    this.visibleVariants,
    this.controls,
  });
  final AdminRecord product;
  final bool locked;
  final bool tableOnWide;
  final String? lockedReason;
  final List<AdminRecord>? visibleVariants;
  final Widget? controls;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variants = (product['variants'] as List? ?? [])
        .map(commerceMap)
        .toList();
    final role = ref.watch(staffRoleProvider),
        canWrite = canStaff(ref.watch(staffRoleProvider), 'catalog.write');
    final shown = visibleVariants ?? variants;
    return ProductEditorSection(
      title: 'Biến thể & tồn kho',
      description:
          '${variants.length} biến thể. Tổng tồn kho: ${variants.fold<int>(0, (n, v) => n + ((v['inventory']?['quantity'] as num?)?.toInt() ?? 0))} sản phẩm.',
      actions: [
        if (canWrite)
          AppButton(
            'Thêm biến thể',
            icon: Icons.add,
            outlined: true,
            onPressed: locked ? null : () => _sku(context, ref, product),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?controls,
          if (lockedReason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                lockedReason!,
                style: T.small.copyWith(color: T.warning),
              ),
            ),
          if (variants.isEmpty)
            const AdminCard(
              child: Text(
                'Chưa có biến thể. Hãy thêm size, màu và giá trước khi mở bán.',
                style: T.body,
              ),
            ),
          if (variants.isNotEmpty && shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Không có biến thể phù hợp. Thử đổi từ khóa hoặc xóa bộ lọc.',
                style: T.body,
              ),
            ),
          if (shown.isNotEmpty)
            LayoutBuilder(
              builder: (context, c) {
                if (tableOnWide &&
                    c.maxWidth >= 900 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 18) {
                  return SizedBox(
                    width: c.maxWidth,
                    child: DataTable(
                      columnSpacing: 18,
                      horizontalMargin: 0,
                      headingRowHeight: 48,
                      dataRowMinHeight: 76,
                      dataRowMaxHeight: double.infinity,
                      headingTextStyle: T.small.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      columns: const [
                        DataColumn(label: Text('SKU')),
                        DataColumn(label: Text('Màu / Cỡ')),
                        DataColumn(label: Text('Giá bán')),
                        DataColumn(label: Text('Tồn kho')),
                        DataColumn(label: Text('Trạng thái')),
                        DataColumn(label: Text('Thao tác')),
                      ],
                      rows: [
                        for (final variant in shown)
                          DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 190,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: SelectableText(
                                      '${variant['sku']}',
                                      style: T.small.copyWith(
                                        color: T.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    '${variant['color']} / ${variant['size']}',
                                    style: T.small,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  money(vnd(variant['price'])),
                                  style: T.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataCell(
                                variantStock(
                                  (variant['inventory']?['quantity'] as num?)
                                          ?.toInt() ??
                                      0,
                                ),
                              ),
                              DataCell(
                                AdminStatus(
                                  variant['active'] == true
                                      ? 'Đang bán'
                                      : 'Đã ẩn',
                                  color: variant['active'] == true
                                      ? T.success
                                      : T.muted,
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (canWrite)
                                      IconButton(
                                        tooltip: 'Sửa giá / trạng thái',
                                        onPressed: locked
                                            ? null
                                            : () => _sku(
                                                context,
                                                ref,
                                                product,
                                                variant: variant,
                                              ),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 20,
                                        ),
                                      ),
                                    if (variant['inventory'] != null &&
                                        canStaff(role, 'inventory.write'))
                                      IconButton(
                                        tooltip: 'Điều chỉnh kho',
                                        onPressed: locked
                                            ? null
                                            : () => adjustInventory(
                                                context,
                                                ref,
                                                commerceMap(
                                                  variant['inventory'],
                                                ),
                                                variant['sku'],
                                              ),
                                        icon: const Icon(
                                          Icons.inventory_2_outlined,
                                          size: 20,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final variant in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 0),
                        child: AdminCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SelectableText(
                                    '${variant['sku']}',
                                    style: T.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  AdminStatus(
                                    variant['active'] == true
                                        ? 'Đang bán'
                                        : 'Đã ẩn',
                                    color: variant['active'] == true
                                        ? T.success
                                        : T.muted,
                                  ),
                                ],
                              ),
                              Text(
                                '${variant['color']} / ${variant['size']} · ${money(vnd(variant['price']))}',
                                style: T.body,
                              ),
                              Text(
                                'Tồn kho: ${variant['inventory']?['quantity'] ?? 0} · ${(variant['inventory']?['quantity'] ?? 0) == 0
                                    ? 'Hết hàng'
                                    : (variant['inventory']?['quantity'] ?? 0) <= 5
                                    ? 'Sắp hết'
                                    : 'Còn hàng'}',
                                style: T.small,
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  if (canWrite)
                                    AppButton(
                                      'Sửa giá / trạng thái',
                                      outlined: true,
                                      onPressed: locked
                                          ? null
                                          : () => _sku(
                                              context,
                                              ref,
                                              product,
                                              variant: variant,
                                            ),
                                    ),
                                  if (variant['inventory'] != null &&
                                      canStaff(role, 'inventory.write'))
                                    AppButton(
                                      'Điều chỉnh kho',
                                      outlined: true,
                                      onPressed: locked
                                          ? null
                                          : () => adjustInventory(
                                              context,
                                              ref,
                                              commerceMap(variant['inventory']),
                                              variant['sku'],
                                            ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 12),
          const Text(
            'Giá bán và tồn kho được quản lý riêng cho từng SKU. Biến thể mới có tồn kho bằng 0.',
            style: T.small,
          ),
        ],
      ),
    );
  }
}

Future<void> _sku(
  BuildContext context,
  WidgetRef ref,
  AdminRecord product, {
  AdminRecord? variant,
}) async {
  final controls = {
    for (final key in ['sku', 'size', 'color', 'colorHex', 'price'])
      key: TextEditingController(
        text: variant?[key] ?? (key == 'colorHex' ? '#000000' : ''),
      ),
  };
  var active = variant?['active'] ?? true;
  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AdminMutationDialog(
        title: variant == null ? 'Thêm biến thể' : 'Sửa biến thể',
        message: variant == null
            ? 'Biến thể mới có tồn kho bằng 0. Nhập kho sau khi lưu.'
            : '${variant['sku']} · ${variant['color']} / ${variant['size']}',
        reload: () => refreshAdmin(ref),
        onDisposed: () {
          for (final control in controls.values) {
            control.dispose();
          }
        },
        fields: [
          if (variant == null) ...[
            AppField(
              label: 'Mã SKU',
              controller: controls['sku'],
              validator: (s) => requiredText(s, max: 100),
            ),
            AppField(
              label: 'Kích cỡ',
              controller: controls['size'],
              validator: (s) => requiredText(s, max: 30),
            ),
            AppField(
              label: 'Màu sắc',
              controller: controls['color'],
              validator: (s) => requiredText(s, max: 60),
            ),
            AppField(
              label: 'Mã màu HEX',
              controller: controls['colorHex'],
              validator: (s) => RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(s ?? '')
                  ? null
                  : 'Ví dụ: #000000',
            ),
          ],
          AppField(
            label: 'Giá bán (VND)',
            controller: controls['price'],
            keyboardType: TextInputType.number,
            validator: priceValidation,
          ),
          if (variant != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Đang bán'),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
        ],
        submit: () async {
          await repo.saveSku(
            variant?['id'],
            variant == null
                ? {
                    'productId': product['id'],
                    for (final e in controls.entries)
                      e.key: e.value.text.trim(),
                  }
                : {
                    if (controls['price']!.text.trim() != variant['price'])
                      'price': controls['price']!.text.trim(),
                    if (active != variant['active']) 'active': active,
                    if (variant['updatedAt'] != null)
                      'expectedUpdatedAt': variant['updatedAt'],
                  },
          );
        },
      ),
    ),
  );
  if (context.mounted && changed == true) {
    refreshAdmin(ref);
    ref.read(catalogRevisionProvider.notifier).refresh();
    toast(context, 'Đã lưu biến thể.');
  }
}
