import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'order_presentation.dart';
import 'taxonomy_actions.dart';
import 'taxonomy_widgets.dart';
import 'taxonomy_kind.dart';

class TaxonomyDetail extends ConsumerWidget {
  const TaxonomyDetail({
    super.key,
    required this.id,
    required this.kind,
    this.returnTo,
  });
  final TaxonomyKind kind;
  final String id;
  final String? returnTo;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminDetailProvider((kind: kind.name, id: id)));
    final row = value.asData?.value;
    final writable = canStaff(ref.watch(staffRoleProvider), 'catalog.write');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go(kind.back(returnTo)),
            icon: const Icon(Icons.arrow_back),
            label: Text('Về danh sách ${kind.label}'),
          ),
        ),
        AdminHeading(
          'Chi tiết ${kind.label}',
          'Thông tin phân loại và sản phẩm liên quan.',
          actions: [
            if (row != null && writable)
              AppButton(
                'Đổi tên ${kind.label}',
                icon: Icons.edit_outlined,
                onPressed: () => editTaxonomy(context, ref, kind.name, row),
              ),
            AppButton(
              'Tải lại',
              icon: Icons.refresh,
              outlined: true,
              onPressed: value.isLoading ? null : () => refreshAdmin(ref),
            ),
          ],
        ),
        if (value.error case ApiException(status: 404))
          StatePanel(
            title: 'Không tìm thấy ${kind.label}',
            message:
                '${kind.title} có thể đã được xóa. Quay lại danh sách để xem dữ liệu mới nhất.',
            action: AppButton(
              'Về danh sách',
              onPressed: () => context.go(kind.back(returnTo)),
            ),
          )
        else
          AdminAsync(
            value: value,
            reload: () => refreshAdmin(ref),
            builder: (r) {
              final products = (r['recentProducts'] as List? ?? [])
                  .cast<AdminRecord>();
              final identity = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: T.accent.withValues(alpha: .08),
                          borderRadius: T.radius,
                        ),
                        child: Icon(kind.icon, color: T.accent, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['name'],
                              style: T
                                  .display(27)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            taxonomyPublication(r),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Đường dẫn ${kind.label}', style: T.small),
                  const SizedBox(height: 6),
                  SelectableText('/${r['slug']}', style: T.body),
                  const SizedBox(height: 10),
                  const Text(
                    'Đường dẫn được giữ cố định sau khi tạo. Đổi tên không thay đổi liên kết sản phẩm hay số lượng tồn kho.',
                    style: T.small,
                  ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminCard(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final coverage = Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: T.canvas,
                            borderRadius: T.radius,
                          ),
                          child: TaxonomyCoverage(row: r, kind: kind),
                        );
                        if (c.maxWidth >= 850 &&
                            MediaQuery.textScalerOf(context).scale(14) <= 17) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: identity),
                              const SizedBox(width: 32),
                              Expanded(child: coverage),
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            identity,
                            const SizedBox(height: 24),
                            coverage,
                          ],
                        );
                      },
                    ),
                  ),
                  AdminCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AdminSectionTitle(
                          'Sản phẩm trong ${kind.label}',
                          action: AppButton(
                            'Xem sản phẩm',
                            outlined: true,
                            icon: Icons.checkroom_outlined,
                            onPressed: () => context.go(kind.products(id)),
                          ),
                        ),
                        if ((r['_count']['products'] as num) == 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'Chưa có sản phẩm. Vào trang sản phẩm để thêm mới hoặc phân loại sản phẩm hiện có.',
                              style: T.body,
                            ),
                          )
                        else ...[
                          const Text(
                            'Tối đa 6 sản phẩm mới cập nhật, bao gồm sản phẩm chưa công khai.',
                            style: T.small,
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, c) {
                              final width =
                                  c.maxWidth >= 750 &&
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) <=
                                          17
                                  ? (c.maxWidth - 16) / 2
                                  : c.maxWidth;
                              return Wrap(
                                spacing: 16,
                                runSpacing: 12,
                                children: [
                                  for (final product in products)
                                    SizedBox(
                                      width: width,
                                      child: _product(context, product),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            AppButton(
                              'Xem tồn kho',
                              outlined: true,
                              icon: Icons.inventory_2_outlined,
                              onPressed: () => context.go(
                                Uri(
                                  path: '/admin/inventory',
                                  queryParameters: {
                                    kind.filterId: id,
                                    'visibility': 'all',
                                  },
                                ).toString(),
                              ),
                            ),
                            if ((r['_count']['products'] as num) >
                                (r['publishedProducts'] as num))
                              AppButton(
                                'Xem chưa công khai',
                                outlined: true,
                                onPressed: () => context.go(
                                  kind.products(id, visibility: 'incomplete'),
                                ),
                              ),
                            if ((r['publishedProducts'] as num) > 0)
                              AppButton(
                                'Xem tại cửa hàng',
                                outlined: true,
                                icon: Icons.open_in_new,
                                onPressed: () => context.go(
                                  Uri(
                                    path: '/shop',
                                    queryParameters: {kind.filter: r['slug']},
                                  ).toString(),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AdminCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const AdminSectionTitle('Thông tin bản ghi'),
                        Wrap(
                          spacing: 20,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SelectableText(
                              'Mã ${kind.label}: ${r['id']}',
                              style: T.small,
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              label: const Text('Sao chép mã'),
                              onPressed: () async {
                                try {
                                  await Clipboard.setData(
                                    ClipboardData(text: id),
                                  );
                                  if (context.mounted) {
                                    toast(
                                      context,
                                      'Đã sao chép mã ${kind.label}.',
                                    );
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    toast(
                                      context,
                                      'Không thể sao chép. Bạn có thể chọn mã ở trên để sao chép thủ công.',
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        Text(
                          'Ngày tạo: ${adminOrderDate(r['createdAt'])} (UTC+7)',
                          style: T.small,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cập nhật: ${adminOrderDate(r['updatedAt'])} (UTC+7)',
                          style: T.small,
                        ),
                        if (writable) ...[
                          const Divider(height: 32, color: T.line),
                          Wrap(
                            spacing: 20,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: T.danger,
                                ),
                                icon: const Icon(Icons.delete_outline),
                                label: Text('Xóa ${kind.label}'),
                                onPressed: () async {
                                  final deleted = await deleteTaxonomy(
                                    context,
                                    ref,
                                    kind,
                                    r,
                                  );
                                  if (context.mounted && deleted) {
                                    context.go(kind.back(returnTo));
                                  }
                                },
                              ),
                              Text(
                                'Chỉ xóa được ${kind.label} không chứa sản phẩm.',
                                style: T.small,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _product(BuildContext context, AdminRecord product) {
    final images = product['images'] as List? ?? [];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: T.line),
        borderRadius: T.radius,
      ),
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.all(14),
          foregroundColor: T.ink,
          shape: const RoundedRectangleBorder(borderRadius: T.radius),
        ),
        onPressed: () => context.go(
          Uri(
            path: '/admin/products/${product['id']}',
            queryParameters: {'from': kind.products(id)},
          ).toString(),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 70,
              child: images.isEmpty
                  ? const Icon(Icons.image_outlined, color: T.muted)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: FashionImage(
                        images.first['url'],
                        label: product['name'],
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: T.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  AdminStatus(
                    product['published'] == true
                        ? 'Công khai'
                        : product['active'] == false
                        ? 'Đã ẩn'
                        : 'Chưa đủ điều kiện',
                    color: product['published'] == true ? T.success : T.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}
