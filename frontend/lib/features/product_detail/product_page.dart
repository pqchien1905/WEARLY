import 'package:flutter/material.dart';
import '../../core/widgets/wishlist_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../../domain/catalog.dart';
import '../../app/commerce_state.dart';
import '../cart/cart_page.dart';
import 'product_gallery.dart';
import 'product_reviews.dart';
import '../../app/api_providers.dart';

final purchaseAnchor = GlobalKey();

class ProductPageView extends ConsumerWidget {
  const ProductPageView({super.key, required this.slug});
  final String slug;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    child: ref
        .watch(productProvider(slug))
        .when(
          data: (p) => p == null
              ? StatePanel(
                  title: 'Thiết kế không còn ở đây',
                  message: 'Sản phẩm đã ẩn hoặc đường dẫn không đúng.',
                  action: AppButton(
                    'Về cửa hàng',
                    onPressed: () => context.go('/shop'),
                  ),
                )
              : ProductDetail(key: ValueKey(p.id), product: p),
          error: (_, _) => StatePanel(
            title: 'Chưa tải được thiết kế',
            message: 'Thử lại để xem giá và lựa chọn size.',
            action: AppButton(
              'Thử lại',
              onPressed: () => ref.invalidate(productProvider(slug)),
            ),
          ),
          loading: () => const LoadingPanel(),
        ),
  );
}

class ProductDetail extends ConsumerStatefulWidget {
  const ProductDetail({super.key, required this.product});
  final Product product;
  @override
  ConsumerState<ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends ConsumerState<ProductDetail> {
  final reviewsAnchor = GlobalKey();
  late String color = widget.product.colors.first;
  String? size, error;
  int quantity = 1;
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final variants = p.variants.where((v) => v.color == color).toList();
    final selected = variants.where((v) => v.size == size).firstOrNull;
    final mobile = MediaQuery.sizeOf(context).width < 800;
    Future<void> add() async {
      if (selected == null) {
        setState(() => error = 'Chọn size trước khi thêm vào giỏ.');
        return;
      }
      setState(() => busy = true);
      try {
        await ref.read(commerceProvider).add(p.slug, selected.sku, quantity);
        if (context.mounted) {
          showCartDrawer(context);
        }
      } catch (e) {
        if (mounted) {
          setState(() => error = '$e');
        }
      } finally {
        if (mounted) {
          setState(() => busy = false);
        }
      }
    }

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.style, style: T.small.copyWith(color: T.accent)),
        const SizedBox(height: 16),
        Text(p.name, style: T.display(mobile ? 32 : 40)),
        const SizedBox(height: 20),
        Text(
          money(selected?.price ?? p.price),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 20),
        Text(p.description, style: T.body.copyWith(color: T.muted)),
        if (ref.watch(remoteApiProvider))
          TextButton.icon(
            onPressed: () {
              final target = reviewsAnchor.currentContext;
              if (target != null) {
                Scrollable.ensureVisible(
                  target,
                  duration: const Duration(milliseconds: 250),
                );
              }
            },
            icon: const Icon(Icons.star_outline_rounded, size: 18),
            label: const Text('Xem đánh giá'),
          ),
        const Divider(height: 48),
        Text(
          'Màu sắc: $color',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: p.colors
              .map(
                (c) => Tooltip(
                  message: c,
                  child: Semantics(
                    selected: color == c,
                    label: 'Màu $c',
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.all(8),
                        side: BorderSide(
                          color: color == c ? T.accent : T.line,
                          width: color == c ? 2 : 1,
                        ),
                      ),
                      onPressed: () => setState(() {
                        color = c;
                        size = null;
                        quantity = 1;
                      }),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(
                            p.variants.firstWhere((v) => v.color == c).colorHex,
                          ),
                          border: Border.all(color: T.line),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          children: [
            const Text(
              'Chọn size',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            TextButton(
              onPressed: () => showSizeGuide(context),
              child: const Text('Xem bảng size'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizeSelector(
          key: purchaseAnchor,
          variants: variants,
          selected: size,
          onSelected: (s) => setState(() {
            size = s;
            error = null;
            quantity = 1;
          }),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: const TextStyle(color: T.danger)),
          ),
        const SizedBox(height: 16),
        Text(
          selected == null
              ? 'Chọn size để xem tồn kho demo.'
              : 'Còn ${selected.stock} sản phẩm · Tồn kho demo',
          style: T.small.copyWith(
            color: selected == null ? T.muted : T.success,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            QuantitySelector(
              value: quantity,
              max: selected?.stock ?? 1,
              onChanged: (v) => setState(() => quantity = v),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton('Thêm vào giỏ', busy: busy, onPressed: add),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (p.tryOn)
              AppButton(
                'Thử đồ (bản demo)',
                outlined: true,
                icon: Icons.checkroom_outlined,
                onPressed: () =>
                    context.go('/virtual-try-on?product=${p.slug}'),
              ),
            WishlistButton(p),
          ],
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Icon(Icons.local_shipping_outlined, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Giao tiêu chuẩn 30.000đ, miễn phí từ 1.500.000đ.',
                style: T.small,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ExpansionTile(
          key: PageStorageKey('product:${p.id}:care'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Chất liệu & chăm sóc', style: T.body),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${p.material}. Giặt nhẹ với nước lạnh, phơi trong bóng râm. Thông tin minh họa.',
                  style: T.body,
                ),
              ),
            ),
          ],
        ),
        ExpansionTile(
          key: PageStorageKey('product:${p.id}:shipping'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Giao hàng & đổi trả', style: T.body),
          children: [
            const Text(
              'Demo: giao trong 3–5 ngày, đổi size trong 7 ngày khi chưa sử dụng. Chính sách cần xác nhận trước khi bán hàng.',
            ),
            TextButton(
              onPressed: () => context.go('/shipping-returns'),
              child: const Text('Xem chính sách demo'),
            ),
          ],
        ),
      ],
    );
    final gallery = ProductGallery(product: p, color: color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => context.go('/shop'),
              child: const Text('Cửa hàng'),
            ),
            const Text(' / ', style: T.small),
            Text(p.name, style: T.small),
          ],
        ),
        const SizedBox(height: 24),
        if (mobile) ...[
          gallery,
          const SizedBox(height: 32),
          info,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: gallery),
              const SizedBox(width: 64),
              Expanded(
                flex: 5,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: info,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 40),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          color: T.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Phối món đồ này theo cách của bạn.', style: T.display(28)),
              const SizedBox(height: 12),
              const Text(
                'Mang thiết kế đang xem đến Stylist để gợi ý cách phối theo dịp, size và ngân sách. Trải nghiệm mô phỏng.',
                style: T.body,
              ),
              const SizedBox(height: 20),
              AppButton(
                'Phối đồ cùng AI',
                outlined: true,
                icon: Icons.auto_awesome_outlined,
                onPressed: () => context.go(
                  Uri(
                    path: '/ai-stylist',
                    queryParameters: {
                      'prompt':
                          'Gợi ý phối đồ cùng ${p.name}, phong cách ${p.style}.',
                    },
                  ).toString(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 64),
        if (ref.watch(remoteApiProvider))
          ProductReviews(key: reviewsAnchor, productId: p.id, slug: p.slug),
        Text('Có thể bạn cũng thích', style: T.display(30)),
        const SizedBox(height: 28),
        ref
            .watch(catalogProvider(''))
            .when(
              data: (page) => ProductGrid(
                page.items.where((item) => item.id != p.id).take(4).toList(),
              ),
              error: (_, _) => const SizedBox(),
              loading: () => const LoadingPanel(),
            ),
        const SizedBox(height: 40),
      ],
    );
  }
}

void showSizeGuide(BuildContext context) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: const Text('Tìm size của bạn'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Số đo cơ thể tham khảo (cm), dữ liệu demo. Try-On không thay thế bảng size.',
          ),
          const SizedBox(height: 20),
          Table(
            border: TableBorder.all(color: T.line),
            children: [
              for (final row in [
                ['Size', 'Ngực', 'Eo', 'Hông'],
                ['S', '82–86', '64–68', '88–92'],
                ['M', '86–90', '68–72', '92–96'],
                ['L', '90–94', '72–76', '96–100'],
                ['XL', '94–98', '76–80', '100–104'],
              ])
                TableRow(
                  children: row
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(s, style: T.small),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [AppButton('Đã hiểu', onPressed: () => Navigator.pop(c))],
  ),
);
