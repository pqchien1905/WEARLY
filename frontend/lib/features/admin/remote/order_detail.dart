import '../../../core/widgets/promotion_price.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/commerce_json.dart';
import '../../../domain/commerce.dart';
import '../../account/order_tracking.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'order_presentation.dart';
import 'order_actions.dart';
import 'shipment_actions.dart';
import 'return_actions.dart';
import 'refund_actions.dart';
import '../../../data/remote_payments.dart';

class RemoteAdminOrder extends ConsumerWidget {
  const RemoteAdminOrder({super.key, required this.id, this.returnTo});
  final String id;
  final String? returnTo;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (kind: 'orders', id: id);
    final value = ref.watch(adminDetailProvider(key));
    final back = adminOrdersBack(returnTo);
    if (value.hasError &&
        value.error is ApiException &&
        (value.error as ApiException).status == 404) {
      return StatePanel(
        title: 'Không tìm thấy đơn hàng',
        message: 'Đơn hàng không tồn tại hoặc đường dẫn không đúng.',
        action: AppButton(
          back.startsWith('/admin/customers/')
              ? 'Về khách hàng'
              : 'Về danh sách đơn',
          onPressed: () => context.go(back),
        ),
      );
    }
    return AdminAsync(
      value: value,
      reload: () => ref.invalidate(adminDetailProvider(key)),
      builder: (data) {
        final Order order;
        try {
          order = commerceOrder(data, email: data['user']?['email'] ?? '');
        } catch (_) {
          return StatePanel(
            title: 'Dữ liệu đơn hàng chưa đầy đủ',
            message:
                'Không thể xử lý đơn này khi thông tin sản phẩm hoặc thanh toán chưa hợp lệ.',
            action: AppButton(
              'Tải lại',
              onPressed: () => ref.invalidate(adminDetailProvider(key)),
            ),
          );
        }
        final payment = commerceMap(data['payment']);
        final role = ref.watch(staffRoleProvider);
        final customer = AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionTitle('Thông tin giao nhận'),
              _info('Người nhận', order.draft.name),
              _info('Số điện thoại', order.draft.phone),
              _info('Email tài khoản', order.draft.email),
              _info('Địa chỉ giao hàng', order.draft.address),
              _info(
                'Hình thức giao hàng',
                order.draft.express
                    ? 'Giao hàng nhanh'
                    : 'Giao hàng tiêu chuẩn',
              ),
            ],
          ),
        );
        final products = AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminSectionTitle(
                'Sản phẩm (${order.items.fold<int>(0, (sum, item) => sum + item.quantity)})',
              ),
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 72,
                        child: item.image.isEmpty
                            ? const ColoredBox(
                                color: T.canvas,
                                child: Icon(
                                  Icons.checkroom_outlined,
                                  color: T.muted,
                                ),
                              )
                            : FashionImage(
                                item.image,
                                label: item.name,
                                fit: BoxFit.cover,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: T.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${item.sku} · ${item.color} / ${item.size}',
                              style: T.small,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 20,
                              runSpacing: 4,
                              children: [
                                Text(
                                  '${item.quantity} × ${money(item.unitPrice)}',
                                  style: T.small,
                                ),
                                Text(money(item.total), style: T.body),
                                if (item.discounted)
                                  PromotionPrice(
                                    price: item.unitPrice,
                                    original: item.originalUnitPrice,
                                    name: item.promotionName,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24, color: T.line),
              _total('Tiền hàng', money(order.subtotal)),
              _total('Phí giao hàng', money(order.shipping)),
              if (order.discount > 0)
                _total(
                  'Khuyến mãi ${order.couponCode ?? ''}',
                  '-${money(order.discount)}',
                ),
              const Divider(height: 24, color: T.line),
              _total('Tổng cộng', money(order.total), strong: true),
            ],
          ),
        );
        final payments = AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminSectionTitle('Thanh toán'),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  adminPaymentBadge(payment),
                  Text(
                    adminPaymentProviders[payment['provider']] ?? '',
                    style: T.body,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _total('Tổng tiền đơn hàng', money(order.total)),
              const SizedBox(height: 8),
              const Text(
                'Giao hàng thành công và tiền đã thu được ghi nhận riêng.',
                style: T.small,
              ),
              if (payment['settlement'] case final Map receipt) ...[
                const Divider(height: 28, color: T.line),
                _info('Mã đối soát', '${receipt['reference']}'),
                Text('Đã thu: ${money(vnd(receipt['amount']))}', style: T.body),
                Text(
                  '${adminOrderDate(receipt['settledAt'])} (UTC+7)',
                  style: T.small,
                ),
              ],
              if (canStaff(role, 'payments.manage') &&
                  data['status'] == 'DELIVERED' &&
                  payment['provider'] == 'cod' &&
                  payment['status'] == 'PENDING') ...[
                const SizedBox(height: 16),
                AppButton(
                  'Đối soát COD',
                  onPressed: () => settleCod(context, ref, data, order.total),
                ),
              ],
              if (onlinePaymentProviders.contains(payment['provider'])) ...[
                const SizedBox(height: 16),
                if (![
                  'PAID',
                  'PARTIALLY_REFUNDED',
                  'REFUNDED',
                ].contains(payment['status']))
                  const Text(
                    'Chờ xác minh thanh toán trước khi xử lý giao hàng.',
                    style: T.small,
                  ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Lịch sử thanh toán ${paymentProviderName(payment['provider'])}',
                    style: T.body,
                  ),
                  children: [
                    if ((payment['attempts'] as List? ?? []).isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Chưa có lần thanh toán nào.',
                          style: T.small,
                        ),
                      ),
                    for (final attempt in payment['attempts'] as List? ?? [])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SelectableText(
                              '${attempt['reference']}',
                              style: T.small,
                            ),
                            Text(
                              '${adminPaymentStatuses[attempt['status']] ?? attempt['status']} · ${money(vnd(attempt['amount']))}',
                              style: T.body,
                            ),
                            if (attempt['reviewRequired'] == true)
                              const Text(
                                'Cần kiểm tra khoản thu trùng hoặc đơn đã hủy.',
                                style: TextStyle(color: T.warning),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminHeading(
              'Chi tiết đơn hàng',
              '${order.displayCode} · Đặt lúc ${adminOrderDate(data['createdAt'])}',
              actions: [
                AppButton(
                  back.startsWith('/admin/customers/')
                      ? 'Về khách hàng'
                      : 'Về danh sách đơn',
                  icon: Icons.arrow_back,
                  outlined: true,
                  onPressed: () => context.go(back),
                ),
                AppButton(
                  'Tải lại',
                  icon: Icons.refresh,
                  outlined: true,
                  busy: value.isLoading,
                  onPressed: () => refreshAdmin(ref),
                ),
              ],
            ),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Text(
                            order.displayCode,
                            style: T.body.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          AdminStatus.order(data['status']),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await Clipboard.setData(
                              ClipboardData(text: order.displayCode),
                            );
                            if (context.mounted) {
                              toast(context, 'Đã sao chép mã đơn.');
                            }
                          } catch (_) {
                            if (context.mounted) {
                              toast(
                                context,
                                'Chưa sao chép được. Vui lòng thử lại.',
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Sao chép mã đơn'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _instruction(data),
                    style: T.body.copyWith(color: T.muted),
                  ),
                  if (canStaff(role, 'orders.fulfill')) ...[
                    const SizedBox(height: 16),
                    _AdvanceOrder(data: data, order: order),
                    ShipmentActions(data: data, order: order),
                  ],
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, c) {
                final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    products,
                    AdminCard(child: OrderTracking(order: order)),
                  ],
                );
                final right = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [customer, payments],
                );
                return c.maxWidth >= 900
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 6, child: left),
                          const SizedBox(width: 24),
                          Expanded(flex: 4, child: right),
                        ],
                      )
                    : Column(
                        children: [
                          products,
                          customer,
                          payments,
                          AdminCard(child: OrderTracking(order: order)),
                        ],
                      );
              },
            ),
            AdminReturnActions(data: data, order: order),
            if (canStaff(role, 'payments.manage'))
              AdminCard(
                child: AdminRefundActions(
                  key: ValueKey('refunds-${order.id}'),
                  orderId: order.id,
                ),
              ),
          ],
        );
      },
    );
  }

  String _instruction(AdminRecord data) => switch (data['status']) {
    'PENDING' =>
      'Kiểm tra thông tin người nhận và thanh toán trước khi xác nhận.',
    'CONFIRMED' => 'Chuẩn bị đủ sản phẩm, sau đó bàn giao đơn cho vận chuyển.',
    'SHIPPED' =>
      data['shipment']?['status'] == 'DELIVERY_FAILED'
          ? 'Giao hàng chưa thành công. Chọn giao lại hoặc xác nhận hàng hoàn về kho.'
          : 'Cập nhật tiến trình giao hàng và xác nhận khi khách đã nhận đủ sản phẩm.',
    'DELIVERED' =>
      data['payment']?['provider'] == 'cod' &&
              data['payment']?['status'] == 'PENDING'
          ? 'Đã giao hàng. Cần đối soát COD sau khi nhận đủ tiền thu hộ.'
          : 'Đơn đã giao thành công. Các yêu cầu trả hàng và hoàn tiền được xử lý bên dưới.',
    'CANCELLED' => 'Đơn đã hủy. Kiểm tra hoàn tiền nếu đơn đã thanh toán.',
    _ => 'Hàng đã được nhận lại kho. Kiểm tra khoản tiền cần hoàn cho khách.',
  };
  Widget _info(String label, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text(label, style: T.small)),
        const SizedBox(height: 4),
        SelectableText(
          text.isEmpty ? 'Chưa có thông tin' : text,
          semanticsLabel:
              '$label: ${text.isEmpty ? 'Chưa có thông tin' : text}',
          style: T.body,
        ),
      ],
    ),
  );
  Widget _total(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: T.body)),
        const SizedBox(width: 16),
        Flexible(
          fit: FlexFit.tight,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: T.body.copyWith(
              fontSize: strong ? 20 : 14,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AdvanceOrder extends ConsumerWidget {
  const _AdvanceOrder({required this.data, required this.order});
  final AdminRecord data;
  final Order order;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = {
      'PENDING': ('CONFIRMED', 'Xác nhận đơn'),
      'CONFIRMED': ('SHIPPED', 'Bắt đầu giao hàng'),
      'SHIPPED': ('DELIVERED', 'Đánh dấu đã giao'),
    }[data['status']];
    final payment = data['payment'] as Map;
    final payable =
        payment['amount'] == '${order.total}' &&
        (payment['provider'] == 'cod'
            ? [
                'PENDING',
                'PAID',
                'PARTIALLY_REFUNDED',
              ].contains(payment['status'])
            : payment['provider'] == 'free'
            ? order.total == 0 && payment['status'] == 'PAID'
            : ['PAID', 'PARTIALLY_REFUNDED'].contains(payment['status']));
    if (next == null) return const SizedBox.shrink();
    if (!payable) {
      return const Text(
        'Chưa đủ điều kiện thanh toán để chuyển sang bước tiếp theo.',
        style: T.small,
      );
    }
    if (order.shipment?.status == 'DELIVERY_FAILED') {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: AppButton(
        next.$2,
        icon: Icons.arrow_forward,
        onPressed: () async {
          final repo = ref.read(adminRepositoryProvider);
          final changed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AdminMutationDialog(
              title: next.$2,
              message:
                  'Cập nhật trạng thái cho đơn ${order.displayCode}?${next.$1 == 'DELIVERED' ? '\nChỉ xác nhận khi khách đã nhận hàng. Tiền COD được đối soát riêng.' : ''}',
              reload: () => refreshAdmin(ref),
              submit: () async {
                await repo.status(
                  order.id,
                  status: next.$1,
                  version: data['version'],
                );
              },
            ),
          );
          if (context.mounted && changed == true) {
            refreshAdmin(ref);
            toast(
              context,
              'Đã cập nhật đơn ${order.displayCode}: ${adminOrderStatuses[next.$1]}.',
            );
          }
        },
      ),
    );
  }
}
