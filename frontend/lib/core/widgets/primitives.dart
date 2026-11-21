import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/api_providers.dart';
import '../network/catalog_image.dart';
import '../design/tokens.dart';
import '../design/motion.dart';

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

class AppButton extends StatefulWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.outlined = false,
    this.busy = false,
    this.icon,
    this.light = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool outlined, busy, light;
  final IconData? icon;
  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  final states = WidgetStatesController();
  bool pressed = false;

  @override
  void initState() {
    super.initState();
    states.addListener(updatePressed);
  }

  void updatePressed() {
    if (states.value.contains(WidgetState.pressed) == pressed) return;
    // ButtonStyleButton can update disabled/pressed states while rebuilding.
    // Defer that notification so its ancestor is never dirtied during build.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) updatePressed();
      });
      return;
    }
    setState(() => pressed = states.value.contains(WidgetState.pressed));
  }

  @override
  void dispose() {
    states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy)
          SizedBox(
            width: 16,
            height: 16,
            child: Motion.reduced(context)
                ? const Icon(
                    Icons.hourglass_top_rounded,
                    size: 16,
                    color: T.muted,
                  )
                : const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: T.muted,
                  ),
          )
        else if (widget.icon != null)
          Icon(widget.icon, size: 18),
        if (widget.busy || widget.icon != null) const SizedBox(width: 10),
        Flexible(child: Text(widget.label, textAlign: TextAlign.center)),
      ],
    );
    final button = widget.outlined
        ? OutlinedButton(
            statesController: states,
            onPressed: widget.busy ? null : widget.onPressed,
            child: child,
          )
        : FilledButton(
            statesController: states,
            style: widget.light
                ? FilledButton.styleFrom(
                    backgroundColor: T.surface,
                    foregroundColor: T.accentDeep,
                  )
                : null,
            onPressed: widget.busy ? null : widget.onPressed,
            child: child,
          );
    // Native button states retain keyboard, disabled and pointer semantics.
    // Only paint is scaled; surrounding controls never move on press.
    return Semantics(
      liveRegion: widget.busy,
      value: widget.busy ? 'Đang xử lý' : null,
      child: AnimatedScale(
        scale:
            !Motion.reduced(context) &&
                !widget.busy &&
                widget.onPressed != null &&
                pressed
            ? .98
            : 1,
        duration: Motion.duration(context, Motion.fast),
        curve: Motion.curve,
        child: button,
      ),
    );
  }
}

/// A bounded work area for forms, previews and results, with no idle shadow.
class SurfacePanel extends StatelessWidget {
  const SurfacePanel({super.key, required this.child, this.tinted = false});
  final Widget child;
  final bool tinted;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 20 : 28),
    decoration: BoxDecoration(
      color: tinted ? T.canvas : T.surface,
      borderRadius: T.panelRadius,
      border: Border.all(color: T.line),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
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
    this.readOnly = false,
    this.autofillHints,
    this.textInputAction,
  });
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscure;
  final bool readOnly;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => TextFormField(
    readOnly: readOnly,
    autofillHints: autofillHints,
    textInputAction: textInputAction,
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
            ExcludeSemantics(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: T.soft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: T.accent),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              header: true,
              child: Text(
                title,
                style: T.display(26),
                textAlign: TextAlign.center,
              ),
            ),
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
      builder: (_, c) {
        final columns = c.maxWidth < 330
            ? 1
            : c.maxWidth < 650
            ? 2
            : c.maxWidth < 1000
            ? 3
            : 4;
        final gap = c.maxWidth < 600 ? 14.0 : 24.0;
        return Wrap(
          spacing: gap,
          runSpacing: 32,
          children: List.generate(
            4,
            (_) => SizedBox(
              width: (c.maxWidth - gap * (columns - 1)) / columns,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AspectRatio(
                    aspectRatio: 3 / 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: T.canvas,
                        borderRadius: T.imageRadius,
                      ),
                    ),
                  ),
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
        );
      },
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
  Widget build(BuildContext context) => managedCatalogImage.hasMatch(asset)
      ? Consumer(
          builder: (context, ref, _) => _image(
            NetworkImage(
              catalogImageUrl(ref.watch(apiBaseUrlProvider), asset)!,
            ),
          ),
        )
      : _image(
          asset.startsWith('https://') || asset.startsWith('http://')
              ? NetworkImage(asset)
              : AssetImage(asset),
        );
  Widget _image(ImageProvider provider) => Image(
    image: provider,
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
