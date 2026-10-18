import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/primitives.dart';
import 'account_state.dart';
import 'api_providers.dart';

class RemoteRouteGate extends ConsumerWidget {
  const RemoteRouteGate({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(remoteApiProvider)) return child;
    if ([
      '/admin',
      '/ai-stylist',
      '/virtual-try-on',
      '/wishlist',
      '/account/style',
      '/account/try-ons',
      '/forgot-password',
    ].any((prefix) => path == prefix || path.startsWith('$prefix/'))) {
      return StatePanel(
        title: 'Tính năng chưa được kết nối',
        message:
            'Chức năng này chưa khả dụng trong cửa hàng trực tuyến. Bạn có thể mua sắm, quản lý địa chỉ và theo dõi đơn hàng.',
        action: AppButton('Về cửa hàng', onPressed: () => context.go('/shop')),
      );
    }
    if ((path.startsWith('/account') ||
            path.startsWith('/checkout') ||
            path == '/cart') &&
        ref.watch(accountProvider) == null) {
      return LoginRequired(next: path);
    }
    return child;
  }
}

class LoginRequired extends StatelessWidget {
  const LoginRequired({super.key, required this.next, this.beforeNavigate});
  final String next;
  final VoidCallback? beforeNavigate;
  @override
  Widget build(BuildContext context) => StatePanel(
    title: 'Đăng nhập để tiếp tục',
    message: 'Giỏ hàng, địa chỉ và đơn hàng được lưu theo tài khoản của bạn.',
    icon: Icons.person_outline,
    action: AppButton(
      'Đăng nhập',
      onPressed: () {
        final router = GoRouter.of(context);
        beforeNavigate?.call();
        router.go(
          Uri(path: '/login', queryParameters: {'next': next}).toString(),
        );
      },
    ),
  );
}
