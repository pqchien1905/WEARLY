import '../../app/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../data/mock_account.dart';

import '../../core/design/tokens.dart';

import '../../core/widgets/primitives.dart';

import 'account_navigation.dart';

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
      password = TextEditingController();
  bool obscure = true;
  bool busy = false;
  String? error;

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
          toast(
            context,
            'Đã mô phỏng yêu cầu khôi phục. Không gửi email thật.',
          );
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
          context.go('/account');
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                        : 'Chào bạn trở lại.',
                    style: T.display(40),
                  ),
                  const SizedBox(height: 24),
                  const DemoNotice(
                    text:
                        'Tài khoản mô phỏng. Không xác thực danh tính; không dùng mật khẩu thật. Dữ liệu chỉ trong phiên này.',
                  ),
                  const SizedBox(height: 28),
                  if (register) ...[
                    AppField(
                      label: 'Tên của bạn',
                      controller: name,
                      validator: requiredValue,
                    ),
                    const SizedBox(height: 16),
                  ],
                  AppField(
                    label: 'Email',
                    controller: email,
                    validator: emailValidator,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (!forgot) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: password,
                      obscureText: obscure,
                      validator: (v) => (v?.length ?? 0) >= 8
                          ? null
                          : 'Nhập ít nhất 8 ký tự cho mật khẩu demo.',
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu demo',
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
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      forgot
                          ? 'Gửi hướng dẫn demo'
                          : register
                          ? 'Tạo tài khoản demo'
                          : 'Đăng nhập demo',
                      busy: busy,
                      onPressed: submit,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                        onPressed: () =>
                            context.go(register ? '/login' : '/register'),
                        child: Text(
                          register
                              ? 'Đã có tài khoản? Đăng nhập'
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
              color: T.soft,
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
                    'YOUR EVERYDAY, REIMAGINED.',
                    style: T.small.copyWith(
                      color: T.accent,
                      letterSpacing: 1.4,
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

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});
  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      phone = TextEditingController(),
      address = TextEditingController();
  bool seeded = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(accountProvider);
    if (user == null) {
      return StatePanel(
        title: 'Góc riêng của bạn.',
        message:
            'Mở phiên tài khoản demo để lưu thông tin. Bạn vẫn có thể đặt hàng không cần đăng nhập.',
        icon: Icons.person_outline,
        action: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton('Đăng nhập demo', onPressed: () => context.go('/login')),
            AppButton(
              'Xem đơn trong phiên',
              outlined: true,
              onPressed: () => context.go('/account/orders'),
            ),
          ],
        ),
      );
    }
    if (!seeded) {
      name.text = user.name;
      phone.text = user.phone;
      address.text = user.address;
      seeded = true;
    }
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chào ${user.name}.', style: T.display(40)),
          const SizedBox(height: 24),
          const AccountNavigation(current: '/account'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        await ref.read(accountProvider.notifier).signOut();
                        if (context.mounted) {
                          toast(context, 'Đã kết thúc phiên tài khoản demo.');
                        }
                      },
                child: const Text('Đăng xuất'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: form,
              child: Column(
                children: [
                  const DemoNotice(
                    text:
                        'Hồ sơ chỉ lưu trong bộ nhớ phiên trình duyệt. Không phải tài khoản bảo mật thật.',
                  ),
                  const SizedBox(height: 24),
                  AppField(
                    label: 'Họ và tên',
                    controller: name,
                    validator: requiredValue,
                  ),
                  const SizedBox(height: 16),
                  AppField(
                    label: 'Điện thoại (không bắt buộc)',
                    controller: phone,
                    validator: (v) =>
                        v == null ||
                            v.isEmpty ||
                            RegExp(r'^0\d{9}$').hasMatch(v)
                        ? null
                        : 'Nhập số điện thoại 10 chữ số.',
                  ),
                  const SizedBox(height: 16),
                  AppField(
                    label: 'Địa chỉ (không bắt buộc)',
                    controller: address,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  AppButton(
                    'Lưu hồ sơ demo',
                    busy: busy,
                    onPressed: () async {
                      if (form.currentState!.validate()) {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await ref
                              .read(accountProvider.notifier)
                              .save(
                                UserProfile(
                                  name: name.text.trim(),
                                  email: user.email,
                                  phone: phone.text,
                                  address: address.text,
                                ),
                              );
                          if (context.mounted) {
                            toast(context, 'Đã lưu hồ sơ trong phiên demo.');
                          }
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      }
                    },
                  ),
                  if (error != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: T.danger),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
