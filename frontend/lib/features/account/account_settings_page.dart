import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../app/remote_route_gate.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/change_password_dialog.dart';
import 'account_actions.dart';
import 'account_navigation.dart';
import 'account_components.dart';

class AccountSettingsPage extends ConsumerWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(accountProvider);
    if (user == null) return const LoginRequired(next: '/account/settings');
    return _SettingsContent(key: ValueKey((user.id, user.email)));
  }
}

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent({super.key});
  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  bool loading = false;
  String? error, notice;

  Future<void> refresh() async {
    if (loading || ref.read(accountSignOutProvider).busy) return;
    setState(() {
      loading = true;
      error = notice = null;
    });
    try {
      await ref.read(accountProvider.notifier).refreshProfile();
      if (mounted) setState(() => notice = 'Đã cập nhật thông tin tài khoản.');
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'Chưa cập nhật được thông tin. ${accountError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> changePassword(BuildContext context) async {
    final router = GoRouter.of(context);
    final changed = await showChangePasswordDialog(
      context,
      submit: ref.read(accountProvider.notifier).changePassword,
      onForgot: () => router.go('/forgot-password?from=account'),
    );
    if (changed && mounted) {
      setState(
        () => notice =
            'Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất khỏi tài khoản.',
      );
    }
  }

  Future<void> copyEmail() async {
    final email = ref.read(accountProvider)?.email;
    if (email == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: email));
      if (mounted) setState(() => notice = 'Đã sao chép email.');
    } catch (_) {
      if (mounted) {
        setState(
          () => notice =
              'Chưa sao chép được. Bạn có thể chọn email và sao chép thủ công.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(accountProvider);
    if (user == null) return const SizedBox.shrink();
    final remote = ref.watch(remoteApiProvider);
    final signOut = ref.watch(accountSignOutProvider);
    final enabled = !signOut.busy && !loading;
    return AccountFrame(
      title: 'Cài đặt tài khoản',
      current: '/account/settings',
      enabled: !signOut.busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccountToolbar(
            label: 'Thông tin và tùy chọn của bạn',
            actions: [
              if (remote)
                TextButton.icon(
                  onPressed: enabled ? refresh : null,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(loading ? 'Đang tải…' : 'Tải lại thông tin'),
                ),
            ],
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null || notice != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: AccountNotice(
                text: error ?? notice!,
                icon: error == null
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
              ),
            ),
            if (error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: enabled ? refresh : null,
                  child: const Text('Thử lại'),
                ),
              ),
          ],
          const SizedBox(height: 24),
          AccountGrid(
            equalHeight: true,
            minColumnWidth: 420,
            children: [
              _SettingsSection(
                title: 'Thông tin đăng nhập',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsValue(label: 'Email đăng nhập', value: user.email),
                    TextButton.icon(
                      onPressed: signOut.busy ? null : copyEmail,
                      icon: const Icon(Icons.copy_outlined, size: 16),
                      label: const Text('Sao chép email'),
                    ),
                    const SizedBox(height: 12),
                    _SettingsValue(label: 'Họ và tên', value: user.name),
                    const SizedBox(height: 16),
                    _SettingsValue(
                      label: 'Số điện thoại',
                      value: user.phone.isEmpty
                          ? 'Chưa thêm số điện thoại'
                          : user.phone,
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      'Chỉnh sửa hồ sơ',
                      outlined: true,
                      onPressed: enabled ? () => context.go('/account') : null,
                    ),
                  ],
                ),
              ),
              _SettingsSection(
                title: 'Mật khẩu và bảo mật',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remote
                          ? 'Đổi mật khẩu bằng mật khẩu hiện tại. Nếu đã quên, hãy nhận mã xác nhận qua email đăng nhập.'
                          : 'Đổi mật khẩu chỉ khả dụng khi cửa hàng kết nối máy chủ. Tài khoản demo không dùng mật khẩu thật.',
                      style: T.body.copyWith(color: T.muted),
                    ),
                    if (remote) ...[
                      const SizedBox(height: 20),
                      const _SecurityStep(
                        number: '1',
                        text: 'Nhập mật khẩu hiện tại hoặc mã xác nhận 6 số.',
                      ),
                      const SizedBox(height: 12),
                      const _SecurityStep(
                        number: '2',
                        text: 'Đặt mật khẩu mới từ 8 đến 128 ký tự.',
                      ),
                      const SizedBox(height: 12),
                      const _SecurityStep(
                        number: '3',
                        text: 'Các thiết bị khác sẽ cần đăng nhập lại.',
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        AppButton(
                          'Đổi mật khẩu',
                          icon: Icons.lock_outline,
                          onPressed: remote && enabled
                              ? () => changePassword(context)
                              : null,
                        ),
                        AppButton(
                          'Dùng mã qua email',
                          outlined: true,
                          icon: Icons.mark_email_read_outlined,
                          onPressed: remote && enabled
                              ? () =>
                                    context.go('/forgot-password?from=account')
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _SettingsSection(
                title: 'Tùy chọn mua sắm',
                child: Column(
                  children: [
                    _SettingsLink(
                      icon: Icons.location_on_outlined,
                      title: 'Địa chỉ nhận hàng',
                      description:
                          'Thêm, sửa và chọn địa chỉ mặc định khi đặt hàng.',
                      path: '/account/addresses',
                      enabled: enabled,
                    ),
                    const Divider(height: 24),
                    _SettingsLink(
                      icon: Icons.tune,
                      title: 'Phong cách của tôi',
                      description:
                          'Lưu size, màu sắc, phong cách và ngân sách yêu thích.',
                      path: '/account/style',
                      enabled: enabled,
                    ),
                  ],
                ),
              ),
              _SettingsSection(
                title: 'Quyền riêng tư và phiên đăng nhập',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsLink(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Quyền riêng tư',
                      description:
                          'Tìm hiểu cách cửa hàng lưu và sử dụng thông tin của bạn.',
                      path: '/privacy',
                      enabled: enabled,
                    ),
                    const Divider(height: 24),
                    _SettingsLink(
                      icon: Icons.checkroom_outlined,
                      title: 'Quản lý ảnh thử đồ',
                      description:
                          'Xem lại và xóa những lần thử đồ bạn đã lưu.',
                      path: '/account/try-ons',
                      enabled: enabled,
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Đăng xuất khỏi tài khoản trên trình duyệt này.',
                      style: T.body,
                    ),
                    const SizedBox(height: 8),
                    const AccountSignOutButton(),
                    if (signOut.error != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          signOut.error!,
                          style: T.small.copyWith(color: T.danger),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AccountCard(
    title: title,
    icon: switch (title) {
      'Thông tin đăng nhập' => Icons.person_outline,
      'Mật khẩu và bảo mật' => Icons.lock_outline,
      'Tùy chọn mua sắm' => Icons.shopping_bag_outlined,
      _ => Icons.verified_user_outlined,
    },
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 224),
      child: child,
    ),
  );
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.icon,
    required this.title,
    required this.description,
    required this.path,
    this.enabled = true,
  });
  final IconData icon;
  final String title, description, path;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    child: InkWell(
      borderRadius: T.radius,
      onTap: enabled ? () => context.go(path) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: enabled ? T.accent : T.muted, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: T.body.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  Text(description, style: T.small),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: T.muted),
          ],
        ),
      ),
    ),
  );
}

class _SettingsValue extends StatelessWidget {
  const _SettingsValue({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.small),
        const SizedBox(height: 6),
        SelectableText(value, style: T.body),
      ],
    ),
  );
}

class _SecurityStep extends StatelessWidget {
  const _SecurityStep({required this.number, required this.text});
  final String number, text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: T.soft, shape: BoxShape.circle),
        child: Text(
          number,
          style: T.small.copyWith(color: T.accent),
          textScaler: TextScaler.noScaling,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: T.body)),
    ],
  );
}
