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
import 'product_widgets.dart' show ProductSkeleton;
import 'inventory_rows.dart';

class RemoteAdminInventory extends ConsumerStatefulWidget {
  const RemoteAdminInventory({super.key});
  @override
  ConsumerState<RemoteAdminInventory> createState() => _InventoryState();
}

class _InventoryState extends ConsumerState<RemoteAdminInventory> {
  final search = TextEditingController(),
      min = TextEditingController(),
      max = TextEditingController();
  final form = GlobalKey<FormState>();
  String? applied;
  Map<String, String> get params =>
      GoRouterState.of(context).uri.queryParameters;
  bool get missing => params['record'] == 'missing';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key =
        '${params['q']}|${params['minQuantity']}|${params['maxQuantity']}';
    if (applied != key) {
      search.text = params['q'] ?? '';
      min.text = params['minQuantity'] ?? '';
      max.text = params['maxQuantity'] ?? '';
      applied = key;
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
      form.currentState?.reset();
    }
    context.go(
      Uri(
        path: '/admin/inventory',
        queryParameters: next.isEmpty ? null : next,
      ).toString(),
    );
  }

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
    decoration: InputDecoration(labelText: label, isDense: true),
    items: choices.entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) => apply({
      key: v,
      // Keep the displayed scope when choosing a stock filter. Legacy dashboard
      // links without visibility still open with their active-only scope.
      if (key == 'status' && !params.containsKey('visibility'))
        'visibility': params['status'] == null ? 'all' : 'active',
    }),
  );
  void open(AdminRecord row) => context.go(
    Uri(
      path: '/admin/inventory/${row['id']}',
      queryParameters: {'from': GoRouterState.of(context).uri.toString()},
    ).toString(),
  );
  @override
  Widget build(BuildContext context) {
    final query = Uri(
      queryParameters: {'page': '1', 'limit': '10', ...params},
    ).query;
    final data = ref.watch(adminInventoryProvider(query)),
        summary = ref.watch(adminInventorySummaryProvider);
    final loaded = data.asData?.value;
    if (loaded != null &&
        !data.isLoading &&
        (int.tryParse(params['page'] ?? '1') ?? 1) != loaded.page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = Uri(
          queryParameters: {'page': '1', 'limit': '10', ...params},
        ).query;
        if (current == query) {
          context.replace(
            Uri(
              path: '/admin/inventory',
              queryParameters: {...params, 'page': '${loaded.page}'},
            ).toString(),
          );
        }
      });
    }
    void reload() => refreshAdmin(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Quản lý kho hàng',
          'Theo dõi từng SKU, kiểm soát số lượng và đối soát biến động.',
          actions: [
            if (canStaff(ref.watch(staffRoleProvider), 'catalog.read'))
              AppButton(
                'Xem sản phẩm',
                icon: Icons.checkroom_outlined,
                outlined: true,
                onPressed: () => context.go('/admin/products'),
              ),
            AppButton(
              'Tải lại',
              icon: Icons.refresh,
              outlined: true,
              onPressed: data.isLoading || summary.isLoading ? null : reload,
            ),
          ],
        ),
        AdminAsync(
          value: summary,
          reload: reload,
          builder: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Tổng quan toàn kho', style: T.small),
              ),
              CustomerMetrics(
                compact: true,
                items: [
                  (
                    label: 'SKU có bản ghi kho',
                    value: adminNumber(s['skus']),
                    note: 'Thuộc ${adminNumber(s['products'])} sản phẩm',
                    icon: Icons.inventory_2_outlined,
                    action: () => apply({}, clear: true),
                  ),
                  (
                    label: 'Tổng đơn vị khả dụng',
                    value: adminNumber(s['units']),
                    note: 'Bao gồm cả sản phẩm và SKU ẩn',
                    icon: Icons.layers_outlined,
                    action: null,
                  ),
                  (
                    label: 'SKU sắp hết hàng',
                    value: adminNumber(s['lowStock']),
                    note: 'Còn 1–${s['lowStockThreshold']} đơn vị / SKU',
                    icon: Icons.warning_amber_outlined,
                    action: () => apply({
                      'status': 'low',
                      'visibility': 'all',
                    }, clear: true),
                  ),
                  (
                    label: 'SKU hết hàng',
                    value: adminNumber(s['outOfStock']),
                    note: 'Có bản ghi kho, số lượng bằng 0',
                    icon: Icons.remove_shopping_cart_outlined,
                    action: () => apply({
                      'status': 'out',
                      'visibility': 'all',
                    }, clear: true),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  Text(
                    '${adminNumber(s['inStock'])} SKU còn hàng · ${adminNumber(s['activeUnits'])} đơn vị thuộc sản phẩm và SKU đang bật',
                    style: T.small,
                  ),
                  TextButton.icon(
                    onPressed: () => apply({
                      'record': missing ? null : 'missing',
                    }, clear: true),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(
                      missing
                          ? 'Về danh sách tồn kho'
                          : 'Chưa có bản ghi kho (${s['missing']})',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminCard(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Tồn kho hiện tại'),
                      selected: !missing,
                      onSelected: (_) => apply({'record': null}),
                    ),
                    ChoiceChip(
                      label: Text(
                        'Chưa có kho (${summary.asData?.value['missing'] ?? '—'})',
                      ),
                      selected: missing,
                      onSelected: (_) => apply({
                        'record': 'missing',
                        'status': null,
                        'minQuantity': null,
                        'maxQuantity': null,
                        if (params['sort']?.startsWith('quantity') == true ||
                            params['sort'] == 'attention')
                          'sort': 'updated',
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, c) {
                    final field = TextFormField(
                      controller: search,
                      decoration: const InputDecoration(
                        labelText: 'Tìm kiếm kho hàng',
                        hintText: 'Tên sản phẩm, SKU, màu hoặc mã sản phẩm',
                        prefixIcon: Icon(Icons.search),
                      ),
                      validator: (v) =>
                          (v ?? '').length > 100 ? 'Tối đa 100 ký tự.' : null,
                      onFieldSubmitted: (_) => submit(),
                    );
                    final actions = Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        AppButton(
                          'Áp dụng',
                          icon: Icons.search,
                          onPressed: submit,
                        ),
                        TextButton.icon(
                          onPressed: () => apply({}, clear: true),
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: 18,
                          ),
                          label: const Text('Xóa bộ lọc'),
                        ),
                      ],
                    );
                    return c.maxWidth >= 700 &&
                            MediaQuery.textScalerOf(context).scale(14) <= 18
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 680,
                                  ),
                                  child: field,
                                ),
                              ),
                              const SizedBox(width: 12),
                              actions,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              field,
                              const SizedBox(height: 12),
                              actions,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, c) {
                    final columns =
                        MediaQuery.textScalerOf(context).scale(14) > 18
                        ? 1
                        : c.maxWidth >= 1450
                        ? 6
                        : c.maxWidth >= 650
                        ? 3
                        : c.maxWidth >= 450
                        ? 2
                        : 1;
                    final width = (c.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: width,
                          child: select('Danh mục', 'categoryId', {
                            '': 'Tất cả danh mục',
                            for (final category
                                in summary.asData?.value['categories']
                                        as List? ??
                                    [])
                              '${category['id']}': '${category['name']}',
                          }),
                        ),
                        SizedBox(
                          width: width,
                          child: select('Thương hiệu', 'brandId', {
                            '': 'Tất cả thương hiệu',
                            for (final brand
                                in summary.asData?.value['brands'] as List? ??
                                    [])
                              '${brand['id']}': '${brand['name']}',
                          }),
                        ),
                        SizedBox(
                          width: width,
                          child: select(
                            'Trạng thái kinh doanh',
                            'visibility',
                            {
                              'all': 'Tất cả SKU',
                              'active': 'Sản phẩm và SKU đang bật',
                              'hidden': 'Sản phẩm hoặc SKU đã ẩn',
                            },
                            fallback: params['status'] != null
                                ? 'active'
                                : 'all',
                          ),
                        ),
                        if (!missing)
                          SizedBox(
                            width: width,
                            child: select('Tồn kho', 'status', {
                              '': 'Tất cả tồn kho',
                              'in_stock': 'Còn hàng (> 0)',
                              'low': 'Sắp hết (1–5)',
                              'out': 'Hết hàng (0)',
                            }),
                          ),
                        if (!missing) ...[
                          SizedBox(
                            width: width,
                            child: TextFormField(
                              controller: min,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Số lượng từ',
                              ),
                              validator: quantity,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: TextFormField(
                              controller: max,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Số lượng đến',
                              ),
                              validator: (v) {
                                final error = quantity(v);
                                if (error != null) return error;
                                return v!.isNotEmpty &&
                                        (int.tryParse(min.text) ?? 0) >
                                            int.parse(v)
                                    ? 'Số lượng đến phải lớn hơn hoặc bằng số lượng từ.'
                                    : null;
                              },
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  missing
                      ? 'SKU chưa có bản ghi kho chưa thể bán. Khởi tạo số lượng 0 rồi nhập kho thực tế.'
                      : 'Số lượng khả dụng đã trừ đơn khi đặt hàng. Giỏ hàng không giữ hàng. Cảnh báo sắp hết: 1–5 đơn vị / SKU.',
                  style: T.small,
                ),
                if (params['productId'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextButton(
                      onPressed: () => apply({'productId': null}),
                      child: const Text('Bỏ lọc theo sản phẩm'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (data.isLoading && !data.hasValue)
          const ProductSkeleton()
        else
          AdminAsync(
            value: data,
            reload: reload,
            builder: (page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${adminNumber(page.total)} SKU${missing ? ' chưa có bản ghi kho' : ' phù hợp bộ lọc'}',
                            style: T.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (!missing && page.summary.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${adminNumber(page.summary['units'])} đơn vị khả dụng trong kết quả',
                              style: T.small,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                AdminStatus(
                                  '${adminNumber(page.summary['outOfStock'])} hết hàng',
                                  color: T.danger,
                                ),
                                AdminStatus(
                                  '${adminNumber(page.summary['lowStock'])} sắp hết',
                                  color: T.warning,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: select('Sắp xếp', 'sort', {
                        'updated': 'Mới cập nhật',
                        if (!missing) 'attention': 'Ưu tiên bổ sung hàng',
                        'newest': 'SKU mới tạo',
                        'sku_asc': 'SKU A–Z',
                        'name_asc': 'Tên sản phẩm A–Z',
                        if (!missing) 'quantity_asc': 'Tồn kho ít đến nhiều',
                        if (!missing) 'quantity_desc': 'Tồn kho nhiều đến ít',
                      }, fallback: 'updated'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (page.items.isEmpty)
                  StatePanel(
                    title: missing
                        ? 'Không còn SKU cần khởi tạo'
                        : 'Không có SKU phù hợp',
                    message: missing
                        ? 'Không có SKU thiếu bản ghi kho trong bộ lọc này. Bạn có thể quay lại danh sách để nhập kho.'
                        : 'Thử đổi từ khóa hoặc bộ lọc. SKU mới được tạo từ trang sản phẩm.',
                    action: AppButton(
                      missing ? 'Về danh sách tồn kho' : 'Xóa bộ lọc',
                      outlined: true,
                      onPressed: () => apply({}, clear: true),
                    ),
                  )
                else
                  InventoryRows(rows: page.items, open: open),
                const SizedBox(height: 16),
                AdminPagination(
                  page: page,
                  loading: data.isLoading,
                  onPage: (n) => apply({'page': '$n'}, keepPage: true),
                  onPageSize: (n) => apply({'limit': '$n'}),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String? quantity(String? value) {
    if (value == null || value.isEmpty) return null;
    final n = int.tryParse(value);
    return !RegExp(r'^\d+$').hasMatch(value) || n == null || n > 2147483647
        ? 'Nhập số nguyên từ 0 đến 2.147.483.647.'
        : null;
  }

  void submit() {
    if (form.currentState!.validate()) {
      apply({
        'q': search.text.trim(),
        'minQuantity': missing ? null : min.text.trim(),
        'maxQuantity': missing ? null : max.text.trim(),
      });
    }
  }
}
