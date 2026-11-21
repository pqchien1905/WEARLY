import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'taxonomy_actions.dart' show taxonomySlug;
import 'collection_cover_picker.dart';

Future<void> editCollection(
  BuildContext context,
  WidgetRef ref,
  AdminRecord? row,
) async {
  final revision = ref.read(catalogRevisionProvider.notifier);
  void refresh() {
    revision.refresh();
    if (context.mounted) refreshAdmin(ref);
  }

  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CollectionEditor(row: row, refresh: refresh),
  );
  if (context.mounted && changed == true) {
    toast(
      context,
      row == null ? 'Đã thêm bộ sưu tập.' : 'Đã cập nhật bộ sưu tập.',
    );
  }
}

class CollectionEditor extends ConsumerStatefulWidget {
  const CollectionEditor({super.key, this.row, required this.refresh});
  final AdminRecord? row;
  final VoidCallback refresh;
  @override
  ConsumerState<CollectionEditor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<CollectionEditor> {
  late final repository = ref.read(adminRepositoryProvider);
  late final title = TextEditingController(text: widget.row?['title'] ?? '');
  late final slug = TextEditingController(text: widget.row?['slug'] ?? '');
  late final description = TextEditingController(
    text: widget.row?['description'] ?? '',
  );
  late final style = TextEditingController(text: widget.row?['style'] ?? '');
  late final position = TextEditingController(
    text: '${widget.row?['position'] ?? 0}',
  );
  late bool active = widget.row?['active'] ?? false;
  late String? coverId = widget.row?['coverProductId'];
  late AdminRecord? cover = widget.row?['cover'];
  bool customSlug = false;
  @override
  void dispose() {
    for (final c in [title, slug, description, style, position]) {
      c.dispose();
    }
    super.dispose();
  }

  void styleChanged(String value) {
    setState(() {
      coverId = null;
      cover = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final styles = ref.watch(adminCollectionStylesProvider);
    final refresh = widget.refresh;
    return AdminMutationDialog(
      title: widget.row == null ? 'Thêm bộ sưu tập' : 'Sửa bộ sưu tập',
      message:
          'Sản phẩm tự cập nhật theo phong cách. Mỗi phong cách có một bộ sưu tập; chỉ sản phẩm công khai được dùng làm ảnh bìa.',
      reload: refresh,
      fields: [
        TextFormField(
          controller: title,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Tên bộ sưu tập'),
          validator: (v) => requiredText(v, max: 120),
          onChanged: (v) {
            if (widget.row == null && !customSlug) slug.text = taxonomySlug(v);
          },
        ),
        TextFormField(
          controller: slug,
          readOnly: widget.row != null,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'Đường dẫn',
            helperText:
                'Giữ cố định sau khi tạo. Chữ thường, số và dấu gạch nối.',
          ),
          onChanged: (_) => customSlug = true,
          validator: (v) =>
              RegExp(
                    r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
                  ).hasMatch((v ?? '').trim()) &&
                  v!.trim().length <= 100
              ? null
              : 'Đường dẫn chưa hợp lệ.',
        ),
        TextFormField(
          controller: description,
          maxLength: 1500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Mô tả'),
          validator: (v) =>
              (v ?? '').trim().length <= 1500 ? null : 'Tối đa 1500 ký tự.',
        ),
        TextFormField(
          controller: style,
          maxLength: 100,
          validator: (v) => requiredText(v, max: 100),
          onChanged: styleChanged,
          decoration: InputDecoration(
            labelText: 'Phong cách',
            helperText:
                'Trùng chính xác phong cách của sản phẩm. Có thể nhập phong cách mới.',
            suffixIcon: PopupMenuButton<String>(
              tooltip: 'Chọn phong cách có sẵn',
              enabled: styles.hasValue,
              itemBuilder: (_) => [
                for (final name
                    in styles.asData?.value['styles'] as List? ?? [])
                  PopupMenuItem(value: '$name', child: Text('$name')),
              ],
              onSelected: (v) {
                style.text = v;
                styleChanged(v);
              },
              icon: const Icon(Icons.expand_more),
            ),
          ),
        ),
        if (styles.hasError)
          TextButton.icon(
            onPressed: () => ref.invalidate(adminCollectionStylesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Tải lại gợi ý phong cách'),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Ảnh bìa', style: T.body),
            const SizedBox(height: 8),
            Text(
              coverId == null
                  ? 'Tự động chọn sản phẩm công khai mới nhất.'
                  : widget.row?['coverFallback'] == true &&
                        coverId == widget.row?['coverProductId']
                  ? cover == null
                        ? 'Ảnh đã chọn không còn hợp lệ và chưa có sản phẩm công khai để thay thế.'
                        : 'Ảnh đã chọn không còn hợp lệ. Cửa hàng đang dùng ảnh thay thế.'
                  : 'Đang dùng ảnh bìa được chọn.',
              style: T.small,
            ),
            if (cover != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  height: 140,
                  child: FashionImage(
                    cover!['url'],
                    label: title.text,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                AppButton(
                  'Chọn ảnh bìa',
                  outlined: true,
                  icon: Icons.photo_library_outlined,
                  onPressed: style.text.trim().isEmpty
                      ? null
                      : () async {
                          final selected = await showDialog<AdminRecord>(
                            context: context,
                            builder: (_) =>
                                CollectionCoverPicker(style: style.text.trim()),
                          );
                          if (mounted && selected != null) {
                            setState(() {
                              coverId = selected['id'];
                              cover = {'url': selected['images'][0]['url']};
                            });
                          }
                        },
                ),
                if (coverId != null)
                  TextButton(
                    onPressed: () => setState(() {
                      coverId = null;
                      cover = null;
                    }),
                    child: const Text('Dùng ảnh tự động'),
                  ),
              ],
            ),
          ],
        ),
        TextFormField(
          controller: position,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Thứ tự hiển thị',
            helperText: 'Số nhỏ hơn xuất hiện trước.',
          ),
          validator: (v) {
            final n = int.tryParse(v ?? '');
            return n != null && n >= 0 && n <= 10000
                ? null
                : 'Nhập số từ 0 đến 10000.';
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hiển thị bộ sưu tập'),
          subtitle: const Text(
            'Cần có sản phẩm công khai cùng phong cách để xuất hiện tại cửa hàng.',
          ),
          value: active,
          onChanged: (v) => setState(() => active = v),
        ),
      ],
      submit: () async {
        try {
          await repository.saveCollection(widget.row?['id'], {
            'title': title.text.trim(),
            'description': description.text.trim(),
            'style': style.text.trim(),
            'position': int.parse(position.text),
            'active': active,
            if (widget.row == null)
              'slug': slug.text.trim()
            else
              'expectedVersion': widget.row!['version'],
            if (widget.row == null ||
                coverId != widget.row!['coverProductId'] ||
                style.text.trim() != widget.row!['style'])
              'coverProductId': coverId,
          }, onLateCompletion: refresh);
          // The shared mutation dialog closes itself only after the server confirms.
        } finally {
          refresh();
        }
      },
    );
  }
}
