import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'customer_widgets.dart' show CustomerMetrics;
import 'order_presentation.dart' show adminOrderDate;
import 'product_widgets.dart';

class RemoteAdminProducts extends ConsumerStatefulWidget {
  const RemoteAdminProducts({super.key});
  @override
  ConsumerState<RemoteAdminProducts> createState() => _ProductsState();
}

class _ProductsState extends ConsumerState<RemoteAdminProducts> {
  final search = TextEditingController(),
      min = TextEditingController(),
      max = TextEditingController();
  final filterForm = GlobalKey<FormState>();
  String? applied;
  Map<String, String> get params =>
      GoRouterState.of(context).uri.queryParameters;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current =
        '${params['q']}|${params['minPrice']}|${params['maxPrice']}';
    if (applied != current) {
      search.text = params['q'] ?? '';
      min.text = params['minPrice'] ?? '';
      max.text = params['maxPrice'] ?? '';
      applied = current;
    }
  }

  @override
  void dispose() {
    search.dispose();
    min.dispose();
    max.dispose();
    super.dispose();
  }

  void apply(
    Map<String, String?> changes, {
    bool clear = false,
    bool keepPage = false,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    final next = <String, String>{if (!clear) ...params};
    if (!keepPage) next.remove('page');
    for (final e in changes.entries) {
      if (e.value == null || e.value!.isEmpty) {
        next.remove(e.key);
      } else {
        next[e.key] = e.value!;
      }
    }
    if (clear) {
      search.clear();
      min.clear();
      max.clear();
      filterForm.currentState?.reset();
    }
    context.go(
      Uri(
        path: '/admin/products',
        queryParameters: next.isEmpty ? null : next,
      ).toString(),
    );
  }

  void submit() {
    if (filterForm.currentState!.validate()) {
      apply({
        'q': search.text.trim(),
        'minPrice': min.text.trim(),
        'maxPrice': max.text.trim(),
      });
    }
  }

  void open(AdminRecord p, {bool edit = false}) => context.go(
    Uri(
      path: '/admin/products/${p['id']}${edit ? '/edit' : ''}',
      queryParameters: {'from': GoRouterState.of(context).uri.toString()},
    ).toString(),
  );
  Widget select(
    String label,
    String key,
    Map<String, String> choices, {
    String fallback = '',
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$key-${params[key]}'),
    initialValue: choices.containsKey(params[key] ?? fallback)
        ? params[key] ?? fallback
        : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: choices.entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) => apply({key: v}),
  );
  @override
  Widget build(BuildContext context) {
    final query = Uri(
      queryParameters: {'page': '1', 'limit': '10', ...params},
    ).query;
    final list = ref.watch(adminProductsProvider(query)),
        summary = ref.watch(adminProductSummaryProvider),
        references = ref.watch(adminReferencesProvider);
    final canWrite = canStaff(ref.watch(staffRoleProvider), 'catalog.write');
    final filtered = [
      'q',
      'status',
      'categoryId',
      'brandId',
      'stock',
      'minPrice',
      'maxPrice',
      'visibility',
    ].any((k) => (params[k] ?? '').isNotEmpty);
    void reload() {
      ref.invalidate(adminProductsProvider(query));
      ref.invalidate(adminProductSummaryProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Quản lý sản phẩm',
          'Theo dõi danh mục, giá bán, biến thể và lượng hàng sẵn có.',
          actions: [
            AppButton(
              'Tải lại',
              icon: Icons.refresh,
              outlined: true,
              busy: list.isLoading,
              onPressed: reload,
            ),
            if (canWrite)
              AppButton(
                'Thêm sản phẩm',
                icon: Icons.add,
                onPressed: () => context.go(
                  Uri(
                    path: '/admin/products/new',
                    queryParameters: {
                      'from': GoRouterState.of(context).uri.toString(),
                    },
                  ).toString(),
                ),
              ),
          ],
        ),
        AdminAsync(
          value: summary,
          reload: () => ref.invalidate(adminProductSummaryProvider),
          builder: (data) => CustomerMetrics(
            compact: true,
            items: [
              (
                label: 'Tổng sản phẩm',
                value: adminNumber(data['total']),
                note: 'Trong ${data['categories'] ?? 0} danh mục',
                icon: Icons.checkroom_outlined,
                action: () => apply({}, clear: true),
              ),
              (
                label: 'Đang hiển thị',
                value: adminNumber(data['published']),
                note: 'Đã bật, có ảnh và SKU đang bán',
                icon: Icons.storefront_outlined,
                action: () => apply({'visibility': 'published'}, clear: true),
              ),
              (
                label: 'Có SKU sắp hết',
                value: adminNumber(data['lowStock']),
                note: 'Sản phẩm bật, có SKU còn 1–5',
                icon: Icons.inventory_2_outlined,
                action: () =>
                    apply({'status': 'active', 'stock': 'low'}, clear: true),
              ),
              (
                label: 'Hết hàng',
                value: adminNumber(data['outOfStock']),
                note: 'Sản phẩm bật, mọi SKU bán hết',
                icon: Icons.remove_shopping_cart_outlined,
                action: () =>
                    apply({'status': 'active', 'stock': 'out'}, clear: true),
              ),
            ],
          ),
        ),
        AdminCard(
          child: Form(
            key: filterForm,
            child: LayoutBuilder(
              builder: (context, c) {
                final fieldWidth = c.maxWidth < 600
                    ? c.maxWidth
                    : (c.maxWidth - 24) / 3;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: search,
                      maxLength: 100,
                      textInputAction: TextInputAction.search,
                      onFieldSubmitted: (_) => submit(),
                      decoration: const InputDecoration(
                        labelText: 'Tìm kiếm sản phẩm',
                        hintText: 'Tên, SKU, đường dẫn, danh mục hoặc mã UUID',
                        prefixIcon: Icon(Icons.search),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (params['style'] case final String style)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InputChip(
                          label: Text('Phong cách: $style'),
                          onDeleted: () => apply({'style': null}),
                        ),
                      ),
                    AdminAsync(
                      value: references,
                      reload: () => ref.invalidate(adminReferencesProvider),
                      builder: (data) => Wrap(
                        spacing: 12,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: fieldWidth,
                            child: select('Danh mục', 'categoryId', {
                              '': 'Tất cả danh mục',
                              for (final item in data['categories'] as List)
                                '${item['id']}': '${item['name']}',
                            }),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: select('Thương hiệu', 'brandId', {
                              '': 'Tất cả thương hiệu',
                              for (final item in data['brands'] as List)
                                '${item['id']}': '${item['name']}',
                            }),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: select('Tồn kho SKU đang bán', 'stock', {
                              '': 'Tất cả tồn kho',
                              'in_stock': 'Còn hàng',
                              'low': 'Có SKU còn 1–5',
                              'out': 'Hết toàn bộ hàng',
                              'no_variants': 'Chưa có SKU đang bán',
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: TextFormField(
                            controller: min,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Giá từ (VND)',
                            ),
                            onFieldSubmitted: (_) => submit(),
                            validator: (v) =>
                                (v ?? '').isEmpty ? null : priceValidation(v),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextFormField(
                            controller: max,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Giá đến (VND)',
                            ),
                            onFieldSubmitted: (_) => submit(),
                            validator: (v) {
                              if ((v ?? '').isEmpty) return null;
                              final error = priceValidation(v);
                              if (error != null) return error;
                              return (int.tryParse(min.text) ?? 0) >
                                      int.parse(v!)
                                  ? 'Giá đến phải lớn hơn hoặc bằng giá từ.'
                                  : null;
                            },
                          ),
                        ),
                        AppButton(
                          'Áp dụng',
                          icon: Icons.search,
                          onPressed: submit,
                        ),
                        if (filtered)
                          TextButton.icon(
                            onPressed: () => apply({}, clear: true),
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('Xóa bộ lọc'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Giá và tồn kho dựa trên SKU đang bán. Khoảng giá áp dụng cho cùng một SKU.',
                      style: T.small,
                    ),
                    if (params['visibility'] != null)
                      Text(
                        params['visibility'] == 'published'
                            ? 'Đang lọc sản phẩm hiển thị tại cửa hàng.'
                            : 'Đang lọc sản phẩm chưa hiển thị tại cửa hàng.',
                        style: T.small,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final e in {
              '': 'Tất cả',
              'active': 'Đang bật',
              'hidden': 'Đã ẩn',
            }.entries)
              ChoiceChip(
                label: Text(
                  '${e.value}${e.key.isNotEmpty && summary.hasValue ? ' (${summary.value![e.key] ?? 0})' : ''}',
                ),
                selected: (params['status'] ?? '') == e.key,
                onSelected: (_) => apply({'status': e.key}),
                showCheckmark: false,
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (list.isLoading && !list.hasValue)
          const ProductSkeleton()
        else
          AdminAsync(
            value: list,
            reload: reload,
            builder: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    Text(
                      '${adminNumber(data.total)} sản phẩm${filtered ? ' phù hợp bộ lọc' : ''}',
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(
                      width: 250,
                      child: select('Sắp xếp', 'sort', {
                        'newest': 'Mới tạo',
                        'oldest': 'Cũ nhất',
                        'updated': 'Mới cập nhật',
                        'name_asc': 'Tên A–Z',
                        'name_desc': 'Tên Z–A',
                        'price_asc': 'Giá thấp đến cao',
                        'price_desc': 'Giá cao đến thấp',
                        'stock_asc': 'Tồn kho ít đến nhiều',
                        'stock_desc': 'Tồn kho nhiều đến ít',
                      }, fallback: 'newest'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (data.items.isEmpty)
                  StatePanel(
                    title: filtered
                        ? 'Không có sản phẩm phù hợp'
                        : 'Chưa có sản phẩm',
                    message: filtered
                        ? 'Thử đổi từ khóa hoặc bỏ bớt điều kiện lọc.'
                        : 'Thêm thông tin sản phẩm, sau đó bổ sung ảnh và SKU.',
                    action: filtered
                        ? AppButton(
                            'Xóa bộ lọc',
                            outlined: true,
                            onPressed: () => apply({}, clear: true),
                          )
                        : canWrite
                        ? AppButton(
                            'Thêm sản phẩm',
                            onPressed: () => context.go('/admin/products/new'),
                          )
                        : null,
                  )
                else
                  LayoutBuilder(
                    builder: (context, c) =>
                        c.maxWidth >= 1050 &&
                            MediaQuery.textScalerOf(context).scale(14) <= 17
                        ? table(data.items, canWrite)
                        : Column(
                            children: data.items
                                .map((p) => card(p, canWrite))
                                .toList(),
                          ),
                  ),
                const SizedBox(height: 18),
                AdminPagination(
                  page: data,
                  loading: list.isLoading,
                  onPage: (n) => apply({'page': '$n'}, keepPage: true),
                  onPageSize: (n) => apply({'limit': '$n'}),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget photo(AdminRecord p, {double size = 54}) {
    final images = p['images'] as List? ?? [];
    return SizedBox(
      width: size,
      height: size * 1.2,
      child: ClipRRect(
        borderRadius: T.radius,
        child: images.isEmpty
            ? const ColoredBox(
                color: T.photo,
                child: Icon(Icons.image_outlined, color: T.muted),
              )
            : FashionImage(
                '${images.first['url']}',
                label: '${p['name']}',
                fit: BoxFit.cover,
              ),
      ),
    );
  }

  Widget identity(AdminRecord p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('${p['name']}', style: T.body.copyWith(fontWeight: FontWeight.w600)),
      Tooltip(
        message: '${p['id']}',
        child: Text(
          'ID: ${'${p['id']}'.substring(0, '${p['id']}'.length.clamp(0, 8)).toUpperCase()}…',
          style: T.small,
        ),
      ),
      Text('${ProductFacts(p).variants.length} biến thể', style: T.small),
    ],
  );
  Widget actions(AdminRecord p, bool canWrite) => PopupMenuButton<String>(
    tooltip: 'Thao tác sản phẩm',
    onSelected: (value) {
      if (value == 'toggle') {
        toggleProduct(context, ref, p);
      } else if (value == 'delete') {
        remove(p);
      } else {
        open(p, edit: value == 'edit');
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'view', child: Text('Xem chi tiết')),
      if (canWrite)
        const PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
      if (canWrite)
        PopupMenuItem(
          value: 'toggle',
          child: Text(p['active'] == true ? 'Ẩn sản phẩm' : 'Bật sản phẩm'),
        ),
      if (canWrite) const PopupMenuDivider(),
      if (canWrite)
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 20, color: T.danger),
              SizedBox(width: 10),
              Expanded(
                child: Text('Xóa sản phẩm', style: TextStyle(color: T.danger)),
              ),
            ],
          ),
        ),
    ],
  );
  Future<void> remove(AdminRecord product) async {
    final location = GoRouterState.of(context).uri.toString();
    if (!await deleteProduct(context, ref, product) || !mounted) return;
    if (GoRouterState.of(context).uri.toString() != location) return;
    final query = Uri(
      queryParameters: {'page': '1', 'limit': '10', ...params},
    ).query;
    try {
      final data = await ref.read(adminProductsProvider(query).future);
      if (!mounted || GoRouterState.of(context).uri.toString() != location) {
        return;
      }
      final lastPage = data.total == 0 ? 1 : (data.total - 1) ~/ data.limit + 1;
      if (data.page > lastPage) apply({'page': '$lastPage'}, keepPage: true);
    } catch (_) {
      // The list displays its own error and reload action after invalidation.
    }
  }

  Widget table(List<AdminRecord> items, bool canWrite) => Container(
    decoration: BoxDecoration(
      color: T.surface,
      border: Border.all(color: T.line),
      borderRadius: T.radius,
    ),
    child: DataTable(
      horizontalMargin: 16,
      columnSpacing: 16,
      headingRowColor: const WidgetStatePropertyAll(T.canvas),
      headingTextStyle: T.small.copyWith(fontWeight: FontWeight.w600),
      dataRowMinHeight: 110,
      dataRowMaxHeight: double.infinity,
      columns: const [
        DataColumn(label: Text('Sản phẩm / Mã')),
        DataColumn(label: Text('Danh mục')),
        DataColumn(label: Text('Giá bán')),
        DataColumn(label: Text('Tồn kho')),
        DataColumn(label: Text('Hiển thị')),
        DataColumn(label: Text('Thao tác')),
      ],
      rows: items.map((p) {
        final facts = ProductFacts(p);
        return DataRow(
          cells: [
            DataCell(
              SizedBox(
                width: 285,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      photo(p),
                      const SizedBox(width: 12),
                      Expanded(child: identity(p)),
                    ],
                  ),
                ),
              ),
              onTap: () => open(p),
            ),
            DataCell(
              SizedBox(
                width: 120,
                child: Text('${p['category']['name']}', style: T.small),
              ),
            ),
            DataCell(
              SizedBox(width: 155, child: Text(facts.price, style: T.body)),
            ),
            DataCell(
              SizedBox(
                width: 100,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${facts.stock}',
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(facts.stockLabel, style: T.small),
                  ],
                ),
              ),
            ),
            DataCell(
              SizedBox(
                width: 155,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    productStatus(p),
                    const SizedBox(height: 6),
                    Text(
                      adminOrderDate(p['updatedAt'] ?? p['createdAt']),
                      style: T.small,
                    ),
                  ],
                ),
              ),
            ),
            DataCell(actions(p, canWrite)),
          ],
        );
      }).toList(),
    ),
  );
  Widget card(AdminRecord p, bool canWrite) {
    final facts = ProductFacts(p);
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              photo(p, size: 66),
              const SizedBox(width: 14),
              Expanded(child: identity(p)),
              actions(p, canWrite),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${p['category']['name']} · ${p['brand']['name']}',
            style: T.small,
          ),
          const SizedBox(height: 8),
          Text(
            facts.price,
            style: T.body.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            '${facts.stock} đơn vị đang bán · ${facts.stockLabel}',
            style: T.small,
          ),
          Text(
            'Cập nhật ${adminOrderDate(p['updatedAt'] ?? p['createdAt'])} (UTC+7)',
            style: T.small,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              productStatus(p),
              AppButton(
                'Xem sản phẩm',
                outlined: true,
                onPressed: () => open(p),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
