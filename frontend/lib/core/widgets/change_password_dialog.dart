import 'package:flutter/material.dart';
import '../design/tokens.dart';
import 'primitives.dart';

/// Signed-in password change for customers and staff. [submit] receives the
/// current and new passwords; errors it throws are shown inside the dialog.
/// Returns true when the server confirmed the change.
Future<bool> showChangePasswordDialog(
  BuildContext context, {
  required Future<void> Function(String current, String next) submit,
  VoidCallback? onForgot,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChangePasswordDialog(submit: submit, onForgot: onForgot),
    ) ??
    false;

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.submit, this.onForgot});
  final Future<void> Function(String current, String next) submit;
  final VoidCallback? onForgot;
  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(),
      next = TextEditingController(),
      confirm = TextEditingController();
  bool busy = false, obscure = true;
  String? error;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.submit(current.text, next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String label,
    TextEditingController controller,
    String? Function(String?) validator, {
    required String key,
    bool last = false,
  }) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    obscureText: obscure,
    readOnly: busy,
    validator: validator,
    autofillHints: [
      key == 'change-current'
          ? AutofillHints.password
          : AutofillHints.newPassword,
    ],
    textInputAction: last ? TextInputAction.done : TextInputAction.next,
    onFieldSubmitted: last ? (_) => save() : null,
    decoration: InputDecoration(labelText: label),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Đổi mật khẩu'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sau khi đổi, các thiết bị khác sẽ được đăng xuất. Phiên hiện tại vẫn được giữ.',
                style: T.small,
              ),
              const SizedBox(height: 16),
              field(
                'Mật khẩu hiện tại',
                current,
                (v) => (v ?? '').isEmpty ? 'Nhập mật khẩu hiện tại.' : null,
                key: 'change-current',
              ),
              const SizedBox(height: 12),
              field('Mật khẩu mới', next, (v) {
                final length = v?.length ?? 0;
                if (length < 8 || length > 128) {
                  return 'Mật khẩu cần từ 8 đến 128 ký tự.';
                }
                if (v == current.text) {
                  return 'Mật khẩu mới cần khác mật khẩu hiện tại.';
                }
                return null;
              }, key: 'change-next'),
              const SizedBox(height: 12),
              field(
                'Nhập lại mật khẩu mới',
                confirm,
                (v) => v == next.text ? null : 'Hai mật khẩu chưa khớp.',
                key: 'change-confirm',
                last: true,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: !obscure,
                onChanged: busy
                    ? null
                    : (v) => setState(() => obscure = !(v ?? false)),
                title: const Text('Hiện mật khẩu', style: T.small),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (widget.onForgot != null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.pop(context, false);
                          widget.onForgot!();
                        },
                  child: const Text('Quên mật khẩu hiện tại?'),
                ),
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: T.body.copyWith(color: T.danger),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, false),
        child: const Text('Hủy'),
      ),
      AppButton('Lưu mật khẩu mới', busy: busy, onPressed: save),
    ],
  );
}
