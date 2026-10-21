import 'package:flutter/material.dart';
import '../../account/order_tracking.dart';
import 'shipment_actions.dart';
import 'return_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/format.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/commerce_json.dart';
import '../../../app/providers.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'product_editor.dart';
import 'taxonomy_page.dart';
import 'admin_activity.dart';
import 'content_page.dart';
import 'promotions_page.dart';

class RemoteAdminRoute extends StatelessWidget {
  const RemoteAdminRoute({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) {
    final parts = path.split('/');
    if (path == '/admin') return const RemoteAdminDashboard();
    if (path == '/admin/content') return const RemoteContentPage();
    if (path == '/admin/promotions') return const RemotePromotionsPage();
    if (path == '/admin/categories' || path == '/admin/brands') {
      return RemoteTaxonomyPage(key: ValueKey(path), kind: parts[2]);
    }
    if (path == '/admin/products/new') return const RemoteProductEditor();
    if (parts.length == 5 && parts[2] == 'products' && parts[4] == 'edit') {
      return RemoteProductEditor(id: parts[3]);
    }
    if (parts.length == 4 && parts[2] == 'orders') {
      return RemoteAdminOrder(id: parts[3]);
    }
    final kind = {
      '/admin/products': 'products',
      '/admin/inventory': 'inventory',
      '/admin/orders': 'orders',
      '/admin/customers': 'users',
    }[path];
    if (kind != null) return RemoteAdminList(key: ValueKey(kind), kind: kind);
    return const StatePanel(
      title: 'Chức năng quản trị chưa khả dụng',
      message:
          'Khuyến mãi và theo dõi AI sẽ được kết nối ở giai đoạn tiếp theo.',
    );
  }
}

class RemoteAdminDashboard extends ConsumerWidget {
  const RemoteAdminDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminHeading(
        'Một góc nhìn toàn cảnh.',
        'Số liệu được tổng hợp từ cửa hàng của bạn.',
        actions: [
          AppButton(
            'Tải lại',
            outlined: true,
            onPressed: () => ref.invalidate(adminSummaryProvider),
          ),
        ],
      ),
      AdminAsync(
        value: ref.watch(adminSummaryProvider),
        reload: () => ref.invalidate(adminSummaryProvider),
        builder: (data) => LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 16,
            children: [
              for (final metric in [
                (
                  'Tiền đã thu · toàn thời gian',
                  'paidRevenueVnd',
                  '/admin/orders',
                ),
                (
                  'COD đã giao, chờ đối soát',
                  'codAwaitingSettlementVnd',
                  '/admin/orders',
                ),
                ('Đơn đã thanh toán', 'paidOrders', '/admin/orders'),
                ('Sản phẩm', 'products', '/admin/products'),
                ('Số lượng trong kho', 'inventoryUnits', '/admin/inventory'),
                ('Đơn hàng', 'orders', '/admin/orders'),
                ('Chờ xác nhận', 'pendingOrders', '/admin/orders'),
                ('Khách hàng', 'customers', '/admin/customers'),
              ])
                SizedBox(
                  width: constraints.maxWidth < 600
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 16) / 2,
                  child: AdminCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(metric.$1, style: T.small),
                        const SizedBox(height: 12),
                        Text(
                          metric.$2.endsWith('Vnd')
                              ? '${(data[metric.$2] as String).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.')} ₫'
                              : '${data[metric.$2]}',
                          style: T.display(36),
                        ),
                        TextButton(
                          onPressed: () => context.go(metric.$3),
                          child: const Text('Xem danh sách'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const Text(
        'Đơn COD đã giao vẫn cần đối soát tiền thu. Tổng đơn hàng không phải doanh thu đã nhận.',
        style: T.small,
      ),
      const AdminActivityPanel(),
    ],
  );
}

class RemoteAdminList extends ConsumerStatefulWidget {
  const RemoteAdminList({super.key, required this.kind});
  final String kind;
  @override
  ConsumerState<RemoteAdminList> createState() => _RemoteAdminListState();
}

class _RemoteAdminListState extends ConsumerState<RemoteAdminList> {
  int page = 1;
  @override
  Widget build(BuildContext context) {
    final key = (kind: widget.kind, page: page);
    final title = {
      'products': 'Sản phẩm',
      'inventory': 'Biến thể & kho',
      'orders': 'Đơn hàng',
      'users': 'Khách hàng & tài khoản',
    }[widget.kind]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          title,
          'Dữ liệu được lưu tại cửa hàng.',
          actions: [
            if (widget.kind == 'products')
              AppButton(
                'Thêm sản phẩm',
                icon: Icons.add,
                onPressed: () => context.go('/admin/products/new'),
              ),
            AppButton(
              'Tải lại',
              outlined: true,
              onPressed: () => ref.invalidate(adminListProvider(key)),
            ),
          ],
        ),
        AdminAsync(
          value: ref.watch(adminListProvider(key)),
          reload: () => ref.invalidate(adminListProvider(key)),
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${data.total} bản ghi · Trang ${data.page}',
                  style: T.small,
                ),
              ),
              if (data.items.isEmpty)
                const StatePanel(
                  title: 'Chưa có dữ liệu',
                  message: 'Danh sách này hiện chưa có bản ghi.',
                ),
              for (final item in data.items) _record(context, item),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  AppButton(
                    'Trang trước',
                    outlined: true,
                    onPressed: page > 1 ? () => setState(() => page--) : null,
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

  Widget _record(BuildContext context, AdminRecord item) {
    switch (widget.kind) {
      case 'products':
        return AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['name'],
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                '${item['category']['name']} · ${item['brand']['name']}',
                style: T.small,
              ),
              Text(
                '${item['active'] ? 'Đang hiển thị' : 'Đã ẩn'} · ${(item['variants'] as List).length} biến thể',
                style: T.small,
              ),
              const SizedBox(height: 12),
              AppButton(
                'Chỉnh sửa sản phẩm',
                outlined: true,
                onPressed: () =>
                    context.go('/admin/products/${item['id']}/edit'),
              ),
            ],
          ),
        );
      case 'inventory':
        final variant = commerceMap(item['variant']);
        return AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                variant['product']['name'],
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                '${variant['sku']} · ${variant['color']} / ${variant['size']}',
                style: T.small,
              ),
              Text(
                'Tồn kho: ${item['quantity']} · ${variant['active'] && variant['product']['active'] ? 'Đang bán' : 'Đã ẩn'}',
                style: T.body,
              ),
              const SizedBox(height: 12),
              AppButton(
                'Điều chỉnh kho',
                outlined: true,
                onPressed: () =>
                    adjustInventory(context, ref, item, variant['sku']),
              ),
            ],
          ),
        );
      case 'orders':
        final order = commerceOrder(item, email: item['user']?['email'] ?? '');
        return AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Đơn ${order.id}',
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              Text('${order.draft.name} · ${order.status}', style: T.body),
              Text(
                '${money(order.total)} · ${order.createdAt.toLocal().toString().split('.').first}',
                style: T.small,
              ),
              const SizedBox(height: 12),
              AppButton(
                'Xem đơn hàng',
                outlined: true,
                onPressed: () => context.go('/admin/orders/${order.id}'),
              ),
            ],
          ),
        );
      default:
        return AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['name'],
                style: T.body.copyWith(fontWeight: FontWeight.w600),
              ),
              SelectableText(item['email'], style: T.body),
              Text(
                '${item['phone'] ?? ''} · ${item['role'] == 'ADMIN' ? 'Quản trị viên' : 'Khách hàng'}',
                style: T.small,
              ),
            ],
          ),
        );
    }
  }
}

Future<void> adjustInventory(
  BuildContext context,
  WidgetRef ref,
  AdminRecord inventory,
  String sku,
) async {
  final delta = TextEditingController(), reason = TextEditingController();
  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: 'Điều chỉnh kho',
      message:
          '$sku · Tồn kho hiện tại: ${inventory['quantity']}. Nhập số dương để thêm hoặc số âm để giảm.',
      reload: () => refreshAdmin(ref),
      onDisposed: () {
        delta.dispose();
        reason.dispose();
      },
      fields: [
        AppField(
          label: 'Số lượng thay đổi',
          controller: delta,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          validator: (s) {
            final n = int.tryParse(s ?? '');
            return n == null || n == 0 || n.abs() > 1000000
                ? 'Nhập số nguyên khác 0, tối đa ±1.000.000.'
                : n + (inventory['quantity'] as int) < 0
                ? 'Tồn kho không thể âm.'
                : null;
          },
        ),
        AppField(
          label: 'Lý do',
          controller: reason,
          validator: (s) => (s ?? '').trim().length < 3
              ? 'Nhập ít nhất 3 ký tự.'
              : requiredText(s),
        ),
      ],
      submit: () async {
        await repo.adjust(
          inventory['id'],
          delta: int.parse(delta.text),
          version: inventory['version'],
          reason: reason.text.trim(),
        );
      },
    ),
  );
  // Dialog routes can outlive the originating account/page.
  if (context.mounted && changed == true) {
    refreshAdmin(ref);
    ref.read(catalogRevisionProvider.notifier).refresh();
    toast(context, 'Đã cập nhật tồn kho.');
  }
}

Future<void> settleCod(
  BuildContext context,
  WidgetRef ref,
  AdminRecord order,
  int total,
) async {
  final amount = TextEditingController(), reference = TextEditingController();
  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: 'Đối soát COD',
      message:
          'Chỉ xác nhận sau khi đã nhận đủ ${money(total)} cho đơn ${order['id']}. Mã đối soát dùng để tra cứu khoản thu.',
      reload: () => refreshAdmin(ref),
      onDisposed: () {
        amount.dispose();
        reference.dispose();
      },
      fields: [
        AppField(
          label: 'Số tiền đã thu (VND)',
          controller: amount,
          keyboardType: TextInputType.number,
          validator: (value) =>
              priceValidation(value) ??
              (int.tryParse(value ?? '') != total
                  ? 'Số tiền phải bằng tổng đơn ${money(total)}.'
                  : null),
        ),
        AppField(
          label: 'Mã đối soát',
          controller: reference,
          validator: (value) => (value ?? '').trim().length < 3
              ? 'Nhập mã đối soát từ 3 đến 100 ký tự.'
              : requiredText(value, max: 100),
        ),
      ],
      submit: () async {
        await repo.settleCod(
          order['id'],
          amount: amount.text,
          reference: reference.text.trim(),
          version: order['version'],
        );
      },
    ),
  );
  if (context.mounted && changed == true) {
    refreshAdmin(ref);
    toast(context, 'Đã ghi nhận tiền thu COD.');
  }
}

class RemoteAdminOrder extends ConsumerWidget {
  const RemoteAdminOrder({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (kind: 'orders', id: id);
    return AdminAsync(
      value: ref.watch(adminDetailProvider(key)),
      reload: () => ref.invalidate(adminDetailProvider(key)),
      builder: (data) {
        final order = commerceOrder(data, email: data['user']?['email'] ?? '');
        final payment = commerceMap(data['payment']);
        final receipt = payment['settlement'] == null
            ? null
            : commerceMap(payment['settlement']);
        final next = {
          'PENDING': ('CONFIRMED', 'Xác nhận đơn'),
          'CONFIRMED': ('SHIPPED', 'Bắt đầu giao hàng'),
          'SHIPPED': ('DELIVERED', 'Đánh dấu đã giao'),
        }[data['status']];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminHeading(
              'Chi tiết đơn hàng',
              order.id,
              actions: [
                AppButton(
                  'Về danh sách đơn',
                  outlined: true,
                  onPressed: () => context.go('/admin/orders'),
                ),
                AppButton(
                  'Tải lại',
                  outlined: true,
                  onPressed: () => ref.invalidate(adminDetailProvider(key)),
                ),
              ],
            ),
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.status, style: T.display(24)),
                  const SizedBox(height: 12),
                  Text(
                    '${order.draft.name}\n${order.draft.email}\n${order.draft.phone}\n${order.draft.address}',
                    style: T.body,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${order.draft.payment} · ${money(order.total)}',
                    style: T.body,
                  ),
                  if (order.couponCode != null)
                    Text(
                      'Khuyến mãi ${order.couponCode}: -${money(order.discount)}',
                      style: T.body,
                    ),
                  const Text(
                    'Trạng thái giao hàng và tiền thu COD được theo dõi riêng.',
                    style: T.small,
                  ),
                  Text(
                    order.draft.express
                        ? 'Giao hàng nhanh'
                        : 'Giao hàng tiêu chuẩn',
                    style: T.small,
                  ),
                  if (receipt != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      'Mã đối soát: ${receipt['reference']}',
                      semanticsLabel: 'Mã đối soát: ${receipt['reference']}',
                      style: T.body,
                    ),
                    Text(
                      'Đã thu: ${money(vnd(receipt['amount']))}',
                      style: T.body,
                    ),
                    Text(
                      'Người ghi nhận: ${receipt['actorId']}',
                      style: T.small,
                    ),
                    Text(
                      '${DateTime.parse(receipt['settledAt'] as String).toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 19).replaceFirst('T', ' ')} (UTC+7)',
                      style: T.small,
                    ),
                  ],
                  if (data['status'] == 'DELIVERED' &&
                      payment['provider'] == 'cod' &&
                      payment['status'] == 'PENDING') ...[
                    const SizedBox(height: 20),
                    AppButton(
                      'Đối soát COD',
                      onPressed: () =>
                          settleCod(context, ref, data, order.total),
                    ),
                  ],
                  if (payment['provider'] == 'vnpay') ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Các lần thanh toán VNPay sandbox',
                      style: T.body,
                    ),
                    for (final attempt in (payment['attempts'] as List? ?? []))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SelectableText(
                          '${attempt['reference']} · ${attempt['status']} · ${money(vnd(attempt['amount']))}\nMã giao dịch: ${attempt['transactionNo'] ?? 'Chưa có'}${attempt['reviewRequired'] == true ? '\nCẦN KIỂM TRA: thanh toán trùng hoặc đơn đã hủy.' : ''}',
                        ),
                      ),
                    if (payment['status'] != 'PAID')
                      const Text(
                        'Chờ xác minh thanh toán trước khi xử lý giao hàng.',
                        style: T.small,
                      ),
                  ],
                  if (next != null &&
                      order.shipment?.status != 'DELIVERY_FAILED' &&
                      (payment['provider'] != 'vnpay' ||
                          payment['status'] == 'PAID')) ...[
                    const SizedBox(height: 20),
                    AppButton(
                      next.$2,
                      onPressed: () async {
                        final repo = ref.read(adminRepositoryProvider);
                        final changed = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => AdminMutationDialog(
                            title: next.$2,
                            message: 'Cập nhật trạng thái cho đơn ${order.id}?',
                            reload: () => refreshAdmin(ref),
                            submit: () async {
                              await repo.status(
                                id,
                                status: next.$1,
                                version: data['version'],
                              );
                            },
                          ),
                        );
                        if (context.mounted && changed == true) {
                          refreshAdmin(ref);
                        }
                      },
                    ),
                  ],
                  ShipmentActions(data: data, order: order),
                ],
              ),
            ),
            AdminCard(child: OrderTracking(order: order)),
            AdminReturnActions(data: data, order: order),
            for (final item in order.items)
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: T.body),
                    Text(
                      '${item.sku} · ${item.color} / ${item.size}',
                      style: T.small,
                    ),
                    Text(
                      '${item.quantity} × ${money(item.unitPrice)}',
                      style: T.body,
                    ),
                  ],
                ),
              ),
            Text(
              'Tiền hàng: ${money(order.subtotal)}\nPhí giao hàng: ${money(order.shipping)}\nTổng cộng: ${money(order.total)}',
              style: T.body,
            ),
          ],
        );
      },
    );
  }
}
