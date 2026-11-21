import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'taxonomy_kind.dart';

Widget taxonomyPublication(AdminRecord row) => AdminStatus(
  (row['publishedProducts'] as num? ?? 0) > 0
      ? 'Có ở cửa hàng'
      : 'Chưa có ở cửa hàng',
  color: (row['publishedProducts'] as num? ?? 0) > 0 ? T.success : T.muted,
);

Future<bool> deleteTaxonomy(
  BuildContext context,
  WidgetRef ref,
  TaxonomyKind kind,
  AdminRecord row,
) async {
  if ((row['_count']?['products'] as num? ?? 0) > 0) {
    final viewProducts = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${kind.title} đang có sản phẩm'),
        content: Text(
          '“${row['name']}” có ${adminNumber(row['_count']['products'])} sản phẩm, bao gồm cả sản phẩm ẩn. Chuyển các sản phẩm sang ${kind.label} khác trước khi xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
          AppButton(
            'Xem sản phẩm',
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (context.mounted && viewProducts == true) {
      context.go(kind.products('${row['id']}'));
    }
    return false;
  }
  final repo = ref.read(adminRepositoryProvider);
  final catalog = ref.read(catalogRevisionProvider.notifier);
  void refreshLists() {
    catalog.refresh();
    if (context.mounted) {
      ref.invalidate(
        (kind == TaxonomyKind.categories
            ? adminCategoriesProvider
            : adminBrandsProvider),
      );
      ref.invalidate(
        (kind == TaxonomyKind.categories
            ? adminCategorySummaryProvider
            : adminBrandSummaryProvider),
      );
      ref.invalidate(adminProductSummaryProvider);
      ref.invalidate(adminInventorySummaryProvider);
      ref.invalidate(adminReferencesProvider);
    }
  }

  void refresh() {
    refreshLists();
    if (context.mounted) {
      ref.invalidate(
        adminDetailProvider((kind: kind.name, id: '${row['id']}')),
      );
    }
  }

  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: 'Xóa ${kind.label}',
      submitLabel: 'Xác nhận xóa',
      destructive: true,
      message:
          'Xóa vĩnh viễn “${row['name']}” (/${row['slug']})? Thao tác này không thể hoàn tác. Chỉ ${kind.label} không chứa sản phẩm mới được xóa.',
      reload: refresh,
      submit: () async {
        try {
          await repo.deleteTaxonomy(
            kind.name,
            '${row['id']}',
            '${row['updatedAt']}',
            onLateCompletion: refresh,
          );
          // Do not refetch the removed detail while its route is closing.
          refreshLists();
        } catch (_) {
          refresh();
          rethrow;
        }
      },
    ),
  );
  if (!context.mounted || deleted != true) return false;
  toast(context, 'Đã xóa ${kind.label}.');
  return true;
}

class TaxonomyCoverage extends StatelessWidget {
  const TaxonomyCoverage({super.key, required this.row, required this.kind});
  final AdminRecord row;
  final TaxonomyKind kind;
  @override
  Widget build(BuildContext context) {
    final total = (row['_count']?['products'] as num? ?? 0).toInt();
    final published = (row['publishedProducts'] as num? ?? 0).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${adminNumber(total)} sản phẩm thuộc ${kind.label}',
          style: T.display(24).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        if (total > 0) ...[
          Semantics(
            label: '$published trên $total sản phẩm công khai',
            child: ClipRRect(
              borderRadius: T.radius,
              child: LinearProgressIndicator(
                value: (published / total).clamp(0, 1),
                minHeight: 8,
                color: T.success,
                backgroundColor: T.line,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              AdminStatus(
                '${adminNumber(published)} công khai',
                color: T.success,
              ),
              AdminStatus(
                '${adminNumber(total - published)} chưa công khai',
                color: T.warning,
              ),
            ],
          ),
        ] else
          Text(
            '${kind.title} chưa có sản phẩm. Thêm sản phẩm hoặc đổi ${kind.label} của một sản phẩm hiện có để bắt đầu.',
            style: T.body,
          ),
        const SizedBox(height: 16),
        const Text(
          'Sản phẩm xuất hiện ở cửa hàng khi đang bật, có ảnh và có ít nhất một SKU đang bán. Số liệu quản trị bao gồm cả sản phẩm ẩn.',
          style: T.small,
        ),
      ],
    );
  }
}
