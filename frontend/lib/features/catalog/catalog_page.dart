import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../app/api_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../../core/widgets/category_choices.dart';
import '../../domain/catalog.dart';
import '../account/account_navigation.dart';

class CatalogPage extends ConsumerWidget {
  const CatalogPage({super.key, required this.uri, this.wishlist = false});
  final Uri uri;
  final bool wishlist;
  void change(BuildContext context, String key, String? value) {
    final p = {...uri.queryParameters}..remove('page');
    if (value == null || value.isEmpty) {
      p.remove(key);
    } else {
      p[key] = value;
    }
    context.go(
      Uri(path: uri.path, queryParameters: p.isEmpty ? null : p).toString(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ProductQuery.fromParams(uri.queryParameters);
    final categories =
        ref.watch(catalogCategoriesProvider).value ?? const <String, String>{};
    final brands = query.brand.isEmpty
        ? const <String, String>{}
        : ref.watch(catalogBrandsProvider).value ?? const <String, String>{};
    final result = wishlist
        ? ref.watch(allProductsProvider)
        : ref.watch(catalogProvider(uri.query));
    final favorites = ref.watch(wishlistProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final filters = FilterControls(
      query: query,
      onChange: (key, value) => change(context, key, value),
      onClear: () => context.go('/shop'),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!wishlist) ...[
          Text('Trang chủ / Cửa hàng', style: T.small),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wishlist
                        ? 'Những món đồ bạn thích.'
                        : query.search.isNotEmpty
                        ? 'Kết quả cho “${query.search}”'
                        : query.category.isNotEmpty
                        ? categories[query.category] ?? 'Bộ sưu tập'
                        : query.brand.isNotEmpty
                        ? brands[query.brand] ?? query.brand
                        : 'Tủ đồ của bạn.',
                    style: T.display(wide ? 48 : 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    wishlist
                        ? 'Lưu cảm hứng, trở lại khi bạn sẵn sàng.'
                        : 'Chọn ít hơn. Chọn đúng với mình.',
                    style: T.body.copyWith(color: T.muted),
                  ),
                ],
              );
              final search = _CatalogSearch(
                value: query.search,
                onSearch: (value) => change(context, 'q', value),
              );
              if (constraints.maxWidth >= 880 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 18) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 40),
                    SizedBox(width: 360, child: search),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 24), search],
              );
            },
          ),
          const SizedBox(height: 24),
          CategoryChoices(
            selected: query.category,
            onSelected: (slug) => change(context, 'category', slug),
          ),
          const Divider(height: 48),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wide && !wishlist) ...[
              Container(
                width: 250,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: T.canvas,
                  borderRadius: T.panelRadius,
                  border: Border.all(color: T.line),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: filters,
                ),
              ),
              const SizedBox(width: 32),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      Text(
                        result.hasValue
                            ? '${wishlist ? favorites.length : result.value!.total} thiết kế'
                            : 'Đang tìm thiết kế…',
                        style: T.small,
                      ),
                      if (!wide && !wishlist)
                        OutlinedButton.icon(
                          onPressed: () async {
                            final params =
                                await showModalBottomSheet<Map<String, String>>(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => CatalogFilterSheet(
                                    parameters: uri.queryParameters,
                                  ),
                                );
                            if (params != null && context.mounted) {
                              context.go(
                                Uri(
                                  path: uri.path,
                                  queryParameters: params.isEmpty
                                      ? null
                                      : params,
                                ).toString(),
                              );
                            }
                          },
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('Bộ lọc'),
                        ),
                      if (!wishlist)
                        DropdownButton<String>(
                          value:
                              [
                                'newest',
                                'price-asc',
                                'price-desc',
                                'name',
                              ].contains(query.sort)
                              ? query.sort
                              : 'newest',
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                              value: 'newest',
                              child: Text('Mới nhất'),
                            ),
                            DropdownMenuItem(
                              value: 'price-asc',
                              child: Text('Giá tăng dần'),
                            ),
                            DropdownMenuItem(
                              value: 'price-desc',
                              child: Text('Giá giảm dần'),
                            ),
                            DropdownMenuItem(
                              value: 'name',
                              child: Text('Theo tên'),
                            ),
                          ],
                          onChanged: (v) => change(context, 'sort', v),
                        ),
                    ],
                  ),
                  if (uri.queryParameters.entries.any(
                    (e) => !['page', 'sort'].contains(e.key),
                  ))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in uri.queryParameters.entries.where(
                            (e) => !['page', 'sort'].contains(e.key),
                          ))
                            InputChip(
                              label: Text(
                                e.key == 'max'
                                    ? 'Dưới ${money(int.tryParse(e.value) ?? 0)}'
                                    : e.key == 'stock'
                                    ? 'Còn hàng'
                                    : e.key == 'brand'
                                    ? 'Thương hiệu: ${brands[e.value] ?? e.value}'
                                    : categories[e.value] ?? e.value,
                              ),
                              onDeleted: () => change(context, e.key, null),
                            ),
                          TextButton(
                            onPressed: () => context.go('/shop'),
                            child: const Text('Xóa bộ lọc'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  result.when(
                    data: (page) {
                      final items = wishlist
                          ? page.items
                                .where((p) => favorites.contains(p.id))
                                .toList()
                          : page.items;
                      return Column(
                        children: [
                          if (items.isEmpty)
                            StatePanel(
                              title: wishlist
                                  ? 'Tủ đồ yêu thích còn trống'
                                  : page.total > 0
                                  ? 'Trang này không còn sản phẩm'
                                  : 'Chưa có thiết kế phù hợp',
                              message: wishlist
                                  ? 'Nhấn biểu tượng trái tim trên một sản phẩm để lưu lại.'
                                  : page.total > 0
                                  ? 'Danh mục đã được cập nhật. Trở về trang đầu để xem các sản phẩm hiện có.'
                                  : 'Thử bỏ bớt bộ lọc hoặc dùng từ khóa khác.',
                              action: AppButton(
                                !wishlist && page.total > 0
                                    ? 'Về trang đầu'
                                    : 'Khám phá cửa hàng',
                                onPressed: () => !wishlist && page.total > 0
                                    ? change(context, 'page', null)
                                    : context.go('/shop'),
                              ),
                            )
                          else
                            ProductGrid(items, maxColumns: 4),
                          if (page.total > 12 && items.isNotEmpty && !wishlist)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                children: [
                                  AppButton(
                                    'Trang trước',
                                    outlined: true,
                                    onPressed: query.page > 1
                                        ? () => change(
                                            context,
                                            'page',
                                            '${query.page - 1}',
                                          )
                                        : null,
                                  ),
                                  Text(
                                    '${query.page} / ${(page.total / 12).ceil()}',
                                  ),
                                  AppButton(
                                    'Trang sau',
                                    outlined: true,
                                    onPressed: query.page * 12 < page.total
                                        ? () => change(
                                            context,
                                            'page',
                                            '${query.page + 1}',
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                    error: (e, _) => StatePanel(
                      title: 'Không tải được sản phẩm',
                      message: '$e',
                      action: AppButton(
                        'Thử lại',
                        onPressed: () => ref.invalidate(catalogProvider),
                      ),
                    ),
                    loading: () => const LoadingPanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        if (!ref.watch(remoteApiProvider))
          const Text(
            'Ảnh và catalog minh họa. Màu ảnh có thể khác biến thể demo.',
            style: T.small,
          ),
      ],
    );
    return wishlist
        ? AccountFrame(
            title: 'Những món đồ bạn thích.',
            current: '/wishlist',
            child: body,
          )
        : PageBody(child: body);
  }
}

class _CatalogSearch extends StatefulWidget {
  const _CatalogSearch({required this.value, required this.onSearch});
  final String value;
  final ValueChanged<String> onSearch;
  @override
  State<_CatalogSearch> createState() => _CatalogSearchState();
}

class _CatalogSearchState extends State<_CatalogSearch> {
  late final controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant _CatalogSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) controller.text = widget.value;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLength: 100,
    textInputAction: TextInputAction.search,
    onSubmitted: (value) => widget.onSearch(value.trim()),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: 'Tìm trong cửa hàng',
      hintText: 'Tên sản phẩm, ví dụ: áo sơ mi',
      counterText: '',
      prefixIcon: const Icon(Icons.search),
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Xóa từ khóa',
              onPressed: () {
                controller.clear();
                widget.onSearch('');
                setState(() {});
              },
              icon: const Icon(Icons.close, size: 20),
            ),
          IconButton(
            tooltip: 'Tìm sản phẩm',
            onPressed: () => widget.onSearch(controller.text.trim()),
            icon: const Icon(Icons.arrow_forward),
          ),
        ],
      ),
    ),
  );
}

class CatalogFilterSheet extends StatefulWidget {
  const CatalogFilterSheet({super.key, required this.parameters});
  final Map<String, String> parameters;
  @override
  State<CatalogFilterSheet> createState() => _CatalogFilterSheetState();
}

class _CatalogFilterSheetState extends State<CatalogFilterSheet> {
  late final draft = {...widget.parameters}..remove('page');
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .88,
    child: Column(
      children: [
        ListTile(
          title: const Text('Bộ lọc sản phẩm'),
          trailing: IconButton(
            tooltip: 'Đóng bộ lọc',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: FilterControls(
              query: ProductQuery.fromParams(draft),
              onChange: (key, value) => setState(() {
                if (value == null || value.isEmpty) {
                  draft.remove(key);
                } else {
                  draft[key] = value;
                }
              }),
              onClear: () => setState(
                () =>
                    draft.removeWhere((key, _) => !['q', 'sort'].contains(key)),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: T.line)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: AppButton(
                'Xem kết quả',
                onPressed: () => Navigator.pop(context, draft),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class FilterControls extends ConsumerWidget {
  const FilterControls({
    super.key,
    required this.query,
    required this.onChange,
    required this.onClear,
  });
  final ProductQuery query;
  final void Function(String, String?) onChange;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Lọc theo lựa chọn',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      const Divider(),
      const Text('Khoảng giá'),
      const SizedBox(height: 12),
      RadioGroup<int>(
        groupValue: query.maxPrice ?? -1,
        onChanged: (v) => onChange('max', v == -1 ? null : '$v'),
        child: Column(
          children: [
            for (final amount in {
              -1,
              600000,
              1000000,
              1500000,
              if (query.maxPrice != null) query.maxPrice!,
            })
              RadioListTile<int>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  amount == -1 ? 'Tất cả mức giá' : 'Đến ${money(amount)}',
                  style: T.small.copyWith(color: T.ink),
                ),
                value: amount,
              ),
          ],
        ),
      ),
      const Divider(),
      const Text('Size'),
      const SizedBox(height: 12),
      _CatalogOptions(
        kind: 'sizes',
        selected: query.size,
        onSelected: (value) => onChange('size', value),
      ),
      const Divider(),
      const Text('Màu sắc'),
      const SizedBox(height: 12),
      ref
          .watch(catalogColorsProvider)
          .when(
            loading: () => const Text('Đang tải màu…', style: T.small),
            error: (_, _) => TextButton(
              onPressed: () => ref.invalidate(catalogColorsProvider),
              child: const Text('Tải lại màu sắc'),
            ),
            data: (colors) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: {...colors, if (query.color.isNotEmpty) query.color}
                  .map(
                    (s) => FilterChip(
                      label: Text(s),
                      selected: query.color == s,
                      onSelected: (v) => onChange('color', v ? s : null),
                    ),
                  )
                  .toList(),
            ),
          ),
      const Divider(),
      const Text('Phong cách'),
      const SizedBox(height: 12),
      _CatalogOptions(
        kind: 'styles',
        selected: query.style,
        onSelected: (value) => onChange('style', value),
      ),
      const Divider(),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Chỉ hàng còn sẵn', style: T.small),
        value: query.inStock,
        onChanged: (v) => onChange('stock', v == true ? 'true' : null),
      ),
      TextButton(onPressed: onClear, child: const Text('Xóa tất cả bộ lọc')),
    ],
  );
}

class _CatalogOptions extends ConsumerWidget {
  const _CatalogOptions({
    required this.kind,
    required this.selected,
    required this.onSelected,
  });
  final String kind, selected;
  final ValueChanged<String?> onSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(catalogOptionsProvider)
      .when(
        loading: () => const Text('Đang tải lựa chọn…', style: T.small),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(catalogOptionsProvider),
          child: const Text('Tải lại lựa chọn'),
        ),
        data: (options) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in {
              ...?options[kind],
              if (selected.isNotEmpty) selected,
            })
              FilterChip(
                label: Text(value),
                selected: selected == value,
                onSelected: (checked) => onSelected(checked ? value : null),
              ),
          ],
        ),
      );
}
