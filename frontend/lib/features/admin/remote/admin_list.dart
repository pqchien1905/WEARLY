import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'inventory_actions.dart';

class RemoteAdminList extends ConsumerStatefulWidget {
  const RemoteAdminList({super.key, required this.kind});
  final String kind;
  @override
  ConsumerState<RemoteAdminList> createState() => _RemoteAdminListState();
}

class _RemoteAdminListState extends ConsumerState<RemoteAdminList> {
  final search = TextEditingController();
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      search.text = GoRouterState.of(context).uri.queryParameters['q'] ?? '';
      initialized = true;
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void navigate({String? status, int page = 1, bool clear = false}) {
    final uri = GoRouterState.of(context).uri;
    final filter = status ?? uri.queryParameters['status'] ?? '';
    final query = clear ? '' : search.text.trim();
    context.go(
      Uri(
        path: uri.path,
        queryParameters: {
          if (query.isNotEmpty) 'q': query,
          if (!clear && filter.isNotEmpty) 'status': filter,
          if (page > 1) 'page': '$page',
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final params = GoRouterState.of(context).uri.queryParameters;
    final page = (int.tryParse(params['page'] ?? '') ?? 1).clamp(1, 10000);
    final status = params['status'] ?? '';
    final query = params['q'] ?? '';
    final key = (kind: widget.kind, page: page, query: query, status: status);
    final value = ref.watch(adminSearchProvider(key));
    final title = {
      'products': 'Sản phẩm',
      'inventory': 'Biến thể & kho',
      'orders': 'Đơn hàng',
      'users': 'Khách hàng',
    }[widget.kind]!;
    final hint = switch (widget.kind) {
      'products' => 'Tên sản phẩm, SKU, danh mục hoặc thương hiệu',
      'inventory' => 'Tên sản phẩm hoặc SKU',
      'orders' => 'Mã đơn, tên khách, email hoặc sản phẩm',
      _ => 'Tên khách hàng, email hoặc số điện thoại',
    };
    final filters = switch (widget.kind) {
      'products' => {'active': 'Đang bật', 'hidden': 'Đã ẩn'},
      'inventory' => {
        'in_stock': 'Còn hàng',
        'low': 'Sắp hết · 1–5',
        'out': 'Hết hàng',
      },
      'orders' => adminOrderStatuses,
      _ => {'active': 'Đang hoạt động', 'hidden': 'Đã khóa'},
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          title,
          switch (widget.kind) {
            'products' =>
              'Quản lý danh mục sản phẩm, giá bán và trạng thái hiển thị.',
            'inventory' => 'Theo dõi từng SKU và điều chỉnh số lượng thực tế.',
            'orders' => 'Xử lý đơn hàng, giao hàng và đối soát thanh toán.',
            _ => 'Tra cứu thông tin khách hàng của cửa hàng.',
          },
          actions: [
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              busy: value.isLoading,
              onPressed: () => ref.invalidate(adminSearchProvider(key)),
            ),
            if (widget.kind == 'products' &&
                canStaff(ref.watch(staffRoleProvider), 'catalog.write'))
              AppButton(
                'Thêm sản phẩm',
                icon: Icons.add,
                onPressed: () => context.go('/admin/products/new'),
              ),
          ],
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final field = TextField(
                    controller: search,
                    maxLength: 100,
                    onSubmitted: (_) => navigate(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Tìm kiếm $title',
                      hintText: hint,
                      prefixIcon: const Icon(Icons.search),
                      counterText: '',
                    ),
                  );
                  final button = AppButton(
                    'Tìm kiếm',
                    icon: Icons.search,
                    onPressed: () => navigate(),
                  );
                  return c.maxWidth >= 540
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: field),
                            const SizedBox(width: 12),
                            button,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [field, const SizedBox(height: 12), button],
                        );
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final filter in {'': 'Tất cả', ...filters}.entries)
                    ChoiceChip(
                      label: Text(filter.value),
                      selected: status == filter.key,
                      onSelected: (_) => navigate(status: filter.key),
                    ),
                  if (query.isNotEmpty || status.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => navigate(clear: true),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Xóa bộ lọc'),
                    ),
                ],
              ),
              if (widget.kind == 'inventory')
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Bộ lọc tồn kho chỉ tính biến thể và sản phẩm đang bật.',
                    style: T.small,
                  ),
                ),
            ],
          ),
        ),
        AdminAsync(
          value: value,
          reload: () => ref.invalidate(adminSearchProvider(key)),
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${adminNumber(data.total)} kết quả${query.isNotEmpty ? ' cho “$query”' : ''} · Trang ${data.page}/${(data.total / data.limit).ceil().clamp(1, 10000)}',
                    style: T.small,
                  ),
                ),
              ),
              if (data.items.isEmpty)
                StatePanel(
                  title: query.isNotEmpty || status.isNotEmpty
                      ? 'Không tìm thấy kết quả'
                      : 'Chưa có dữ liệu',
                  message: query.isNotEmpty || status.isNotEmpty
                      ? 'Thử từ khóa khác hoặc xóa bộ lọc để xem toàn bộ danh sách.'
                      : 'Các bản ghi mới sẽ xuất hiện tại đây.',
                  action: query.isNotEmpty || status.isNotEmpty
                      ? AppButton(
                          'Xóa bộ lọc',
                          outlined: true,
                          onPressed: () => navigate(clear: true),
                        )
                      : null,
                )
              else
                LayoutBuilder(
                  builder: (context, c) => c.maxWidth >= 850
                      ? _table(data.items, c.maxWidth)
                      : Column(
                          children: [
                            for (final item in data.items) _card(item),
                          ],
                        ),
                ),
              const SizedBox(height: 8),
              AdminPagination(
                page: data,
                onPage: (n) => navigate(page: n),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _name(AdminRecord item) => switch (widget.kind) {
    'inventory' => '${item['variant']['product']['name']}',
    'orders' => '${item['code'] ?? item['id']}',
    _ => '${item['name']}',
  };
  String _detail(AdminRecord item) => switch (widget.kind) {
    'products' => '${item['category']['name']} · ${item['brand']['name']}',
    'inventory' =>
      '${item['variant']['sku']} · ${item['variant']['color']} / ${item['variant']['size']}',
    'orders' =>
      '${item['addressSnapshot']?['recipient'] ?? item['user']?['name'] ?? 'Khách hàng'}',
    _ => '${item['email']}',
  };
  String _amount(AdminRecord item) => switch (widget.kind) {
    'products' => '${(item['variants'] as List).length} biến thể',
    'inventory' => '${item['quantity']} sản phẩm',
    'orders' => adminMoney(item['total']),
    _ =>
      '${item['phone'] == '' ? 'Chưa có số điện thoại' : item['phone'] ?? 'Chưa có số điện thoại'}',
  };
  Widget _status(AdminRecord item) {
    if (widget.kind == 'orders') return AdminStatus.order(item['status']);
    if (widget.kind == 'inventory') {
      final active =
          item['variant']['active'] == true &&
          item['variant']['product']['active'] == true;
      final count = item['quantity'] as int;
      return AdminStatus(
        !active
            ? 'Đã ẩn'
            : count == 0
            ? 'Hết hàng'
            : count <= 5
            ? 'Sắp hết'
            : 'Còn hàng',
        color: !active
            ? T.muted
            : count == 0
            ? T.danger
            : count <= 5
            ? T.warning
            : T.success,
      );
    }
    final active = item['active'] != false;
    return AdminStatus(
      widget.kind == 'products'
          ? active
                ? 'Đang bật'
                : 'Đã ẩn'
          : active
          ? 'Đang hoạt động'
          : 'Đã khóa',
      color: active ? T.success : T.muted,
    );
  }

  Widget _action(AdminRecord item) {
    final role = ref.watch(staffRoleProvider);
    return switch (widget.kind) {
      'products' when canStaff(role, 'catalog.write') => TextButton.icon(
        onPressed: () => context.go('/admin/products/${item['id']}/edit'),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Chỉnh sửa sản phẩm'),
      ),
      'inventory' when canStaff(role, 'inventory.write') => TextButton.icon(
        onPressed: () =>
            adjustInventory(context, ref, item, item['variant']['sku']),
        icon: const Icon(Icons.tune, size: 18),
        label: const Text('Điều chỉnh kho'),
      ),
      'orders' => TextButton.icon(
        onPressed: () => context.go('/admin/orders/${item['id']}'),
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: const Text('Xem đơn hàng'),
      ),
      _ => Text(adminDate(item['createdAt']), style: T.small),
    };
  }

  Widget _identity(AdminRecord item, {bool image = true}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (image && widget.kind == 'products') ...[
        SizedBox(
          width: 46,
          height: 60,
          child: (item['images'] as List? ?? []).isEmpty
              ? const ColoredBox(
                  color: T.canvas,
                  child: Icon(Icons.checkroom_outlined, color: T.muted),
                )
              : FashionImage(
                  item['images'][0]['url'],
                  fit: BoxFit.cover,
                  label: _name(item),
                ),
        ),
        const SizedBox(width: 12),
      ],
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _name(item),
              style: T.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(_detail(item), style: T.small),
          ],
        ),
      ),
    ],
  );
  Widget _card(AdminRecord item) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _identity(item),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_amount(item), style: T.body),
            _status(item),
          ],
        ),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerLeft, child: _action(item)),
      ],
    ),
  );
  Widget _table(List<AdminRecord> items, double width) => Container(
    decoration: BoxDecoration(
      color: T.surface,
      border: Border.all(color: T.line),
      borderRadius: T.radius,
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width - 2),
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(T.canvas),
          headingTextStyle: T.small.copyWith(fontWeight: FontWeight.w600),
          horizontalMargin: 20,
          columnSpacing: 24,
          dataRowMinHeight: 96,
          dataRowMaxHeight: 128,
          dividerThickness: .6,
          columns: [
            DataColumn(
              label: Text(
                widget.kind == 'orders'
                    ? 'Đơn hàng / Khách hàng'
                    : widget.kind == 'users'
                    ? 'Thông tin khách hàng'
                    : 'Sản phẩm',
              ),
            ),
            DataColumn(
              label: Text(
                widget.kind == 'orders'
                    ? 'Tổng tiền'
                    : widget.kind == 'users'
                    ? 'Liên hệ'
                    : 'Số lượng',
              ),
            ),
            const DataColumn(label: Text('Trạng thái')),
            DataColumn(
              label: Text(
                widget.kind == 'users' ? 'Ngày tham gia' : 'Thao tác',
              ),
            ),
          ],
          rows: [
            for (final item in items)
              DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: (width * .34).clamp(240, 430),
                      child: _identity(item),
                    ),
                  ),
                  DataCell(Text(_amount(item), style: T.body)),
                  DataCell(_status(item)),
                  DataCell(_action(item)),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
