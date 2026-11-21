import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_presentation.dart';
import 'admin_column_row.dart';
import 'promotion_editor.dart' show promotionDate;
import 'promotion_widgets.dart';

const _promotionColumnWidths = <double>[230, 110, 155, 160, 175, 125, 220];
bool _promotionColumns(BuildContext context, double width) =>
    width >= 1200 && MediaQuery.textScalerOf(context).scale(14) <= 18;

class PromotionListHeader extends StatelessWidget {
  const PromotionListHeader({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => _promotionColumns(context, c.maxWidth)
        ? const Padding(
            padding: EdgeInsets.only(top: 16),
            child: AdminColumnRow(
              widths: _promotionColumnWidths,
              header: true,
              children: [
                Text('Chương trình'),
                Text('Trạng thái'),
                Text('Áp dụng'),
                Text('Ưu đãi & điều kiện'),
                Text('Thời hạn (UTC+7)'),
                Text('Lượt sử dụng'),
                Text('Thao tác'),
              ],
            ),
          )
        : const SizedBox.shrink(),
  );
}

class PromotionSummary extends StatelessWidget {
  const PromotionSummary({
    super.key,
    required this.summary,
    required this.status,
    required this.onSelect,
  });
  final AdminRecord summary;
  final String status;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
      final columns = c.maxWidth >= 850 && !largeText
          ? 4
          : c.maxWidth >= 300 && !largeText
          ? 2
          : 1;
      final items = [
        ('', 'Tổng khuyến mãi', 'total', Icons.local_offer_outlined, T.accent),
        ('active', 'Đang áp dụng', 'active', Icons.sell_outlined, T.success),
        (
          'scheduled',
          'Sắp bắt đầu',
          'scheduled',
          Icons.event_outlined,
          T.accent,
        ),
        (
          'exhausted',
          'Hết lượt',
          'exhausted',
          Icons.hourglass_empty_rounded,
          T.warning,
        ),
      ];
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: (c.maxWidth - (columns - 1) * 12) / columns,
                child: Semantics(
                  selected: status == item.$1,
                  child: Material(
                    color: status == item.$1 ? T.soft : T.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: T.radius,
                      side: BorderSide(
                        color: status == item.$1 ? T.accent : T.line,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: T.radius,
                      onTap: () => onSelect(item.$1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$2, style: T.small),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    adminNumber(summary[item.$3]),
                                    style: T
                                        .display(28)
                                        .copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Icon(item.$4, size: 22, color: item.$5),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

enum PromotionListAction { toggle, delete }

class PromotionListItem extends StatelessWidget {
  const PromotionListItem({
    super.key,
    required this.row,
    required this.onOpen,
    required this.onEdit,
    required this.onAction,
  });
  final AdminRecord row;
  final VoidCallback onOpen, onEdit;
  final ValueChanged<PromotionListAction> onAction;

  Widget section(
    String label,
    List<Widget> children, {
    required bool showLabel,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showLabel) ...[
        Text(label, style: T.small),
        const SizedBox(height: 8),
      ],
      ...children,
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = _promotionColumns(context, c.maxWidth);
      final automatic = row['application'] == 'AUTOMATIC';
      final targeting = section('Áp dụng', showLabel: !wide, [
        Text(automatic ? 'Tự động giảm giá' : 'Khách nhập mã', style: T.body),
        const SizedBox(height: 4),
        Text(
          row['scope'] == 'PRODUCTS'
              ? '${(row['productIds'] as List? ?? []).length} sản phẩm đã chọn'
              : 'Toàn bộ sản phẩm',
          style: T.small,
        ),
      ]);
      final used =
          (row['usedCount'] ?? row['_count']?['redemptions'] ?? 0) as int;
      final limit = row['usageLimit'] as int?;
      final discount = row['kind'] == 'PERCENT'
          ? 'Giảm ${row['amount']}%'
          : 'Giảm ${adminMoney(row['amount'])}';
      final identity = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (row['name'] as String? ?? '').isNotEmpty
                ? row['name']
                : row['code'],
            style: T.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (!automatic && (row['name'] as String? ?? '').isNotEmpty)
            Text('${row['code']}', style: T.small),
          if (!wide) ...[
            const SizedBox(height: 10),
            const Text('Trạng thái', style: T.small),
            const SizedBox(height: 6),
            promotionStatus(row),
          ],
        ],
      );
      final offer = section('Ưu đãi & điều kiện', showLabel: !wide, [
        Text(
          discount,
          style: T.body.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: T.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          automatic
              ? 'Giảm trên mỗi sản phẩm'
              : 'Đơn từ ${adminMoney(row['minSubtotal'])}',
          style: T.small,
        ),
        if (row['maxDiscount'] != null)
          Text('Tối đa ${adminMoney(row['maxDiscount'])}', style: T.small),
      ]);
      final dates = section('Thời hạn (UTC+7)', showLabel: !wide, [
        Text(
          row['startsAt'] == null
              ? 'Bắt đầu khi bật'
              : 'Từ ${promotionDate(row['startsAt'])}',
          style: T.small.copyWith(color: T.ink),
        ),
        const SizedBox(height: 4),
        Text(
          row['expiresAt'] == null
              ? 'Không giới hạn thời hạn'
              : 'Đến ${promotionDate(row['expiresAt'])}',
          style: T.small.copyWith(color: T.ink),
        ),
      ]);
      final usage = section('Lượt sử dụng', showLabel: !wide, [
        Text(
          automatic
              ? '${adminNumber(used)} đơn hàng'
              : '${adminNumber(used)} / ${limit == null ? 'Không giới hạn' : adminNumber(limit)}',
          style: T.body.copyWith(fontWeight: FontWeight.w600),
        ),
        if (limit != null && limit > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(
              value: (used / limit).clamp(0, 1),
              minHeight: 4,
              borderRadius: T.radius,
              semanticsLabel: 'Lượt sử dụng: $used trên $limit',
              color: used >= limit ? T.warning : T.accent,
              backgroundColor: T.line,
            ),
          ),
        Text(
          automatic
              ? 'Không cần nhập mã'
              : 'Mỗi khách: ${adminNumber(row['perUserLimit'])}',
          style: T.small,
        ),
      ]);
      final edit = Tooltip(
        message: 'Chỉnh sửa ${automatic ? row['name'] : row['code']}',
        child: TextButton(onPressed: onEdit, child: const Text('Chỉnh sửa')),
      );
      final menu = PopupMenuButton<PromotionListAction>(
        tooltip: 'Thao tác khác: ${automatic ? row['name'] : row['code']}',
        icon: const Icon(Icons.more_horiz),
        onSelected: onAction,
        itemBuilder: (_) => [
          PopupMenuItem(
            value: PromotionListAction.toggle,
            child: Text(
              automatic
                  ? (row['active'] == true
                        ? 'Tắt khuyến mãi'
                        : 'Bật khuyến mãi')
                  : (row['active'] == true ? 'Tắt mã' : 'Bật mã'),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: PromotionListAction.delete,
            enabled: row['canDelete'] == true,
            child: Text(
              automatic ? 'Xóa khuyến mãi' : 'Xóa mã khuyến mãi',
              style: TextStyle(
                color: row['canDelete'] == true ? T.danger : T.muted,
              ),
            ),
          ),
          if (row['canDelete'] != true)
            const PopupMenuItem<PromotionListAction>(
              enabled: false,
              child: Text(
                'Mã có lịch sử đơn hàng chỉ có thể tắt.',
                style: T.small,
              ),
            ),
        ],
      );
      return Container(
        padding: EdgeInsets.symmetric(vertical: wide ? 12 : 20),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: T.line)),
        ),
        child: wide
            ? AdminColumnRow(
                widths: _promotionColumnWidths,
                children: [
                  identity,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: promotionStatus(row),
                  ),
                  targeting,
                  offer,
                  dates,
                  usage,
                  AdminRowActions(onOpen: onOpen, edit: edit, menu: menu),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, details) {
                      final columns =
                          details.maxWidth >= 620 &&
                              MediaQuery.textScalerOf(context).scale(14) <= 18
                          ? 3
                          : details.maxWidth >= 450
                          ? 2
                          : 1;
                      return Wrap(
                        spacing: 20,
                        runSpacing: 16,
                        children: [
                          for (final child in [targeting, offer, dates, usage])
                            SizedBox(
                              width:
                                  (details.maxWidth - (columns - 1) * 20) /
                                  columns,
                              child: child,
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppButton(
                        'Xem chi tiết',
                        outlined: true,
                        onPressed: onOpen,
                      ),
                      edit,
                      menu,
                    ],
                  ),
                ],
              ),
      );
    },
  );
}
