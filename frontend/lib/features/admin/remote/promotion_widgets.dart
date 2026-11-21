import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';
import 'admin_providers.dart';
import 'admin_presentation.dart';
import 'promotion_editor.dart' show promotionDate;

const promotionStatuses = {
  'active': 'Đang áp dụng',
  'scheduled': 'Sắp bắt đầu',
  'expired': 'Hết hạn',
  'exhausted': 'Hết lượt',
  'inactive': 'Đã tắt',
};
Widget promotionStatus(AdminRecord row) => AdminStatus(
  promotionStatuses[row['status']] ??
      (row['active'] == true ? 'Đang bật' : 'Đã tắt'),
  color: switch (row['status']) {
    'active' => T.success,
    'scheduled' => T.accent,
    'exhausted' => T.warning,
    _ => T.muted,
  },
);

class PromotionOverview extends StatelessWidget {
  const PromotionOverview({super.key, required this.row});
  final AdminRecord row;
  @override
  Widget build(BuildContext context) {
    final automatic = row['application'] == 'AUTOMATIC';
    final used =
        (row['usedCount'] ?? row['_count']?['redemptions'] ?? 0) as int;
    final limit = row['usageLimit'] as int?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            promotionStatus(row),
            Text(
              row['kind'] == 'PERCENT'
                  ? 'Giảm theo phần trăm'
                  : 'Giảm số tiền cố định',
              style: T.small,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          (row['name'] as String? ?? '').isNotEmpty ? row['name'] : row['code'],
          style: T.display(24).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          automatic
              ? 'Tự động giảm giá · Không cần nhập mã'
              : 'Khách nhập mã khi thanh toán',
          style: T.small,
        ),
        Text(
          row['scope'] == 'PRODUCTS'
              ? 'Áp dụng: ${(row['products'] as List? ?? []).map((p) => p['name']).join(', ')}'
              : 'Áp dụng: toàn bộ sản phẩm',
          style: T.body,
        ),
        Text(
          row['kind'] == 'PERCENT'
              ? 'Giảm ${row['amount']}%'
              : 'Giảm ${adminMoney(row['amount'])}',
          style: T.body.copyWith(
            color: T.accent,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${automatic ? 'Giảm trên mỗi đơn vị sản phẩm' : 'Đơn từ ${adminMoney(row['minSubtotal'])}'}${row['maxDiscount'] == null ? '' : ' · Giảm tối đa ${adminMoney(row['maxDiscount'])}'}',
          style: T.body,
        ),
        const SizedBox(height: 12),
        Text(
          automatic
              ? '${adminNumber(used)} đơn hàng đã áp dụng'
              : 'Đã dùng: ${adminNumber(used)} / ${limit == null ? 'Không giới hạn' : adminNumber(limit)} · Mỗi khách: ${adminNumber(row['perUserLimit'])}',
          style: T.small,
        ),
        if (limit != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator(
              value: (used / limit).clamp(0, 1),
              minHeight: 5,
              semanticsLabel: 'Lượt sử dụng: $used trên $limit',
              color: T.accent,
              backgroundColor: T.line,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          row['startsAt'] == null
              ? 'Bắt đầu: khi bật mã'
              : 'Bắt đầu: ${promotionDate(row['startsAt'])} (UTC+7)',
          style: T.small,
        ),
        const SizedBox(height: 4),
        Text(
          row['expiresAt'] == null
              ? 'Hết hạn: không giới hạn'
              : 'Hết hạn: ${promotionDate(row['expiresAt'])} (UTC+7)',
          style: T.small,
        ),
      ],
    );
  }
}
