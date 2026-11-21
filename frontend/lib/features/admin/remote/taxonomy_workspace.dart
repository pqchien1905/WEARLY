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
import 'taxonomy_actions.dart';
import 'taxonomy_widgets.dart';
import 'taxonomy_kind.dart';

class TaxonomyWorkspace extends ConsumerStatefulWidget {
  const TaxonomyWorkspace({super.key, required this.kind});
  final TaxonomyKind kind;
  @override
  ConsumerState<TaxonomyWorkspace> createState() => _TaxonomyState();
}

class _TaxonomyState extends ConsumerState<TaxonomyWorkspace> {
  TaxonomyKind get kind => widget.kind;
  final search = TextEditingController();
  final form = GlobalKey<FormState>();
  String? applied;
  Map<String, String> get params =>
      GoRouterState.of(context).uri.queryParameters;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (applied != (params['q'] ?? '')) {
      applied = params['q'] ?? '';
      search.text = applied!;
    }
  }

  @override
  void dispose() {
    search.dispose();
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
    for (final entry in changes.entries) {
      if (entry.value == null || entry.value!.isEmpty) {
        next.remove(entry.key);
      } else {
        next[entry.key] = entry.value!;
      }
    }
    if (clear) {
      form.currentState?.reset();
      search.clear();
    }
    context.go(
      Uri(
        path: kind.path,
        queryParameters: next.isEmpty ? null : next,
      ).toString(),
    );
  }

  void submit() {
    if (form.currentState!.validate()) apply({'q': search.text.trim()});
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
  void open(AdminRecord row) => context.go(
    Uri(
      path: '${kind.path}/${row['id']}',
      queryParameters: {'from': GoRouterState.of(context).uri.toString()},
    ).toString(),
  );
  Future<void> create() async {
    final row = await editTaxonomy(context, ref, kind.name);
    if (mounted && row != null) open(row);
  }

  @override
  Widget build(BuildContext context) {
    final query = Uri(
      queryParameters: {'page': '1', 'limit': '10', ...params},
    ).query;
    final data = ref.watch(
      (kind == TaxonomyKind.categories
          ? adminCategoriesProvider(query)
          : adminBrandsProvider(query)),
    );
    final summary = ref.watch(
      (kind == TaxonomyKind.categories
          ? adminCategorySummaryProvider
          : adminBrandSummaryProvider),
    );
    final writable = canStaff(ref.watch(staffRoleProvider), 'catalog.write');
    final loaded = data.asData?.value;
    if (loaded != null &&
        !data.isLoading &&
        (int.tryParse(params['page'] ?? '1') ?? 1) != loaded.page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (Uri(
              queryParameters: {'page': '1', 'limit': '10', ...params},
            ).query ==
            query) {
          context.replace(
            Uri(
              path: kind.path,
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
          'Quản lý ${kind.label}',
          kind == TaxonomyKind.brands
              ? 'Quản lý thương hiệu và theo dõi sản phẩm đang có tại cửa hàng.'
              : 'Tổ chức sản phẩm, theo dõi độ phủ và quản lý tên hiển thị.',
          actions: [
            if (writable)
              AppButton(
                'Thêm ${kind.label}',
                icon: Icons.add,
                onPressed: create,
              ),
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              onPressed: data.isLoading || summary.isLoading ? null : reload,
            ),
          ],
        ),
        AdminAsync(
          value: summary,
          reload: reload,
          builder: (s) => CustomerMetrics(
            compact: true,
            items: [
              (
                label: 'Tổng ${kind.label}',
                value: adminNumber(s['total']),
                note: 'Toàn bộ ${kind.label} của cửa hàng',
                icon: kind.icon,
                action: () => apply({}, clear: true),
              ),
              (
                label: 'Có ở cửa hàng',
                value: adminNumber(s['published']),
                note: 'Có sản phẩm đủ điều kiện công khai',
                icon: Icons.storefront_outlined,
                action: () => apply({'coverage': 'published'}, clear: true),
              ),
              (
                label: 'Chưa có sản phẩm',
                value: adminNumber(s['empty']),
                note: 'Sẵn sàng để phân loại sản phẩm',
                icon: Icons.folder_open_outlined,
                action: () => apply({'coverage': 'empty'}, clear: true),
              ),
              (
                label: 'Sản phẩm được phân loại',
                value: adminNumber(s['products']),
                note:
                    '${adminNumber(s['publishedProducts'])} sản phẩm đang công khai',
                icon: Icons.checklist_outlined,
                action: null,
              ),
            ],
          ),
        ),
        AdminCard(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: search,
                  decoration: InputDecoration(
                    labelText: 'Tìm kiếm ${kind.label}',
                    hintText:
                        'Tên có hoặc không dấu, slug hoặc mã ${kind.label}',
                    prefixIcon: const Icon(Icons.search),
                  ),
                  validator: (v) =>
                      (v ?? '').length > 100 ? 'Tối đa 100 ký tự.' : null,
                  onFieldSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, c) {
                    final width = c.maxWidth < 650
                        ? c.maxWidth
                        : (c.maxWidth - 24) / 3;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: width,
                          child: select('Phạm vi sản phẩm', 'coverage', {
                            '': 'Tất cả ${kind.label}',
                            'populated': 'Đã có sản phẩm',
                            'empty': 'Chưa có sản phẩm',
                            'published': 'Có ở cửa hàng',
                            'unpublished': 'Chưa có ở cửa hàng',
                          }),
                        ),
                        SizedBox(
                          width: width,
                          child: select('Sắp xếp', 'sort', {
                            'name_asc': 'Tên A–Z',
                            'name_desc': 'Tên Z–A',
                            'newest': 'Mới tạo',
                            'oldest': 'Tạo lâu nhất',
                            'updated': 'Mới cập nhật',
                            'products_asc': 'Ít sản phẩm nhất',
                            'products_desc': 'Nhiều sản phẩm nhất',
                          }, fallback: 'name_asc'),
                        ),
                        SizedBox(
                          width: width,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppButton(
                                'Tìm kiếm',
                                icon: Icons.search,
                                onPressed: submit,
                              ),
                              TextButton(
                                onPressed: () => apply({}, clear: true),
                                child: const Text('Xóa bộ lọc'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  '${kind.title} xuất hiện ở cửa hàng khi có sản phẩm đang bật, có ảnh và có SKU đang bán.',
                  style: T.small,
                ),
              ],
            ),
          ),
        ),
        if (data.isLoading && !data.hasValue)
          _TaxonomySkeleton(kind: kind)
        else
          AdminAsync(
            value: data,
            reload: reload,
            builder: (page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${adminNumber(page.total)} ${kind.label} phù hợp bộ lọc',
                    style: T.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                if (page.items.isEmpty)
                  StatePanel(
                    title: 'Không có ${kind.label} phù hợp',
                    message:
                        'Thử đổi từ khóa, xóa bộ lọc hoặc thêm ${kind.label} mới.',
                    action: AppButton(
                      'Xóa bộ lọc',
                      outlined: true,
                      onPressed: () => apply({}, clear: true),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, c) =>
                        c.maxWidth >= 1050 &&
                            MediaQuery.textScalerOf(context).scale(14) <= 17
                        ? table(page.items)
                        : Column(children: page.items.map(card).toList()),
                  ),
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

  Widget identity(AdminRecord r) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        r['name'],
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: T.body.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        '/${r['slug']}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: T.small,
      ),
    ],
  );
  Widget edit(AdminRecord r) => IconButton(
    tooltip: 'Đổi tên ${r['name']}',
    icon: const Icon(Icons.edit_outlined),
    onPressed: () => editTaxonomy(context, ref, kind.name, r),
  );
  Widget table(List<AdminRecord> rows) => AdminCard(
    child: DataTable(
      horizontalMargin: 0,
      columnSpacing: 20,
      dataRowMinHeight: 100,
      dataRowMaxHeight: 150,
      columns: [
        for (final name in [
          '${kind.title} / slug',
          'Sản phẩm',
          'Cửa hàng',
          'Cập nhật (UTC+7)',
          'Thao tác',
        ])
          DataColumn(label: Text(name, style: T.small)),
      ],
      rows: rows
          .map(
            (r) => DataRow(
              cells: [
                DataCell(
                  SizedBox(width: 260, child: identity(r)),
                  onTap: () => open(r),
                ),
                DataCell(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        adminNumber(r['_count']['products']),
                        style: T.body.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${adminNumber(r['publishedProducts'])} công khai',
                        style: T.small,
                      ),
                    ],
                  ),
                ),
                DataCell(taxonomyPublication(r)),
                DataCell(Text(adminOrderDate(r['updatedAt']), style: T.small)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Chi tiết ${r['name']}',
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () => open(r),
                      ),
                      if (canStaff(
                        ref.watch(staffRoleProvider),
                        'catalog.write',
                      )) ...[
                        edit(r),
                        remove(r),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          )
          .toList(),
    ),
  );
  Widget card(AdminRecord r) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: identity(r)),
            if (canStaff(ref.watch(staffRoleProvider), 'catalog.write'))
              edit(r),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${adminNumber(r['_count']['products'])} sản phẩm · ${adminNumber(r['publishedProducts'])} công khai',
          style: T.body,
        ),
        const SizedBox(height: 6),
        Text(
          'Cập nhật ${adminOrderDate(r['updatedAt'])} (UTC+7)',
          style: T.small,
        ),
        const SizedBox(height: 4),
        Tooltip(
          message: 'Mã ${kind.label}: ${r['id']}',
          child: Text(
            'ID: ${r['id'].toString().split('-').first}',
            style: T.small,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            taxonomyPublication(r),
            AppButton('Xem chi tiết', outlined: true, onPressed: () => open(r)),
            if (canStaff(ref.watch(staffRoleProvider), 'catalog.write'))
              remove(r),
          ],
        ),
      ],
    ),
  );

  Widget remove(AdminRecord row) => IconButton(
    tooltip: 'Xóa ${row['name']}',
    icon: const Icon(Icons.delete_outline),
    color: T.danger,
    onPressed: () => deleteTaxonomy(context, ref, kind, row),
  );
}

class _TaxonomySkeleton extends StatelessWidget {
  const _TaxonomySkeleton({required this.kind});
  final TaxonomyKind kind;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Đang tải ${kind.label}',
    liveRegion: true,
    child: Column(
      children: [
        const LinearProgressIndicator(),
        for (var i = 0; i < 4; i++)
          Container(
            height: 86,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: T.line.withValues(alpha: .35),
              borderRadius: T.radius,
            ),
          ),
      ],
    ),
  );
}
