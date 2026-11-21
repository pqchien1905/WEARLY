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
import 'order_presentation.dart' show adminOrderDate;
import 'collection_actions.dart';
import 'collection_editor.dart';
import 'collections_workspace.dart' show collectionStatus;

class RemoteCollectionDetail extends ConsumerWidget {
  const RemoteCollectionDetail({super.key, required this.id, this.returnTo});
  final String id;
  final String? returnTo;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminDetailProvider((kind: 'collections', id: id)));
    final row = value.asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go(collectionsBack(returnTo)),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Về danh sách bộ sưu tập'),
          ),
        ),
        AdminHeading(
          'Chi tiết bộ sưu tập',
          'Kiểm tra nội dung, ảnh bìa và sản phẩm trước khi giới thiệu tại cửa hàng.',
          actions: [
            if (row != null)
              AppButton(
                'Sửa bộ sưu tập',
                icon: Icons.edit_outlined,
                onPressed: () => editCollection(context, ref, row),
              ),
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              onPressed: value.isLoading ? null : () => refreshAdmin(ref),
            ),
          ],
        ),
        if (value.error case ApiException(status: 404))
          StatePanel(
            title: 'Không tìm thấy bộ sưu tập',
            message:
                'Bộ sưu tập có thể đã được xóa. Quay lại danh sách để xem dữ liệu mới nhất.',
            action: AppButton(
              'Về danh sách',
              onPressed: () => context.go(collectionsBack(returnTo)),
            ),
          )
        else
          AdminAsync(
            value: value,
            reload: () => refreshAdmin(ref),
            builder: (r) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminCard(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final photo = ClipRRect(
                        borderRadius: T.radius,
                        child: SizedBox(
                          height: 300,
                          child: r['cover'] == null
                              ? ColoredBox(
                                  color: T.canvas,
                                  child: const Center(
                                    child: Icon(
                                      Icons.photo_library_outlined,
                                      size: 56,
                                      color: T.muted,
                                    ),
                                  ),
                                )
                              : FashionImage(
                                  r['cover']['url'],
                                  label: r['cover']['alt'] ?? r['title'],
                                  fit: BoxFit.contain,
                                ),
                        ),
                      );
                      final text = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: collectionStatus(r),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            r['title'],
                            style: T
                                .display(30)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            (r['description'] ?? '').toString().isEmpty
                                ? 'Chưa có mô tả.'
                                : r['description'],
                            style: T.body,
                          ),
                          const SizedBox(height: 18),
                          Text('Phong cách: ${r['style']}', style: T.body),
                          const SizedBox(height: 8),
                          Text(
                            '${adminNumber(r['productCount'])} công khai / ${adminNumber(r['totalProducts'])} sản phẩm',
                            style: T.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            r['coverFallback'] == true
                                ? r['cover'] == null
                                      ? 'Ảnh đã chọn không còn hợp lệ và chưa có sản phẩm công khai để thay thế.'
                                      : 'Ảnh đã chọn không còn công khai cùng phong cách. Cửa hàng tự dùng ảnh thay thế; bạn có thể chọn lại ảnh bìa.'
                                : r['coverProductId'] == null
                                ? 'Ảnh bìa tự động từ sản phẩm công khai mới nhất.'
                                : 'Ảnh bìa đã được chọn từ sản phẩm.',
                            style: T.small,
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              AppButton(
                                r['active'] == true
                                    ? 'Ẩn bộ sưu tập'
                                    : 'Hiện bộ sưu tập',
                                outlined: true,
                                onPressed: () =>
                                    changeCollection(context, ref, r),
                              ),
                              if (collectionPublished(r))
                                AppButton(
                                  'Xem tại cửa hàng',
                                  outlined: true,
                                  icon: Icons.open_in_new,
                                  onPressed: () =>
                                      context.go('/collections/${r['slug']}'),
                                ),
                            ],
                          ),
                        ],
                      );
                      return c.maxWidth >= 850 &&
                              MediaQuery.textScalerOf(context).scale(14) <= 17
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: photo),
                                const SizedBox(width: 28),
                                Expanded(flex: 2, child: text),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                photo,
                                const SizedBox(height: 24),
                                text,
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
                        'Sản phẩm theo phong cách',
                        action: AppButton(
                          'Xem sản phẩm',
                          outlined: true,
                          onPressed: () => context.go(collectionProducts(r)),
                        ),
                      ),
                      const Text(
                        'Danh sách tự cập nhật khi phong cách hoặc trạng thái sản phẩm thay đổi. Hiển thị tối đa 6 sản phẩm mới cập nhật, bao gồm sản phẩm ẩn.',
                        style: T.small,
                      ),
                      const SizedBox(height: 16),
                      if ((r['recentProducts'] as List? ?? []).isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'Chưa có sản phẩm cùng phong cách. Thêm hoặc chỉnh sửa phong cách tại trang sản phẩm.',
                          ),
                        ),
                      for (final product in r['recentProducts'] as List? ?? [])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextButton(
                            onPressed: () => context.go(
                              Uri(
                                path: '/admin/products/${product['id']}',
                                queryParameters: {
                                  'from': collectionProducts(r),
                                },
                              ).toString(),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 48,
                                  height: 60,
                                  child: (product['images'] as List).isEmpty
                                      ? const Icon(Icons.image_outlined)
                                      : FashionImage(
                                          product['images'][0]['url'],
                                          label: product['name'],
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(product['name'], style: T.body),
                                      const SizedBox(height: 6),
                                      AdminStatus(
                                        product['published'] == true
                                            ? 'Công khai'
                                            : 'Chưa công khai',
                                        color: product['published'] == true
                                            ? T.success
                                            : T.muted,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                      if ((r['totalProducts'] as num? ?? 0) >
                          (r['productCount'] as num? ?? 0))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => context.go(
                              collectionProducts(r, visibility: 'incomplete'),
                            ),
                            child: const Text('Xem sản phẩm chưa công khai'),
                          ),
                        ),
                    ],
                  ),
                ),
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AdminSectionTitle('Thông tin bản ghi'),
                      SelectableText(
                        '/collections/${r['slug']}',
                        style: T.body,
                      ),
                      const SizedBox(height: 12),
                      SelectableText('Mã bộ sưu tập: $id', style: T.small),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            try {
                              await Clipboard.setData(ClipboardData(text: id));
                              if (context.mounted) {
                                toast(context, 'Đã sao chép mã bộ sưu tập.');
                              }
                            } catch (_) {
                              if (context.mounted) {
                                toast(
                                  context,
                                  'Không thể sao chép. Bạn có thể chọn mã để sao chép thủ công.',
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: const Text('Sao chép mã'),
                        ),
                      ),
                      Text(
                        'Thứ tự hiển thị: ${r['position']} · Phiên bản: ${r['version']}',
                        style: T.small,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ngày tạo: ${adminOrderDate(r['createdAt'])} (UTC+7)',
                        style: T.small,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cập nhật: ${adminOrderDate(r['updatedAt'])} (UTC+7)',
                        style: T.small,
                      ),
                      const Divider(height: 32),
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
                            label: const Text('Xóa bộ sưu tập'),
                            onPressed: () async {
                              final removed = await changeCollection(
                                context,
                                ref,
                                r,
                                remove: true,
                              );
                              if (context.mounted && removed) {
                                context.go(collectionsBack(returnTo));
                              }
                            },
                          ),
                          const Text(
                            'Xóa trang giới thiệu, giữ nguyên sản phẩm và tồn kho.',
                            style: T.small,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
