import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../app/auth_routes.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/primitives.dart';

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});
  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false, obscure = true;
  String? error;

  void enter() => context.go(
    loginDestination(
      GoRouterState.of(context).uri.queryParameters['next'],
      admin: true,
    ),
  );

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(adminAccountProvider.notifier)
          .signIn('', email.text.trim(), password.text);
      if (mounted) {
        password.clear();
        enter();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              e is ApiException && (e.status == 403 || e.code == 'FORBIDDEN')
              ? 'Tài khoản này chưa có quyền quản trị. Vui lòng dùng tài khoản được cửa hàng cấp quyền.'
              : '$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOut() async {
    try {
      await ref.read(adminAccountProvider.notifier).signOut();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Đã thoát trên thiết bị này. Không thể xác nhận đăng xuất với máy chủ.',
        );
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteApiProvider);
    final account = remote ? ref.watch(adminAccountProvider) : null;
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Đăng nhập quản trị', style: T.display(wide ? 38 : 32)),
          ),
          const SizedBox(height: 16),
          Text(
            remote
                ? 'Sử dụng tài khoản đã được cấp quyền quản trị.'
                : 'Không gian thử nghiệm với dữ liệu minh họa. Không sử dụng tài khoản thật.',
            style: T.body.copyWith(color: T.muted),
          ),
          const SizedBox(height: 32),
          if (!remote)
            AppButton('Mở quản trị demo', onPressed: () => context.go('/admin'))
          else if (account != null) ...[
            Text('Bạn đang đăng nhập với ${account.email}.', style: T.body),
            const SizedBox(height: 24),
            AppButton('Vào trang quản trị', onPressed: enter),
            TextButton(
              onPressed: signOut,
              child: const Text('Đăng xuất quản trị'),
            ),
          ] else
            AutofillGroup(
              child: Form(
                key: form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: email,
                      validator: emailValidator,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: password,
                      obscureText: obscure,
                      enabled: !busy,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => submit(),
                      validator: (v) =>
                          (v?.length ?? 0) >= 12 && (v?.length ?? 0) <= 128
                          ? null
                          : 'Mật khẩu cần từ 12 đến 128 ký tự.',
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        suffixIcon: IconButton(
                          tooltip: obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                          onPressed: busy
                              ? null
                              : () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        'Đăng nhập quản trị',
                        busy: busy,
                        onPressed: submit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(error!, style: T.body.copyWith(color: T.danger)),
              ),
            ),
          const SizedBox(height: 28),
          const Text(
            'Chưa có quyền truy cập? Liên hệ người quản lý cửa hàng.',
            style: T.small,
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.west, size: 18),
            label: const Text('Đăng nhập khách hàng'),
          ),
        ],
      ),
    );
    Widget identity() => Container(
      color: T.accent,
      padding: EdgeInsets.all(wide ? 48 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'wearly Studio',
            style: T.display(wide ? 34 : 28).copyWith(color: T.surface),
          ),
          if (wide) ...[
            const Spacer(),
            Text(
              'Không gian\nquản trị.',
              style: T.display(64).copyWith(color: T.surface),
            ),
            const SizedBox(height: 24),
            Text(
              'Chăm chút sản phẩm.\nTheo sát từng đơn hàng.',
              style: T.body.copyWith(color: T.soft, fontSize: 16),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => context.go('/'),
              style: TextButton.styleFrom(foregroundColor: T.surface),
              icon: const Icon(Icons.west, size: 18),
              label: const Text('Về cửa hàng'),
            ),
          ],
        ],
      ),
    );
    return Scaffold(
      backgroundColor: T.surface,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width * .38,
                    child: LayoutBuilder(
                      builder: (_, constraints) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(child: identity()),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (_, constraints) => SingleChildScrollView(
                        padding: const EdgeInsets.all(48),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: (constraints.maxHeight - 96).clamp(
                              0,
                              double.infinity,
                            ),
                          ),
                          child: Center(child: content),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 36,
                      ),
                      child: Center(child: content),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
