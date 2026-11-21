import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_activity.dart';
import 'admin_presentation.dart';

class RemoteAdminDashboard extends ConsumerWidget {
  const RemoteAdminDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminSummaryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Tổng quan cửa hàng',
          'Theo dõi kinh doanh và những việc cần xử lý.',
          actions: [
            AppButton(
              'Tải lại',
              icon: Icons.refresh,
              outlined: true,
              busy: value.isLoading,
              onPressed: () {
                ref.invalidate(adminSummaryProvider);
                ref.invalidate(adminListProvider);
              },
            ),
            AppButton(
              'Thêm sản phẩm',
              icon: Icons.add,
              onPressed: () => context.go('/admin/products/new'),
            ),
          ],
        ),
        AdminAsync(
          value: value,
          reload: () => ref.invalidate(adminSummaryProvider),
          builder: (data) {
            final recent = (data['recentOrders'] as List? ?? [])
                .cast<Map<String, dynamic>>();
            final statuses = Map<String, dynamic>.from(
              data['orderStatuses'] as Map? ?? {},
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      const Text('Toàn thời gian', style: T.small),
                      if (data['generatedAt'] != null)
                        Text(
                          'Cập nhật ${adminDate(data['generatedAt'])}',
                          style: T.small,
                        ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    final columns = c.maxWidth >= 1080
                        ? 4
                        : c.maxWidth >= 540
                        ? 2
                        : 1;
                    final width = (c.maxWidth - (columns - 1) * 16) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final metric in [
                          (
                            'Tiền đã thu',
                            adminMoney(data['paidRevenueVnd']),
                            '${adminNumber(data['paidOrders'])} đơn đã thanh toán',
                            Icons.account_balance_wallet_outlined,
                            '/admin/orders',
                          ),
                          (
                            'Đơn hàng',
                            adminNumber(data['orders']),
                            'Tất cả trạng thái',
                            Icons.receipt_long_outlined,
                            '/admin/orders',
                          ),
                          (
                            'Chờ xác nhận',
                            adminNumber(data['pendingOrders']),
                            'Đơn hàng cần xử lý',
                            Icons.pending_actions_outlined,
                            '/admin/orders?status=PENDING',
                          ),
                          (
                            'Sản phẩm đang bật',
                            adminNumber(data['activeProducts']),
                            'Trong ${adminNumber(data['products'])} sản phẩm',
                            Icons.checkroom_outlined,
                            '/admin/products?status=active',
                          ),
                        ])
                          SizedBox(
                            width: width,
                            child: _Metric(
                              label: metric.$1,
                              value: metric.$2,
                              detail: metric.$3,
                              icon: metric.$4,
                              path: metric.$5,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AdminSectionTitle('Cần chú ý'),
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          _Alert(
                            '${adminNumber(data['lowStockVariants'])} biến thể sắp hết',
                            'Còn 1–5 sản phẩm trong kho',
                            Icons.inventory_2_outlined,
                            '/admin/inventory?status=low',
                          ),
                          _Alert(
                            '${adminNumber(data['outOfStockVariants'])} biến thể hết hàng',
                            'Kiểm tra và bổ sung tồn kho',
                            Icons.remove_shopping_cart_outlined,
                            '/admin/inventory?status=out',
                          ),
                          _Alert(
                            adminMoney(data['codAwaitingSettlementVnd']),
                            'COD đã giao, chờ đối soát',
                            Icons.payments_outlined,
                            '/admin/orders?paymentStatus=COD_UNSETTLED',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (data['dailySales'] is List)
                  AdminCard(
                    child: _SalesChart(
                      days: (data['dailySales'] as List)
                          .cast<Map<String, dynamic>>(),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, c) {
                    final latest = AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdminSectionTitle(
                            'Đơn hàng mới nhất',
                            action: TextButton(
                              onPressed: () => context.go('/admin/orders'),
                              child: const Text('Xem tất cả'),
                            ),
                          ),
                          if (recent.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'Chưa có đơn hàng. Đơn mới sẽ xuất hiện tại đây.',
                                style: T.body,
                              ),
                            ),
                          for (final order in recent) _RecentOrder(order),
                        ],
                      ),
                    );
                    final distribution = AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AdminSectionTitle('Trạng thái đơn hàng'),
                          for (final status in adminOrderStatuses.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          status.value,
                                          style: T.small,
                                        ),
                                      ),
                                      Text(
                                        adminNumber(statuses[status.key]),
                                        style: T.body,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: (data['orders'] as num? ?? 0) == 0
                                        ? 0
                                        : ((statuses[status.key] as num? ?? 0) /
                                                  (data['orders'] as num))
                                              .clamp(0.0, 1.0),
                                    minHeight: 5,
                                    borderRadius: T.radius,
                                    backgroundColor: T.canvas,
                                    color: status.key == 'DELIVERED'
                                        ? T.success
                                        : T.accent,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                    return c.maxWidth >= 850
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 7, child: latest),
                              const SizedBox(width: 20),
                              Expanded(flex: 4, child: distribution),
                            ],
                          )
                        : Column(children: [latest, distribution]);
                  },
                ),
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AdminSectionTitle('Đối soát & vận hành'),
                      Wrap(
                        spacing: 32,
                        runSpacing: 20,
                        children: [
                          for (final field in [
                            (
                              'Tiền đã hoàn có biên nhận',
                              adminMoney(data['refundedVnd']),
                            ),
                            (
                              'Tiền còn lại đã xác định',
                              adminMoney(data['netCollectedVnd']),
                            ),
                            (
                              'Số lượng trong kho',
                              adminNumber(data['inventoryUnits']),
                            ),
                            ('Khách hàng', adminNumber(data['customers'])),
                          ])
                            SizedBox(
                              width: 225,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(field.$1, style: T.small),
                                  const SizedBox(height: 6),
                                  Text(
                                    field.$2,
                                    style: T.body.copyWith(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Tiền đã thu gồm thanh toán thành công và khoản thu thêm, trước khi trừ hoàn tiền. COD đã giao chỉ được tính sau khi đối soát.',
                        style: T.small,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Khoản thanh toán thu thêm: ${adminMoney(data['extraCollectedVnd'])} · Hoàn cũ cần đối chiếu: ${adminMoney(data['legacyRefundUnverifiedVnd'])}',
                        style: T.small,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const AdminCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Nhật ký hoạt động', style: T.body),
            subtitle: Text(
              'Lịch sử thay đổi và người thực hiện',
              style: T.small,
            ),
            children: [AdminActivityPanel()],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.path,
  });
  final String label, value, detail, path;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Material(
    color: T.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: T.radius,
      side: BorderSide(color: T.line),
    ),
    child: InkWell(
      borderRadius: T.radius,
      onTap: () => context.go(path),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: T.small.copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                Icon(icon, size: 20, color: T.accent),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              value,
              style: T.body.copyWith(
                fontSize: 27,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(detail, style: T.small),
          ],
        ),
      ),
    ),
  );
}

class _Alert extends StatelessWidget {
  const _Alert(this.title, this.subtitle, this.icon, this.path);
  final String title, subtitle, path;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 320),
    child: InkWell(
      borderRadius: T.radius,
      onTap: () => context.go(path),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: T.warning, size: 22),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: T.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(subtitle, style: T.small),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right, size: 18, color: T.muted),
          ],
        ),
      ),
    ),
  );
}

class _RecentOrder extends StatelessWidget {
  const _RecentOrder(this.order);
  final Map<String, dynamic> order;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.go('/admin/orders/${order['id']}'),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: T.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order['code'] ?? 'Đơn hàng',
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(order['user']?['name'] ?? 'Khách hàng', style: T.small),
              Text(adminDate(order['createdAt']), style: T.small),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(adminMoney(order['total']), style: T.body),
              const SizedBox(height: 6),
              AdminStatus.order(order['status']),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Daily order value for the last 14 days (single series, so no legend).
class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.days});
  final List<Map<String, dynamic>> days;
  // Lighter brand plum: validated for lightness, chroma and 3:1 contrast.
  static const bar = Color(0xFFA8607F);
  static const height = 160.0;

  static String _label(String day) {
    final parts = day.split('-');
    return parts.length == 3 ? '${parts[2]}/${parts[1]}' : day;
  }

  @override
  Widget build(BuildContext context) {
    final totals = [for (final d in days) int.tryParse('${d['total']}') ?? 0];
    final orders = days.fold<int>(
      0,
      (sum, d) => sum + ((d['orders'] as num?)?.toInt() ?? 0),
    );
    final sum = totals.fold<int>(0, (a, b) => a + b);
    final max = totals.fold<int>(0, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionTitle('Doanh số 14 ngày gần nhất'),
        Text(adminMoney(sum), style: T.display(28)),
        const SizedBox(height: 4),
        Text(
          '${adminNumber(orders)} đơn · Không gồm đơn đã hủy hoặc hoàn về kho · Giờ Việt Nam',
          style: T.small,
        ),
        const SizedBox(height: 20),
        if (max == 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Chưa có đơn hàng trong 14 ngày gần nhất.',
              style: T.small,
            ),
          )
        else ...[
          Text('Cao nhất ${adminMoney(max)}', style: T.small),
          const SizedBox(height: 8),
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${_label('${days[i]['day']}')}: ${adminMoney(totals[i])} · ${adminNumber(days[i]['orders'])} đơn',
                      child: Semantics(
                        label:
                            'Ngày ${_label('${days[i]['day']}')}, ${adminMoney(totals[i])}, ${adminNumber(days[i]['orders'])} đơn',
                        // Full-height hit target, larger than the bar itself.
                        child: Container(
                          color: Colors.transparent,
                          alignment: Alignment.bottomCenter,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Container(
                            height: totals[i] == 0
                                ? 0
                                : (totals[i] / max * height).clamp(2, height),
                            constraints: const BoxConstraints(maxWidth: 28),
                            decoration: const BoxDecoration(
                              color: bar,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: T.line),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Text(
                    i == 0 || i == days.length - 1 || i == days.length ~/ 2
                        ? _label('${days[i]['day']}')
                        : '',
                    textAlign: TextAlign.center,
                    style: T.small,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
