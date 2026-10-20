import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

const _actions = {
  'PRODUCT_CREATED': 'Tạo sản phẩm',
  'PRODUCT_UPDATED': 'Cập nhật sản phẩm',
  'SKU_CREATED': 'Tạo biến thể',
  'SKU_UPDATED': 'Cập nhật biến thể',
  'CATEGORY_CREATED': 'Tạo danh mục',
  'CATEGORY_RENAMED': 'Đổi tên danh mục',
  'BRAND_CREATED': 'Tạo thương hiệu',
  'BRAND_RENAMED': 'Đổi tên thương hiệu',
  'INVENTORY_ADJUSTED': 'Điều chỉnh tồn kho',
  'ORDER_STATUS_CHANGED': 'Chuyển trạng thái đơn hàng',
  'CONTENT_DRAFT_SAVED': 'Lưu bản nháp nội dung',
  'CONTENT_PUBLISHED': 'Xuất bản nội dung',
};

class AdminActivityPanel extends ConsumerStatefulWidget {
  const AdminActivityPanel({super.key});

  @override
  ConsumerState<AdminActivityPanel> createState() => _AdminActivityPanelState();
}

class _AdminActivityPanelState extends ConsumerState<AdminActivityPanel> {
  int page = 1;

  @override
  Widget build(BuildContext context) {
    final provider = adminListProvider((kind: 'audit', page: page));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        AdminHeading(
          'Thay đổi gần đây',
          'Các thao tác quản trị đã lưu thành công. Thời gian hiển thị theo múi giờ thiết bị.',
          actions: [
            AppButton(
              'Tải lại lịch sử',
              outlined: true,
              onPressed: () => ref.invalidate(provider),
            ),
          ],
        ),
        AdminAsync(
          value: ref.watch(provider),
          reload: () => ref.invalidate(provider),
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.items.isEmpty)
                const Text(
                  'Chưa có thao tác quản trị được ghi nhận.',
                  style: T.body,
                ),
              for (final event in data.items)
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _actions[event['action']] ?? 'Thao tác quản trị',
                        style: T.body,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        DateTime.parse(
                          event['createdAt'] as String,
                        ).toLocal().toString().split('.').first,
                        style: T.small,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Quản trị viên: ${event['actorId']}',
                        style: T.small,
                      ),
                      Text('Bản ghi: ${event['targetId']}', style: T.small),
                    ],
                  ),
                ),
              if (data.total > 0 || page > 1)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppButton(
                      'Trang trước',
                      outlined: true,
                      onPressed: page > 1 ? () => setState(() => page--) : null,
                    ),
                    Text(
                      'Trang $page · ${data.total} thao tác',
                      style: T.small,
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
