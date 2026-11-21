import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_pagination.dart';

class PromotionProductPicker extends ConsumerStatefulWidget {
  const PromotionProductPicker({super.key, required this.selected});
  final Map<String, String> selected;
  @override
  ConsumerState<PromotionProductPicker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<PromotionProductPicker> {
  late final selected = Map<String, String>.from(widget.selected);
  final search = TextEditingController();
  String query = '';
  int page = 1;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = adminProductsProvider(
      Uri(
        queryParameters: {
          'page': '$page',
          'limit': '10',
          if (query.isNotEmpty) 'q': query,
        },
      ).query,
    );
    return AlertDialog(
      title: const Text('Chọn sản phẩm áp dụng'),
      content: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * .65,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: search,
                decoration: InputDecoration(
                  labelText: 'Tìm tên sản phẩm hoặc SKU',
                  suffixIcon: IconButton(
                    tooltip: 'Tìm sản phẩm',
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() {
                      query = search.text.trim();
                      page = 1;
                    }),
                  ),
                ),
                onSubmitted: (v) => setState(() {
                  query = v.trim();
                  page = 1;
                }),
              ),
              const SizedBox(height: 12),
              Text(
                'Đã chọn ${selected.length} sản phẩm · Áp dụng cho mọi màu và kích cỡ',
                style: T.small,
              ),
              if (selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(selected.clear),
                  child: const Text('Bỏ chọn tất cả'),
                ),
              AdminAsync(
                value: ref.watch(provider),
                reload: () => ref.invalidate(provider),
                builder: (data) => Column(
                  children: [
                    if (data.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Không tìm thấy sản phẩm.'),
                      ),
                    for (final product in data.items)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${product['name']}'),
                        subtitle: Text(
                          product['active'] == true
                              ? 'Đang kinh doanh'
                              : 'Đang ẩn',
                          style: T.small,
                        ),
                        value: selected.containsKey(product['id']),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selected['${product['id']}'] = '${product['name']}';
                          } else {
                            selected.remove(product['id']);
                          }
                        }),
                      ),
                    AdminPagination(
                      page: data,
                      onPage: (n) => setState(() => page = n),
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
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, selected),
          child: Text('Dùng ${selected.length} sản phẩm'),
        ),
      ],
    );
  }
}
