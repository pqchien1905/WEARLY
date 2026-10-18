import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/commerce_state.dart';
import '../../domain/commerce.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../cart/cart_page.dart';
import 'account_navigation.dart';

const orderStages = [
  'Chờ xác nhận',
  'Đã xác nhận',
  'Đang đóng gói',
  'Đang giao',
  'Đã giao',
];

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key, this.id});
  final String? id;
  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  final search = TextEditingController();
  String status = '';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(commerceProvider).orders;
    final query = search.text.trim().toLowerCase();
    final selected = orders.where((o) => o.id == widget.id).firstOrNull;
    final filtered =
        orders
            .where(
              (o) =>
                  (status.isEmpty || o.status == status) &&
                  '${o.id} ${o.items.map((i) => i.name).join(' ')}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return AccountFrame(
      title: widget.id == null
          ? 'Đơn hàng của bạn.'
          : 'Chi tiết đơn ${widget.id}',
      current: '/account/orders',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DemoNotice(
            text:
                'Đơn hàng mô phỏng – chưa thanh toán thật. Lịch sử của tab hiện tại, không phải dữ liệu tài khoản đã xác thực. Tải lại trang sẽ xóa đơn.',
          ),
          const SizedBox(height: 24),
          if (widget.id != null) ...[
            TextButton.icon(
              onPressed: () => context.go('/account/orders'),
              icon: const Icon(Icons.west, size: 18),
              label: const Text('Về danh sách đơn'),
            ),
            const SizedBox(height: 24),
            if (selected == null)
              StatePanel(
                title: 'Không tìm thấy đơn hàng',
                message:
                    'Mã đơn không có trong tab này hoặc dữ liệu đã mất khi tải lại trang.',
                action: AppButton(
                  'Xem đơn trong phiên',
                  onPressed: () => context.go('/account/orders'),
                ),
              )
            else
              _OrderDetail(order: selected),
          ] else ...[
            LayoutBuilder(
              builder: (_, c) => Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: c.maxWidth < 750 ? c.maxWidth : c.maxWidth - 296,
                    child: TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Tìm mã đơn hoặc tên sản phẩm',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: c.maxWidth < 750 ? c.maxWidth : 280,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(status),
                      initialValue: status,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Trạng thái',
                      ),
                      items: ['', ...orderStages, 'Đã hủy']
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.isEmpty ? 'Tất cả trạng thái' : s),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => status = v!),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${filtered.length} đơn hàng', style: T.small),
                if (query.isNotEmpty || status.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      search.clear();
                      status = '';
                    }),
                    child: const Text('Xóa bộ lọc'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (filtered.isEmpty)
              StatePanel(
                title: orders.isEmpty
                    ? 'Chưa có đơn trong phiên này'
                    : 'Không có đơn phù hợp',
                message: orders.isEmpty
                    ? 'Đơn được tạo từ checkout demo sẽ xuất hiện ở đây.'
                    : 'Thử mã đơn khác hoặc bỏ bộ lọc trạng thái.',
                action: AppButton(
                  orders.isEmpty ? 'Khám phá cửa hàng' : 'Bỏ bộ lọc',
                  onPressed: () {
                    if (orders.isEmpty) {
                      context.go('/shop');
                    } else {
                      setState(() {
                        search.clear();
                        status = '';
                      });
                    }
                  },
                ),
              ),
            for (final order in filtered) _OrderCard(order: order),
          ],
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      border: Border.all(color: T.line),
      borderRadius: T.radius,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(order.id, style: T.body.copyWith(fontWeight: FontWeight.w600)),
            OrderStatusLabel(order.status),
            Text('Đặt ngày ${orderDate(order.createdAt)}', style: T.small),
          ],
        ),
        const SizedBox(height: 20),
        if (order.items.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                height: 76,
                child: FashionImage(
                  order.items.first.image,
                  label: order.items.first.name,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.items.first.name),
                    const SizedBox(height: 8),
                    Text(
                      '${order.items.fold(0, (s, i) => s + i.quantity)} sản phẩm · ${order.draft.payment}',
                      style: T.small,
                    ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              money(order.total),
              style: T.body.copyWith(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            AppButton(
              'Xem chi tiết',
              outlined: true,
              onPressed: () => context.go('/account/orders/${order.id}'),
            ),
          ],
        ),
      ],
    ),
  );
}

class OrderStatusLabel extends StatelessWidget {
  const OrderStatusLabel(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Text(
    status,
    style: T.body.copyWith(
      fontWeight: FontWeight.w500,
      color: status == 'Đã hủy'
          ? T.danger
          : status == 'Đã giao'
          ? T.success
          : T.accent,
    ),
  );
}

class OrderProgress extends StatelessWidget {
  const OrderProgress({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final current = orderStages.indexOf(status);
    if (status == 'Đã hủy') {
      return const StatePanel(
        title: 'Đơn đã hủy',
        message:
            'Đây là thay đổi trạng thái mô phỏng; không thực hiện hoàn tiền hoặc vận chuyển thật.',
        icon: Icons.cancel_outlined,
      );
    }
    if (current < 0) {
      return DemoNotice(
        text: 'Trạng thái hiện tại: $status. Chưa có tiến trình tương ứng.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tiến trình đơn hàng', style: T.display(26)),
        const SizedBox(height: 12),
        const Text(
          'Minh họa theo trạng thái hiện tại; chưa có vận đơn hay mốc giao hàng thực tế.',
          style: T.small,
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (_, c) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (var i = 0; i < orderStages.length; i++)
                SizedBox(
                  width: c.maxWidth < 700 ? c.maxWidth : (c.maxWidth - 64) / 5,
                  child: Semantics(
                    selected: i == current,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          i == current
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: i == current ? T.accent : T.controlLine,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            orderStages[i],
                            style: T.small.copyWith(
                              color: i == current ? T.accent : T.muted,
                              fontWeight: i == current
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.order});
  final Order order;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1120),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            OrderStatusLabel(order.status),
            Text('Đặt ngày ${orderDate(order.createdAt)}', style: T.small),
          ],
        ),
        const SizedBox(height: 28),
        OrderProgress(status: order.status),
        const Divider(height: 64),
        Text('Thông tin nhận hàng', style: T.display(26)),
        const SizedBox(height: 16),
        Text(
          order.draft.name,
          style: T.body.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(order.draft.phone),
        Text(order.draft.email),
        Text(order.draft.address),
        const SizedBox(height: 12),
        Text(
          '${order.draft.express ? 'Giao nhanh' : 'Giao tiêu chuẩn'} · ${order.draft.payment}',
          style: T.small,
        ),
        const Divider(height: 48),
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  height: 86,
                  child: FashionImage(item.image, label: item.name),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${item.color} / ${item.size} × ${item.quantity}',
                        style: T.small,
                      ),
                      Text('SKU: ${item.sku}', style: T.small),
                      const SizedBox(height: 8),
                      Text(money(item.total)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: CartSummary(
            subtotal: order.subtotal,
            shipping: order.shipping,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton('Tiếp tục mua sắm', onPressed: () => context.go('/shop')),
            AppButton(
              'Cần hỗ trợ đơn hàng',
              outlined: true,
              onPressed: () => context.go('/contact'),
            ),
          ],
        ),
      ],
    ),
  );
}

String orderDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
