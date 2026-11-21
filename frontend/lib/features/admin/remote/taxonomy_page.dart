import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/design/tokens.dart';
import 'taxonomy_actions.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

class RemoteTaxonomyPage extends ConsumerStatefulWidget {
  const RemoteTaxonomyPage({super.key, required this.kind});
  final String kind;
  @override
  ConsumerState<RemoteTaxonomyPage> createState() => _RemoteTaxonomyPageState();
}

class _RemoteTaxonomyPageState extends ConsumerState<RemoteTaxonomyPage> {
  int page = 1;
  String get label => widget.kind == 'categories' ? 'danh mục' : 'thương hiệu';

  void refresh() {
    if (!mounted) return;
    refreshAdmin(ref);
    ref.invalidate(adminReferencesProvider);
    ref.read(catalogRevisionProvider.notifier).refresh();
  }

  Future<void> edit([AdminRecord? row]) =>
      editTaxonomy(context, ref, widget.kind, row);

  @override
  Widget build(BuildContext context) {
    final key = (kind: widget.kind, page: page);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          widget.kind == 'categories'
              ? 'Danh mục của cửa hàng.'
              : 'Thương hiệu của cửa hàng.',
          'Sắp xếp sản phẩm bằng những tên gọi rõ ràng, dễ tìm.',
          actions: [
            AppButton('Thêm $label', icon: Icons.add, onPressed: edit),
            AppButton('Tải lại', outlined: true, onPressed: refresh),
          ],
        ),
        AdminAsync(
          value: ref.watch(adminListProvider(key)),
          reload: refresh,
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${data.total} $label · Trang $page',
                  style: T.small,
                ),
              ),
              if (data.items.isEmpty)
                AdminCard(
                  child: Text(
                    'Chưa có $label trên trang này. Thêm mới hoặc quay lại trang trước.',
                    style: T.body,
                  ),
                ),
              for (final row in data.items)
                AdminCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row['name'],
                              style: T.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('/${row['slug']}', style: T.small),
                            const SizedBox(height: 12),
                            Text(
                              '${row['_count']['products']} sản phẩm',
                              style: T.small,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đổi tên ${row['name']}',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => edit(row),
                      ),
                    ],
                  ),
                ),
              AdminPagination(
                page: data,
                onPage: (n) => setState(() => page = n),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
