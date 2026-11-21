import 'admin_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'order_presentation.dart';
import 'customer_widgets.dart';
import 'customer_actions.dart';
import 'customer_password_dialog.dart';

class RemoteAdminCustomers extends ConsumerStatefulWidget {
  const RemoteAdminCustomers({super.key});
  @override
  ConsumerState<RemoteAdminCustomers> createState() => _CustomersState();
}

class _CustomersState extends ConsumerState<RemoteAdminCustomers> {
  final search = TextEditingController();
  bool initialized = false;
  String? appliedSearch;
  Map<String, String> get params =>
      GoRouterState.of(context).uri.queryParameters;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized || appliedSearch != params['q']) {
      search.text = params['q'] ?? '';
      appliedSearch = params['q'];
      initialized = true;
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void apply(
    Map<String, String?> changes, {
    bool clear = false,
    bool keepPage = false,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    final next = <String, String>{if (!clear) ...params};
    if (clear) search.clear();
    if (!keepPage) next.remove('page');
    for (final entry in changes.entries) {
      if (entry.value == null || entry.value!.isEmpty) {
        next.remove(entry.key);
      } else {
        next[entry.key] = entry.value!;
      }
    }
    context.go(
      Uri(
        path: '/admin/customers',
        queryParameters: next.isEmpty ? null : next,
      ).toString(),
    );
  }

  void open(AdminRecord customer) => context.go(
    Uri(
      path: '/admin/customers/${customer['id']}',
      queryParameters: {'from': GoRouterState.of(context).uri.toString()},
    ).toString(),
  );
  Widget select(
    String label,
    String param,
    Map<String, String> options, {
    String fallback = '',
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$param-${params[param]}'),
    initialValue: options.containsKey(params[param] ?? fallback)
        ? params[param] ?? fallback
        : null,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    items: options.entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: (v) => apply({param: v}),
  );
  @override
  Widget build(BuildContext context) {
    final key = Uri(
      queryParameters: {'page': '1', 'limit': '10', ...params},
    ).query;
    final value = ref.watch(adminCustomersProvider(key)),
        summary = ref.watch(adminCustomerSummaryProvider);
    final filtered = [
      'q',
      'status',
      'orders',
      'registered',
    ].any((p) => (params[p] ?? '').isNotEmpty);
    void reload() {
      ref.invalidate(adminCustomersProvider(key));
      ref.invalidate(adminCustomerSummaryProvider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Quản lý khách hàng',
          'Thông tin tài khoản, lịch sử mua hàng và trạng thái hoạt động.',
          actions: [
            if (canStaff(ref.watch(staffRoleProvider), 'customers.manage'))
              AppButton(
                'Thêm khách hàng',
                icon: Icons.person_add_alt_outlined,
                onPressed: () async {
                  final created = await editCustomer(context, ref);
                  if (mounted && created != null && !isStaff(created['role'])) {
                    open(created);
                  }
                },
              ),
            AppButton(
              'Tải lại',
              icon: Icons.refresh,
              outlined: true,
              busy: value.isLoading || summary.isLoading,
              onPressed: reload,
            ),
          ],
        ),
        AdminAsync(
          value: summary,
          reload: () => ref.invalidate(adminCustomerSummaryProvider),
          builder: (data) => CustomerMetrics(
            compact: true,
            items: [
              (
                label: 'Tổng khách hàng',
                value: adminNumber(data['total']),
                note: 'Toàn bộ tài khoản khách hàng',
                icon: Icons.people_outline,
                action: () => apply({}, clear: true),
              ),
              (
                label: 'Khách hàng mới',
                value: adminNumber(data['newCustomers']),
                note: 'Đăng ký trong 30 ngày gần nhất',
                icon: Icons.person_add_alt_outlined,
                action: () => apply({'registered': '30d'}, clear: true),
              ),
              (
                label: 'Đang hoạt động',
                value: adminNumber(data['active']),
                note: 'Tài khoản được phép đăng nhập',
                icon: Icons.verified_user_outlined,
                action: () => apply({'status': 'active'}, clear: true),
              ),
              (
                label: 'Đã khóa',
                value: adminNumber(data['inactive']),
                note: 'Tạm ngừng quyền truy cập',
                icon: Icons.lock_outline,
                action: () => apply({'status': 'hidden'}, clear: true),
              ),
            ],
          ),
        ),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final input = TextField(
                    controller: search,
                    maxLength: 100,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => apply({'q': search.text.trim()}),
                    decoration: const InputDecoration(
                      labelText: 'Tìm kiếm khách hàng',
                      hintText: 'Họ tên, email, số điện thoại hoặc mã UUID',
                      prefixIcon: Icon(Icons.search),
                      counterText: '',
                    ),
                  );
                  final button = AppButton(
                    'Tìm kiếm',
                    icon: Icons.search,
                    onPressed: () => apply({'q': search.text.trim()}),
                  );
                  return c.maxWidth >= 600
                      ? Row(
                          children: [
                            Expanded(child: input),
                            const SizedBox(width: 12),
                            button,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [input, const SizedBox(height: 12), button],
                        );
                },
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 12,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: c.maxWidth < 540 ? c.maxWidth : 215,
                      child: select('Lịch sử mua hàng', 'orders', {
                        '': 'Mọi khách hàng',
                        'has_orders': 'Đã có đơn hàng',
                        'no_orders': 'Chưa có đơn hàng',
                      }),
                    ),
                    SizedBox(
                      width: c.maxWidth < 540 ? c.maxWidth : 225,
                      child: select('Ngày đăng ký', 'registered', {
                        '': 'Toàn thời gian',
                        '30d': '30 ngày gần nhất',
                      }),
                    ),
                    if (params.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => apply({}, clear: true),
                        icon: const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 18,
                        ),
                        label: const Text('Xóa bộ lọc'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in {
              '': 'Tất cả',
              'active': 'Đang hoạt động',
              'hidden': 'Đã khóa',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: (params['status'] ?? '') == entry.key,
                showCheckmark: false,
                onSelected: (_) => apply({'status': entry.key}),
              ),
          ],
        ),
        const SizedBox(height: 20),
        AdminAsync(
          value: value,
          reload: () => ref.invalidate(adminCustomersProvider(key)),
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${adminNumber(data.total)} khách hàng${filtered ? ' phù hợp bộ lọc' : ''}',
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 235,
                    child: select('Sắp xếp', 'sort', {
                      'newest': 'Mới đăng ký',
                      'oldest': 'Đăng ký lâu nhất',
                      'name_asc': 'Tên A–Z',
                      'name_desc': 'Tên Z–A',
                      'orders_desc': 'Nhiều đơn hàng nhất',
                    }, fallback: 'newest'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (data.items.isEmpty)
                AdminCard(
                  child: StatePanel(
                    title: filtered
                        ? 'Không tìm thấy khách hàng'
                        : data.page > 1
                        ? 'Trang này không có khách hàng'
                        : 'Chưa có khách hàng',
                    message:
                        'Thử từ khóa khác hoặc xóa bộ lọc để xem danh sách.',
                    action: data.page > 1
                        ? AppButton(
                            'Về trang đầu',
                            outlined: true,
                            onPressed: () => apply({}),
                          )
                        : null,
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, c) => c.maxWidth >= 1050
                      ? table(data.items, c.maxWidth)
                      : Column(
                          children: [for (final item in data.items) card(item)],
                        ),
                ),
              const SizedBox(height: 16),
              AdminPagination(
                page: data,
                loading: value.isLoading,
                onPage: (n) => apply({'page': '$n'}, keepPage: true),
                onPageSize: (n) => apply({'limit': '$n'}),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget identity(AdminRecord row) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '${row['name']}',
        style: T.body.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Tooltip(
        message: '${row['id']}',
        child: Text('ID: ${customerCode(row['id'])}', style: T.small),
      ),
    ],
  );
  Widget contact(AdminRecord row, {bool compact = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Tooltip(
        message: '${row['email']}',
        child: Text(
          '${row['email']}',
          style: T.body,
          maxLines: compact ? 1 : null,
          overflow: compact ? TextOverflow.ellipsis : TextOverflow.clip,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        (row['phone'] ?? '').toString().isEmpty
            ? 'Chưa có số điện thoại'
            : '${row['phone']}',
        style: T.small,
      ),
    ],
  );
  Widget table(List<AdminRecord> items, double width) => Container(
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
          columnSpacing: 22,
          horizontalMargin: 16,
          dataRowMinHeight: 90,
          dataRowMaxHeight: double.infinity,
          headingTextStyle: T.small.copyWith(fontWeight: FontWeight.w600),
          columns: const [
            DataColumn(label: Text('Khách hàng / Mã')),
            DataColumn(label: Text('Liên hệ')),
            DataColumn(label: Text('Đăng ký · UTC+7')),
            DataColumn(label: Text('Đơn hàng'), numeric: true),
            DataColumn(label: Text('Trạng thái')),
            DataColumn(label: Text('Thao tác')),
          ],
          rows: items
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 150,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: identity(row),
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 200,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: contact(row, compact: true),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(adminOrderDate(row['createdAt']), style: T.small),
                    ),
                    DataCell(
                      Text('${row['_count']?['orders'] ?? 0}', style: T.body),
                    ),
                    DataCell(customerStatus(row['active'] == true)),
                    DataCell(actions(row)),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
  Widget card(AdminRecord row) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          children: [identity(row), customerStatus(row['active'] == true)],
        ),
        const SizedBox(height: 16),
        contact(row),
        const SizedBox(height: 16),
        Text(
          'Đăng ký ${adminOrderDate(row['createdAt'])} · UTC+7',
          style: T.small,
        ),
        const SizedBox(height: 12),
        if (canStaff(ref.watch(staffRoleProvider), 'customers.manage'))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => editCustomer(context, ref, customer: row),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Chỉnh sửa'),
                ),
                TextButton.icon(
                  onPressed: () => resetCustomerPassword(context, ref, row),
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Đặt lại mật khẩu'),
                ),
                TextButton.icon(
                  onPressed: () => toggleCustomer(context, ref, row),
                  icon: Icon(
                    row['active'] == true
                        ? Icons.lock_outline
                        : Icons.lock_open_outlined,
                    size: 18,
                  ),
                  label: Text(
                    row['active'] == true
                        ? 'Khóa tài khoản'
                        : 'Mở khóa tài khoản',
                  ),
                ),
                TextButton.icon(
                  onPressed: () => deleteCustomer(context, ref, row),
                  style: TextButton.styleFrom(foregroundColor: T.danger),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Xóa tài khoản'),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${row['_count']?['orders'] ?? 0} đơn hàng', style: T.body),
            AppButton(
              'Xem khách hàng',
              outlined: true,
              icon: Icons.arrow_forward,
              onPressed: () => open(row),
            ),
          ],
        ),
      ],
    ),
  );

  Widget actions(AdminRecord row) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Xem khách hàng',
        onPressed: () => open(row),
        icon: const Icon(Icons.arrow_forward, size: 20),
      ),
      if (canStaff(ref.watch(staffRoleProvider), 'customers.manage')) ...[
        IconButton(
          tooltip: 'Chỉnh sửa khách hàng',
          onPressed: () => editCustomer(context, ref, customer: row),
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        IconButton(
          tooltip: 'Đặt lại mật khẩu',
          onPressed: () => resetCustomerPassword(context, ref, row),
          icon: const Icon(Icons.key_outlined, size: 20),
        ),
        IconButton(
          tooltip: row['active'] == true
              ? 'Khóa tài khoản'
              : 'Mở khóa tài khoản',
          onPressed: () => toggleCustomer(context, ref, row),
          icon: Icon(
            row['active'] == true
                ? Icons.lock_outline
                : Icons.lock_open_outlined,
            size: 20,
          ),
        ),
        IconButton(
          tooltip: 'Xóa tài khoản',
          color: T.danger,
          onPressed: () => deleteCustomer(context, ref, row),
          icon: const Icon(Icons.delete_outline, size: 20),
        ),
      ],
    ],
  );
}
