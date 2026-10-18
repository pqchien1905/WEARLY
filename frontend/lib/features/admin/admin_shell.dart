import '../../app/config.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/store_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/api_providers.dart';
import '../../app/account_state.dart';

const adminNav = [
  ('Tổng quan', '/admin', Icons.space_dashboard_outlined),
  ('Sản phẩm', '/admin/products', Icons.checkroom_outlined),
  ('Biến thể & kho', '/admin/inventory', Icons.inventory_2_outlined),
  ('Đơn hàng', '/admin/orders', Icons.receipt_long_outlined),
  ('Khách hàng', '/admin/customers', Icons.people_outline),
  ('Khuyến mãi', '/admin/promotions', Icons.local_offer_outlined),
  ('Nội dung', '/admin/content', Icons.edit_note_outlined),
  ('Theo dõi AI', '/admin/ai-monitoring', Icons.auto_awesome_outlined),
  ('Cài đặt demo', '/admin/settings', Icons.tune),
];

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteApiProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final path = GoRouterState.of(context).uri.path;
    Widget navigation({bool drawer = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 32, 24, 8),
          child: BrandMark(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 0, 24, 32),
          child: Text('Không gian quản trị', style: T.small),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final item in remote ? adminNav.take(5) : adminNav)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: ListTile(
                    selected:
                        path == item.$2 ||
                        item.$2 != '/admin' && path.startsWith(item.$2),
                    selectedTileColor: T.soft,
                    selectedColor: T.accent,
                    shape: const RoundedRectangleBorder(borderRadius: T.radius),
                    leading: Icon(item.$3, size: 20),
                    title: Text(item.$1, style: T.body),
                    onTap: () {
                      if (drawer) {
                        Navigator.pop(context);
                      }
                      context.go(item.$2);
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.west, size: 18),
            label: const Text('Về cửa hàng'),
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: T.canvas,
      drawer: Drawer(child: SafeArea(child: navigation(drawer: true))),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 240,
              child: Material(color: T.surface, child: navigation()),
            ),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 32 : 16,
                    vertical: 16,
                  ),
                  color: T.surface,
                  child: Row(
                    children: [
                      if (!wide)
                        Builder(
                          builder: (c) => IconButton(
                            tooltip: 'Mở menu quản trị',
                            onPressed: () => Scaffold.of(c).openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          '${BrandConfig.displayName} Studio',
                          style: T.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: const BoxDecoration(
                          color: T.soft,
                          borderRadius: T.radius,
                        ),
                        child: Text(
                          remote
                              ? 'Trực tuyến'
                              : wide
                              ? 'Phiên quản trị demo'
                              : 'Demo',
                          style: T.small.copyWith(color: T.accent),
                        ),
                      ),
                      if (wide) const SizedBox(width: 16),
                      if (remote && ref.watch(adminAccountProvider) != null)
                        IconButton(
                          tooltip: 'Đăng xuất quản trị',
                          icon: const Icon(Icons.logout),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await ref
                                  .read(adminAccountProvider.notifier)
                                  .signOut();
                            } catch (_) {
                              if (messenger.mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Đã thoát trên thiết bị này. Không thể xác nhận đăng xuất với máy chủ.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      if (wide)
                        const CircleAvatar(
                          radius: 17,
                          backgroundColor: T.canvas,
                          child: Icon(Icons.person_outline, size: 20),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
