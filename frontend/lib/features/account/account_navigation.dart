import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/account_details.dart';
import '../../app/api_providers.dart';
import '../../core/network/api_client.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';

class AccountNavigation extends StatelessWidget {
  const AccountNavigation({super.key, required this.current});
  final String current;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final item in const [
        ('Hồ sơ', '/account'),
        ('Đơn hàng', '/account/orders'),
        ('Sổ địa chỉ', '/account/addresses'),
        ('Phong cách của tôi', '/account/style'),
        ('Lịch sử thử đồ', '/account/try-ons'),
        ('Yêu thích', '/wishlist'),
      ])
        Semantics(
          selected: current == item.$2,
          child: TextButton(
            style: TextButton.styleFrom(
              backgroundColor: current == item.$2 ? T.soft : Colors.transparent,
              foregroundColor: current == item.$2 ? T.accent : T.ink,
              shape: const RoundedRectangleBorder(borderRadius: T.radius),
            ),
            onPressed: () => context.go(item.$2),
            child: Text(item.$1),
          ),
        ),
    ],
  );
}

class AccountFrame extends StatelessWidget {
  const AccountFrame({
    super.key,
    required this.title,
    required this.current,
    required this.child,
  });
  final String title, current;
  final Widget child;
  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: T.display(MediaQuery.sizeOf(context).width < 600 ? 32 : 40),
        ),
        const SizedBox(height: 24),
        AccountNavigation(current: current),
        const SizedBox(height: 32),
        child,
        const SizedBox(height: 40),
      ],
    ),
  );
}

class AccountDataView extends ConsumerWidget {
  const AccountDataView({super.key, required this.builder});
  final Widget Function(AccountDetails) builder;
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
          data: builder,
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Đang mở hồ sơ của bạn…'),
          ),
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
