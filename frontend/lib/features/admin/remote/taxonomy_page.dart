import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
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

  Future<void> edit([AdminRecord? row]) async {
    final repository = ref.read(adminRepositoryProvider);
    final name = TextEditingController(text: row?['name'] ?? '');
    final slug = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminMutationDialog(
        title: row == null ? 'Thêm $label' : 'Đổi tên $label',
        message: row == null
            ? 'Tên hiển thị có thể đổi sau. Đường dẫn được giữ cố định.'
            : 'Giữ nguyên đường dẫn /${row['slug']} và các sản phẩm liên quan.',
        onDisposed: () {
          name.dispose();
          slug.dispose();
        },
        fields: [
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Tên hiển thị'),
            maxLength: 100,
            validator: (v) => requiredText(v, max: 100),
          ),
          if (row == null)
            TextFormField(
              controller: slug,
              decoration: const InputDecoration(
                labelText: 'Đường dẫn',
                helperText: 'Ví dụ: mua-thu, wearly-studio',
              ),
              maxLength: 100,
              validator: (v) =>
                  RegExp(
                        r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
                      ).hasMatch((v ?? '').trim()) &&
                      (v ?? '').trim().length <= 100
                  ? null
                  : 'Dùng chữ thường không dấu, số và dấu gạch nối.',
            ),
        ],
        reload: refresh,
        submit: () async {
          try {
            await repository.saveTaxonomy(widget.kind, row?['id'], {
              'name': name.text.trim(),
              if (row == null)
                'slug': slug.text.trim()
              else
                'expectedName': row['name'],
            });
          } on ApiException catch (e) {
            if (e.status == 409 && e.code == 'CONFLICT') {
              throw const ApiException(
                'CONFLICT',
                'Đường dẫn đã được sử dụng. Tải lại danh sách để kiểm tra.',
                status: 409,
              );
            }
            rethrow;
          }
        },
      ),
    );
    if (saved == true) refresh();
  }

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
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  AppButton(
                    'Trang trước',
                    outlined: true,
                    onPressed: page > 1 ? () => setState(() => page--) : null,
                  ),
                  AppButton(
                    'Trang sau',
                    outlined: true,
                    onPressed: data.hasNext
                        ? () => setState(() => page++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
