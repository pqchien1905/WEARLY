import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'inventory_widgets.dart' show InventoryPager;

class CollectionCoverPicker extends ConsumerStatefulWidget {
  const CollectionCoverPicker({super.key, required this.style});
  final String style;
  @override
  ConsumerState<CollectionCoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends ConsumerState<CollectionCoverPicker> {
  final search = TextEditingController();
  final form = GlobalKey<FormState>();
  String query = '';
  int page = 1;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      setState(() {
        query = search.text.trim();
        page = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = Uri(
      queryParameters: {
        'style': widget.style,
        'q': query,
        'page': '$page',
        'limit': '10',
      },
    ).query;
    final value = ref.watch(adminCollectionCoversProvider(key));
    return AlertDialog(
      title: const Text('Chọn ảnh bìa'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sản phẩm công khai thuộc phong cách “${widget.style}”.',
                style: T.small,
              ),
              const SizedBox(height: 16),
              Form(
                key: form,
                child: TextFormField(
                  controller: search,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Tìm sản phẩm làm bìa',
                    suffixIcon: IconButton(
                      tooltip: 'Tìm ảnh bìa',
                      icon: const Icon(Icons.search),
                      onPressed: submit,
                    ),
                  ),
                  onFieldSubmitted: (_) => submit(),
                ),
              ),
              AdminAsync(
                value: value,
                reload: () =>
                    ref.invalidate(adminCollectionCoversProvider(key)),
                builder: (data) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (data.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'Chưa có sản phẩm phù hợp. Thử từ khóa khác hoặc dùng ảnh tự động.',
                        ),
                      ),
                    for (final row in data.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, row),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
                                height: 60,
                                child: FashionImage(
                                  row['images'][0]['url'],
                                  label: row['name'],
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(row['name'], style: T.body)),
                              const Icon(Icons.add_photo_alternate_outlined),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    InventoryPager(
                      page: data,
                      go: (n) => setState(() => page = n),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
