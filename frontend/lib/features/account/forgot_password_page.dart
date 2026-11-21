import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/api_providers.dart';
import '../../app/account_state.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/primitives.dart';
import 'reset_password_page.dart';

// Component aliases stay aligned with the Wearly semantic palette.
abstract final class _RecoveryStyle {
  static const panel = T.soft, surface = T.surface;
  static const double width = 1120, formWidth = 480;
  static const padding = EdgeInsets.all(40);
  static final body = T.body.copyWith(fontSize: 16);
}

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key, this.fromAccount = false});
  final bool fromAccount;
  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      code = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  final codeFocus = FocusNode(), passwordFocus = FocusNode();
  Timer? timer;
  int step = 0, resendSeconds = 0;
  bool busy = false,
      obscure = true,
      obscureConfirmation = true,
      uncertain = false;
  String? resetToken, error, notice;
  String sentEmail = '';

  @override
  void initState() {
    super.initState();
    if (widget.fromAccount) email.text = ref.read(accountProvider)?.email ?? '';
  }

  void cooldown() {
    timer?.cancel();
    resendSeconds = 60;
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => resendSeconds--);
      if (resendSeconds == 0) timer.cancel();
    });
  }

  void focus(FocusNode node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });

  Future<void> sendCode({bool resend = false}) async {
    if (busy || (resend && resendSeconds > 0)) return;
    if (!resend && !form.currentState!.validate()) return;
    final address = resend ? sentEmail : email.text.trim().toLowerCase();
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await ref.read(passwordRecoveryProvider).requestCode(address);
      if (!mounted) return;
      setState(() {
        sentEmail = address;
        step = 1;
        code.clear();
        resetToken = null;
        notice = resend
            ? 'Đã tiếp nhận yêu cầu gửi lại. Hãy dùng mã trong email mới nhất.'
            : null;
        cooldown();
      });
      focus(codeFocus);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final token = await ref
          .read(passwordRecoveryProvider)
          .verifyCode(sentEmail, code.text);
      if (!mounted) return;
      setState(() {
        resetToken = token;
        code.clear();
        step = 2;
      });
      focus(passwordFocus);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => error = e.code == 'RESET_CODE_INVALID'
              ? 'Mã không đúng, đã hết hạn hoặc đã được dùng. Kiểm tra lại mã hoặc chọn Gửi lại mã.'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Chưa xác nhận được mã. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reset() async {
    if (busy || resetToken == null || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(passwordRecoveryProvider)
          .reset(resetToken!, password.text);
      if (!mounted) return;
      setState(() {
        step = 3;
        resetToken = null;
      });
      timer?.cancel();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'RESET_LINK_INVALID') {
          step = 1;
          resetToken = null;
          error = 'Phiên xác nhận đã hết hạn. Hãy gửi lại mã để tiếp tục.';
        } else if ([
          'TIMEOUT',
          'CONNECTION_ERROR',
          'INVALID_RESPONSE',
        ].contains(e.code)) {
          uncertain = true;
          resetToken = null;
        } else {
          error = e.message;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          uncertain = true;
          resetToken = null;
        });
      }
    } finally {
      if (mounted) {
        password.clear();
        confirmation.clear();
        setState(() => busy = false);
      }
    }
  }

  void changeEmail() {
    if (busy) return;
    setState(() {
      step = 0;
      error = null;
      notice = null;
      uncertain = false;
      resetToken = null;
      code.clear();
      password.clear();
      confirmation.clear();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    resetToken = null;
    for (final controller in [email, code, password, confirmation]) {
      controller.dispose();
    }
    codeFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteApiProvider);
    return PageBody(
      vertical: 40,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _RecoveryStyle.width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => context.go(
                        widget.fromAccount && ref.read(accountProvider) != null
                            ? '/account/settings'
                            : '/login',
                      ),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(
                  widget.fromAccount && ref.watch(accountProvider) != null
                      ? 'Trở về cài đặt tài khoản'
                      : 'Trở về đăng nhập',
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 860;
                  final content = Padding(
                    padding: wide
                        ? _RecoveryStyle.padding
                        : const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _RecoveryStyle.formWidth,
                      ),
                      child: _formContent(remote, wide),
                    ),
                  );
                  return Container(
                    decoration: BoxDecoration(
                      color: _RecoveryStyle.surface,
                      border: Border.all(color: T.line),
                      borderRadius: T.radius,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: wide
                        ? IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 5, child: _editorialPanel()),
                                Expanded(
                                  flex: 6,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: content,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : content,
                  );
                },
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'WEARLY · Phong cách riêng, tài khoản của riêng bạn.',
                  textAlign: TextAlign.center,
                  style: T.small,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editorialPanel() => Container(
    color: _RecoveryStyle.panel,
    padding: _RecoveryStyle.padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WEARLY ACCOUNT',
          style: T.small.copyWith(
            color: T.accent,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 48),
        Text('Tìm lại lối vào.\nTiếp tục là bạn.', style: T.display(40)),
        const SizedBox(height: 20),
        Text(
          'Tủ đồ yêu thích, những đơn hàng và cảm hứng mỗi ngày vẫn đang chờ bạn.',
          style: _RecoveryStyle.body.copyWith(color: T.muted),
        ),
        const SizedBox(height: 48),
        for (var index = 0; index < 3; index++) ...[
          _stepLabel(index, vertical: true),
          if (index < 2) const SizedBox(height: 24),
        ],
        const SizedBox(height: 48),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline_rounded, color: T.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mã xác nhận chỉ dành cho bạn.\nĐừng chia sẻ mã với bất kỳ ai.',
                style: T.small.copyWith(color: T.accent),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _stepLabel(int index, {bool vertical = false}) {
    final complete = step > index, active = step == index;
    final label = ['Email của bạn', 'Mã xác nhận', 'Mật khẩu mới'][index];
    return Semantics(
      label:
          'Bước ${index + 1}: $label${complete
              ? ', hoàn tất'
              : active
              ? ', hiện tại'
              : ''}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: complete || active ? T.accent : T.surface,
              border: Border.all(color: T.accent),
            ),
            child: complete
                ? const Icon(Icons.check_rounded, color: T.surface, size: 16)
                : Text(
                    '${index + 1}',
                    style: T.small.copyWith(
                      color: active ? T.surface : T.accent,
                    ),
                  ),
          ),
          SizedBox(width: vertical ? 14 : 8),
          Flexible(
            child: Text(
              label,
              style: T.body.copyWith(
                color: complete || active ? T.accent : T.muted,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                fontSize: vertical ? 14 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formContent(bool remote, bool wide) {
    if (step == 3 || uncertain) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            uncertain
                ? Icons.info_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 48,
            color: uncertain ? T.accent : T.success,
          ),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            child: Text(
              uncertain
                  ? 'Kiểm tra lại đăng nhập'
                  : 'Mật khẩu đã được thay đổi',
              style: T.display(30),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            uncertain
                ? 'Yêu cầu có thể đã hoàn tất. Hãy thử đăng nhập bằng mật khẩu mới. Nếu chưa được, bạn có thể yêu cầu mã khác.'
                : 'Bạn đã sẵn sàng trở lại. Đăng nhập bằng mật khẩu mới để tiếp tục; các phiên đăng nhập cũ đã được thu hồi.',
            style: _RecoveryStyle.body.copyWith(color: T.muted),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: AppButton(
              'Đăng nhập',
              onPressed: () => context.go('/login'),
              icon: Icons.arrow_forward_rounded,
            ),
          ),
          if (uncertain)
            TextButton(
              onPressed: changeEmail,
              child: const Text('Yêu cầu mã mới'),
            ),
        ],
      );
    }
    return Form(
      key: form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!wide) ...[
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [for (var i = 0; i < 3; i++) _stepLabel(i)],
              ),
              const SizedBox(height: 32),
            ],
            Text(
              'BƯỚC ${step + 1} / 3',
              style: T.small.copyWith(color: T.accent, letterSpacing: 1.5),
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                [
                  widget.fromAccount ? 'Đổi mật khẩu' : 'Quên mật khẩu?',
                  'Kiểm tra email của bạn',
                  'Đặt mật khẩu mới',
                ][step],
                style: T.display(wide ? 32 : 28),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              [
                'Nhập email đã đăng ký. Chúng tôi sẽ gửi mã 6 số để giúp bạn trở lại tài khoản.',
                'Nếu email đã được đăng ký, bạn sẽ nhận được mã gồm 6 số. Kiểm tra cả thư rác nhé.',
                'Chọn mật khẩu mới có từ 8 đến 128 ký tự để bảo vệ tài khoản của bạn.',
              ][step],
              style: _RecoveryStyle.body.copyWith(color: T.muted),
            ),
            if (!remote) ...[
              const SizedBox(height: 24),
              const DemoNotice(
                text:
                    'Chế độ demo không gửi email. Mở cửa hàng kết nối API để khôi phục mật khẩu.',
              ),
            ],
            const SizedBox(height: 28),
            if (step == 0)
              TextFormField(
                key: const ValueKey('recovery-email'),
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                style: _RecoveryStyle.body,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'ban@example.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (v) =>
                    RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v?.trim() ?? '') &&
                        (v?.trim().length ?? 0) <= 254
                    ? null
                    : 'Nhập địa chỉ email hợp lệ.',
                onFieldSubmitted: remote ? (_) => sendCode() : null,
              ),
            if (step == 1) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: T.canvas,
                  borderRadius: T.radius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Email nhận mã', style: T.small),
                    const SizedBox(height: 4),
                    Text(
                      sentEmail,
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    TextButton(
                      onPressed: busy ? null : changeEmail,
                      child: const Text('Đổi email'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const ValueKey('recovery-code'),
                controller: code,
                focusNode: codeFocus,
                enabled: !busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                autocorrect: false,
                enableSuggestions: false,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: T.body.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 10,
                  color: T.accent,
                ),
                decoration: const InputDecoration(
                  labelText: 'Mã xác nhận',
                  hintText: '000000',
                  helperText: 'Mã có hiệu lực trong 10 phút.',
                  helperMaxLines: 2,
                ),
                validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '')
                    ? null
                    : 'Nhập đủ 6 chữ số trong email.',
                onFieldSubmitted: (_) => verify(),
              ),
            ],
            if (step == 2) ...[
              _passwordField(false),
              const SizedBox(height: 20),
              _passwordField(true),
            ],
            if (error != null || notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error ?? notice!,
                    style: T.body.copyWith(
                      color: error != null ? T.danger : T.success,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                ['Gửi mã xác nhận', 'Xác nhận mã', 'Lưu mật khẩu mới'][step],
                busy: busy,
                icon: Icons.arrow_forward_rounded,
                onPressed: !remote
                    ? null
                    : step == 0
                    ? () => sendCode()
                    : step == 1
                    ? verify
                    : reset,
              ),
            ),
            const SizedBox(height: 12),
            if (step == 0)
              Center(
                child: TextButton(
                  onPressed: busy || !remote
                      ? null
                      : () {
                          if (!form.currentState!.validate()) return;
                          setState(() {
                            sentEmail = email.text.trim().toLowerCase();
                            step = 1;
                            error = null;
                          });
                          focus(codeFocus);
                        },
                  child: const Text('Tôi đã có mã xác nhận'),
                ),
              ),
            if (step == 1)
              Center(
                child: TextButton(
                  onPressed: busy || resendSeconds > 0
                      ? null
                      : () => sendCode(resend: true),
                  child: Text(
                    resendSeconds > 0
                        ? 'Gửi lại mã sau ${resendSeconds}s'
                        : 'Gửi lại mã',
                  ),
                ),
              ),
            if (step == 2)
              Text(
                'Sau khi đổi mật khẩu, bạn cần đăng nhập lại trên các thiết bị.',
                style: T.small,
              ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField(bool confirm) => TextFormField(
    key: ValueKey(confirm ? 'recovery-confirmation' : 'recovery-password'),
    controller: confirm ? confirmation : password,
    focusNode: confirm ? null : passwordFocus,
    enabled: !busy,
    obscureText: confirm ? obscureConfirmation : obscure,
    enableSuggestions: false,
    autocorrect: false,
    autofillHints: const [AutofillHints.newPassword],
    style: _RecoveryStyle.body,
    decoration: InputDecoration(
      labelText: confirm ? 'Nhập lại mật khẩu mới' : 'Mật khẩu mới',
      suffixIcon: IconButton(
        tooltip: (confirm ? obscureConfirmation : obscure)
            ? 'Hiện mật khẩu${confirm ? ' xác nhận' : ''}'
            : 'Ẩn mật khẩu${confirm ? ' xác nhận' : ''}',
        onPressed: () => setState(() {
          if (confirm) {
            obscureConfirmation = !obscureConfirmation;
          } else {
            obscure = !obscure;
          }
        }),
        icon: Icon(
          (confirm ? obscureConfirmation : obscure)
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: (v) => confirm
        ? v == password.text
              ? null
              : 'Hai mật khẩu chưa khớp.'
        : (v?.length ?? 0) >= 8 && (v?.length ?? 0) <= 128
        ? null
        : 'Mật khẩu cần từ 8 đến 128 ký tự.',
    onFieldSubmitted: confirm
        ? (_) => reset()
        : (_) => FocusScope.of(context).nextFocus(),
  );
}
