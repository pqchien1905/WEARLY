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
import 'inventory_widgets.dart' show InventoryPager;
import 'order_presentation.dart' show adminOrderDate;
import 'promotion_actions.dart';
import 'promotion_editor.dart';
import 'promotion_widgets.dart';

class RemotePromotionDetail extends ConsumerStatefulWidget {
  const RemotePromotionDetail({super.key, required this.id, this.returnTo});
  final String id;
  final String? returnTo;
  @override
  ConsumerState<RemotePromotionDetail> createState() => _PromotionDetailState();
}

class _PromotionDetailState extends ConsumerState<RemotePromotionDetail> {
  int page = 1;
  @override
  void didUpdateWidget(covariant RemotePromotionDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) page = 1;
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(
      adminDetailProvider((kind: 'promotions', id: widget.id)),
    );
    final row = data.asData?.value;
    void reload() => refreshAdmin(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go(promotionsBack(widget.returnTo)),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Về danh sách khuyến mãi'),
          ),
        ),
        AdminHeading(
          'Chi tiết khuyến mãi',
          'Điều kiện áp dụng và lịch sử giảm giá từ đơn hàng thực tế.',
          actions: [
            if (row != null)
              AppButton(
                row['application'] == 'AUTOMATIC'
                    ? 'Sửa khuyến mãi'
                    : 'Sửa mã khuyến mãi',
                icon: Icons.edit_outlined,
                onPressed: () => editPromotion(context, ref, row),
              ),
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              onPressed: data.isLoading ? null : reload,
            ),
          ],
        ),
        if (data.error case ApiException(status: 404))
          StatePanel(
            title: 'Không tìm thấy mã khuyến mãi',
            message:
                'Mã có thể đã được xóa. Quay lại danh sách để xem dữ liệu mới nhất.',
            action: AppButton(
              'Về danh sách',
              onPressed: () => context.go(promotionsBack(widget.returnTo)),
            ),
          )
        else
          AdminAsync(
            value: data,
            reload: reload,
            builder: (r) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PromotionOverview(row: r),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          AppButton(
                            r['application'] == 'AUTOMATIC'
                                ? (r['active'] == true
                                      ? 'Tắt khuyến mãi'
                                      : 'Bật khuyến mãi')
                                : (r['active'] == true ? 'Tắt mã' : 'Bật mã'),
                            outlined: true,
                            onPressed: () => changePromotion(context, ref, r),
                          ),
                          if (r['application'] != 'AUTOMATIC')
                            TextButton.icon(
                              icon: const Icon(Icons.copy_outlined),
                              label: const Text('Sao chép mã'),
                              onPressed: () async {
                                try {
                                  await Clipboard.setData(
                                    ClipboardData(text: r['code']),
                                  );
                                  if (context.mounted) {
                                    toast(context, 'Đã sao chép mã.');
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    toast(
                                      context,
                                      'Không sao chép được. Hãy chọn mã bên dưới.',
                                    );
                                  }
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (r['application'] != 'AUTOMATIC')
                        SelectableText('${r['code']}', style: T.small),
                      const SizedBox(height: 12),
                      const Text(
                        'Giảm trên tiền sản phẩm, không giảm phí giao hàng. Phần trăm được làm tròn xuống đến đồng; số tiền giảm không vượt quá tiền sản phẩm.',
                        style: T.small,
                      ),
                    ],
                  ),
                ),
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AdminSectionTitle('Lịch sử sử dụng'),
                      Text(
                        '${adminNumber(r['usedCount'])} lượt đang tính · ${adminNumber((r['historyCount'] as int? ?? 0) - (r['usedCount'] as int? ?? 0))} lượt đã trả lại',
                        style: T.body,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tổng giảm của lượt đang tính: ${adminMoney(r['discountTotal'] ?? '0')}',
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Bao gồm đơn chưa thanh toán. Đây không phải doanh thu đã quyết toán. Lượt được trả lại khi hủy đơn hợp lệ trước giao hàng; hoàn hàng không tự trả lượt.',
                        style: T.small,
                      ),
                      const SizedBox(height: 16),
                      history(),
                    ],
                  ),
                ),
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AdminSectionTitle('Thông tin quản lý'),
                      Text(
                        'Tạo: ${adminOrderDate(r['createdAt'])} (UTC+7)',
                        style: T.small,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cập nhật: ${adminOrderDate(r['updatedAt'])} (UTC+7)',
                        style: T.small,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        r['canDelete'] == true
                            ? 'Chỉ khuyến mãi chưa có lịch sử đơn hàng mới được xóa vĩnh viễn.'
                            : 'Khuyến mãi đã có lịch sử đơn hàng nên không thể xóa. Tắt khuyến mãi để ngừng áp dụng.',
                        style: T.small,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: T.danger,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            r['application'] == 'AUTOMATIC'
                                ? 'Xóa khuyến mãi'
                                : 'Xóa mã khuyến mãi',
                          ),
                          onPressed: r['canDelete'] == true
                              ? () async {
                                  final deleted = await changePromotion(
                                    context,
                                    ref,
                                    r,
                                    remove: true,
                                  );
                                  if (context.mounted && deleted) {
                                    context.go(promotionsBack(widget.returnTo));
                                  }
                                }
                              : null,
                        ),
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

  Widget history() {
    final key = (id: widget.id, page: page);
    return AdminAsync(
      value: ref.watch(adminPromotionHistoryProvider(key)),
      reload: () => ref.invalidate(adminPromotionHistoryProvider(key)),
      builder: (result) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Chưa có đơn hàng sử dụng mã này.', style: T.body),
            ),
          for (final r in result.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () =>
                            context.go('/admin/orders/${r['orderId']}'),
                        child: Text(
                          'Đơn ${r['order']['code'] ?? '#${r['orderId'].toString().substring(0, 8).toUpperCase()}'}',
                        ),
                      ),
                      Text('Giảm ${adminMoney(r['discount'])}', style: T.body),
                      AdminStatus(
                        r['releasedAt'] == null
                            ? 'Đang tính lượt'
                            : 'Đã trả lượt',
                        color: r['releasedAt'] == null ? T.accent : T.muted,
                      ),
                      AdminStatus.order(r['order']['status']),
                    ],
                  ),
                  Text(
                    'Sử dụng ${adminOrderDate(r['createdAt'])} (UTC+7)${r['releasedAt'] == null ? '' : ' · Trả lượt ${adminOrderDate(r['releasedAt'])} (UTC+7)'}',
                    style: T.small,
                  ),
                  const Divider(height: 24),
                ],
              ),
            ),
          InventoryPager(page: result, go: (n) => setState(() => page = n)),
        ],
      ),
    );
  }
}
