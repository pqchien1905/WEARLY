import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/activity.dart';
import '../../app/commerce_state.dart';
import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../data/mock_catalog.dart';
import 'admin_state.dart';
import '../virtual_tryon/tryon_results.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(commerceProvider).orders;
    final catalog = ref.watch(adminProductsProvider);
    final activity = ref.watch(activityProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Một góc nhìn toàn cảnh.', style: T.display(38)),
        const SizedBox(height: 12),
        const Text(
          'Hoạt động của cửa hàng trong phiên trình diễn hiện tại.',
          style: T.small,
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (_, c) => Wrap(
            spacing: 20,
            runSpacing: 20,
            children: [
              for (final metric in [
                (
                  'Giá trị đơn demo',
                  money(orders.fold(0, (s, o) => s + o.total)),
                  Icons.payments_outlined,
                ),
                (
                  'Đơn hàng trong phiên',
                  '${orders.length}',
                  Icons.receipt_long_outlined,
                ),
                (
                  'Sản phẩm trong catalog',
                  '${catalog.value?.total ?? 0}',
                  Icons.checkroom_outlined,
                ),
                (
                  'Sự kiện AI demo',
                  '${activity.length}',
                  Icons.auto_awesome_outlined,
                ),
              ])
                Container(
                  width: c.maxWidth < 600
                      ? c.maxWidth
                      : c.maxWidth < 1100
                      ? (c.maxWidth - 20) / 2
                      : (c.maxWidth - 60) / 4,
                  padding: const EdgeInsets.all(24),
                  color: T.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(metric.$3, color: T.accent, size: 22),
                      const SizedBox(height: 20),
                      Text(metric.$1, style: T.small),
                      const SizedBox(height: 12),
                      Text(metric.$2, style: T.display(26)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Material(
          color: T.surface,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nhịp mua sắm trong phiên', style: T.display(25)),
                const SizedBox(height: 12),
                const Text(
                  'Giá trị từng đơn mô phỏng; không phải doanh thu đã thu tiền.',
                  style: T.small,
                ),
                const SizedBox(height: 28),
                if (orders.isEmpty)
                  const StatePanel(
                    title: 'Cửa hàng sẵn sàng đón đơn đầu tiên',
                    message:
                        'Tạo một đơn từ storefront để xem dữ liệu thay đổi tại đây.',
                    icon: Icons.bar_chart_outlined,
                  )
                else ...[
                  for (final order in orders.take(7))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(order.id, style: T.small),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (_, c) => Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width:
                                      c.maxWidth *
                                      order.total /
                                      orders
                                          .map((o) => o.total)
                                          .reduce((a, b) => a > b ? a : b),
                                  height: 24,
                                  color: T.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(money(order.total), style: T.small),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    AppButton(
                      'Quản lý sản phẩm',
                      onPressed: () => context.go('/admin/products'),
                    ),
                    AppButton(
                      'Xem cửa hàng',
                      outlined: true,
                      onPressed: () => context.go('/'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text('Thay đổi gần đây', style: T.display(26)),
        const SizedBox(height: 16),
        if (ref.watch(adminStateProvider).audit.isEmpty)
          const Text('Chưa có thay đổi trong phiên.', style: T.small)
        else
          for (final row in ref.watch(adminStateProvider).audit.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 20),
              title: Text(row, style: T.body),
            ),
      ],
    );
  }
}

class AdminOrdersPage extends ConsumerStatefulWidget {
  const AdminOrdersPage({super.key, this.id});
  final String? id;
  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  String query = '', status = '';
  bool ascending = false;
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(commerceProvider);
    final orders =
        store.orders
            .where(
              (o) =>
                  (widget.id == null || o.id == widget.id) &&
                  (query.isEmpty ||
                      '${o.id} ${o.draft.name}'.toLowerCase().contains(
                        query.toLowerCase(),
                      )) &&
                  (status.isEmpty || o.status == status),
            )
            .toList()
          ..sort(
            (a, b) => ascending
                ? a.total.compareTo(b.total)
                : b.createdAt.compareTo(a.createdAt),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Đơn hàng demo', style: T.display(34)),
        const SizedBox(height: 20),
        const DemoNotice(
          text:
              'Không xử lý thanh toán, hoàn tiền hoặc vận đơn thật. Trạng thái chỉ để trình diễn.',
        ),
        const SizedBox(height: 24),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Tìm mã đơn hoặc tên người nhận',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 250,
              child: DropdownButton<String>(
                isExpanded: true,
                value: status,
                items:
                    [
                          '',
                          'Chờ xác nhận',
                          'Đã xác nhận',
                          'Đang đóng gói',
                          'Đang giao',
                          'Đã giao',
                          'Đã hủy',
                        ]
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(v.isEmpty ? 'Tất cả trạng thái' : v),
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() => status = v!),
              ),
            ),
            FilterChip(
              label: const Text('Giá trị tăng dần'),
              selected: ascending,
              onSelected: (v) => setState(() => ascending = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (orders.isEmpty)
          const StatePanel(
            title: 'Chưa có đơn phù hợp',
            message: 'Tạo đơn checkout demo hoặc bỏ bộ lọc để xem dữ liệu.',
            icon: Icons.receipt_long_outlined,
          ),
        for (final order in orders)
          Material(
            color: T.surface,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      Text(
                        order.id,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(order.draft.name),
                      Text(money(order.total)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${order.draft.address}\n${order.draft.payment} · Chưa thanh toán thật',
                    style: T.small,
                  ),
                  const SizedBox(height: 16),
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '${item.name} / ${item.color} / ${item.size} × ${item.quantity}',
                      ),
                    ),
                  const SizedBox(height: 16),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Trạng thái đơn demo',
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: ValueKey('order-status-${order.id}'),
                        isExpanded: true,
                        value: order.status,
                        items:
                            [
                                  'Chờ xác nhận',
                                  'Đã xác nhận',
                                  'Đang đóng gói',
                                  'Đang giao',
                                  'Đã giao',
                                  'Đã hủy',
                                ]
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) async {
                          if (v == 'Đã hủy') {
                            final confirmed = await confirmAction(
                              context,
                              'Hủy đơn mô phỏng?',
                              'Đơn chuyển sang trạng thái đã hủy. Không thực hiện hoàn tiền thật.',
                            );
                            if (!mounted || !confirmed) return;
                          }
                          await store.setStatus(order.id, v!);
                          if (!mounted) return;
                          ref
                              .read(adminStateProvider)
                              .log('Đơn ${order.id}: $v');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class AdminCustomersPage extends ConsumerWidget {
  const AdminCustomersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(commerceProvider).orders;
    final emails = orders.map((o) => o.draft.email).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Khách hàng trong phiên', style: T.display(34)),
        const SizedBox(height: 24),
        const DemoNotice(
          text:
              'Chỉ tổng hợp thông tin đã nhập trong các đơn demo của tab này.',
        ),
        const SizedBox(height: 24),
        if (emails.isEmpty)
          const StatePanel(
            title: 'Chưa có khách hàng demo',
            message: 'Dữ liệu xuất hiện sau khi tạo đơn hàng.',
            icon: Icons.people_outline,
          ),
        for (final email in emails)
          Card(
            elevation: 0,
            color: T.surface,
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(
                orders.firstWhere((o) => o.draft.email == email).draft.name,
              ),
              subtitle: Text(email),
              trailing: Text(
                '${orders.where((o) => o.draft.email == email).length} đơn',
              ),
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(email),
                  content: Text(
                    orders
                        .where((o) => o.draft.email == email)
                        .map((o) => '${o.id}: ${money(o.total)} — ${o.status}')
                        .join('\n'),
                  ),
                  actions: [
                    AppButton('Đóng', onPressed: () => Navigator.pop(c)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AdminPromotionsPage extends ConsumerWidget {
  const AdminPromotionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminStateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Khuyến mãi', style: T.display(34)),
        const SizedBox(height: 20),
        const DemoNotice(
          text:
              'Quản lý cấu hình voucher demo. Chưa áp dụng giảm giá ở checkout; không công bố ưu đãi thật.',
        ),
        const SizedBox(height: 24),
        AppButton('Tạo mã khuyến mãi', onPressed: () => edit(context, ref)),
        const SizedBox(height: 24),
        for (final p in state.promotions)
          Material(
            color: T.surface,
            child: ListTile(
              title: Text('${p.code} · ${p.discount}%'),
              subtitle: Text(p.enabled ? 'Đã bật cấu hình demo' : 'Đang tắt'),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Sửa ${p.code}',
                    onPressed: () => edit(context, ref, p),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Xóa ${p.code}',
                    onPressed: () async {
                      if (await confirmAction(
                        context,
                        'Xóa mã demo?',
                        'Mã sẽ được xóa khỏi cấu hình phiên này.',
                      )) {
                        state.deletePromotion(p.code);
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> edit(BuildContext context, WidgetRef ref, [Promotion? p]) async {
    final form = GlobalKey<FormState>();
    final code = TextEditingController(text: p?.code ?? ''),
        discount = TextEditingController(text: '${p?.discount ?? 10}');
    bool enabled = p?.enabled ?? false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Cấu hình mã demo'),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppField(
                  label: 'Mã khuyến mãi',
                  controller: code,
                  validator: (v) =>
                      RegExp(r'^[A-Z0-9]{3,20}$').hasMatch(v ?? '')
                      ? null
                      : 'Dùng 3–20 chữ hoa hoặc số.',
                ),
                const SizedBox(height: 16),
                AppField(
                  label: 'Giảm giá (%)',
                  controller: discount,
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (int.tryParse(v ?? '') ?? 0) > 0 &&
                          (int.tryParse(v ?? '') ?? 101) <= 100
                      ? null
                      : 'Nhập số 1–100.',
                ),
                SwitchListTile(
                  value: enabled,
                  onChanged: (v) => set(() => enabled = v),
                  title: const Text('Bật cấu hình demo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Hủy'),
            ),
            AppButton(
              'Lưu mã',
              onPressed: () {
                if (form.currentState!.validate()) {
                  if (p != null && p.code != code.text) {
                    ref.read(adminStateProvider).deletePromotion(p.code);
                  }
                  ref
                      .read(adminStateProvider)
                      .promotion(
                        Promotion(code.text, int.parse(discount.text), enabled),
                      );
                  Navigator.pop(c);
                }
              },
            ),
          ],
        ),
      ),
    );
    code.dispose();
    discount.dispose();
  }
}

class AdminContentPage extends ConsumerStatefulWidget {
  const AdminContentPage({super.key});
  @override
  ConsumerState<AdminContentPage> createState() => _AdminContentPageState();
}

class _AdminContentPageState extends ConsumerState<AdminContentPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController banner, policy;
  @override
  void initState() {
    super.initState();
    final data = ref.read(adminStateProvider);
    banner = TextEditingController(text: data.banner);
    policy = TextEditingController(text: data.policy);
  }

  @override
  void dispose() {
    banner.dispose();
    policy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Nội dung cửa hàng', style: T.display(34)),
        const SizedBox(height: 24),
        const DemoNotice(
          text:
              'Bản nháp nội dung trong phiên demo. Chưa xuất bản lên storefront.',
        ),
        const SizedBox(height: 24),
        AppField(
          label: 'Tiêu đề campaign',
          controller: banner,
          validator: requiredValue,
        ),
        const SizedBox(height: 20),
        AppField(
          label: 'Nội dung chính sách',
          controller: policy,
          maxLines: 5,
          validator: requiredValue,
        ),
        const SizedBox(height: 24),
        AppButton(
          'Lưu bản nháp',
          onPressed: () {
            if (form.currentState!.validate()) {
              ref.read(adminStateProvider).content(banner.text, policy.text);
              toast(context, 'Đã lưu bản nháp trong phiên.');
            }
          },
        ),
        const SizedBox(height: 32),
        Text('Bản nháp đã lưu', style: T.display(26)),
        const SizedBox(height: 16),
        Text(ref.watch(adminStateProvider).banner, style: T.display(30)),
        const SizedBox(height: 16),
        Text(ref.watch(adminStateProvider).policy),
      ],
    ),
  );
}

class AdminMonitoringPage extends ConsumerWidget {
  const AdminMonitoringPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(activityProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Theo dõi trải nghiệm AI', style: T.display(34)),
        const SizedBox(height: 24),
        const DemoNotice(
          text:
              'Nhật ký trạng thái demo trong phiên. Không lưu prompt, ảnh hoặc dữ liệu cá nhân. Nhà cung cấp: chưa kết nối. Chi phí thực tế: không phát sinh.',
        ),
        const SizedBox(height: 24),
        if (entries.isEmpty)
          StatePanel(
            title: 'Chưa có hoạt động AI',
            message: 'Thử một gợi ý phối đồ để thấy trạng thái tại đây.',
            icon: Icons.auto_awesome_outlined,
            action: AppButton(
              'Mở AI Stylist',
              onPressed: () => context.go('/ai-stylist'),
            ),
          ),
        for (final e in entries)
          Material(
            color: T.surface,
            child: ListTile(
              leading: const Icon(Icons.timeline),
              title: Text(e.feature),
              subtitle: Text(e.status),
              trailing: Text(
                '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}',
                style: T.small,
              ),
            ),
          ),
      ],
    );
  }
}

class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(catalogRevisionProvider);
    final repo = ref.watch(productRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cài đặt phiên demo', style: T.display(34)),
        const SizedBox(height: 24),
        const DemoNotice(
          text:
              'Trang quản trị không có bảo mật production. Khi nối API, quyền admin phải được xác minh bởi backend.',
        ),
        const SizedBox(height: 24),
        if (repo is MockProductRepository)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: repo.offline,
            title: const Text('Mô phỏng mất kết nối catalog'),
            subtitle: const Text(
              'Dùng để kiểm tra loading, error và retry. Có thể tắt lại tại đây.',
            ),
            onChanged: (v) {
              repo.offline = v;
              ref.read(catalogRevisionProvider.notifier).refresh();
            },
          ),
        const SizedBox(height: 24),
        AppButton(
          'Đặt lại toàn bộ dữ liệu demo',
          outlined: true,
          onPressed: () async {
            if (await confirmAction(
              context,
              'Đặt lại phiên demo?',
              'Giỏ hàng, đơn hàng, yêu thích, catalog chỉnh sửa và hồ sơ trong tab sẽ được xóa.',
            )) {
              ref.invalidate(productRepositoryProvider);
              ref.invalidate(cartRepositoryProvider);
              ref.invalidate(orderRepositoryProvider);
              ref.invalidate(commerceProvider);
              ref.invalidate(accountProvider);
              ref.invalidate(accountRepositoryProvider);
              ref.invalidate(wishlistProvider);
              ref.invalidate(adminStateProvider);
              ref.invalidate(activityProvider);
              ref.invalidate(tryOnResultsProvider);
              ref.read(catalogRevisionProvider.notifier).refresh();
              if (context.mounted) {
                toast(context, 'Đã khôi phục dữ liệu ban đầu.');
              }
            }
          },
        ),
        const SizedBox(height: 32),
        AppButton(
          'Mở thư viện component',
          onPressed: () => context.go('/design-system'),
        ),
      ],
    );
  }
}
