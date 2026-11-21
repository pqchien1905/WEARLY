import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/format.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/commerce_json.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';

String productsBack(String? value) {
  final uri = Uri.tryParse(value ?? '');
  return uri != null &&
          !uri.hasScheme &&
          !uri.hasAuthority &&
          uri.path == '/admin/products'
      ? uri.toString()
      : '/admin/products';
}

class ProductFacts {
  ProductFacts(this.product);
  final AdminRecord product;
  List<AdminRecord> get variants =>
      (product['variants'] as List? ?? []).map(commerceMap).toList();
  List<AdminRecord> get selling =>
      variants.where((v) => v['active'] == true).toList();
  int quantity(AdminRecord v) =>
      (v['inventory']?['quantity'] as num?)?.toInt() ?? 0;
  int get stock => selling.fold(0, (sum, v) => sum + quantity(v));
  int get totalStock => variants.fold(0, (sum, v) => sum + quantity(v));
  int get low =>
      selling.where((v) => quantity(v) > 0 && quantity(v) <= 5).length;
  int get out => selling.where((v) => quantity(v) == 0).length;
  bool get published =>
      product['active'] == true &&
      selling.isNotEmpty &&
      (product['images'] as List? ?? []).isNotEmpty;
  String get price {
    if (selling.isEmpty) return 'Chưa có giá bán';
    final prices = selling.map((v) => vnd(v['price'])).toList()..sort();
    return prices.first == prices.last
        ? money(prices.first)
        : '${money(prices.first)} – ${money(prices.last)}';
  }

  String get stockLabel => selling.isEmpty
      ? 'Chưa có SKU đang bán'
      : stock == 0
      ? 'Hết hàng'
      : low > 0
      ? 'Có SKU sắp hết'
      : 'Còn hàng';
}

Widget productStatus(AdminRecord p) {
  final facts = ProductFacts(p);
  return AdminStatus(
    p['active'] != true
        ? 'Đã ẩn'
        : facts.published
        ? 'Đang hiển thị'
        : 'Chưa đủ điều kiện',
    color: p['active'] != true
        ? T.muted
        : facts.published
        ? T.success
        : T.warning,
  );
}

Future<void> toggleProduct(
  BuildContext context,
  WidgetRef ref,
  AdminRecord product,
) async {
  final active = product['active'] == true;
  final repo = ref.read(adminRepositoryProvider);
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: active ? 'Ẩn sản phẩm' : 'Bật sản phẩm',
      message: active
          ? 'Ẩn “${product['name']}” khỏi cửa hàng? Đơn đã đặt và tồn kho được giữ nguyên.'
          : 'Bật “${product['name']}”? Sản phẩm cần có ảnh và ít nhất một SKU đang bán để xuất hiện tại cửa hàng.',
      reload: () => refreshAdmin(ref),
      submit: () async {
        await repo.saveProduct(product['id'], {
          'active': !active,
          if (product['updatedAt'] != null)
            'expectedUpdatedAt': product['updatedAt'],
        });
      },
    ),
  );
  if (context.mounted && changed == true) {
    refreshAdmin(ref);
    ref.read(catalogRevisionProvider.notifier).refresh();
    toast(context, active ? 'Đã ẩn sản phẩm.' : 'Đã bật sản phẩm.');
  }
}

Future<bool> deleteProduct(
  BuildContext context,
  WidgetRef ref,
  AdminRecord product,
) async {
  final repo = ref.read(adminRepositoryProvider);
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminMutationDialog(
      title: 'Xóa sản phẩm?',
      submitLabel: 'Xác nhận xóa',
      destructive: true,
      message:
          'Xóa vĩnh viễn “${product['name']}” cùng các biến thể, tồn kho và bộ ảnh khỏi danh sách sản phẩm? Thao tác này không thể hoàn tác.\n\n'
          'Sản phẩm có đơn hàng, lịch sử kho, đánh giá, lượt thử đồ hoặc đang trong giỏ hàng sẽ được bảo vệ. Bạn có thể dùng “Ẩn sản phẩm” với những sản phẩm này.',
      reload: () => refreshAdmin(ref),
      submit: () async {
        await repo.deleteProduct('${product['id']}', '${product['updatedAt']}');
      },
    ),
  );
  if (!context.mounted || deleted != true) return false;
  refreshAdmin(ref);
  ref.read(catalogRevisionProvider.notifier).refresh();
  toast(context, 'Đã xóa sản phẩm.');
  return true;
}

class ProductSkeleton extends StatelessWidget {
  const ProductSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Đang tải sản phẩm',
    liveRegion: true,
    child: Column(
      children: [
        const LinearProgressIndicator(),
        for (var i = 0; i < 4; i++)
          Container(
            height: 86,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: T.line.withValues(alpha: .35),
              borderRadius: T.radius,
            ),
          ),
      ],
    ),
  );
}
