import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/api_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/primitives.dart';

final passwordRecoveryProvider = Provider<PasswordRecovery>((ref) {
  VoidCallback prepareInvalidation() {
    final shopper = ref.read(sessionTokensProvider);
    final shopperGeneration = shopper.generation;
    return () {
      if (!ref.mounted) return;
      if (shopper.generation == shopperGeneration) shopper.clear();
    };
  }

  return PasswordRecovery(ref.watch(apiClientProvider), prepareInvalidation);
});

class PasswordRecovery {
  PasswordRecovery(this.api, this.prepareInvalidation);
  final ApiClient api;
  final VoidCallback Function() prepareInvalidation;
  Future<void> requestCode(String email) async {
    final response = await api.request(
      'POST',
      'auth/forgot-password',
      authenticated: false,
      body: {'email': email.trim().toLowerCase()},
    );
    if (response is! Map || response['accepted'] != true) {
      throw const ApiException(
        'INVALID_RESPONSE',
        'Chưa gửi được yêu cầu. Vui lòng thử lại.',
      );
    }
  }

  Future<String> verifyCode(String email, String code) async {
    final response = await api.request(
      'POST',
      'auth/verify-reset-code',
      authenticated: false,
      body: {'email': email.trim().toLowerCase(), 'code': code},
    );
    if (response is! Map ||
        response['resetToken'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{43}$',
        ).hasMatch(response['resetToken'] as String)) {
      throw const ApiException(
        'INVALID_RESPONSE',
        'Chưa xác nhận được mã. Vui lòng thử lại.',
      );
    }
    return response['resetToken'] as String;
  }

  Future<void> reset(String token, String password) async {
    final invalidateSessions = prepareInvalidation();
    try {
      final response = await api.request(
        'POST',
        'auth/reset-password',
        authenticated: false,
        body: {'token': token, 'password': password},
        onLateCompletion: invalidateSessions,
      );
      if (response is! Map || response['changed'] != true) {
        throw const ApiException(
          'INVALID_RESPONSE',
          'Chưa xác nhận được kết quả.',
        );
      }
      invalidateSessions();
    } on ApiException catch (error) {
      if ([
        'TIMEOUT',
        'CONNECTION_ERROR',
        'INVALID_RESPONSE',
      ].contains(error.code)) {
        invalidateSessions();
      }
      rethrow;
    }
  }
}

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, required this.takeToken});
  final String? Function() takeToken;
  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController(),
      confirmation = TextEditingController();
  String? token, error;
  bool busy = false, changed = false, uncertain = false;
  @override
  void initState() {
    super.initState();
    token = widget.takeToken();
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token ?? '')) token = null;
  }

  @override
  void dispose() {
    token = null;
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || token == null || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(passwordRecoveryProvider).reset(token!, password.text);
      if (mounted) {
        setState(() {
          token = null;
          changed = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          if (e.code == 'RESET_LINK_INVALID') {
            token = null;
          } else if ([
            'TIMEOUT',
            'CONNECTION_ERROR',
            'INVALID_RESPONSE',
          ].contains(e.code)) {
            uncertain = true;
            token = null;
          } else {
            error = e.toString();
          }
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

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(remoteApiProvider)) {
      return const StatePanel(
        title: 'Đặt lại mật khẩu',
        message: 'Liên kết này dành cho cửa hàng kết nối API.',
      );
    }
    if (changed) {
      return StatePanel(
        title: 'Mật khẩu đã được thay đổi',
        message:
            'Các phiên đăng nhập đã được thu hồi. Hãy đăng nhập bằng mật khẩu mới.',
        action: AppButton('Đăng nhập', onPressed: () => context.go('/login')),
      );
    }
    if (token == null) {
      return StatePanel(
        title: uncertain
            ? 'Chưa xác nhận được kết quả'
            : 'Liên kết không còn hiệu lực',
        message: uncertain
            ? 'Yêu cầu có thể đã hoàn tất. Hãy thử đăng nhập bằng mật khẩu mới hoặc yêu cầu mã xác nhận khác.'
            : 'Liên kết có thể đã hết hạn, đã sử dụng hoặc chưa đầy đủ. Hãy yêu cầu mã xác nhận mới.',
        action: AppButton(
          'Yêu cầu mã mới',
          onPressed: () => context.go('/forgot-password'),
        ),
      );
    }
    return PageBody(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Đặt lại mật khẩu', style: T.display(36)),
                const SizedBox(height: 16),
                const Text(
                  'Mật khẩu cần từ 8 đến 128 ký tự. Sau khi thay đổi, bạn cần đăng nhập lại trên các thiết bị.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
                  validator: (v) =>
                      (v?.length ?? 0) >= 8 && (v?.length ?? 0) <= 128
                      ? null
                      : 'Mật khẩu cần từ 8 đến 128 ký tự.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmation,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Nhập lại mật khẩu mới',
                  ),
                  validator: (v) =>
                      v == password.text ? null : 'Hai mật khẩu chưa khớp.',
                ),
                const SizedBox(height: 24),
                AppButton('Đặt lại mật khẩu', busy: busy, onPressed: submit),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Semantics(
                      liveRegion: true,
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
      ),
    );
  }
}
