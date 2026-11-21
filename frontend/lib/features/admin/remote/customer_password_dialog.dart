import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

Future<void> resetCustomerPassword(
  BuildContext context,
  WidgetRef ref,
  AdminRecord customer,
) async {
  final password = TextEditingController();
  final confirmation = TextEditingController();
  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: 'Đặt lại mật khẩu khách hàng',
      submitLabel: 'Xác nhận đặt lại',
      message:
          '${customer['name']} (${customer['email']})\n\n'
          'Khách hàng sẽ dùng mật khẩu mới để đăng nhập. Các phiên đăng nhập và mã khôi phục cũ sẽ hết hiệu lực.'
          '${customer['active'] == false ? ' Tài khoản đang khóa sẽ vẫn bị khóa.' : ''}',
      reload: () => refreshAdmin(ref),
      onDisposed: () {
        password.dispose();
        confirmation.dispose();
      },
      fields: [
        _PasswordField(
          label: 'Mật khẩu mới',
          controller: password,
          helper: 'Từ 8 đến 128 ký tự.',
          validator: (value) =>
              (value ?? '').length < 8 || (value ?? '').length > 128
              ? 'Mật khẩu phải có từ 8 đến 128 ký tự.'
              : null,
        ),
        _PasswordField(
          label: 'Nhập lại mật khẩu mới',
          controller: confirmation,
          validator: (value) =>
              value != password.text ? 'Mật khẩu nhập lại chưa khớp.' : null,
        ),
      ],
      submit: () async {
        await repo.resetCustomerPassword(
          '${customer['id']}',
          password: password.text,
          expectedUpdatedAt: '${customer['updatedAt']}',
        );
      },
    ),
  );
  if (!context.mounted || changed != true) return;
  refreshAdmin(ref);
  toast(context, 'Đã đặt lại mật khẩu. Khách hàng cần đăng nhập lại.');
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.label,
    required this.controller,
    required this.validator,
    this.helper,
  });
  final String label;
  final String? helper;
  final TextEditingController controller;
  final String? Function(String?) validator;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    validator: widget.validator,
    obscureText: hidden,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: const [AutofillHints.newPassword],
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: '${hidden ? 'Hiện' : 'Ẩn'} ${widget.label.toLowerCase()}',
        onPressed: () => setState(() => hidden = !hidden),
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );
}
