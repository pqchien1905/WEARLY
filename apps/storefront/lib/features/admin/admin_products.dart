import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/catalog.dart';
import '../../data/fixtures/catalog_fixture.dart';
import 'admin_state.dart';

class AdminProductsPage extends ConsumerStatefulWidget {
  const AdminProductsPage({super.key, this.inventory = false});
  final bool inventory;
  @override
  ConsumerState<AdminProductsPage> createState() => _AdminProductsPageState();
}

class _AdminProductsPageState extends ConsumerState<AdminProductsPage> {
  String search = '';
  bool lowOnly = false;
  int tablePage = 1;
  @override
  Widget build(BuildContext context) {
    final result = ref.watch(adminProductsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 24,
          runSpacing: 16,
          children: [
            Text(
              widget.inventory ? 'Biến thể & tồn kho' : 'Quản lý sản phẩm',
              style: T.display(34),
            ),
            AppButton(
              'Thêm sản phẩm',
              icon: Icons.add,
              onPressed: () => context.go('/admin/products/new'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Mọi thay đổi áp dụng cho catalog trong phiên demo.',
          style: T.small,
        ),
        const SizedBox(height: 24),
        TextField(
          decoration: InputDecoration(
            labelText: widget.inventory
                ? 'Tìm tên hoặc SKU'
                : 'Tìm tên sản phẩm',
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (v) => setState(() {
            search = v.toLowerCase();
            tablePage = 1;
          }),
        ),
        if (widget.inventory)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Chỉ biến thể còn dưới 5 sản phẩm'),
            value: lowOnly,
            onChanged: (v) => setState(() {
              lowOnly = v ?? false;
              tablePage = 1;
            }),
          ),
        const SizedBox(height: 24),
        result.when(
          data: (page) {
            final items = page.items
                .where(
                  (p) =>
                      p.name.toLowerCase().contains(search) ||
                      p.variants.any(
                        (v) => v.sku.toLowerCase().contains(search),
                      ),
                )
                .toList();
            if (items.isEmpty) {
              return const StatePanel(
                title: 'Không có sản phẩm phù hợp',
                message: 'Đổi từ khóa tìm kiếm hoặc thêm sản phẩm mới.',
              );
            }
            final variantRows = [
              for (final p in items)
                for (final v in p.variants)
                  if ((!lowOnly || v.stock < 5) &&
                      (p.name.toLowerCase().contains(search) ||
                          v.sku.toLowerCase().contains(search)))
                    (p, v),
            ];
            final total = widget.inventory ? variantRows.length : items.length;
            final perPage = widget.inventory ? 12 : 8;
            final pageCount = (total / perPage).ceil().clamp(1, 100000);
            final current = tablePage.clamp(1, pageCount);
            final visibleItems = items
                .skip((current - 1) * perPage)
                .take(perPage);
            final table = Material(
              color: T.surface,
              child: TableViewport(
                child: widget.inventory
                    ? DataTable(
                        columns: const [
                          DataColumn(label: Text('SKU')),
                          DataColumn(label: Text('Sản phẩm')),
                          DataColumn(label: Text('Màu / size')),
                          DataColumn(label: Text('Giá')),
                          DataColumn(label: Text('Tồn kho')),
                          DataColumn(label: Text('Thao tác')),
                        ],
                        rows: [
                          for (final row
                              in variantRows
                                  .skip((current - 1) * perPage)
                                  .take(perPage))
                            DataRow(
                              cells: [
                                DataCell(Text(row.$2.sku, style: T.small)),
                                DataCell(Text(row.$1.name)),
                                DataCell(
                                  Text('${row.$2.color} / ${row.$2.size}'),
                                ),
                                DataCell(Text(money(row.$2.price))),
                                DataCell(
                                  Text(
                                    '${row.$2.stock}${row.$2.stock == 0
                                        ? ' · Hết hàng'
                                        : row.$2.stock < 5
                                        ? ' · Sắp hết'
                                        : ''}',
                                    style: TextStyle(
                                      color: row.$2.stock < 5
                                          ? T.warning
                                          : T.ink,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  TextButton(
                                    onPressed: () => editStock(row.$1, row.$2),
                                    child: const Text('Điều chỉnh'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      )
                    : DataTable(
                        dataRowMinHeight: 72,
                        dataRowMaxHeight: 80,
                        columns: const [
                          DataColumn(label: Text('Sản phẩm')),
                          DataColumn(label: Text('Danh mục')),
                          DataColumn(label: Text('Giá từ')),
                          DataColumn(label: Text('Trạng thái')),
                          DataColumn(label: Text('Thao tác')),
                        ],
                        rows: visibleItems
                            .map(
                              (p) => DataRow(
                                cells: [
                                  DataCell(
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 40,
                                          height: 56,
                                          child: FashionImage(
                                            p.image,
                                            label: p.name,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          width: 240,
                                          child: Text(p.name, maxLines: 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Text(categories[p.category] ?? p.category),
                                  ),
                                  DataCell(Text(money(p.price))),
                                  DataCell(
                                    Text(
                                      p.active ? 'Đang hiển thị' : 'Đã ẩn',
                                      style: TextStyle(
                                        color: p.active ? T.success : T.muted,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Sửa ${p.name}',
                                          onPressed: () => context.go(
                                            '/admin/products/${p.id}/edit',
                                          ),
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Xóa ${p.name}',
                                          onPressed: () async {
                                            if (await confirmAction(
                                                  context,
                                                  'Xóa sản phẩm demo?',
                                                  'Sản phẩm sẽ biến mất khỏi catalog của phiên này. Đơn cũ giữ snapshot.',
                                                ) &&
                                                context.mounted) {
                                              try {
                                                await ref
                                                    .read(
                                                      productRepositoryProvider,
                                                    )
                                                    .delete(p.id);
                                                ref
                                                    .read(
                                                      catalogRevisionProvider
                                                          .notifier,
                                                    )
                                                    .refresh();
                                                ref
                                                    .read(adminStateProvider)
                                                    .log('Xóa ${p.name}');
                                              } catch (e) {
                                                if (context.mounted) {
                                                  toast(context, '$e');
                                                }
                                              }
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (MediaQuery.sizeOf(context).width >= 700 &&
                    MediaQuery.sizeOf(context).width < 1100)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Cuộn ngang bảng để xem giá, tồn kho và thao tác.',
                      style: T.small,
                    ),
                  ),
                if (total == 0)
                  const StatePanel(
                    title: 'Không có biến thể phù hợp',
                    message: 'Thử bỏ bộ lọc tồn kho hoặc đổi từ khóa.',
                  )
                else if (MediaQuery.sizeOf(context).width < 700)
                  Column(
                    children: [
                      if (widget.inventory)
                        for (final row
                            in variantRows
                                .skip((current - 1) * perPage)
                                .take(perPage))
                          _MobileAdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.$1.name,
                                  style: T.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(row.$2.sku, style: T.small),
                                const SizedBox(height: 12),
                                Text(
                                  '${row.$2.color} / ${row.$2.size} · ${money(row.$2.price)}',
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      row.$2.stock == 0
                                          ? 'Hết hàng'
                                          : 'Còn ${row.$2.stock}${row.$2.stock < 5 ? ' · Sắp hết' : ''}',
                                      style: TextStyle(
                                        color: row.$2.stock < 5
                                            ? T.warning
                                            : T.ink,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          editStock(row.$1, row.$2),
                                      child: const Text('Điều chỉnh'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                      else
                        for (final p in visibleItems)
                          _MobileAdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 56,
                                      height: 74,
                                      child: FashionImage(
                                        p.image,
                                        label: p.name,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            p.name,
                                            style: T.body.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text('Từ ${money(p.price)}'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '${p.variants.length} biến thể · ${p.variants.fold<int>(0, (sum, v) => sum + v.stock)} sản phẩm trong kho',
                                  style: T.small,
                                ),
                                Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      p.active ? 'Đang hiển thị' : 'Đã ẩn',
                                      style: T.small.copyWith(
                                        color: p.active ? T.success : T.muted,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Sửa ${p.name}',
                                      onPressed: () => context.go(
                                        '/admin/products/${p.id}/edit',
                                      ),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Xóa ${p.name}',
                                      onPressed: () => deleteProduct(p),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                    ],
                  )
                else
                  table,
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '$total ${widget.inventory ? 'biến thể' : 'sản phẩm'}',
                      style: T.small,
                    ),
                    IconButton(
                      tooltip: 'Trang trước',
                      onPressed: current > 1
                          ? () => setState(() => tablePage = current - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('$current / $pageCount'),
                    IconButton(
                      tooltip: 'Trang sau',
                      onPressed: current < pageCount
                          ? () => setState(() => tablePage = current + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            );
          },
          error: (e, _) => StatePanel(
            title: 'Không tải được catalog',
            message: '$e',
            action: AppButton(
              'Thử lại',
              onPressed: () => ref.invalidate(adminProductsProvider),
            ),
          ),
          loading: () => const LoadingPanel(),
        ),
      ],
    );
  }

  Future<void> deleteProduct(Product p) async {
    if (!await confirmAction(
          context,
          'Xóa sản phẩm demo?',
          'Sản phẩm sẽ biến mất khỏi catalog của phiên này. Đơn cũ giữ snapshot.',
        ) ||
        !mounted) {
      return;
    }
    try {
      await ref.read(productRepositoryProvider).delete(p.id);
      if (!mounted) return;
      ref.read(catalogRevisionProvider.notifier).refresh();
      ref.read(adminStateProvider).log('Xóa ${p.name}');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> editStock(Product p, ProductVariant v) async {
    final input = TextEditingController(text: '${v.stock}');
    final form = GlobalKey<FormState>();
    final amount = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Tồn kho ${v.sku}'),
        content: Form(
          key: form,
          child: AppField(
            label: 'Số lượng khả dụng',
            controller: input,
            keyboardType: TextInputType.number,
            validator: (s) =>
                int.tryParse(s ?? '') != null && int.parse(s!) >= 0
                ? null
                : 'Nhập số nguyên không âm.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Hủy'),
          ),
          AppButton(
            'Lưu tồn kho',
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(c, int.parse(input.text));
              }
            },
          ),
        ],
      ),
    );
    if (amount != null) {
      try {
        await ref
            .read(productRepositoryProvider)
            .save(
              p.copyWith(
                variants: p.variants
                    .map(
                      (item) =>
                          item.sku == v.sku ? v.copyWith(stock: amount) : item,
                    )
                    .toList(),
              ),
            );
        ref.read(catalogRevisionProvider.notifier).refresh();
        ref.read(adminStateProvider).log('Cập nhật ${v.sku}: $amount');
        if (mounted) {
          toast(context, 'Đã cập nhật tồn kho demo.');
        }
      } catch (e) {
        if (mounted) {
          toast(context, '$e');
        }
      }
    }
    input.dispose();
  }
}

class _MobileAdminCard extends StatelessWidget {
  const _MobileAdminCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: T.surface,
      border: Border.all(color: T.line),
      borderRadius: T.radius,
    ),
    child: child,
  );
}

class AdminProductForm extends ConsumerWidget {
  const AdminProductForm({super.key, this.id});
  final String? id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(adminProductsProvider)
      .when(
        data: (page) {
          final p = page.items.where((p) => p.id == id).firstOrNull;
          if (id != null && p == null) {
            return const StatePanel(
              title: 'Sản phẩm không tồn tại',
              message: 'Quay lại danh sách để chọn thiết kế khác.',
            );
          }
          return ProductEditor(key: ValueKey(id ?? 'new'), product: p);
        },
        error: (e, _) => Text('$e'),
        loading: () => const LoadingPanel(),
      );
}

class ProductEditor extends ConsumerStatefulWidget {
  const ProductEditor({super.key, this.product});
  final Product? product;
  @override
  ConsumerState<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<ProductEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, description, material;
  late String category, image, style;
  late List<ProductVariant> variants;
  final Map<String, TextEditingController> prices = {}, stocks = {};
  bool active = true, busy = false;
  String? error;
  late final String id, slug;
  Future<void> addVariant() async {
    final value = await showDialog<(String, String, int)>(
      context: context,
      builder: (_) => _NewVariantDialog(existing: variants),
    );
    if (value == null || !mounted) return;
    final sku =
        '${id.toUpperCase()}-${DateTime.now().microsecondsSinceEpoch}-${value.$1}';
    setState(() {
      variants.add(
        ProductVariant(
          sku: sku,
          size: value.$1,
          color: value.$2,
          colorHex: value.$3,
          price: 490000,
          stock: 0,
        ),
      );
      prices[sku] = TextEditingController(text: '490000');
      stocks[sku] = TextEditingController(text: '0');
    });
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    id = p?.id ?? 'p${DateTime.now().microsecondsSinceEpoch}';
    slug = p?.slug ?? 'nep-${id.substring(1)}';
    name = TextEditingController(text: p?.name ?? '');
    description = TextEditingController(
      text: p?.description ?? 'Sản phẩm minh họa được tạo trong phiên demo.',
    );
    material = TextEditingController(text: p?.material ?? 'Cotton');
    category = p?.category ?? 'ao';
    image = p?.image ?? 'assets/images/shirt.jpg';
    style = p?.style ?? 'Tối giản';
    active = p?.active ?? true;
    variants = [...?p?.variants];
    if (variants.isEmpty) {
      variants = [
        for (final s in ['S', 'M', 'L', 'XL'])
          ProductVariant(
            sku: '${id.toUpperCase()}-MAIN-$s',
            size: s,
            color: 'Trắng',
            colorHex: 0xFFE8E7E2,
            price: 490000,
            stock: 10,
          ),
      ];
    }
    for (final v in variants) {
      prices[v.sku] = TextEditingController(text: '${v.price}');
      stocks[v.sku] = TextEditingController(text: '${v.stock}');
    }
  }

  @override
  void dispose() {
    for (final c in [
      name,
      description,
      material,
      ...prices.values,
      ...stocks.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final product = Product(
        id: id,
        slug: slug,
        name: name.text.trim(),
        category: category,
        image: image,
        media: image == widget.product?.image
            ? widget.product!.media
            : const [],
        description: description.text.trim(),
        material: material.text.trim(),
        style: style,
        active: active,
        tryOn: category != 'quan',
        variants: variants
            .map(
              (v) => v.copyWith(
                price: int.parse(prices[v.sku]!.text),
                stock: int.parse(stocks[v.sku]!.text),
              ),
            )
            .toList(),
      );
      await ref.read(productRepositoryProvider).save(product);
      ref.read(catalogRevisionProvider.notifier).refresh();
      ref.read(adminStateProvider).log('Lưu sản phẩm ${product.name}');
      if (mounted) {
        toast(context, 'Đã lưu vào catalog demo.');
        context.go('/admin/products');
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.product == null ? 'Thêm một thiết kế' : 'Chỉnh sửa thiết kế',
          style: T.display(34),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (_, c) {
            final fields = Column(
              children: [
                AppField(
                  label: 'Tên sản phẩm',
                  controller: name,
                  validator: requiredValue,
                ),
                const SizedBox(height: 16),
                AppField(
                  label: 'Mô tả',
                  controller: description,
                  maxLines: 3,
                  validator: requiredValue,
                ),
                const SizedBox(height: 16),
                AppField(
                  label: 'Chất liệu',
                  controller: material,
                  validator: requiredValue,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Danh mục'),
                  items: categories.entries
                      .where((e) => e.key.isNotEmpty)
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => category = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: style,
                  decoration: const InputDecoration(labelText: 'Phong cách'),
                  items: styles
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => style = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: image,
                  decoration: const InputDecoration(labelText: 'Ảnh minh họa'),
                  items:
                      [
                            'shirt.jpg',
                            'black-dress.jpg',
                            'trousers.jpg',
                            'outerwear.jpg',
                            'dress.jpg',
                            'jacket.jpg',
                            'campaign.jpg',
                          ]
                          .map(
                            (s) => DropdownMenuItem(
                              value: 'assets/images/$s',
                              child: Text(s),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => image = v!),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                  title: const Text('Hiển thị trong cửa hàng'),
                ),
              ],
            );
            final preview = AspectRatio(
              aspectRatio: 3 / 4,
              child: FashionImage(image, label: 'Xem trước sản phẩm'),
            );
            return c.maxWidth < 800
                ? Column(
                    children: [
                      fields,
                      const SizedBox(height: 24),
                      SizedBox(width: 260, child: preview),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: fields),
                      const SizedBox(width: 32),
                      Expanded(flex: 4, child: preview),
                    ],
                  );
          },
        ),
        const SizedBox(height: 32),
        Text('Biến thể & tồn kho', style: T.display(26)),
        const SizedBox(height: 12),
        const Text(
          'SKU cố định để giữ liên kết giỏ hàng. Giá là số nguyên VNĐ.',
          style: T.small,
        ),
        const SizedBox(height: 16),
        AppButton(
          'Thêm biến thể',
          outlined: true,
          onPressed: busy ? null : addVariant,
        ),
        const SizedBox(height: 16),
        Material(
          color: T.surface,
          child: TableViewport(
            child: DataTable(
              dataRowMinHeight: 88,
              dataRowMaxHeight: 88,
              columns: const [
                DataColumn(label: Text('SKU')),
                DataColumn(label: Text('Màu / size')),
                DataColumn(label: Text('Giá (VNĐ)')),
                DataColumn(label: Text('Tồn kho')),
                DataColumn(label: Text('Thao tác')),
              ],
              rows: variants
                  .map(
                    (v) => DataRow(
                      cells: [
                        DataCell(Text(v.sku, style: T.small)),
                        DataCell(Text('${v.color} / ${v.size}')),
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: TextFormField(
                              controller: prices[v.sku],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Giá',
                              ),
                              validator: (s) => (int.tryParse(s ?? '') ?? 0) > 0
                                  ? null
                                  : 'Giá phải > 0',
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              controller: stocks[v.sku],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Tồn kho',
                              ),
                              validator: (s) =>
                                  (int.tryParse(s ?? '') ?? -1) >= 0
                                  ? null
                                  : 'Tồn phải ≥ 0',
                            ),
                          ),
                        ),
                        DataCell(
                          IconButton(
                            tooltip: 'Xóa biến thể ${v.sku}',
                            onPressed: busy || variants.length <= 1
                                ? null
                                : () async {
                                    if (await confirmAction(
                                      context,
                                      'Xóa biến thể?',
                                      'Biến thể sẽ được loại bỏ khi lưu sản phẩm. Giỏ hàng cũ cần chọn lại size.',
                                    )) {
                                      if (mounted) {
                                        setState(
                                          () => variants.removeWhere(
                                            (item) => item.sku == v.sku,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(error!, style: const TextStyle(color: T.danger)),
          ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          children: [
            AppButton('Lưu sản phẩm demo', busy: busy, onPressed: save),
            AppButton(
              'Hủy chỉnh sửa',
              outlined: true,
              onPressed: busy ? null : () => context.go('/admin/products'),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    ),
  );
}

class _NewVariantDialog extends StatefulWidget {
  const _NewVariantDialog({required this.existing});
  final List<ProductVariant> existing;
  @override
  State<_NewVariantDialog> createState() => _NewVariantDialogState();
}

class _NewVariantDialogState extends State<_NewVariantDialog> {
  String size = 'XXL', color = 'Trắng';
  String? error;
  static const colors = {
    'Trắng': 0xFFE8E7E2,
    'Đen': 0xFF29282B,
    'Mận': 0xFF65394D,
    'Xanh': 0xFF66899C,
    'Nâu': 0xFF97614B,
    'Hồng đất': 0xFFC69887,
    'Tím': 0xFF453C76,
    'Đỏ': 0xFFAB3143,
  };
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thêm biến thể'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: size,
            decoration: const InputDecoration(labelText: 'Size'),
            items: [
              'XS',
              'S',
              'M',
              'L',
              'XL',
              'XXL',
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => size = v!),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: color,
            decoration: const InputDecoration(labelText: 'Màu'),
            items: colors.keys
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => color = v!),
          ),
          const SizedBox(height: 16),
          const Text(
            'SKU được tạo riêng. Nhập giá và tồn kho ở bảng trước khi lưu.',
            style: T.small,
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: T.danger)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      AppButton(
        'Thêm vào bảng',
        onPressed: () {
          if (widget.existing.any((v) => v.size == size && v.color == color)) {
            setState(() => error = 'Màu và size này đã có trong bảng.');
          } else {
            Navigator.pop(context, (size, color, colors[color]!));
          }
        },
      ),
    ],
  );
}
