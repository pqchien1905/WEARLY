import '../../app/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../app/auth_routes.dart';
import '../../data/mock_account.dart';

import '../../core/design/tokens.dart';

import '../../core/widgets/primitives.dart';

export 'account_profile_page.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key, required this.mode});
  final String mode;
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool obscure = true;
  bool busy = false;
  String? error;
  bool recoveryAccepted = false;

  Future<void> submit() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final register = widget.mode == '/register';
    try {
      final account = ref.read(accountProvider.notifier);
      if (widget.mode == '/forgot-password') {
        await account.requestPasswordReset(email.text.trim());
        if (mounted) {
          if (ref.read(remoteApiProvider)) {
            setState(() => recoveryAccepted = true);
          } else {
            toast(
              context,
              'Đã mô phỏng yêu cầu khôi phục. Không gửi email thật.',
            );
          }
        }
      } else {
        await account.signIn(
          register ? name.text.trim() : 'Khách ${BrandConfig.displayName}',
          email.text.trim(),
          password.text,
          register: register,
        );
        if (mounted) {
          password.clear();
          confirm.clear();
          final next = GoRouterState.of(context).uri.queryParameters['next'];
          context.go(loginDestination(next));
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteApiProvider);
    final register = widget.mode == '/register',
        forgot = widget.mode == '/forgot-password';
    return PageBody(
      vertical: 64,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: _AuthFrame(
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    forgot
                        ? 'Tìm lại lối vào.'
                        : register
                        ? 'Tủ đồ mới, của bạn.'
                        : 'Đăng nhập khách hàng',
                    style: T.display(
                      MediaQuery.sizeOf(context).width < 600 ? 32 : 40,
                    ),
                  ),
                  const SizedBox(height: 24),
                  DemoNotice(
                    text: remote
                        ? forgot
                              ? 'Nhập email tài khoản. Nếu tài khoản hợp lệ, bạn sẽ nhận được liên kết dùng một lần, có hiệu lực 15 phút.'
                              : 'Đăng nhập để lưu giỏ hàng, địa chỉ và đơn hàng. Phiên đăng nhập được khôi phục khi bạn tải lại trang.'
                        : 'Tài khoản mô phỏng. Không xác thực danh tính; không dùng mật khẩu thật. Dữ liệu chỉ trong phiên này.',
                  ),
                  const SizedBox(height: 28),
                  if (register) ...[
                    AppField(
                      label: 'Tên của bạn',
                      controller: name,
                      validator: requiredValue,
                      readOnly: busy,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppField(
                    label: 'Email',
                    controller: email,
                    validator: emailValidator,
                    keyboardType: TextInputType.emailAddress,
                    readOnly: busy,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                  ),
                  if (!forgot) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: password,
                      obscureText: obscure,
                      readOnly: busy,
                      autofillHints: [
                        register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: register
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: register ? null : (_) => submit(),
                      validator: (v) =>
                          (v?.length ?? 0) >= 8 && (v?.length ?? 0) <= 128
                          ? null
                          : remote
                          ? 'Mật khẩu cần từ 8 đến 128 ký tự.'
                          : 'Nhập ít nhất 8 ký tự cho mật khẩu demo.',
                      decoration: InputDecoration(
                        labelText: remote ? 'Mật khẩu' : 'Mật khẩu demo',
                        suffixIcon: IconButton(
                          tooltip: obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                          onPressed: () => setState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (register) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('register-confirm'),
                        controller: confirm,
                        obscureText: obscure,
                        readOnly: busy,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        validator: (v) => v == password.text
                            ? null
                            : 'Hai mật khẩu chưa khớp.',
                        decoration: const InputDecoration(
                          labelText: 'Nhập lại mật khẩu',
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      forgot
                          ? remote
                                ? 'Gửi liên kết khôi phục'
                                : 'Gửi hướng dẫn demo'
                          : register
                          ? remote
                                ? 'Tạo tài khoản'
                                : 'Tạo tài khoản demo'
                          : remote
                          ? 'Đăng nhập'
                          : 'Đăng nhập demo',
                      busy: busy,
                      onPressed: recoveryAccepted ? null : submit,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (recoveryAccepted)
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        'Đã tiếp nhận yêu cầu. Nếu email thuộc tài khoản đang hoạt động, hướng dẫn sẽ được gửi đến hộp thư. Hãy kiểm tra cả thư rác.',
                      ),
                    ),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: T.danger),
                        ),
                      ),
                    ),
                  if (ref.read(accountRepositoryProvider)
                      case final MockAccountRepository repo)
                    ExpansionTile(
                      key: const PageStorageKey('account:demo-scenarios'),
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Kịch bản kiểm thử demo',
                        style: T.small,
                      ),
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mô phỏng lỗi tài khoản'),
                          value: repo.offline,
                          onChanged: busy
                              ? null
                              : (v) => setState(() => repo.offline = v),
                        ),
                      ],
                    ),
                  Wrap(
                    spacing: 16,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                final next = GoRouterState.of(
                                  context,
                                ).uri.queryParameters['next'];
                                context.go(
                                  Uri(
                                    path: register ? '/login' : '/register',
                                    queryParameters: next == null
                                        ? null
                                        : {'next': loginDestination(next)},
                                  ).toString(),
                                );
                              },
                        child: Text(
                          register
                              ? 'Đã có tài khoản? Đăng nhập'
                              : remote
                              ? 'Tạo tài khoản'
                              : 'Tạo tài khoản demo',
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/forgot-password'),
                        child: const Text('Quên mật khẩu?'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthFrame extends StatelessWidget {
  const _AuthFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) {
      final form = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: child,
      );
      if (c.maxWidth < 950) return Center(child: form);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: const BoxDecoration(
                color: T.soft,
                borderRadius: T.heroRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phong cách riêng.\nMột nơi để trở về.',
                    style: T.display(44),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Lưu những món đồ bạn thích, xem lại đơn hàng và tìm cảm hứng cho mỗi ngày.',
                    style: T.body.copyWith(color: T.muted),
                  ),
                  const SizedBox(height: 32),
                  const AspectRatio(
                    aspectRatio: 1,
                    child: FashionImage(
                      'assets/images/shirt.jpg',
                      label: 'Cảm hứng tủ đồ Wearly, ảnh minh họa',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cảm hứng mới cho mỗi ngày.',
                    style: T.small.copyWith(
                      color: T.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 64),
          Expanded(
            child: Align(alignment: Alignment.topRight, child: form),
          ),
        ],
      );
    },
  );
}
