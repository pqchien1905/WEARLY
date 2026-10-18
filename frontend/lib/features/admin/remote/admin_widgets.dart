import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import '../../../app/account_state.dart';

class AdminAsync<Value> extends StatelessWidget {
  const AdminAsync({
    super.key,
    required this.value,
    required this.reload,
    required this.builder,
  });
  final AsyncValue<Value> value;
  final VoidCallback reload;
  final Widget Function(Value) builder;
  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnRefresh: true,
    data: (data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value.isLoading) const LinearProgressIndicator(),
        builder(data),
      ],
    ),
    loading: () => const Padding(
      padding: EdgeInsets.all(40),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (error, _) => StatePanel(
      title: 'Chưa tải được dữ liệu',
      message: adminError(error),
      action: AppButton('Thử tải lại', onPressed: reload),
    ),
  );
}

String adminError(Object error) => error is ApiException
    ? error.message
    : 'Không đọc được dữ liệu. Vui lòng tải lại.';

class AdminHeading extends StatelessWidget {
  const AdminHeading(
    this.title,
    this.subtitle, {
    super.key,
    this.actions = const [],
  });
  final String title, subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: T.display(MediaQuery.sizeOf(context).width < 600 ? 28 : 38),
        ),
        const SizedBox(height: 12),
        Text(subtitle, style: T.body),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: actions),
        ],
      ],
    ),
  );
}

class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: T.surface,
      border: Border.all(color: T.line),
      borderRadius: T.radius,
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

/// Awaited mutations cannot be submitted twice. An uncertain result or version
/// conflict must be reloaded before another write, especially stock increments.
class AdminMutationDialog extends ConsumerStatefulWidget {
  const AdminMutationDialog({
    super.key,
    required this.title,
    required this.submit,
    required this.reload,
    this.fields = const [],
    this.message = '',
    this.onDisposed,
  });
  final String title, message;
  final List<Widget> fields;
  final Future<void> Function() submit;
  final VoidCallback reload;
  final VoidCallback? onDisposed;
  @override
  ConsumerState<AdminMutationDialog> createState() =>
      _AdminMutationDialogState();
}

class _AdminMutationDialogState extends ConsumerState<AdminMutationDialog> {
  late final identity = ref.read(accountProvider)?.id;
  final form = GlobalKey<FormState>();
  bool saving = false, needsReload = false;
  String? error;
  Future<void> save() async {
    if (saving || needsReload || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.submit();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = adminError(e);
        needsReload = e is! ApiException || ![400, 422].contains(e.status);
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    if (account?.role != 'ADMIN' || account?.id != identity) {
      return AlertDialog(
        title: const Text('Phiên quản trị đã kết thúc'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      );
    }
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(widget.message),
                    ),
                  for (final field in widget.fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: field,
                    ),
                  if (error != null)
                    Text(error!, style: T.body.copyWith(color: T.danger)),
                  if (needsReload)
                    const Text(
                      'Hãy tải lại dữ liệu để kiểm tra kết quả trước khi thao tác tiếp.',
                      style: T.small,
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          if (needsReload)
            AppButton(
              'Tải lại dữ liệu',
              onPressed: () {
                widget.reload();
                Navigator.pop(context);
              },
            )
          else
            AppButton('Lưu thay đổi', busy: saving, onPressed: save),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.onDisposed?.call();
    super.dispose();
  }
}

String? requiredText(String? value, {int max = 200}) =>
    (value ?? '').trim().isEmpty
    ? 'Vui lòng nhập thông tin.'
    : value!.trim().length > max
    ? 'Tối đa $max ký tự.'
    : null;
String? priceValidation(String? value) =>
    RegExp(r'^\d{1,14}$').hasMatch(value ?? '')
    ? null
    : 'Nhập số tiền nguyên, tối đa 14 chữ số.';
