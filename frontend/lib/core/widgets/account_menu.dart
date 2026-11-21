import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../features/account/account_actions.dart';
import '../design/store_header_style.dart';
import '../design/tokens.dart';

class AccountMenu extends ConsumerStatefulWidget {
  const AccountMenu({super.key, required this.path});
  final String path;

  @override
  ConsumerState<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends ConsumerState<AccountMenu> {
  final controller = MenuController();
  final triggerFocus = FocusNode(debugLabel: 'Account menu');
  final firstItemFocus = FocusNode(debugLabel: 'Account profile');
  Timer? closeTimer;
  bool open = false;

  void keepOpen() => closeTimer?.cancel();

  void openMenu() {
    keepOpen();
    controller.open();
  }

  void scheduleClose() {
    closeTimer?.cancel();
    // Leave time to cross the small gap between the trigger and the panel.
    closeTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted) controller.close();
    });
  }

  @override
  void didUpdateWidget(AccountMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.close();
      });
    }
  }

  @override
  void dispose() {
    closeTimer?.cancel();
    triggerFocus.dispose();
    firstItemFocus.dispose();
    super.dispose();
  }

  void navigate(String path) {
    controller.close();
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final signingOut = ref.watch(accountSignOutProvider).busy;
    final signedIn = account != null;
    final greeting = StoreHeaderStyle.greeting(account?.name);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final width = math.min(
      248.0 * math.max(1.0, textScale),
      MediaQuery.sizeOf(context).width - 32,
    );
    final itemHeight = MediaQuery.sizeOf(context).width < 600 ? 44.0 : 40.0;
    final itemStyle = MenuItemButton.styleFrom(
      visualDensity: VisualDensity.standard,
      minimumSize: Size(double.infinity, itemHeight),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      foregroundColor: T.muted,
      textStyle: T.body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
    );
    return MenuAnchor(
      controller: controller,
      childFocusNode: triggerFocus,
      consumeOutsideTap: true,
      alignmentOffset: Offset(-width, 8),
      onOpen: () => setState(() => open = true),
      onClose: () {
        keepOpen();
        if (mounted) setState(() => open = false);
      },
      style: const MenuStyle(
        alignment: Alignment.bottomRight,
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(T.surface),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(Color(0x24000000)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: T.line),
          ),
        ),
      ),
      menuChildren: [
        MouseRegion(
          onEnter: (_) => keepOpen(),
          onExit: (_) => scheduleClose(),
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Tài khoản',
                        style: T.body.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  for (final item in const [
                    ('Hồ sơ', '/account'),
                    ('Đơn đặt hàng', '/account/orders'),
                    ('Yêu thích', '/wishlist'),
                    ('Cài đặt tài khoản', '/account/settings'),
                  ])
                    MenuItemButton(
                      focusNode: item.$2 == '/account' ? firstItemFocus : null,
                      style: itemStyle,
                      onPressed: () => navigate(item.$2),
                      child: Text(item.$1),
                    ),
                  if (signedIn)
                    MenuItemButton(
                      style: itemStyle.copyWith(
                        foregroundColor: const WidgetStatePropertyAll(T.accent),
                      ),
                      onPressed: signingOut
                          ? null
                          : () => signOutCustomer(context, ref),
                      child: Text(signingOut ? 'Đang đăng xuất…' : 'Đăng xuất'),
                    )
                  else ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Divider(height: 12),
                    ),
                    MenuItemButton(
                      style: itemStyle.copyWith(
                        foregroundColor: const WidgetStatePropertyAll(T.accent),
                      ),
                      onPressed: () => navigate('/login'),
                      child: const Text('Đăng nhập'),
                    ),
                    MenuItemButton(
                      style: itemStyle,
                      onPressed: () => navigate('/register'),
                      child: const Text('Tạo tài khoản'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) => openMenu(),
        onExit: (_) => scheduleClose(),
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              openMenu();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) firstItemFocus.requestFocus();
              });
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MergeSemantics(
            child: Semantics(
              label: 'Tài khoản',
              expanded: open,
              child: IconButton(
                key: const ValueKey('account-menu-trigger'),
                focusNode: triggerFocus,
                style: StoreHeaderStyle.utilityButton(context),
                icon: Builder(
                  builder: (context) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (signedIn) ...[
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: StoreHeaderStyle.greetingMaxWidth,
                          ),
                          child: Text(
                            greeting,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: StoreHeaderStyle.utilityText(
                              context,
                            ).copyWith(color: IconTheme.of(context).color),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      const Icon(
                        Icons.person_outline,
                        size: StoreHeaderStyle.iconSize,
                      ),
                    ],
                  ),
                ),
                onPressed: () {
                  keepOpen();
                  controller.isOpen ? controller.close() : controller.open();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
