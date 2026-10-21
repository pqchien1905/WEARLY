import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/format.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/commerce_json.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

String promotionDate(Object? value) => value == null
    ? ''
    : DateTime.parse(value as String)
          .toUtc()
          .add(const Duration(hours: 7))
          .toIso8601String()
          .substring(0, 16)
          .replaceFirst('T', ' ');
DateTime? parsePromotionDate(String value) {
  if (value.trim().isEmpty) return null;
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$',
  ).firstMatch(value.trim());
  if (m == null) throw const FormatException('Dùng YYYY-MM-DD HH:mm (UTC+7).');
  final values = List.generate(5, (i) => int.parse(m.group(i + 1)!));
  final local = DateTime.utc(
    values[0],
    values[1],
    values[2],
    values[3],
    values[4],
  );
  if (local.year != values[0] ||
      local.month != values[1] ||
      local.day != values[2] ||
      local.hour != values[3] ||
      local.minute != values[4]) {
    throw const FormatException('Ngày giờ không hợp lệ.');
  }
  return local.subtract(const Duration(hours: 7));
}

class RemotePromotionsPage extends ConsumerStatefulWidget {
  const RemotePromotionsPage({super.key});
  @override
  ConsumerState<RemotePromotionsPage> createState() =>
      _RemotePromotionsPageState();
}

class _RemotePromotionsPageState extends ConsumerState<RemotePromotionsPage> {
  int page = 1;
  void refresh() => refreshAdmin(ref);
  Future<void> edit([AdminRecord? row]) async {
    final repo = ref.read(adminRepositoryProvider);
    final code = TextEditingController(text: row?['code'] ?? ''),
        amount = TextEditingController(text: row?['amount'] ?? '');
    final minimum = TextEditingController(text: row?['minSubtotal'] ?? '0'),
        cap = TextEditingController(text: row?['maxDiscount'] ?? '');
    final uses = TextEditingController(
          text: row?['usageLimit']?.toString() ?? '',
        ),
        personal = TextEditingController(
          text: row?['perUserLimit']?.toString() ?? '1',
        );
    final starts = TextEditingController(text: promotionDate(row?['startsAt'])),
        ends = TextEditingController(text: promotionDate(row?['expiresAt']));
    String? dateValue(TextEditingController controller, String field) =>
        row != null && controller.text.trim() == promotionDate(row[field])
        ? row[field] as String?
        : parsePromotionDate(controller.text)?.toIso8601String();
    var kind = row?['kind'] as String? ?? 'FIXED',
        active = row?['active'] as bool? ?? false;
    String? positive(String? value, {bool optional = false, int? max}) {
      final s = (value ?? '').trim();
      if (optional && s.isEmpty) return null;
      if (!RegExp(r'^[1-9]\d{0,13}$').hasMatch(s)) {
        return 'Nhập số nguyên dương.';
      }
      if (max != null && int.parse(s) > max) return 'Tối đa $max.';
      return null;
    }

    String? date(String? value) {
      try {
        parsePromotionDate(value ?? '');
        return null;
      } on FormatException catch (e) {
        return e.message;
      }
    }

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminMutationDialog(
        title: row == null ? 'Thêm mã khuyến mãi' : 'Chỉnh sửa ${row['code']}',
        message:
            'Giảm trên giá sản phẩm, không giảm phí giao hàng. Ngày giờ theo UTC+7. Để trống giới hạn tổng để không giới hạn.',
        onDisposed: () {
          for (final c in [
            code,
            amount,
            minimum,
            cap,
            uses,
            personal,
            starts,
            ends,
          ]) {
            c.dispose();
          }
        },
        fields: [
          StatefulBuilder(
            builder: (context, update) => Column(
              children: [
                TextFormField(
                  controller: code,
                  readOnly: row != null,
                  decoration: const InputDecoration(labelText: 'Mã khuyến mãi'),
                  validator: (v) =>
                      RegExp(
                        r'^[A-Z0-9_-]{3,32}$',
                      ).hasMatch((v ?? '').trim().toUpperCase())
                      ? null
                      : 'Dùng 3–32 chữ, số, dấu gạch ngang hoặc gạch dưới.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Loại giảm giá'),
                  items: const [
                    DropdownMenuItem(
                      value: 'FIXED',
                      child: Text('Số tiền VND'),
                    ),
                    DropdownMenuItem(
                      value: 'PERCENT',
                      child: Text('Phần trăm'),
                    ),
                  ],
                  onChanged: (v) => update(() => kind = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amount,
                  decoration: const InputDecoration(labelText: 'Giá trị giảm'),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      positive(v, max: kind == 'PERCENT' ? 100 : null),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: minimum,
                  decoration: const InputDecoration(
                    labelText: 'Giá sản phẩm tối thiểu (VND)',
                  ),
                  validator: priceValidation,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: cap,
                  decoration: const InputDecoration(
                    labelText: 'Giảm tối đa (VND, tùy chọn)',
                  ),
                  validator: (v) => positive(v, optional: true),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: uses,
                  decoration: const InputDecoration(
                    labelText: 'Tổng lượt tối đa (tùy chọn)',
                  ),
                  validator: (v) =>
                      positive(v, optional: true, max: 2147483647),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: personal,
                  decoration: const InputDecoration(
                    labelText: 'Lượt tối đa mỗi khách',
                  ),
                  validator: (v) => positive(v, max: 2147483647),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: starts,
                  decoration: const InputDecoration(
                    labelText: 'Bắt đầu (UTC+7)',
                    hintText: 'YYYY-MM-DD HH:mm',
                  ),
                  validator: date,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: ends,
                  decoration: const InputDecoration(
                    labelText: 'Hết hạn (UTC+7)',
                    hintText: 'YYYY-MM-DD HH:mm',
                  ),
                  validator: date,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang áp dụng'),
                  value: active,
                  onChanged: (v) => update(() => active = v),
                ),
              ],
            ),
          ),
        ],
        reload: refresh,
        submit: () => repo.savePromotion(row?['id'], {
          if (row == null)
            'code': code.text.trim().toUpperCase()
          else
            'expectedVersion': row['version'],
          'kind': kind,
          'amount': amount.text.trim(),
          'active': active,
          'minSubtotal': minimum.text.trim(),
          'maxDiscount': cap.text.trim().isEmpty ? null : cap.text.trim(),
          'usageLimit': uses.text.trim().isEmpty
              ? null
              : int.parse(uses.text.trim()),
          'perUserLimit': int.parse(personal.text.trim()),
          'startsAt': dateValue(starts, 'startsAt'),
          'expiresAt': dateValue(ends, 'expiresAt'),
        }),
      ),
    );
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminHeading(
        'Khuyến mãi',
        'Lượt dùng được giữ khi tạo đơn và trả lại khi hủy đơn đang chờ.',
        actions: [
          AppButton('Thêm mã khuyến mãi', onPressed: edit),
          AppButton('Tải lại', outlined: true, onPressed: refresh),
        ],
      ),
      AdminAsync(
        value: ref.watch(adminListProvider((kind: 'promotions', page: page))),
        reload: refresh,
        builder: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data.items.isEmpty)
              const Text('Chưa có mã khuyến mãi.', style: T.body),
            for (final row in data.items)
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row['code'], style: T.display(24)),
                    Text(
                      '${row['kind'] == 'PERCENT' ? '${row['amount']}%' : money(vnd(row['amount']))} · ${row['active'] == true ? 'Đang bật' : 'Đã tắt'}',
                      style: T.body,
                    ),
                    Text(
                      'Đã dùng: ${row['_count']?['redemptions'] ?? 0} / ${row['usageLimit'] ?? 'Không giới hạn'} · Mỗi khách: ${row['perUserLimit']}',
                      style: T.small,
                    ),
                    Text(
                      'Tối thiểu: ${money(vnd(row['minSubtotal']))}${row['maxDiscount'] == null ? '' : ' · Giảm tối đa: ${money(vnd(row['maxDiscount']))}'}',
                      style: T.small,
                    ),
                    if (row['startsAt'] != null)
                      Text(
                        'Bắt đầu: ${promotionDate(row['startsAt'])} (UTC+7)',
                        style: T.small,
                      ),
                    if (row['expiresAt'] != null)
                      Text(
                        'Hết hạn: ${promotionDate(row['expiresAt'])} (UTC+7)',
                        style: T.small,
                      ),
                    const SizedBox(height: 12),
                    AppButton(
                      'Chỉnh sửa ${row['code']}',
                      outlined: true,
                      onPressed: () => edit(row),
                    ),
                  ],
                ),
              ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: page > 1 ? () => setState(() => page--) : null,
                  child: const Text('Trang trước'),
                ),
                Text('Trang $page'),
                TextButton(
                  onPressed: data.hasNext ? () => setState(() => page++) : null,
                  child: const Text('Trang sau'),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
