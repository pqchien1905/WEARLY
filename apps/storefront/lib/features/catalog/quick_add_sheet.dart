import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/commerce_state.dart';
import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../cart/cart_page.dart';

Future<void> showQuickAdd(BuildContext context, String slug) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => QuickAddSheet(slug: slug),
  );
  if (added == true && context.mounted) showCartDrawer(context);
}

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, required this.slug});
  final String slug;
  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  String? color, size, error;
  bool busy = false;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Chọn nhanh', style: T.display(28))),
                IconButton(
                  tooltip: 'Đóng chọn nhanh',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ref
                .watch(productProvider(widget.slug))
                .when(
                  loading: () => const LoadingPanel(),
                  error: (_, _) => StatePanel(
                    title: 'Chưa tải được sản phẩm',
                    message: 'Hãy thử lại để kiểm tra giá và size.',
                    action: AppButton(
                      'Thử lại',
                      onPressed: () =>
                          ref.invalidate(productProvider(widget.slug)),
                    ),
                  ),
                  data: (p) {
                    if (p == null) {
                      return const StatePanel(
                        title: 'Sản phẩm không còn bán',
                        message: 'Chọn thiết kế khác trong cửa hàng.',
                      );
                    }
                    final currentColor = p.colors.contains(color)
                        ? color!
                        : p.colors.first;
                    final variants = p.variants
                        .where((v) => v.color == currentColor)
                        .toList();
                    final selected = variants
                        .where((v) => v.size == size)
                        .firstOrNull;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 80,
                              height: 106,
                              child: FashionImage(p.image, label: p.name),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: T.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    money(
                                      selected?.price ??
                                          variants
                                              .map((v) => v.price)
                                              .reduce((a, b) => a < b ? a : b),
                                    ),
                                    style: T.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text('Màu sắc'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final c in p.colors)
                              ChoiceChip(
                                label: Text(c),
                                selected: currentColor == c,
                                onSelected: busy
                                    ? null
                                    : (_) => setState(() {
                                        color = c;
                                        size = null;
                                        error = null;
                                      }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text('Chọn size'),
                        const SizedBox(height: 8),
                        AbsorbPointer(
                          absorbing: busy,
                          child: SizeSelector(
                            variants: variants,
                            selected: size,
                            onSelected: (s) => setState(() {
                              size = s;
                              error = null;
                            }),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          selected == null
                              ? 'Chọn size để thêm sản phẩm vào giỏ.'
                              : selected.stock == 0
                              ? 'Size này đã hết hàng.'
                              : 'Còn ${selected.stock} sản phẩm trong kho demo.',
                          style: T.small,
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error!,
                              style: const TextStyle(color: T.danger),
                            ),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: AppButton(
                            'Thêm vào giỏ',
                            busy: busy,
                            onPressed:
                                selected == null || selected.stock == 0 || busy
                                ? null
                                : () async {
                                    setState(() {
                                      busy = true;
                                      error = null;
                                    });
                                    try {
                                      await ref
                                          .read(commerceProvider)
                                          .add(p.slug, selected.sku, 1);
                                      if (context.mounted) {
                                        Navigator.pop(context, true);
                                      }
                                    } catch (e) {
                                      if (mounted) setState(() => error = '$e');
                                    } finally {
                                      if (mounted) setState(() => busy = false);
                                    }
                                  },
                          ),
                        ),
                      ],
                    );
                  },
                ),
          ],
        ),
      ),
    ),
  );
}
