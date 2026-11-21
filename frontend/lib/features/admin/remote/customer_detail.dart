import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import 'customer_actions.dart';
import 'customer_password_dialog.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'order_presentation.dart';
import 'customer_widgets.dart';

class RemoteAdminCustomer extends ConsumerWidget {
  const RemoteAdminCustomer({super.key, required this.id, this.returnTo});
  final String id;
  final String? returnTo;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = adminDetailProvider((kind: 'users', id: id)),
        value = ref.watch(provider);
    final back = customersBack(returnTo), role = ref.watch(staffRoleProvider);
    final uri = GoRouterState.of(context).uri;
    final page = (int.tryParse(uri.queryParameters['orderPage'] ?? '') ?? 1)
        .clamp(1, 10000);
    if (value.hasError &&
        value.error is ApiException &&
        (value.error as ApiException).status == 404) {
      return StatePanel(
        title: 'Không tìm thấy khách hàng',
        message:
            'Tài khoản không tồn tại hoặc không phải tài khoản khách hàng.',
        action: AppButton(
          'Về danh sách khách hàng',
          onPressed: () => context.go(back),
        ),
      );
    }
    return AdminAsync(
      value: value,
      reload: () => ref.invalidate(provider),
      builder: (data) {
        final stats = data['summary'] as Map, active = data['active'] == true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminHeading(
              'Hồ sơ khách hàng',
              'Thông tin tài khoản và lịch sử mua hàng.',
              actions: [
                AppButton(
                  'Về danh sách khách hàng',
                  outlined: true,
                  icon: Icons.arrow_back,
                  onPressed: () => context.go(back),
                ),
                AppButton(
                  'Tải lại',
                  outlined: true,
                  icon: Icons.refresh,
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
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${data['name']}',
                        style: T.body.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      customerStatus(active),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, c) {
                      final cells = [
                        info('Email đăng nhập', '${data['email']}'),
                        info('Số điện thoại', '${data['phone']}'),
                        info(
                          'Ngày đăng ký',
                          '${adminOrderDate(data['createdAt'])} (UTC+7)',
                        ),
                        info(
                          'Cập nhật gần nhất',
                          '${adminOrderDate(data['updatedAt'])} (UTC+7)',
                        ),
                      ];
                      return Wrap(
                        spacing: 24,
                        runSpacing: 16,
                        children: [
                          for (final cell in cells)
                            SizedBox(
                              width: c.maxWidth < 700
                                  ? c.maxWidth
                                  : (c.maxWidth - 24) / 2,
                              child: cell,
                            ),
                        ],
                      );
                    },
                  ),
                  const Divider(height: 32, color: T.line),
                  info('Mã khách hàng (UUID)', id),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (canStaff(role, 'customers.manage'))
                        AppButton(
                          'Chỉnh sửa thông tin',
                          icon: Icons.edit_outlined,
                          onPressed: () =>
                              editCustomer(context, ref, customer: data),
                        ),
                      if (canStaff(role, 'customers.manage'))
                        AppButton(
                          'Đặt lại mật khẩu',
                          outlined: true,
                          icon: Icons.key_outlined,
                          onPressed: () =>
                              resetCustomerPassword(context, ref, data),
                        ),
                      if (canStaff(role, 'customers.manage'))
                        AppButton(
                          active ? 'Khóa tài khoản' : 'Mở khóa tài khoản',
                          outlined: true,
                          icon: active
                              ? Icons.lock_outline
                              : Icons.lock_open_outlined,
                          onPressed: () => toggleCustomer(context, ref, data),
                        ),
                      TextButton.icon(
                        onPressed: canStaff(role, 'customers.manage')
                            ? () async {
                                if (await deleteCustomer(context, ref, data) &&
                                    context.mounted) {
                                  context.go(back);
                                }
                              }
                            : null,
                        style: TextButton.styleFrom(foregroundColor: T.danger),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Xóa tài khoản'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await Clipboard.setData(ClipboardData(text: id));
                            if (context.mounted) {
                              toast(context, 'Đã sao chép mã khách hàng.');
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
                        label: const Text('Sao chép mã'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            CustomerMetrics(
              items: [
                (
                  label: 'Tổng đơn hàng',
                  value: adminNumber(stats['totalOrders']),
                  note: 'Bao gồm đơn đang xử lý và đã hủy',
                  icon: Icons.receipt_long_outlined,
                  action: null,
                ),
                (
                  label: 'Đơn đã giao',
                  value: adminNumber(stats['deliveredOrders']),
                  note: 'Giao hàng thành công',
                  icon: Icons.local_shipping_outlined,
                  action: null,
                ),
                (
                  label: 'Giá trị đơn đã giao',
                  value: adminMoney(stats['deliveredValueVnd']),
                  note: 'Gồm COD đang chờ thu, trước hoàn tiền',
                  icon: Icons.shopping_bag_outlined,
                  action: null,
                ),
                (
                  label: 'Đã thu sau hoàn tiền',
                  value: adminMoney(stats['netPaidVnd']),
                  note: 'Khoản thu chính, trừ hoàn thành công',
                  icon: Icons.account_balance_wallet_outlined,
                  action: null,
                ),
              ],
            ),
            AdminHeading(
              'Lịch sử đơn hàng',
              'Đơn được liên kết theo mã khách hàng, kể cả khi thay đổi email.',
              actions: [
                AppButton(
                  'Mở trong quản lý đơn',
                  outlined: true,
                  icon: Icons.open_in_new,
                  onPressed: () => context.go(
                    Uri(
                      path: '/admin/orders',
                      queryParameters: {'customerId': id},
                    ).toString(),
                  ),
                ),
              ],
            ),
            _CustomerOrders(
              id: id,
              page: page,
              returnTo: uri.toString(),
              onPage: (next) => context.go(
                uri
                    .replace(
                      queryParameters: {
                        ...uri.queryParameters,
                        'orderPage': '$next',
                      },
                    )
                    .toString(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget info(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(child: Text(label, style: T.small)),
      const SizedBox(height: 6),
      SelectableText(
        value.isEmpty ? 'Chưa có thông tin' : value,
        semanticsLabel:
            '$label: ${value.isEmpty ? 'Chưa có thông tin' : value}',
        style: T.body,
      ),
    ],
  );
}

class _CustomerOrders extends ConsumerWidget {
  const _CustomerOrders({
    required this.id,
    required this.page,
    required this.returnTo,
    required this.onPage,
  });
  final String id, returnTo;
  final int page;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = Uri(
          queryParameters: {'customerId': id, 'page': '$page', 'limit': '10'},
        ).query,
        provider = adminOrdersProvider(key);
    return AdminAsync(
      value: ref.watch(provider),
      reload: () => ref.invalidate(provider),
      builder: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.items.isEmpty)
            AdminCard(
              child: StatePanel(
                title: page > 1
                    ? 'Trang này không có đơn hàng'
                    : 'Khách hàng chưa có đơn hàng',
                message: 'Các đơn hàng mới của khách sẽ xuất hiện tại đây.',
                action: page > 1
                    ? AppButton(
                        'Về trang đầu',
                        outlined: true,
                        onPressed: () => onPage(1),
                      )
                    : null,
              ),
            ),
          for (final row in data.items)
            AdminCard(
              child: Wrap(
                spacing: 24,
                runSpacing: 16,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['code']}',
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(adminOrderDate(row['createdAt']), style: T.small),
                    ],
                  ),
                  AdminStatus.order('${row['status']}'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        adminMoney(row['total']),
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      adminPaymentBadge(row['payment'] as Map? ?? {}),
                    ],
                  ),
                  AppButton(
                    'Xem đơn hàng',
                    outlined: true,
                    icon: Icons.arrow_forward,
                    onPressed: () => context.go(
                      Uri(
                        path: '/admin/orders/${row['id']}',
                        queryParameters: {'from': returnTo},
                      ).toString(),
                    ),
                  ),
                ],
              ),
            ),
          AdminPagination(page: data, onPage: onPage),
        ],
      ),
    );
  }
}
