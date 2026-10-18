import 'package:flutter/material.dart';
import '../design/tokens.dart';

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.vertical = 40});
  final Widget child;
  final double vertical;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: T.maxWidth),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: T.gutter(context),
          vertical: vertical,
        ),
        child: child,
      ),
    ),
  );
}

/// Tables fill wide panels while retaining horizontal access on narrow screens.
class TableViewport extends StatelessWidget {
  const TableViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: c.maxWidth),
        child: child,
      ),
    ),
  );
}

class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.outlined = false,
    this.busy = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool outlined, busy;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: T.muted),
          )
        else if (icon != null)
          Icon(icon, size: 18),
        if (busy || icon != null) const SizedBox(width: 10),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return outlined
        ? OutlinedButton(onPressed: busy ? null : onPressed, child: child)
        : FilledButton(onPressed: busy ? null : onPressed, child: child);
  }
}

class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.onSubmitted,
    this.hint,
  });
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscure;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    obscureText: obscure,
    keyboardType: keyboardType,
    maxLines: maxLines,
    onFieldSubmitted: onSubmitted,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}

class DemoNotice extends StatelessWidget {
  const DemoNotice({
    super.key,
    this.text = 'Trải nghiệm mô phỏng – chưa kết nối AI',
  });
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(color: T.soft, borderRadius: T.radius),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: T.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: T.small.copyWith(color: T.accent)),
        ),
      ],
    ),
  );
}

class StatePanel extends StatelessWidget {
  const StatePanel({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.search_off_outlined,
  });
  final String title, message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          children: [
            Icon(icon, size: 40, color: T.accent),
            const SizedBox(height: 20),
            Text(title, style: T.display(26), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: T.body.copyWith(color: T.muted),
            ),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 24), child: action),
          ],
        ),
      ),
    ),
  );
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Đang tải sản phẩm',
    liveRegion: true,
    child: LayoutBuilder(
      builder: (_, c) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: List.generate(
          4,
          (_) => SizedBox(
            width: (c.maxWidth - 16) / 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 240, color: T.canvas),
                const SizedBox(height: 12),
                FractionallySizedBox(
                  widthFactor: .8,
                  child: Container(height: 12, color: T.canvas),
                ),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: .4,
                  child: Container(height: 12, color: T.canvas),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class FashionImage extends StatelessWidget {
  const FashionImage(
    this.asset, {
    super.key,
    required this.label,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
  });
  final String asset, label;
  final BoxFit fit;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    fit: fit,
    alignment: alignment,
    semanticLabel: label,
    width: double.infinity,
    height: double.infinity,
    errorBuilder: (_, _, _) => ColoredBox(
      color: T.photo,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined),
            Text('Ảnh chưa có', style: T.small),
          ],
        ),
      ),
    ),
  );
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      );
Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Giữ lại'),
          ),
          AppButton('Xác nhận', onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    ) ??
    false;
String? requiredValue(String? v) =>
    v == null || v.trim().isEmpty ? 'Vui lòng điền thông tin này.' : null;
String? emailValidator(String? v) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v?.trim() ?? '')
    ? null
    : 'Nhập email hợp lệ, ví dụ ban@example.com.';
