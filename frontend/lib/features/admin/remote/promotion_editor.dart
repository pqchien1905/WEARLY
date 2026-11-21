import '../../../app/providers.dart' show catalogRevisionProvider;
import 'promotion_product_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';

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
  if (values[0] < 1 ||
      local.year != values[0] ||
      local.month != values[1] ||
      local.day != values[2] ||
      local.hour != values[3] ||
      local.minute != values[4]) {
    throw const FormatException('Ngày giờ không hợp lệ.');
  }
  return local.subtract(const Duration(hours: 7));
}

Future<void> editPromotion(
  BuildContext context,
  WidgetRef ref,
  AdminRecord? row,
) async {
  void refresh() {
    if (context.mounted) {
      refreshAdmin(ref);
      ref.read(catalogRevisionProvider.notifier).refresh();
    }
  }

  final repo = ref.read(adminRepositoryProvider);
  final name = TextEditingController(text: row?['name'] ?? '');
  var application =
      row?['application'] as String? ?? (row == null ? 'AUTOMATIC' : 'CODE');
  var scope = row?['scope'] as String? ?? 'ALL';
  var selectedProducts = <String, String>{
    for (final p in row?['products'] as List? ?? [])
      '${p['id']}': '${p['name']}',
  };
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
  Future<void> pickDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    DateTime initial = DateTime.now().toUtc().add(const Duration(hours: 7));
    try {
      initial =
          parsePromotionDate(controller.text)?.add(const Duration(hours: 7)) ??
          initial;
    } on FormatException {
      /* Keep the current date when input is invalid. */
    }
    final selected = await showDatePicker(
      context: context,
      initialDate: initial.year < 1900 || initial.year > 9999
          ? DateTime.now()
          : initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (selected == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !context.mounted) return;
    final utc = DateTime.utc(
      selected.year,
      selected.month,
      selected.day,
      time.hour,
      time.minute,
    ).subtract(const Duration(hours: 7));
    controller.text = promotionDate(utc.toIso8601String());
  }

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

  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: row == null ? 'Thêm khuyến mãi' : 'Chỉnh sửa khuyến mãi',
      message:
          'Tự động: giá giảm hiển thị ngay cho khách, chọn ưu đãi tốt nhất cho từng sản phẩm. Nhập mã: giảm thêm trên tiền hàng sau ưu đãi tự động. Thời gian UTC+7.',
      onDisposed: () {
        for (final c in [
          name,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionTitle('Cách áp dụng & sản phẩm'),
              DropdownButtonFormField<String>(
                initialValue: application,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Cách áp dụng'),
                items: const [
                  DropdownMenuItem(
                    value: 'AUTOMATIC',
                    child: Text('Tự động giảm giá'),
                  ),
                  DropdownMenuItem(value: 'CODE', child: Text('Khách nhập mã')),
                ],
                onChanged: row != null
                    ? null
                    : (v) => update(() => application = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Tên chương trình',
                ),
                maxLength: 120,
                validator: (v) =>
                    application == 'AUTOMATIC' && (v ?? '').trim().isEmpty
                    ? 'Nhập tên hiển thị cho khách hàng.'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: scope,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Phạm vi áp dụng'),
                items: const [
                  DropdownMenuItem(
                    value: 'ALL',
                    child: Text('Toàn bộ sản phẩm'),
                  ),
                  DropdownMenuItem(
                    value: 'PRODUCTS',
                    child: Text('Một số sản phẩm'),
                  ),
                ],
                onChanged: (v) => update(() => scope = v!),
              ),
              if (scope == 'PRODUCTS') ...[
                const SizedBox(height: 12),
                FormField<int>(
                  validator: (_) => selectedProducts.isEmpty
                      ? 'Chọn ít nhất một sản phẩm.'
                      : null,
                  builder: (field) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.checklist),
                        label: Text(
                          'Chọn sản phẩm (${selectedProducts.length})',
                        ),
                        onPressed: () async {
                          final chosen = await showDialog<Map<String, String>>(
                            context: context,
                            builder: (_) => PromotionProductPicker(
                              selected: selectedProducts,
                            ),
                          );
                          if (chosen != null && context.mounted) {
                            update(() => selectedProducts = chosen);
                            field.didChange(chosen.length);
                          }
                        },
                      ),
                      for (final product in selectedProducts.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• ${product.value}', style: T.small),
                        ),
                      if (field.hasError)
                        Text(
                          field.errorText!,
                          style: const TextStyle(color: T.danger),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const AdminSectionTitle('Thông tin giảm giá'),
              if (application == 'CODE')
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
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Loại giảm giá'),
                items: const [
                  DropdownMenuItem(
                    value: 'FIXED',
                    child: Text('Số tiền VND', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'PERCENT',
                    child: Text('Phần trăm', overflow: TextOverflow.ellipsis),
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
              if (application == 'CODE')
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
                decoration: InputDecoration(
                  labelText: 'Giảm tối đa (VND, tùy chọn)',
                  helperText: application == 'AUTOMATIC'
                      ? 'Giới hạn giảm cho mỗi đơn vị sản phẩm.'
                      : 'Giới hạn giảm cho toàn đơn hàng.',
                ),
                validator: (v) => positive(v, optional: true),
              ),
              const SizedBox(height: 16),
              if (application == 'CODE') ...[
                const AdminSectionTitle('Giới hạn sử dụng'),
                const Text(
                  'Lượt dùng được giữ khi tạo đơn và trả lại khi hủy đơn hợp lệ trước giao hàng. Giới hạn mới chỉ áp dụng cho lần đặt tiếp theo.',
                  style: T.small,
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
              ],
              const AdminSectionTitle('Thời gian áp dụng'),
              const Text(
                'Để trống ngày bắt đầu để áp dụng ngay khi bật. Để trống ngày hết hạn để không giới hạn thời gian.',
                style: T.small,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: starts,
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    tooltip: 'Chọn ngày bắt đầu',
                    icon: const Icon(Icons.event_outlined),
                    onPressed: () => pickDate(context, starts),
                  ),
                  labelText: 'Bắt đầu (UTC+7)',
                  hintText: 'YYYY-MM-DD HH:mm',
                ),
                validator: date,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: ends,
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    tooltip: 'Chọn ngày hết hạn',
                    icon: const Icon(Icons.event_outlined),
                    onPressed: () => pickDate(context, ends),
                  ),
                  labelText: 'Hết hạn (UTC+7)',
                  hintText: 'YYYY-MM-DD HH:mm',
                ),
                validator: (v) {
                  final error = date(v);
                  if (error != null) return error;
                  if (date(starts.text) != null) return null;
                  final a = dateValue(starts, 'startsAt'),
                      b = dateValue(ends, 'expiresAt');
                  if (a != null &&
                      b != null &&
                      !DateTime.parse(b).isAfter(DateTime.parse(a))) {
                    return 'Hết hạn phải sau ngày bắt đầu.';
                  }
                  return null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bật khuyến mãi'),
                subtitle: Text(
                  application == 'AUTOMATIC'
                      ? 'Giá giảm tự hiển thị trong thời hạn, không cần nhập mã.'
                      : 'Khách dùng mã trong thời hạn và khi còn lượt.',
                ),
                value: active,
                onChanged: (v) => update(() => active = v),
              ),
            ],
          ),
        ),
      ],
      reload: refresh,
      submit: () => repo.savePromotion(row?['id'], {
        if (row == null && application == 'CODE')
          'code': code.text.trim().toUpperCase(),
        if (row != null) 'expectedVersion': row['version'],
        'name': name.text.trim(),
        'application': application,
        'scope': scope,
        'productIds': scope == 'ALL'
            ? <String>[]
            : selectedProducts.keys.toList(),
        'kind': kind,
        'amount': amount.text.trim(),
        'active': active,
        'minSubtotal': application == 'AUTOMATIC' ? '0' : minimum.text.trim(),
        'maxDiscount': cap.text.trim().isEmpty ? null : cap.text.trim(),
        'usageLimit': application == 'AUTOMATIC' || uses.text.trim().isEmpty
            ? null
            : int.parse(uses.text.trim()),
        'perUserLimit': application == 'AUTOMATIC'
            ? 1
            : int.parse(personal.text.trim()),
        'startsAt': dateValue(starts, 'startsAt'),
        'expiresAt': dateValue(ends, 'expiresAt'),
      }, onLateCompletion: refresh),
    ),
  );
  if (context.mounted && changed == true) {
    refresh();
    toast(
      context,
      application == 'AUTOMATIC'
          ? (row == null
                ? 'Đã thêm khuyến mãi tự động.'
                : 'Đã cập nhật khuyến mãi tự động.')
          : (row == null
                ? 'Đã thêm mã khuyến mãi.'
                : 'Đã cập nhật mã khuyến mãi.'),
    );
  }
}
