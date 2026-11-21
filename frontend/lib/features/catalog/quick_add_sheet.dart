import '../../core/widgets/promotion_price.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/commerce_state.dart';
import '../../app/api_providers.dart';
import '../../app/providers.dart';
import '../../core/network/api_client.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../cart/cart_page.dart';

Future<void> showQuickAdd(BuildContext context, String slug) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final commerce = container.read(commerceProvider);
  final generation = commerce.remote
      ? container.read(apiClientProvider).tokens.generation
      : null;
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => QuickAddSheet(slug: slug),
  );
  if (added == true &&
      context.mounted &&
      identical(commerce, container.read(commerceProvider)) &&
      (!commerce.remote ||
          generation == container.read(apiClientProvider).tokens.generation)) {
    showCartDrawer(context);
  }
}

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, required this.slug});
  final String slug;
  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  String? color, size, error;
  bool busy = false, uncertain = false;
  late final CommerceController _commerce;
  late final int? _generation;
  @override
  void initState() {
    super.initState();
    _commerce = ref.read(commerceProvider);
    _generation = _commerce.remote
        ? ref.read(apiClientProvider).tokens.generation
        : null;
  }

  bool get _current =>
      identical(_commerce, ref.read(commerceProvider)) &&
      (!_commerce.remote ||
          _generation == ref.read(apiClientProvider).tokens.generation);

  @override
  Widget build(BuildContext context) {
    ref.watch(commerceProvider);
    return PopScope(
      canPop: !busy,
      child: SafeArea(
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
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!_current)
                  const StatePanel(
                    title: 'Phiên tài khoản đã thay đổi',
                    message:
                        'Đóng cửa sổ này rồi chọn lại sản phẩm để tiếp tục.',
                  )
                else
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
                          if (p == null || p.variants.isEmpty || !p.active) {
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
                                    child: FashionImage(
                                      p.image,
                                      label: p.name,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: T.body.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        PromotionPrice(
                                          price:
                                              (selected ??
                                                      variants.reduce(
                                                        (a, b) =>
                                                            a.price <= b.price
                                                            ? a
                                                            : b,
                                                      ))
                                                  .price,
                                          original:
                                              (selected ??
                                                      variants.reduce(
                                                        (a, b) =>
                                                            a.price <= b.price
                                                            ? a
                                                            : b,
                                                      ))
                                                  .originalPrice,
                                          name:
                                              (selected ??
                                                      variants.reduce(
                                                        (a, b) =>
                                                            a.price <= b.price
                                                            ? a
                                                            : b,
                                                      ))
                                                  .promotionName,
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
                                      onSelected: busy || uncertain
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
                              SizeSelector(
                                enabled: !busy && !uncertain,
                                variants: variants,
                                selected: size,
                                onSelected: (s) => setState(() {
                                  size = s;
                                  error = null;
                                }),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                selected == null
                                    ? 'Chọn size để thêm sản phẩm vào giỏ.'
                                    : selected.stock == 0
                                    ? 'Size này đã hết hàng.'
                                    : 'Còn ${selected.stock} sản phẩm.',
                                style: T.small,
                              ),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      error!,
                                      style: const TextStyle(color: T.danger),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: double.infinity,
                                child: Semantics(
                                  label: busy
                                      ? 'Đang cập nhật giỏ hàng…'
                                      : null,
                                  button: busy ? true : null,
                                  enabled: busy ? false : null,
                                  excludeSemantics: busy,
                                  child: AppButton(
                                    uncertain
                                        ? 'Kiểm tra giỏ hàng'
                                        : 'Thêm vào giỏ',
                                    busy: busy,
                                    onPressed:
                                        selected == null ||
                                            selected.stock == 0 ||
                                            busy
                                        ? null
                                        : () async {
                                            if (busy || !_current) return;
                                            setState(() {
                                              busy = true;
                                              error = null;
                                            });
                                            try {
                                              if (uncertain) {
                                                await _commerce.refreshCart();
                                                if (_commerce.cartState.error !=
                                                    null) {
                                                  throw _commerce
                                                      .cartState
                                                      .error!;
                                                }
                                              } else {
                                                await _commerce.add(
                                                  p.slug,
                                                  selected.sku,
                                                  1,
                                                );
                                              }
                                              if (context.mounted && _current) {
                                                setState(() => busy = false);
                                                // PopScope must observe the completed operation first.
                                                await WidgetsBinding
                                                    .instance
                                                    .endOfFrame;
                                                if (!context.mounted ||
                                                    !_current) {
                                                  return;
                                                }
                                                Navigator.pop(context, true);
                                              }
                                            } catch (e) {
                                              if (mounted && _current) {
                                                setState(() {
                                                  if (_commerce.remote &&
                                                      (e is! ApiException ||
                                                          e.status == null ||
                                                          e.status! >= 500 ||
                                                          e.code ==
                                                              'INVALID_RESPONSE')) {
                                                    uncertain = true;
                                                  }
                                                  error = uncertain
                                                      ? 'Chưa xác nhận được thay đổi. Kiểm tra giỏ hàng trước khi thêm tiếp.'
                                                      : '$e';
                                                });
                                              }
                                            } finally {
                                              if (mounted) {
                                                setState(() => busy = false);
                                              }
                                            }
                                          },
                                  ),
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
      ),
    );
  }
}
