import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

/// Stable ASCII URL from Vietnamese; user edits take precedence over suggestions.
String taxonomySlug(String value) {
  const groups = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  var text = value.toLowerCase();
  for (final e in groups.entries) {
    text = text.replaceAll(RegExp('[${e.value}]'), e.key);
  }
  text = text
      .replaceAll(RegExp(r'[̀-ͯ]'), '')
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (text.length > 100) {
    text = text.substring(0, 100).replaceAll(RegExp(r'-+$'), '');
  }
  return text;
}

Future<AdminRecord?> editTaxonomy(
  BuildContext context,
  WidgetRef ref,
  String kind, [
  AdminRecord? row,
]) async {
  final label = kind == 'categories' ? 'danh mục' : 'thương hiệu';
  void refresh() {
    if (!context.mounted) return;
    refreshAdmin(ref);
    ref.invalidate(adminReferencesProvider);
    ref.read(catalogRevisionProvider.notifier).refresh();
  }

  final repository = ref.read(adminRepositoryProvider);
  // Public cache lifetime is independent of this page and staff session.
  final catalogRevision = ref.read(catalogRevisionProvider.notifier);
  final name = TextEditingController(text: row?['name'] ?? '');
  final slug = TextEditingController();
  final slugField = GlobalKey<FormFieldState<String>>();
  String? rejectedSlug;
  bool customSlug = false;
  AdminRecord? saved;
  final changed = await showDialog<bool>(
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
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: (value) {
            if (row == null && !customSlug) slug.text = taxonomySlug(value);
          },
          decoration: const InputDecoration(labelText: 'Tên hiển thị'),
          maxLength: 100,
          validator: (v) => requiredText(v, max: 100),
        ),
        if (row == null)
          TextFormField(
            key: slugField,
            controller: slug,
            onChanged: (_) => customSlug = true,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Đường dẫn',
              helperText: 'Ví dụ: mua-thu, wearly-studio',
            ),
            maxLength: 100,
            validator: (v) => (v ?? '').trim() == rejectedSlug
                ? 'Đường dẫn đã được sử dụng.'
                : RegExp(
                        r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
                      ).hasMatch((v ?? '').trim()) &&
                      (v ?? '').trim().length <= 100
                ? null
                : 'Dùng chữ thường không dấu, số và dấu gạch nối.',
          ),
      ],
      reload: refresh,
      submit: () async {
        final submittedSlug = slug.text.trim();
        try {
          saved = await repository.saveTaxonomy(
            kind,
            row?['id'],
            {
              'name': name.text.trim(),
              if (row == null)
                'slug': submittedSlug
              else
                'expectedName': row['name'],
              if (row?['updatedAt'] != null)
                'expectedUpdatedAt': row!['updatedAt'],
            },
            onLateCompletion: () {
              catalogRevision.refresh();
              if (context.mounted) {
                refreshAdmin(ref);
                ref.invalidate(adminReferencesProvider);
              }
            },
          );
        } on ApiException catch (e) {
          if (e.code == 'TAXONOMY_SLUG_EXISTS') {
            rejectedSlug = submittedSlug;
            slugField.currentState?.validate();
          }
          if (e.status == 409 && e.code == 'CONFLICT') {
            throw const ApiException(
              'CONFLICT',
              'Đường dẫn đã được sử dụng. Tải lại danh sách để kiểm tra.',
              status: 409,
            );
          }
          rethrow;
        } finally {
          // The server may have committed even if logout/navigation or a lost
          // response prevents acknowledging success. Re-read, never replay.
          catalogRevision.refresh();
          if (context.mounted) {
            refreshAdmin(ref);
            ref.invalidate(adminReferencesProvider);
          }
        }
      },
    ),
  );
  if (context.mounted && changed == true) {
    toast(context, row == null ? 'Đã thêm $label.' : 'Đã cập nhật $label.');
    return saved;
  }
  return null;
}
