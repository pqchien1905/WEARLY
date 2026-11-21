import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/config.dart';
import '../../app/api_providers.dart';
import '../../app/account_state.dart';
import '../../core/design/tokens.dart';
import '../../core/design/motion.dart';
import '../../core/widgets/store_shell.dart';
import '../../core/widgets/change_password_dialog.dart';
import '../../domain/staff_permissions.dart';

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
const taxonomyNav = [
  ('Danh mục', '/admin/categories', Icons.category_outlined),
  ('Thương hiệu', '/admin/brands', Icons.label_outline),
  ('Bộ sưu tập', '/admin/collections', Icons.collections_bookmark_outlined),
];
const _groups = [
  (
    'Cửa hàng',
    [
      ('Tổng quan', '/admin', Icons.space_dashboard_outlined),
      ('Đơn hàng', '/admin/orders', Icons.receipt_long_outlined),
      ('Khách hàng', '/admin/customers', Icons.people_outline),
    ],
  ),
  (
    'Sản phẩm & nội dung',
    [
      ('Sản phẩm', '/admin/products', Icons.checkroom_outlined),
      ('Biến thể & kho', '/admin/inventory', Icons.inventory_2_outlined),
      ...taxonomyNav,
      ('Khuyến mãi', '/admin/promotions', Icons.local_offer_outlined),
      ('Nội dung', '/admin/content', Icons.edit_note_outlined),
      ('Đánh giá', '/admin/reviews', Icons.rate_review_outlined),
      ('Bản tin', '/admin/newsletter', Icons.campaign_outlined),
    ],
  ),
  (
    'Vận hành',
    [
      ('Hỗ trợ khách hàng', '/admin/support', Icons.support_agent_outlined),
      ('Theo dõi thư', '/admin/mail', Icons.mail_outline),
      ('Vận hành & AI', '/admin/ai-monitoring', Icons.monitor_heart_outlined),
      ('Nhân sự & quyền', '/admin/staff', Icons.manage_accounts_outlined),
    ],
  ),
];

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  bool signingOut = false;
  Future<void> signOut() async {
    if (signingOut) return;
    setState(() => signingOut = true);
    try {
      await ref.read(adminAccountProvider.notifier).signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Máy chủ chưa xác nhận đăng xuất. Kiểm tra kết nối và thử lại.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => signingOut = false);
    }
  }

  Future<void> changePassword() async {
    final changed = await showChangePasswordDialog(
      context,
      submit: ref.read(adminAccountProvider.notifier).changePassword,
    );
    if (changed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteApiProvider);
    final account = ref.watch(adminAccountProvider);
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final path = GoRouterState.of(context).uri.path;
    final allItems = _groups.expand((g) => g.$2);
    final matches = allItems.where(
      (item) =>
          path == item.$2 ||
          item.$2 != '/admin' && path.startsWith('${item.$2}/'),
    );
    final current =
        matches.isEmpty || (remote && !canVisitAdmin(account?.role, path))
        ? 'Quản trị'
        : matches.last.$1;
    final roleName = remote
        ? staffRoleNames[account?.role] ?? 'Nhân viên'
        : 'Phiên demo';
    Widget navigation({bool drawer = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 4),
          child: BrandMark(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Text('Không gian quản trị', style: T.small),
        ),
        const Divider(height: 1, color: T.line),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              for (final group
                  in remote ? _groups : [('Quản trị demo', adminNav)])
                if (group.$2.any(
                  (item) => !remote || canVisitAdmin(account?.role, item.$2),
                )) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
                    child: Text(
                      group.$1,
                      style: T.small.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final item in group.$2.where(
                    (item) => !remote || canVisitAdmin(account?.role, item.$2),
                  ))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      child: Builder(
                        builder: (context) {
                          final selected =
                              path == item.$2 ||
                              item.$2 != '/admin' &&
                                  path.startsWith('${item.$2}/');
                          return ListTile(
                            minTileHeight: 48,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            horizontalTitleGap: 12,
                            selected: selected,
                            selectedTileColor: T.soft,
                            selectedColor: T.accent,
                            iconColor: T.muted,
                            shape: const RoundedRectangleBorder(
                              borderRadius: T.radius,
                            ),
                            leading: AnimatedContainer(
                              duration: Motion.duration(context, Motion.fast),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: selected ? T.accent : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                item.$3,
                                size: 19,
                                color: selected ? T.surface : T.muted,
                              ),
                            ),
                            title: Text(
                              item.$1,
                              style: T.body.copyWith(
                                color: selected ? T.accent : T.ink,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                fontSize: 13,
                              ),
                            ),
                            onTap: () {
                              if (drawer) Navigator.pop(context);
                              context.go(item.$2);
                            },
                          );
                        },
                      ),
                    ),
                ],
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: T.canvas,
      drawer: Drawer(child: SafeArea(child: navigation(drawer: true))),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 248,
                decoration: const BoxDecoration(
                  color: T.surface,
                  border: Border(right: BorderSide(color: T.line)),
                ),
                child: Material(color: T.surface, child: navigation()),
              ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 12,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      color: T.surface,
                      border: Border(bottom: BorderSide(color: T.line)),
                    ),
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
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            children: [
                              if (wide) ...[
                                Text(
                                  '${BrandConfig.displayName} Studio',
                                  style: T.small,
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: T.muted,
                                ),
                              ],
                              Text(
                                current,
                                style: T.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!wide && account == null)
                          IconButton(
                            tooltip: 'Xem cửa hàng',
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.storefront_outlined),
                          ),
                        if (wide)
                          TextButton.icon(
                            onPressed: () => context.go('/'),
                            style: TextButton.styleFrom(
                              foregroundColor: T.muted,
                              textStyle: T.small.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            icon: const Icon(
                              Icons.storefront_outlined,
                              size: 18,
                            ),
                            label: const Text('Xem cửa hàng'),
                          ),
                        if (account != null) ...[
                          if (wide)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: SizedBox(
                                height: 24,
                                child: VerticalDivider(width: 1, color: T.line),
                              ),
                            )
                          else
                            const SizedBox(width: 8),
                          _AccountMenu(
                            name: account.name,
                            roleName: roleName,
                            compact: !wide,
                            signingOut: signingOut,
                            onChangePassword: remote ? changePassword : null,
                            onSignOut: remote ? signOut : null,
                          ),
                        ] else if (!remote && wide) ...[
                          const SizedBox(width: 8),
                          Text(roleName, style: T.small),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-aligned account controls shared by desktop and mobile admin pages.
class _AccountMenu extends StatefulWidget {
  const _AccountMenu({
    required this.name,
    required this.roleName,
    required this.compact,
    required this.signingOut,
    this.onChangePassword,
    this.onSignOut,
  });
  final String name, roleName;
  final bool compact, signingOut;
  final VoidCallback? onChangePassword, onSignOut;

  @override
  State<_AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<_AccountMenu> {
  final triggerFocus = FocusNode(debugLabel: 'Admin account menu');
  final firstItemFocus = FocusNode(debugLabel: 'Admin account first action');
  bool open = false;

  @override
  void dispose() {
    triggerFocus.dispose();
    firstItemFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = widget.name.trim();
    final name = trimmed.isEmpty ? 'Tài khoản' : trimmed;
    final roleName = widget.roleName;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final menuWidth = math.min(
      280.0 * math.max(1.0, textScale),
      MediaQuery.sizeOf(context).width - 32,
    );
    final initial = trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    Widget avatar(double radius) => CircleAvatar(
      radius: radius,
      backgroundColor: T.soft,
      child: Text(
        initial,
        style: TextStyle(
          color: T.accent,
          fontSize: radius * .85,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final itemStyle = MenuItemButton.styleFrom(
      minimumSize: Size(menuWidth - 16, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      foregroundColor: T.ink,
      iconColor: T.muted,
      textStyle: T.body.copyWith(fontSize: 13, height: 1.5),
      shape: const RoundedRectangleBorder(borderRadius: T.radius),
      visualDensity: VisualDensity.standard,
    );
    return MenuAnchor(
      childFocusNode: triggerFocus,
      consumeOutsideTap: true,
      alignmentOffset: Offset(-menuWidth, 8),
      onOpen: () {
        setState(() => open = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && open) firstItemFocus.requestFocus();
        });
      },
      onClose: () {
        if (mounted) setState(() => open = false);
      },
      style: const MenuStyle(
        alignment: Alignment.bottomRight,
        backgroundColor: WidgetStatePropertyAll(T.surface),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(Color(0x24000000)),
        padding: WidgetStatePropertyAll(EdgeInsets.all(8)),
        side: WidgetStatePropertyAll(BorderSide(color: T.line)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(
          width: menuWidth - 16,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                avatar(20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        softWrap: true,
                        style: T.body.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(roleName, style: T.small),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 16, color: T.line),
        if (widget.onChangePassword != null)
          MenuItemButton(
            focusNode: firstItemFocus,
            style: itemStyle,
            leadingIcon: const Icon(Icons.lock_outline, size: 18),
            onPressed: widget.onChangePassword,
            child: const Text('Đổi mật khẩu'),
          ),
        MenuItemButton(
          focusNode: widget.onChangePassword == null ? firstItemFocus : null,
          style: itemStyle,
          leadingIcon: const Icon(Icons.storefront_outlined, size: 18),
          trailingIcon: const Icon(Icons.arrow_outward, size: 16),
          onPressed: () => context.go('/'),
          child: const Text('Về cửa hàng'),
        ),
        if (widget.onSignOut != null) ...[
          const Divider(height: 16, color: T.line),
          MenuItemButton(
            style: itemStyle.copyWith(
              foregroundColor: const WidgetStatePropertyAll(T.danger),
              iconColor: const WidgetStatePropertyAll(T.danger),
            ),
            leadingIcon: const Icon(Icons.logout, size: 18),
            onPressed: widget.signingOut ? null : widget.onSignOut,
            child: const Text('Đăng xuất'),
          ),
        ],
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        return Semantics(
          container: true,
          button: true,
          expanded: open,
          label: 'Tài khoản quản trị',
          enabled: !widget.signingOut,
          onTap: widget.signingOut ? null : toggle,
          excludeSemantics: true,
          child: Tooltip(
            message: open ? '' : 'Tài khoản quản trị',
            child: TextButton(
              focusNode: triggerFocus,
              onPressed: widget.signingOut ? null : toggle,
              style:
                  TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.padded,
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 8 : 12,
                      vertical: 8,
                    ),
                    backgroundColor: open ? T.soft : T.canvas,
                    foregroundColor: T.ink,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith((states) {
                      final focused = states.contains(WidgetState.focused);
                      return BorderSide(
                        color: focused || open ? T.accent : T.line,
                        width: focused ? 2 : 1,
                      );
                    }),
                  ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.signingOut)
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    avatar(16),
                  if (!widget.compact) ...[
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.body.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          Text(
                            roleName,
                            style: T.small.copyWith(fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: T.muted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
