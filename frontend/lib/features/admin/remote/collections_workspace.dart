import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'collection_list_widgets.dart';
import 'collection_editor.dart';
import 'collection_actions.dart';

Widget collectionStatus(AdminRecord row) => AdminStatus(
  collectionPublished(row)
      ? 'Đang hiển thị'
      : row['active'] == true
      ? 'Chờ sản phẩm công khai'
      : 'Đang ẩn',
  color: collectionPublished(row)
      ? T.success
      : row['active'] == true
      ? T.warning
      : T.muted,
);

class RemoteCollectionsPage extends ConsumerStatefulWidget {
  const RemoteCollectionsPage({super.key});
  @override
  ConsumerState<RemoteCollectionsPage> createState() => _CollectionsState();
}

class _CollectionsState extends ConsumerState<RemoteCollectionsPage> {
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
    for (final e in changes.entries) {
      if (e.value == null || e.value!.isEmpty) {
        next.remove(e.key);
      } else {
        next[e.key] = e.value!;
      }
    }
    if (clear) {
      form.currentState?.reset();
      search.clear();
    }
    context.go(
      Uri(
        path: '/admin/collections',
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
    decoration: InputDecoration(labelText: label, isDense: true),
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
      path: '/admin/collections/${row['id']}',
      queryParameters: {'from': GoRouterState.of(context).uri.toString()},
    ).toString(),
  );
  @override
  Widget build(BuildContext context) {
    final key = Uri(
      queryParameters: {'page': '1', 'limit': '10', ...params},
    ).query;
    final data = ref.watch(adminCollectionsProvider(key));
    final summary = ref.watch(adminCollectionSummaryProvider);
    final loaded = data.asData?.value;
    if (loaded != null &&
        !data.isLoading &&
        (int.tryParse(params['page'] ?? '1') ?? 1) != loaded.page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            Uri(
                  queryParameters: {'page': '1', 'limit': '10', ...params},
                ).query ==
                key) {
          context.replace(
            Uri(
              path: '/admin/collections',
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
          'Quản lý bộ sưu tập',
          'Sắp xếp phong cách, quản lý ảnh bìa và nội dung hiển thị tại cửa hàng.',
          actions: [
            AppButton(
              'Thêm bộ sưu tập',
              icon: Icons.add,
              onPressed: () => editCollection(context, ref, null),
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
          builder: (s) => CollectionOverview(
            summary: s,
            status: params['status'] ?? '',
            onSelect: (status) => apply({'status': status}, clear: true),
          ),
        ),
        AdminCard(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final field = TextFormField(
                      controller: search,
                      decoration: const InputDecoration(
                        labelText: 'Tìm kiếm bộ sưu tập',
                        hintText: 'Tên, phong cách hoặc đường dẫn',
                        prefixIcon: Icon(Icons.search),
                      ),
                      validator: (v) =>
                          (v ?? '').length > 100 ? 'Tối đa 100 ký tự.' : null,
                      onFieldSubmitted: (_) => submit(),
                    );
                    final button = AppButton(
                      'Tìm kiếm',
                      outlined: true,
                      onPressed: submit,
                    );
                    return c.maxWidth < 450 ||
                            MediaQuery.textScalerOf(context).scale(14) > 18
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              field,
                              const SizedBox(height: 12),
                              button,
                            ],
                          )
                        : Row(
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
                              button,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, c) {
                    final width =
                        c.maxWidth < 600 ||
                            MediaQuery.textScalerOf(context).scale(14) > 18
                        ? c.maxWidth
                        : ((c.maxWidth - 24) / 3).clamp(0.0, 300.0);
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: width,
                          child: select('Trạng thái', 'status', {
                            '': 'Tất cả trạng thái',
                            'published': 'Đang hiển thị',
                            'hidden': 'Đang ẩn',
                            'waiting': 'Chờ sản phẩm công khai',
                          }),
                        ),
                        SizedBox(
                          width: width,
                          child: select('Sắp xếp', 'sort', {
                            'position': 'Thứ tự hiển thị',
                            'newest': 'Mới tạo',
                            'updated': 'Mới cập nhật',
                            'title_asc': 'Tên A–Z',
                            'title_desc': 'Tên Z–A',
                            'products_desc': 'Nhiều sản phẩm công khai',
                          }, fallback: 'position'),
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
                  },
                ),
                const Divider(height: 32),
                AdminAsync(
                  value: data,
                  reload: reload,
                  builder: (result) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '${adminNumber(result.total)} bộ sưu tập phù hợp bộ lọc',
                          style: T.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (result.items.isEmpty)
                        StatePanel(
                          title: 'Chưa có bộ sưu tập phù hợp',
                          message:
                              'Thử đổi từ khóa, xóa bộ lọc hoặc thêm bộ sưu tập mới.',
                          action: AppButton(
                            'Xóa bộ lọc',
                            outlined: true,
                            onPressed: () => apply({}, clear: true),
                          ),
                        ),
                      if (result.items.isNotEmpty) const CollectionListHeader(),
                      for (final row in result.items)
                        CollectionListItem(
                          row: row,
                          status: collectionStatus(row),
                          published: collectionPublished(row),
                          onOpen: () => open(row),
                          onEdit: () => editCollection(context, ref, row),
                          onAction: (action) {
                            switch (action) {
                              case CollectionListAction.visibility:
                                changeCollection(context, ref, row);
                              case CollectionListAction.storefront:
                                context.go('/collections/${row['slug']}');
                              case CollectionListAction.delete:
                                changeCollection(
                                  context,
                                  ref,
                                  row,
                                  remove: true,
                                );
                            }
                          },
                        ),
                      const SizedBox(height: 20),
                      AdminPagination(
                        page: result,
                        loading: data.isLoading,
                        onPage: (n) => apply({'page': '$n'}, keepPage: true),
                        onPageSize: (n) => apply({'limit': '$n'}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
