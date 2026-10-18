import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/format.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/commerce_json.dart';
import 'admin_pages.dart' show adjustInventory;
import 'admin_providers.dart';
import 'admin_widgets.dart';

class RemoteProductEditor extends ConsumerWidget {
  const RemoteProductEditor({super.key, this.id});
  final String? id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AdminAsync(
    value: ref.watch(adminReferencesProvider),
    reload: () => ref.invalidate(adminReferencesProvider),
    builder: (references) {
      if (id == null) return _ProductForm(references: references);
      final key = (kind: 'products', id: id!);
      return AdminAsync(
        value: ref.watch(adminDetailProvider(key)),
        reload: () => ref.invalidate(adminDetailProvider(key)),
        builder: (product) => _ProductForm(
          key: ValueKey(id),
          product: product,
          references: references,
        ),
      );
    },
  );
}

class _ImageFields {
  _ImageFields(AdminRecord image)
    : url = TextEditingController(text: image['url'] ?? ''),
      alt = TextEditingController(text: image['alt'] ?? ''),
      color = TextEditingController(text: image['color'] ?? '');
  final TextEditingController url, alt, color;
  void dispose() {
    url.dispose();
    alt.dispose();
    color.dispose();
  }

  AdminRecord json() => {
    'url': url.text.trim(),
    'alt': alt.text.trim(),
    if (color.text.trim().isNotEmpty) 'color': color.text.trim(),
  };
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({super.key, this.product, required this.references});
  final AdminRecord? product;
  final AdminRecord references;
  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final images = <_ImageFields>[];
  final removedImages = <_ImageFields>[];
  late final AdminRecord baseline;
  bool active = false, tryOn = false, saving = false;
  String? category, brand, error;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    for (final key in ['name', 'slug', 'description', 'material', 'style']) {
      fields[key] = TextEditingController(text: p?[key] ?? '');
    }
    active = p?['active'] ?? false;
    tryOn = p?['tryOnSupported'] ?? false;
    category = p?['categoryId'];
    brand = p?['brandId'];
    for (final image in (p?['images'] ?? []) as List) {
      images.add(_ImageFields(commerceMap(image)));
    }
    baseline = draft();
  }

  AdminRecord draft() => {
    for (final entry in fields.entries) entry.key: entry.value.text.trim(),
    'categoryId': category,
    'brandId': brand,
    'active': active,
    'tryOnSupported': tryOn,
    'images': images.map((i) => i.json()).toList(),
  };

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    for (final image in [...images, ...removedImages]) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    final snapshot = draft();
    // PATCH only the fields edited in this form. In particular an unchanged
    // gallery must not replace images another administrator added meanwhile.
    final changes = widget.product == null
        ? snapshot
        : <String, dynamic>{
            for (final entry in snapshot.entries)
              if (jsonEncode(entry.value) != jsonEncode(baseline[entry.key]))
                entry.key: entry.value,
          };
    if (changes.isEmpty) {
      toast(context, 'Không có thay đổi cần lưu.');
      return;
    }
    final repo = ref.read(adminRepositoryProvider);
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await repo.saveProduct(widget.product?['id'], changes);
      if (!mounted) return;
      // Advance only confirmed edits, not untouched fields from a newer server
      // response, since those may differ from the form still on screen.
      baseline.addAll(changes);
      refreshAdmin(ref);
      ref.read(catalogRevisionProvider.notifier).refresh();
      toast(context, 'Đã lưu thông tin sản phẩm.');
      if (widget.product == null) {
        context.go('/admin/products/${saved['id']}/edit');
      }
    } catch (e) {
      if (mounted) setState(() => error = adminError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final variants = (widget.product?['variants'] ?? []) as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          widget.product == null ? 'Thêm sản phẩm' : 'Chỉnh sửa sản phẩm',
          'Lưu thông tin trước, sau đó thêm biến thể và nhập kho.',
          actions: [
            AppButton(
              'Về danh sách sản phẩm',
              outlined: true,
              onPressed: saving ? null : () => context.go('/admin/products'),
            ),
          ],
        ),
        AdminCard(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field('name', 'Tên sản phẩm', validator: requiredText),
                _field(
                  'slug',
                  'Đường dẫn sản phẩm',
                  validator: (s) =>
                      RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(s ?? '') &&
                          s!.length <= 100
                      ? null
                      : 'Dùng chữ thường, số và dấu gạch ngang; tối đa 100 ký tự.',
                ),
                _select(
                  'Danh mục',
                  'categories',
                  category,
                  (v) => setState(() => category = v),
                ),
                _select(
                  'Thương hiệu',
                  'brands',
                  brand,
                  (v) => setState(() => brand = v),
                ),
                _field(
                  'description',
                  'Mô tả',
                  maxLines: 4,
                  validator: (s) =>
                      (s ?? '').length > 5000 ? 'Tối đa 5.000 ký tự.' : null,
                ),
                _field(
                  'material',
                  'Chất liệu',
                  validator: (s) =>
                      (s ?? '').length > 200 ? 'Tối đa 200 ký tự.' : null,
                ),
                _field(
                  'style',
                  'Phong cách',
                  validator: (s) =>
                      (s ?? '').length > 100 ? 'Tối đa 100 ký tự.' : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hiển thị sản phẩm'),
                  subtitle: const Text(
                    'Sản phẩm cần ít nhất một biến thể đang bán để xuất hiện tại cửa hàng.',
                  ),
                  value: active,
                  onChanged: saving ? null : (v) => setState(() => active = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hỗ trợ thử đồ'),
                  value: tryOn,
                  onChanged: saving ? null : (v) => setState(() => tryOn = v),
                ),
                const SizedBox(height: 24),
                Text('Bộ ảnh sản phẩm', style: T.display(24)),
                const Text(
                  'Ảnh đầu tiên là ảnh bìa. Dùng đường dẫn HTTPS công khai hoặc ảnh có sẵn trong assets/images/.',
                  style: T.small,
                ),
                for (final image in images)
                  Padding(
                    key: ObjectKey(image),
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppField(
                          label: 'Đường dẫn ảnh',
                          controller: image.url,
                          readOnly: saving,
                          validator: (s) =>
                              RegExp(
                                    r'^(https://[^\s]+|assets/images/[a-zA-Z0-9_./-]+)$',
                                  ).hasMatch(s ?? '') &&
                                  s!.length <= 2000
                              ? null
                              : 'Nhập đường dẫn ảnh HTTPS hoặc assets/images/ hợp lệ.',
                        ),
                        const SizedBox(height: 12),
                        AppField(
                          label: 'Mô tả ảnh',
                          controller: image.alt,
                          readOnly: saving,
                          validator: (s) => (s ?? '').length > 200
                              ? 'Tối đa 200 ký tự.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        AppField(
                          label: 'Màu áp dụng (không bắt buộc)',
                          controller: image.color,
                          readOnly: saving,
                          validator: (s) =>
                              (s ?? '').length > 60 ? 'Tối đa 60 ký tự.' : null,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: saving
                                ? null
                                : () => setState(() {
                                    images.remove(image);
                                    removedImages.add(image);
                                  }),
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('Bỏ ảnh'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    'Thêm ảnh',
                    outlined: true,
                    onPressed: saving || images.length >= 20
                        ? null
                        : () => setState(() => images.add(_ImageFields({}))),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      error!,
                      style: T.body.copyWith(color: T.danger),
                    ),
                  ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    'Lưu thông tin sản phẩm',
                    busy: saving,
                    onPressed: save,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.product != null) ...[
          const SizedBox(height: 20),
          AdminHeading(
            'Biến thể & tồn kho',
            'Mỗi biến thể có mã SKU riêng. Thay đổi giá và tồn kho được lưu riêng.',
            actions: [
              AppButton(
                'Thêm biến thể',
                outlined: true,
                onPressed: saving
                    ? null
                    : () => _sku(context, ref, widget.product!),
              ),
            ],
          ),
          if (variants.isEmpty)
            const Text(
              'Chưa có biến thể. Hãy thêm size, màu và giá trước khi mở bán.',
              style: T.body,
            ),
          for (final raw in variants)
            Builder(
              builder: (context) {
                final variant = commerceMap(raw);
                final inventory = variant['inventory'];
                return AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        variant['sku'],
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${variant['color']} / ${variant['size']} · ${money(vnd(variant['price']))}',
                        style: T.body,
                      ),
                      Text(
                        '${variant['active'] ? 'Đang bán' : 'Đã ẩn'} · Tồn kho: ${inventory?['quantity'] ?? 0}',
                        style: T.small,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          AppButton(
                            'Sửa giá / trạng thái',
                            outlined: true,
                            onPressed: saving
                                ? null
                                : () => _sku(
                                    context,
                                    ref,
                                    widget.product!,
                                    variant: variant,
                                  ),
                          ),
                          if (inventory != null)
                            AppButton(
                              'Điều chỉnh kho',
                              outlined: true,
                              onPressed: saving
                                  ? null
                                  : () => adjustInventory(
                                      context,
                                      ref,
                                      commerceMap(inventory),
                                      variant['sku'],
                                    ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ],
    );
  }

  Widget _field(
    String key,
    String label, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: AppField(
      label: label,
      controller: fields[key],
      maxLines: maxLines,
      validator: validator,
      readOnly: saving,
    ),
  );
  Widget _select(
    String label,
    String kind,
    String? current,
    ValueChanged<String?> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in widget.references[kind] as List)
          DropdownMenuItem(
            value: item['id'] as String,
            child: Text(item['name'], overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: saving ? null : change,
      validator: (s) => s == null ? 'Vui lòng chọn $label.' : null,
    ),
  );
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
                : {'price': controls['price']!.text.trim(), 'active': active},
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
