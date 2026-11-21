import 'package:flutter/material.dart';
import '../../core/contact_phone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/account_state.dart';
import '../../app/api_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import 'account_components.dart';
import 'account_navigation.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(accountProvider);
    final remote = ref.watch(remoteApiProvider);
    if (user == null) {
      return StatePanel(
        title: 'Góc riêng của bạn.',
        message: remote
            ? 'Đăng nhập để xem hồ sơ, địa chỉ và đơn hàng đã lưu.'
            : 'Mở phiên tài khoản demo để lưu thông tin. Bạn vẫn có thể đặt hàng không cần đăng nhập.',
        icon: Icons.person_outline,
        action: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              remote ? 'Đăng nhập' : 'Đăng nhập demo',
              onPressed: () => context.go('/login?next=%2Faccount'),
            ),
            AppButton(
              remote ? 'Xem đơn hàng' : 'Xem đơn trong phiên',
              outlined: true,
              onPressed: () => context.go('/account/orders'),
            ),
          ],
        ),
      );
    }
    return _ProfileEditor(
      // Drafts and pending feedback belong to one authenticated session only.
      key: ValueKey((
        user.id,
        user.email,
        remote ? ref.watch(sessionTokensProvider).generation : 0,
      )),
      user: user,
      remote: remote,
    );
  }
}

class _ProfileEditor extends ConsumerStatefulWidget {
  const _ProfileEditor({super.key, required this.user, required this.remote});
  final UserProfile user;
  final bool remote;

  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
  final form = GlobalKey<FormState>();
  late UserProfile baseline = widget.user;
  late final name = TextEditingController(text: baseline.name);
  late final phone = TextEditingController(text: baseline.phone);
  late final address = TextEditingController(text: baseline.address);
  bool busy = false, saved = false, seeding = false, changedElsewhere = false;
  String? error;

  bool get dirty =>
      name.text.trim() != baseline.name ||
      phone.text.trim() != baseline.phone ||
      (!widget.remote && address.text.trim() != baseline.address);

  @override
  void initState() {
    super.initState();
    for (final controller in [name, phone, address]) {
      controller.addListener(changed);
    }
  }

  void changed() {
    if (seeding) return;
    setState(() {
      saved = false;
      error = null;
    });
  }

  void restore(UserProfile value) {
    seeding = true;
    baseline = value;
    name.text = value.name;
    phone.text = value.phone;
    address.text = value.address;
    seeding = false;
    saved = false;
    error = null;
    changedElsewhere = false;
  }

  @override
  void didUpdateWidget(covariant _ProfileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (busy || identical(oldWidget.user, widget.user)) return;
    if (widget.user.name == baseline.name &&
        widget.user.phone == baseline.phone &&
        widget.user.address == baseline.address) {
      return;
    }
    if (dirty) {
      changedElsewhere = true;
    } else {
      restore(widget.user);
    }
  }

  Future<void> save() async {
    if (busy || !dirty || changedElsewhere || !form.currentState!.validate()) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      saved = false;
      error = null;
    });
    try {
      await ref
          .read(accountProvider.notifier)
          .save(
            UserProfile(
              id: baseline.id,
              name: name.text.trim(),
              email: baseline.email,
              phone: phone.text.trim(),
              address: address.text.trim(),
              role: baseline.role,
              username: baseline.username,
            ),
          );
      if (!mounted) return;
      final persisted = ref.read(accountProvider);
      if (persisted == null ||
          persisted.id != baseline.id ||
          persisted.email != baseline.email) {
        return;
      }
      setState(() {
        restore(persisted);
        saved = true;
      });
      toast(
        context,
        widget.remote ? 'Đã lưu hồ sơ.' : 'Đã lưu hồ sơ trong phiên demo.',
      );
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void undo() {
    if (busy) return;
    setState(() {
      seeding = true;
      form.currentState?.reset();
      restore(widget.user);
    });
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AccountFrame(
    title: 'Chào ${widget.user.name}.',
    current: '/account',
    enabled: !busy,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountCard(
          title: 'Thông tin cá nhân',
          description: 'Quản lý tên hiển thị và thông tin liên hệ của bạn.',
          icon: Icons.person_outline,
          child: Form(
            key: form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AccountGrid(
                    columns: 3,
                    minColumnWidth: 280,
                    children: [
                      AppField(
                        label: 'Họ và tên',
                        controller: name,
                        readOnly: busy,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        validator: (value) =>
                            requiredValue(value) ??
                            ((value?.trim().length ?? 0) > 100
                                ? 'Họ và tên không quá 100 ký tự.'
                                : null),
                      ),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Điện thoại (không bắt buộc)',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                        controller: phone,
                        readOnly: busy,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => save(),
                        validator: contactPhoneValidation,
                      ),
                      TextFormField(
                        initialValue: widget.user.email,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Email đăng nhập',
                          helperText: 'Email này không thể chỉnh sửa tại đây.',
                          helperMaxLines: 3,
                          suffixIcon: Icon(Icons.lock_outline, size: 18),
                        ),
                      ),
                    ],
                  ),
                  if (!widget.remote) ...[
                    const SizedBox(height: 24),
                    AppField(
                      label: 'Địa chỉ (không bắt buộc)',
                      controller: address,
                      readOnly: busy,
                      maxLines: 2,
                    ),
                  ],
                  const SizedBox(height: 24),
                  AccountNotice(
                    icon: Icons.info_outline,
                    text: widget.remote
                        ? 'Địa chỉ và số điện thoại nhận hàng được quản lý riêng trong Sổ địa chỉ. Thay đổi hồ sơ không cập nhật các đơn hàng đã đặt.'
                        : 'Hồ sơ chỉ lưu trong bộ nhớ phiên trình duyệt. Không phải tài khoản bảo mật thật.',
                  ),
                  const Divider(height: 40),
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          busy
                              ? Icons.sync
                              : error != null || changedElsewhere
                              ? Icons.error_outline
                              : dirty
                              ? Icons.edit_outlined
                              : Icons.check_circle_outline,
                          size: 18,
                          color: error != null || changedElsewhere
                              ? T.danger
                              : T.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            busy
                                ? 'Đang lưu hồ sơ…'
                                : changedElsewhere
                                ? 'Hồ sơ vừa được cập nhật. Chọn hoàn tác để dùng thông tin mới nhất trước khi sửa tiếp.'
                                : error != null
                                ? 'Chưa lưu được hồ sơ. $error'
                                : dirty
                                ? 'Bạn có thay đổi chưa lưu.'
                                : saved
                                ? 'Thông tin mới đã được lưu.'
                                : 'Hồ sơ đang khớp với thông tin đã lưu.',
                            style: T.body.copyWith(
                              color: error != null || changedElsewhere
                                  ? T.danger
                                  : T.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Semantics(
                        // The progress indicator otherwise hides the button's
                        // accessible label while the request is in flight.
                        button: busy ? true : null,
                        enabled: busy ? false : null,
                        label: busy ? 'Đang lưu hồ sơ' : null,
                        excludeSemantics: busy,
                        child: AppButton(
                          widget.remote ? 'Lưu hồ sơ' : 'Lưu hồ sơ demo',
                          icon: Icons.check,
                          busy: busy,
                          onPressed: dirty && !changedElsewhere ? save : null,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: !busy && (dirty || changedElsewhere)
                            ? undo
                            : null,
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('Hoàn tác thay đổi'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Thay đổi chỉ được lưu khi bạn chọn Lưu hồ sơ.',
                    style: T.small,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        AccountCard(
          title: 'Tiện ích tài khoản',
          description:
              'Theo dõi mua sắm và chăm chút phong cách ở cùng một nơi.',
          icon: Icons.grid_view_outlined,
          child: AccountGrid(
            columns: 3,
            minColumnWidth: 280,
            children: [
              for (final item in [
                (
                  'Theo dõi đơn hàng',
                  'Xem chi tiết và tình trạng giao hàng.',
                  Icons.shopping_bag_outlined,
                  '/account/orders',
                ),
                (
                  'Quản lý địa chỉ nhận hàng',
                  'Lưu người nhận và địa chỉ thường dùng.',
                  Icons.location_on_outlined,
                  '/account/addresses',
                ),
                (
                  'Phong cách của tôi',
                  'Chọn size, màu sắc và ngân sách.',
                  Icons.tune,
                  '/account/style',
                ),
                (
                  'Xem lịch sử thử đồ',
                  'Mở lại ảnh thử và trang phục đã chọn.',
                  Icons.checkroom_outlined,
                  '/account/try-ons',
                ),
                (
                  'Tủ đồ yêu thích',
                  'Trở lại những thiết kế bạn đã lưu.',
                  Icons.favorite_border,
                  '/wishlist',
                ),
                (
                  'Bảo mật và cài đặt',
                  'Quản lý mật khẩu và phiên đăng nhập.',
                  Icons.lock_outline,
                  '/account/settings',
                ),
              ])
                AccountLink(
                  title: item.$1,
                  description: item.$2,
                  icon: item.$3,
                  path: item.$4,
                  enabled: !busy,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
