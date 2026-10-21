import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/primitives.dart';
import 'account_state.dart';
import 'api_providers.dart';
import '../domain/staff_permissions.dart';
import '../features/admin/remote/admin_pages.dart';
import '../features/catalog/remote_wishlist_page.dart';
import '../features/ai_stylist/remote_stylist_page.dart';
import '../features/virtual_tryon/remote_tryon_page.dart';
import '../features/virtual_tryon/remote_tryon_history.dart';

class RemoteRouteGate extends ConsumerWidget {
  const RemoteRouteGate({super.key, required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(remoteApiProvider)) return child;
    if (path == '/admin' || path.startsWith('/admin/')) {
      final account = ref.watch(adminAccountProvider);
      if (!isStaff(account?.role)) return const SizedBox.shrink();
      if (!canVisitAdmin(account?.role, path)) {
        return StatePanel(
          title: 'Bạn chưa có quyền truy cập',
          message: 'Vai trò hiện tại không được mở chức năng này.',
          action: AppButton(
            'Về khu vực làm việc',
            onPressed: () => context.go(staffHome(account?.role)),
          ),
        );
      }
      return RemoteAdminRoute(
        key: ValueKey((account!.id, account.role, path)),
        path: path,
      );
    }
    if (path == '/wishlist') {
      return ref.watch(accountProvider) == null
          ? const LoginRequired(next: '/wishlist')
          : const RemoteWishlistPage();
    }
    if (path == '/ai-stylist') {
      final user = ref.watch(accountProvider);
      return user == null
          ? const LoginRequired(next: '/ai-stylist')
          : RemoteStylistPage(
              key: ValueKey(user.id),
              initialPrompt: GoRouterState.of(
                context,
              ).uri.queryParameters['prompt'],
            );
    }
    if ([
      '/virtual-try-on',
      '/account/try-ons',
    ].any((prefix) => path == prefix || path.startsWith('$prefix/'))) {
      final user = ref.watch(accountProvider);
      final uri = GoRouterState.of(context).uri;
      if (user == null) return LoginRequired(next: uri.toString());
      if (path == '/account/try-ons') {
        return RemoteTryOnHistory(key: ValueKey(user.id));
      }
      return RemoteTryOnPage(
        key: ValueKey((user.id, path)),
        slug: uri.queryParameters['product'],
        jobId: path.startsWith('/virtual-try-on/')
            ? uri.pathSegments.last
            : null,
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
