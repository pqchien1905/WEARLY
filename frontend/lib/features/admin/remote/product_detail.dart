import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'order_presentation.dart';
import 'product_widgets.dart';
import 'product_variants.dart';
import 'product_editor_widgets.dart';
import 'product_gallery.dart';

class RemoteAdminProduct extends ConsumerStatefulWidget {
  const RemoteAdminProduct({super.key, required this.id, this.returnTo});
  final String id;
  final String? returnTo;
  @override
  ConsumerState<RemoteAdminProduct> createState() => _ProductDetailState();
}

class _ProductDetailState extends ConsumerState<RemoteAdminProduct> {
  final search = TextEditingController();
  final overviewAnchor = GlobalKey(),
      variantsAnchor = GlobalKey(),
      recordAnchor = GlobalKey();
  String status = '', stock = '';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RemoteAdminProduct oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      search.clear();
      status = stock = '';
    }
  }

  void jumpTo(GlobalKey key) {
    if (key.currentContext case final target?) {
      Scrollable.ensureVisible(
        target,
        alignment: .04,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
      );
    }
  }

  void clearFilters() => setState(() {
    search.clear();
    status = stock = '';
  });

  @override
  Widget build(BuildContext context) {
    final key = (kind: 'products', id: widget.id),
        value = ref.watch(
          adminDetailProvider((kind: 'products', id: widget.id)),
        );
    final back = productsBack(widget.returnTo),
        canWrite = canStaff(ref.watch(staffRoleProvider), 'catalog.write');
    if (value.error case ApiException(status: 404)) {
      return StatePanel(
        title: 'Không tìm thấy sản phẩm',
        message: 'Sản phẩm không còn tồn tại hoặc đường dẫn không đúng.',
        action: AppButton(
          'Về danh sách sản phẩm',
          onPressed: () => context.go(back),
        ),
      );
    }
    return AdminAsync(
      value: value,
      reload: () => ref.invalidate(adminDetailProvider(key)),
      builder: (p) {
        final facts = ProductFacts(p), images = p['images'] as List? ?? [];
        final edit = Uri(
          path: '/admin/products/${widget.id}/edit',
          queryParameters: {'from': back},
        ).toString();
        final term = search.text.trim().toLowerCase();
        final shown = facts.variants.where((v) {
          final quantity = facts.quantity(v);
          return '${v['sku']} ${v['size']} ${v['color']}'
                  .toLowerCase()
                  .contains(term) &&
              (status.isEmpty ||
                  (v['active'] == true) == (status == 'active')) &&
              (stock.isEmpty ||
                  switch (stock) {
                    'low' => quantity > 0 && quantity <= 5,
                    'out' => quantity == 0,
                    _ => quantity > 0,
                  });
        }).toList();
        final information = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                productStatus(p),
                Text(
                  '${p['category']['name']} / ${p['brand']['name']}',
                  style: T.small,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SelectableText(
              '${p['name']}',
              style: T
                  .display(28)
                  .copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.6,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 24),
            const Text('Giá bán', style: T.small),
            const SizedBox(height: 4),
            Text(
              facts.price,
              style: T.body.copyWith(
                fontSize: 26,
                color: T.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Text('Theo các biến thể đang bán', style: T.small),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, c) => Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final item in [
                    ('Tồn kho đang bán', '${facts.stock}', facts.stockLabel),
                    (
                      'Biến thể đang bán',
                      '${facts.selling.length}/${facts.variants.length}',
                      '${facts.totalStock} đơn vị trong toàn bộ kho',
                    ),
                  ])
                    SizedBox(
                      width: c.maxWidth >= 400
                          ? (c.maxWidth - 16) / 2
                          : c.maxWidth,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        color: T.canvas,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$1, style: T.small),
                            const SizedBox(height: 4),
                            Text(
                              item.$2,
                              style: T.body.copyWith(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(item.$3, style: T.small),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _property(
              'Kích cỡ',
              facts.variants.map((v) => '${v['size']}').toSet().join(' · '),
            ),
            const SizedBox(height: 12),
            _property(
              'Màu sắc',
              facts.variants.map((v) => '${v['color']}').toSet().join(' · '),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (facts.published)
                  AppButton(
                    'Xem tại cửa hàng',
                    outlined: true,
                    icon: Icons.open_in_new,
                    onPressed: () => context.go('/products/${p['slug']}'),
                  ),
                if (canWrite)
                  AppButton(
                    p['active'] == true ? 'Ẩn sản phẩm' : 'Bật sản phẩm',
                    outlined: true,
                    icon: p['active'] == true
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    onPressed: () => toggleProduct(context, ref, p),
                  ),
              ],
            ),
          ],
        );
        final description = ProductEditorSection(
          title: 'Thông tin sản phẩm',
          description: 'Nội dung và thuộc tính tại cửa hàng.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _property('Mô tả', '${p['description'] ?? ''}'),
              const Divider(height: 32),
              _property('Chất liệu', '${p['material'] ?? ''}'),
              const SizedBox(height: 20),
              _property('Phong cách', '${p['style'] ?? ''}'),
              const SizedBox(height: 20),
              _property(
                'Thử đồ AI',
                p['tryOnSupported'] == true ? 'Được hỗ trợ' : 'Không áp dụng',
              ),
            ],
          ),
        );
        final publication = ProductEditorSection(
          title: 'Trạng thái bán hàng',
          description: 'Điều kiện hiển thị tại cửa hàng.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: productStatus(p)),
              const SizedBox(height: 10),
              ProductEditorCheck(
                'Sản phẩm được bật',
                complete: p['active'] == true,
              ),
              ProductEditorCheck(
                'Có ảnh sản phẩm',
                complete: images.isNotEmpty,
              ),
              ProductEditorCheck(
                'Có biến thể đang bán',
                complete: facts.selling.isNotEmpty,
              ),
              const SizedBox(height: 20),
              Text(
                facts.published
                    ? facts.stock == 0
                          ? 'Sản phẩm đang hiển thị nhưng các biến thể đang bán đã hết hàng.'
                          : 'Khách hàng có thể xem và chọn các biến thể đang bán.'
                    : 'Hoàn tất các điều kiện trên để sản phẩm xuất hiện tại cửa hàng.',
                style: T.small,
              ),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminHeading(
              'Chi tiết sản phẩm',
              'Bộ ảnh, thông tin bán hàng và tồn kho theo từng biến thể.',
              actions: [
                AppButton(
                  'Về danh sách sản phẩm',
                  icon: Icons.arrow_back,
                  outlined: true,
                  onPressed: () => context.go(back),
                ),
                if (canWrite)
                  AppButton(
                    'Chỉnh sửa sản phẩm',
                    icon: Icons.edit_outlined,
                    onPressed: () => context.go(edit),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => jumpTo(overviewAnchor),
                        child: const Text('Tổng quan'),
                      ),
                      TextButton(
                        onPressed: () => jumpTo(variantsAnchor),
                        child: Text('Biến thể (${facts.variants.length})'),
                      ),
                      TextButton(
                        onPressed: () => jumpTo(recordAnchor),
                        child: const Text('Hồ sơ sản phẩm'),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: value.isLoading
                            ? null
                            : () => ref.invalidate(adminDetailProvider(key)),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Tải lại'),
                      ),
                      if (canWrite)
                        PopupMenuButton<String>(
                          tooltip: 'Thao tác sản phẩm',
                          onSelected: (_) async {
                            if (await deleteProduct(context, ref, p) &&
                                context.mounted) {
                              context.go(back);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'Xóa sản phẩm',
                                style: TextStyle(color: T.danger),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            AdminCard(
              key: overviewAnchor,
              child: LayoutBuilder(
                builder: (context, c) {
                  final gallery = ProductDetailGallery(
                    key: ValueKey(widget.id),
                    images: images,
                    productName: '${p['name']}',
                  );
                  return c.maxWidth >= 850
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: gallery),
                            const SizedBox(width: 32),
                            Expanded(flex: 6, child: information),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            gallery,
                            const SizedBox(height: 28),
                            information,
                          ],
                        );
                },
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) => c.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: description),
                        const SizedBox(width: 24),
                        Expanded(flex: 4, child: publication),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [description, publication],
                    ),
            ),
            ProductVariantSection(
              key: variantsAnchor,
              product: p,
              tableOnWide: true,
              visibleVariants: shown,
              controls: facts.variants.isEmpty
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, c) => Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              SizedBox(
                                width: c.maxWidth >= 700
                                    ? c.maxWidth - 452
                                    : c.maxWidth,
                                child: TextField(
                                  controller: search,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Tìm biến thể',
                                    hintText: 'SKU, màu hoặc kích cỡ',
                                    prefixIcon: Icon(Icons.search),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: c.maxWidth >= 700 ? 210 : c.maxWidth,
                                child: _filter('Trạng thái biến thể', status, {
                                  '': 'Tất cả trạng thái',
                                  'active': 'Đang bán',
                                  'hidden': 'Đã ẩn',
                                }, (v) => setState(() => status = v)),
                              ),
                              SizedBox(
                                width: c.maxWidth >= 700 ? 210 : c.maxWidth,
                                child: _filter('Tồn kho biến thể', stock, {
                                  '': 'Tất cả tồn kho',
                                  'in': 'Còn hàng',
                                  'low': 'Sắp hết (1–5)',
                                  'out': 'Hết hàng',
                                }, (v) => setState(() => stock = v)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Hiển thị ${shown.length}/${facts.variants.length} biến thể',
                              style: T.small,
                            ),
                            if (term.isNotEmpty ||
                                status.isNotEmpty ||
                                stock.isNotEmpty)
                              TextButton.icon(
                                onPressed: clearFilters,
                                icon: const Icon(
                                  Icons.filter_alt_off_outlined,
                                  size: 18,
                                ),
                                label: const Text('Xóa bộ lọc biến thể'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
            ),
            ProductEditorSection(
              key: recordAnchor,
              title: 'Hồ sơ sản phẩm',
              description: 'Thông tin định danh và thời gian cập nhật.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _property('Mã sản phẩm', widget.id),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: widget.id));
                        if (context.mounted) {
                          toast(context, 'Đã sao chép mã sản phẩm.');
                        }
                      },
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: const Text('Sao chép mã'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _property('Đường dẫn sản phẩm', '/products/${p['slug']}'),
                  const Divider(height: 32),
                  Wrap(
                    spacing: 40,
                    runSpacing: 16,
                    children: [
                      _property(
                        'Ngày tạo (UTC+7)',
                        adminOrderDate(p['createdAt']),
                      ),
                      _property(
                        'Cập nhật gần nhất (UTC+7)',
                        adminOrderDate(p['updatedAt']),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filter(
    String label,
    String selected,
    Map<String, String> choices,
    ValueChanged<String> change,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$selected'),
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: choices.entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) => change(v ?? ''),
  );
  Widget _property(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: T.small),
      const SizedBox(height: 6),
      SelectableText(
        value.trim().isEmpty ? 'Chưa bổ sung' : value,
        style: T.body,
      ),
    ],
  );
}
