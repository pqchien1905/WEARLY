import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../core/widgets/primitives.dart';

const signOutError = 'Chưa đăng xuất được. Kiểm tra kết nối và thử lại.';
typedef SignOutState = ({bool busy, String? error});
final accountSignOutProvider =
    NotifierProvider<AccountSignOutController, SignOutState>(
      AccountSignOutController.new,
    );

class AccountSignOutController extends Notifier<SignOutState> {
  bool get isSignedOut => ref.mounted && ref.read(accountProvider) == null;
  @override
  SignOutState build() {
    ref.listen(accountProvider.select((u) => (u?.id, u?.email)), (
      previous,
      next,
    ) {
      if (state.error != null) state = (busy: state.busy, error: null);
    });
    return (busy: false, error: null);
  }

  // Shared by the settings card, responsive sidebar and header menu.
  Future<bool> signOut() async {
    if (state.busy || ref.read(accountProvider) == null) return false;
    final user = ref.read(accountProvider);
    state = (busy: true, error: null);
    try {
      await ref.read(accountProvider.notifier).signOut();
      return ref.mounted && ref.read(accountProvider) == null;
    } catch (_) {
      if (ref.mounted && identical(ref.read(accountProvider), user)) {
        state = (busy: true, error: signOutError);
      }
      rethrow;
    } finally {
      if (ref.mounted) state = (busy: false, error: state.error);
    }
  }
}

Future<void> signOutCustomer(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  final controller = ref.read(accountSignOutProvider.notifier);
  try {
    final signedOut = await controller.signOut();
    if (!signedOut || !controller.isSignedOut) return;
    if (context.mounted) toast(context, 'Đã đăng xuất.');
    router.go('/login');
  } catch (_) {
    if (context.mounted) {
      toast(context, signOutError);
    }
  }
}

class AccountSignOutButton extends ConsumerWidget {
  const AccountSignOutButton({super.key, this.enabled = true});
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(accountSignOutProvider).busy;
    return TextButton.icon(
      icon: const Icon(Icons.logout, size: 18),
      label: Text(busy ? 'Đang đăng xuất…' : 'Đăng xuất'),
      onPressed: busy || !enabled ? null : () => signOutCustomer(context, ref),
    );
  }
}
