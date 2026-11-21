import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/auth_routes.dart';
import '../../app/commerce_state.dart';
import '../../features/cart/cart_page.dart';
import '../design/store_header_style.dart';
import '../design/tokens.dart';
import 'account_menu.dart';

class StoreUtilityBar extends ConsumerWidget {
  const StoreUtilityBar({
    super.key,
    required this.path,
    required this.horizontalPadding,
  });
  final String path;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    final next = loginDestination(GoRouterState.of(context).uri.toString());
    final links = <(String, Widget)>[
      ('Tìm cửa hàng', const _UtilityLink('Tìm cửa hàng', path: '/contact')),
      ('Trợ giúp', const _UtilityLink('Trợ giúp', path: '/faq')),
      if (account != null)
        (StoreHeaderStyle.greeting(account.name), AccountMenu(path: path))
      else ...[
        (
          'Đăng ký',
          _UtilityLink(
            'Đăng ký',
            path: Uri(
              path: '/register',
              queryParameters: {'next': next},
            ).toString(),
          ),
        ),
        (
          'Đăng nhập',
          _UtilityLink(
            'Đăng nhập',
            path: Uri(
              path: '/login',
              queryParameters: {'next': next},
            ).toString(),
          ),
        ),
      ],
    ];
    return Container(
      color: T.canvas,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 0),
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: StoreHeaderStyle.actionsWidth,
        child: LayoutBuilder(
          builder: (context, constraints) {
            var requiredWidth = (links.length - 1) * _UtilityDivider.extent;
            for (final link in links) {
              final painter = TextPainter(
                text: TextSpan(
                  text: link.$1,
                  style: StoreHeaderStyle.utilityText(context),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final labelWidth = link.$2 is AccountMenu
                  ? math.min(painter.width, StoreHeaderStyle.greetingMaxWidth) +
                        8 +
                        StoreHeaderStyle.iconSize
                  : painter.width;
              requiredWidth += math.max(
                StoreHeaderStyle.controlSize,
                labelWidth + 2 * StoreHeaderStyle.utilityPadding(context),
              );
              painter.dispose();
            }
            if (requiredWidth <= constraints.maxWidth) {
              // Each separator is a peer so free space is equal on both sides.
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var index = 0; index < links.length; index++) ...[
                    if (index > 0) const _UtilityDivider(),
                    links[index].$2,
                  ],
                ],
              );
            }
            // Reflow enlarged text without stretching either side of a divider.
            return Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var index = 0; index < links.length; index++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (index > 0) const _UtilityDivider(),
                      links[index].$2,
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UtilityLink extends StatelessWidget {
  const _UtilityLink(this.label, {required this.path});
  final String label, path;

  @override
  Widget build(BuildContext context) => TextButton(
    style: StoreHeaderStyle.utilityButton(context),
    onPressed: () => context.go(path),
    child: Text(label),
  );
}

class _UtilityDivider extends StatelessWidget {
  const _UtilityDivider();
  static const double extent = 7;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: T.ink,
    ),
  );
}

class StoreHeaderActions extends ConsumerStatefulWidget {
  const StoreHeaderActions({
    super.key,
    required this.openSearch,
    this.compact = false,
  });
  final VoidCallback openSearch;
  final bool compact;

  @override
  ConsumerState<StoreHeaderActions> createState() => _StoreHeaderActionsState();
}

class _StoreHeaderActionsState extends ConsumerState<StoreHeaderActions> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  void search() {
    final value = query.text.trim();
    if (value.isEmpty) {
      widget.openSearch();
      return;
    }
    FocusScope.of(context).unfocus();
    context.go(Uri(path: '/search', queryParameters: {'q': value}).toString());
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(commerceProvider).count;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    const baseHeight = 44.0;
    final fieldHeight = textScale > 1
        ? baseHeight + 20 * (textScale - 1)
        : baseHeight;
    return Row(
      children: [
        if (widget.compact)
          IconButton(
            tooltip: 'Tìm kiếm',
            onPressed: widget.openSearch,
            icon: const Icon(Icons.search, size: StoreHeaderStyle.iconSize),
          ),
        if (!widget.compact)
          Expanded(
            child: Semantics(
              label: 'Tìm kiếm sản phẩm',
              child: SizedBox(
                height: fieldHeight,
                child: TextField(
                  key: const ValueKey('header-search'),
                  controller: query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search(),
                  style: T.body.copyWith(fontSize: 14, height: 1.2),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm',
                    hintStyle: T.body.copyWith(
                      fontSize: 14,
                      height: 1.2,
                      color: T.muted,
                    ),
                    fillColor: T.canvas,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    prefixIcon: IconButton(
                      tooltip: 'Tìm kiếm',
                      onPressed: search,
                      icon: const Icon(
                        Icons.search,
                        size: StoreHeaderStyle.iconSize,
                        color: T.ink,
                      ),
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(32)),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(32)),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(32)),
                      borderSide: BorderSide(color: T.ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!widget.compact) const SizedBox(width: 8),
        IconButton(
          tooltip: 'Yêu thích',
          style: IconButton.styleFrom(
            minimumSize: const Size(
              StoreHeaderStyle.controlSize,
              StoreHeaderStyle.controlSize,
            ),
            visualDensity: VisualDensity.standard,
          ),
          icon: const Icon(
            Icons.favorite_border,
            size: StoreHeaderStyle.iconSize,
          ),
          onPressed: () => context.go('/wishlist'),
        ),
        IconButton(
          tooltip: 'Giỏ hàng',
          style: IconButton.styleFrom(
            minimumSize: const Size(
              StoreHeaderStyle.controlSize,
              StoreHeaderStyle.controlSize,
            ),
            visualDensity: VisualDensity.standard,
          ),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            child: const Icon(
              Icons.shopping_bag_outlined,
              size: StoreHeaderStyle.iconSize,
            ),
          ),
          onPressed: () => showCartDrawer(context),
        ),
      ],
    );
  }
}
