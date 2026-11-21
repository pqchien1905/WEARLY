import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/account_details.dart';
import '../../app/api_providers.dart';
import '../../core/network/api_client.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/design/account_tokens.dart';
import 'account_actions.dart';
import 'account_components.dart';

const accountDestinations = [
  ('Hồ sơ', '/account', Icons.person_outline),
  ('Đơn hàng', '/account/orders', Icons.shopping_bag_outlined),
  ('Đánh giá của tôi', '/account/reviews', Icons.star_outline_rounded),
  ('Sổ địa chỉ', '/account/addresses', Icons.location_on_outlined),
  ('Phong cách của tôi', '/account/style', Icons.tune_outlined),
  ('Lịch sử thử đồ', '/account/try-ons', Icons.checkroom_outlined),
  ('Hỗ trợ', '/account/support', Icons.support_agent_outlined),
  ('Yêu thích', '/wishlist', Icons.favorite_border),
  ('Cài đặt tài khoản', '/account/settings', Icons.settings_outlined),
];

String accountLabel(String path) => accountDestinations
    .firstWhere(
      (item) => item.$2 == path,
      orElse: () => accountDestinations.first,
    )
    .$1;

String accountDescription(String path) => switch (path) {
  '/account' => 'Một góc riêng để chăm chút thông tin và phong cách của bạn.',
  '/account/orders' => 'Theo dõi hành trình của những món đồ bạn đã chọn.',
  '/account/reviews' =>
    'Những trải nghiệm của bạn giúp lựa chọn tiếp theo tốt hơn.',
  '/account/addresses' =>
    'Lưu những địa chỉ quen thuộc để mỗi lần đặt hàng thuận tiện hơn.',
  '/account/style' => 'Những lựa chọn nhỏ, tạo nên phong cách rất riêng.',
  '/account/try-ons' =>
    'Xem lại những trang phục bạn đã thử và tìm cảm hứng mới.',
  '/wishlist' => 'Lưu cảm hứng, trở lại khi bạn sẵn sàng.',
  '/account/support' =>
    'Theo dõi câu trả lời của cửa hàng và nhắn thêm khi cần.',
  _ => 'Quản lý thông tin đăng nhập, bảo mật và tùy chọn mua sắm.',
};

class AccountNavigation extends ConsumerWidget {
  const AccountNavigation({
    super.key,
    required this.current,
    this.enabled = true,
  });
  final String current;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in accountDestinations)
        if (!const {'/account/reviews', '/account/support'}.contains(item.$2) ||
            ref.watch(remoteApiProvider))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Semantics(
              selected: current == item.$2,
              child: TextButton(
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  minimumSize: const Size(44, AccountTokens.controlHeight),
                  backgroundColor: current == item.$2
                      ? AccountTokens.selected
                      : Colors.transparent,
                  foregroundColor: current == item.$2
                      ? AccountTokens.selectedText
                      : T.muted,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AccountTokens.radius,
                  ),
                ),
                onPressed: enabled ? () => context.go(item.$2) : null,
                child: Row(
                  children: [
                    Icon(item.$3, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.$1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: current == item.$2
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (current == item.$2)
                      const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ),
    ],
  );
}

class AccountFrame extends ConsumerWidget {
  const AccountFrame({
    super.key,
    required this.title,
    required this.current,
    required this.child,
    this.enabled = true,
  });
  final String title, current;
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(accountProvider);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final navigation = AccountNavigation(current: current, enabled: enabled);
    final sidebar = AccountCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (user != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: T.soft,
                    child: Text(
                      user.name.trim().isEmpty
                          ? 'W'
                          : user.name.trim().characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: T.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: T.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        const Text('Tài khoản Wearly', style: T.small),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
          ],
          navigation,
          if (user != null) ...[
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: AccountSignOutButton(enabled: enabled),
            ),
          ],
        ],
      ),
    );
    final content = ConstrainedBox(
      key: const ValueKey('account-content'),
      constraints: BoxConstraints(
        minHeight: mobile
            ? 0
            : (MediaQuery.sizeOf(context).height - 360)
                  .clamp(600, double.infinity)
                  .toDouble(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            headingLevel: 1,
            child: Text(title, style: AccountTokens.display(mobile ? 28 : 36)),
          ),
          const SizedBox(height: 12),
          Text(
            accountDescription(current),
            style: T.body.copyWith(color: T.muted),
          ),
          const SizedBox(height: 28),
          child,
        ],
      ),
    );
    return ColoredBox(
      color: AccountTokens.background,
      child: PageBody(
        vertical: mobile ? 24 : 32,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Trang chủ', style: T.small),
                ),
                const Icon(Icons.chevron_right, size: 14, color: T.muted),
                TextButton(
                  onPressed: () => context.go('/account'),
                  child: const Text('Tài khoản', style: T.small),
                ),
                const Icon(Icons.chevron_right, size: 14, color: T.muted),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    accountLabel(current),
                    style: T.small.copyWith(color: T.accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (_, c) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                if (c.maxWidth >= 920 * scale) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: AccountTokens.sidebarWidth,
                        child: sidebar,
                      ),
                      const SizedBox(width: AccountTokens.gap),
                      Expanded(child: content),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: T.surface,
                      shape: const RoundedRectangleBorder(
                        side: BorderSide(color: T.line),
                        borderRadius: T.radius,
                      ),
                      child: ExpansionTile(
                        // Expansion and the route scroll offset need separate
                        // PageStorage entries when the responsive tree changes.
                        key: PageStorageKey('account-menu-$current'),
                        leading: const Icon(
                          Icons.menu,
                          size: 20,
                          color: T.accent,
                        ),
                        title: Text(
                          accountLabel(current),
                          style: T.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Menu tài khoản', style: T.small),
                        shape: const RoundedRectangleBorder(
                          borderRadius: T.radius,
                        ),
                        collapsedShape: const RoundedRectangleBorder(
                          borderRadius: T.radius,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        children: [
                          navigation,
                          if (user != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: AccountSignOutButton(enabled: enabled),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    content,
                  ],
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class AccountDataView extends ConsumerWidget {
  const AccountDataView({
    super.key,
    required this.builder,
    this.freshWhileLoading = false,
  });
  final Widget Function(AccountDetails) builder;
  final bool freshWhileLoading;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteApiProvider);
    if (ref.watch(accountProvider) == null) {
      return StatePanel(
        title: 'Mở góc riêng của bạn',
        message: remote
            ? 'Đăng nhập để mở sổ địa chỉ đã lưu trong tài khoản.'
            : 'Đăng nhập demo để dùng sổ địa chỉ và hồ sơ phong cách. Dữ liệu được xóa khi đăng xuất hoặc tải lại trang.',
        icon: Icons.person_outline,
        action: AppButton(
          remote ? 'Đăng nhập' : 'Đăng nhập demo',
          onPressed: () => context.go('/login'),
        ),
      );
    }
    return ref
        .watch(accountDetailsProvider)
        .when(
          skipLoadingOnRefresh: !freshWhileLoading,
          data: builder,
          loading: () => const AccountLoading(label: 'Đang mở hồ sơ của bạn…'),
          error: (error, _) => StatePanel(
            title: 'Chưa mở được hồ sơ',
            message: accountError(error),
            action: AppButton(
              'Thử lại',
              onPressed: () => ref.invalidate(accountDetailsProvider),
            ),
          ),
        );
  }
}

String accountError(Object error) => error is ApiException
    ? error.message
    : error is StateError
    ? error.message.toString()
    : error is ArgumentError
    ? error.message.toString()
    : 'Chưa hoàn tất thay đổi. Hãy thử lại.';
