import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

const _actions = {
  'STAFF_UPDATED': 'Thay đổi quyền nhân viên',
  'SUPPORT_REPLIED': 'Trả lời yêu cầu hỗ trợ',
  'SUPPORT_STATUS_CHANGED': 'Đổi trạng thái yêu cầu hỗ trợ',
  'PRODUCT_CREATED': 'Tạo sản phẩm',
  'PRODUCT_UPDATED': 'Cập nhật sản phẩm',
  'PRODUCT_IMAGE_UPLOADED': 'Tải ảnh sản phẩm',
  'SKU_CREATED': 'Tạo biến thể',
  'SKU_UPDATED': 'Cập nhật biến thể',
  'CATEGORY_CREATED': 'Tạo danh mục',
  'CATEGORY_RENAMED': 'Đổi tên danh mục',
  'BRAND_CREATED': 'Tạo thương hiệu',
  'BRAND_RENAMED': 'Đổi tên thương hiệu',
  'INVENTORY_ADJUSTED': 'Điều chỉnh tồn kho',
  'ORDER_STATUS_CHANGED': 'Chuyển trạng thái đơn hàng',
  'COD_SETTLED': 'Đối soát tiền thu COD',
  'SHIPMENT_UPDATED': 'Cập nhật vận chuyển',
  'ORDER_CANCELLED': 'Hủy đơn trước khi gửi',
  'RETURN_DECIDED': 'Duyệt yêu cầu trả hàng',
  'RETURN_RECEIVED': 'Nhận hàng khách trả',
  'REFUND_CREATED': 'Tạo khoản hoàn tiền',
  'REFUND_UPDATED': 'Xác minh kết quả hoàn tiền',
  'PROMOTION_CREATED': 'Tạo mã khuyến mãi',
  'PROMOTION_UPDATED': 'Cập nhật mã khuyến mãi',
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
                      ...auditChanges(
                        event['details'],
                      ).map((line) => Text(line, style: T.small)),
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

const _fields = {
  'quantity': 'Số lượng',
  'version': 'Phiên bản',
  'staffVersion': 'Phiên bản quyền',
  'role': 'Vai trò',
  'active': 'Đang hoạt động',
  'status': 'Trạng thái',
  'price': 'Giá (VND)',
  'amount': 'Số tiền (VND)',
  'minSubtotal': 'Đơn tối thiểu (VND)',
  'maxDiscount': 'Giảm tối đa (VND)',
  'usageLimit': 'Giới hạn lượt dùng',
  'perUserLimit': 'Lượt dùng mỗi khách',
  'kind': 'Loại giảm giá',
  'startsAt': 'Bắt đầu',
  'expiresAt': 'Kết thúc',
  'publishedVersion': 'Phiên bản đã xuất bản',
  'tryOnSupported': 'Hỗ trợ thử đồ',
  'categoryId': 'Danh mục',
  'brandId': 'Thương hiệu',
  'productId': 'Sản phẩm',
  'provider': 'Thanh toán',
  'primary': 'Khoản thu chính',
};
Iterable<String> auditChanges(Object? details) sync* {
  if (details is! Map) return;
  final before = details['before'] is Map ? details['before'] as Map : const {},
      after = details['after'] is Map ? details['after'] as Map : const {};
  String value(Object? item) => item == null
      ? '—'
      : item is bool
      ? (item ? 'Có' : 'Không')
      : staffRoleNames[item] ?? '$item';
  for (final field in _fields.entries) {
    if (field.key == 'amount' &&
        (const ['FIXED', 'PERCENT'].contains(before['kind']) ||
            const ['FIXED', 'PERCENT'].contains(after['kind']))) {
      String discount(Map snapshot) {
        final amount = snapshot['amount'];
        if (amount == null) return value(null);
        return snapshot['kind'] == 'PERCENT' ? '$amount%' : '$amount VND';
      }

      if (before['amount'] != after['amount'] ||
          before['kind'] != after['kind']) {
        yield 'Giá trị giảm: ${discount(before)} → ${discount(after)}';
      }
      continue;
    }
    if ((before.containsKey(field.key) || after.containsKey(field.key)) &&
        before[field.key] != after[field.key]) {
      yield '${field.value}: ${value(before[field.key])} → ${value(after[field.key])}';
    }
  }
}
