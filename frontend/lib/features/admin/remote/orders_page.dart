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
import 'overdue_payments.dart';

class RemoteAdminOrders extends ConsumerStatefulWidget {
  const RemoteAdminOrders({super.key});
  @override
  ConsumerState<RemoteAdminOrders> createState() => _RemoteAdminOrdersState();
}

class _RemoteAdminOrdersState extends ConsumerState<RemoteAdminOrders> {
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
    bool preservePage = false,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    final next = <String, String>{if (!clear) ...params};
    if (clear) search.clear();
    if (!preservePage) next.remove('page');
    for (final entry in changes.entries) {
      if (entry.value == null || entry.value!.isEmpty) {
        next.remove(entry.key);
      } else {
        next[entry.key] = entry.value!;
      }
    }
    context.go(
      Uri(
        path: '/admin/orders',
        queryParameters: next.isEmpty ? null : next,
      ).toString(),
    );
  }

  void open(AdminRecord order) => context.go(
    Uri(
      path: '/admin/orders/${order['id']}',
      queryParameters: {'from': GoRouterState.of(context).uri.toString()},
    ).toString(),
  );
  Future<void> dates() async {
    final from = DateTime.tryParse(params['from'] ?? ''),
        to = DateTime.tryParse(params['to'] ?? '');
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
      initialDateRange:
          from != null &&
              to != null &&
              !from.isAfter(to) &&
              from.year >= 2000 &&
              to.year <= 2099
          ? DateTimeRange(start: from, end: to)
          : null,
      helpText: 'Lọc theo ngày đặt · UTC+7',
      saveText: 'Áp dụng',
      confirmText: 'Áp dụng',
      fieldStartHintText: 'dd/mm/yyyy',
      fieldEndHintText: 'dd/mm/yyyy',
      cancelText: 'Hủy',
    );
    if (!mounted || chosen == null) return;
    String iso(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    apply({'from': iso(chosen.start), 'to': iso(chosen.end)});
  }

  @override
  Widget build(BuildContext context) {
    final query = <String, String>{'page': '1', 'limit': '10', ...params};
    final key = Uri(queryParameters: query).query;
    final result = ref.watch(adminOrdersProvider(key));
    final page = int.tryParse(query['page']!) ?? 1;
    final filtered = [
      'q',
      'customerId',
      'status',
      'provider',
      'paymentStatus',
      'dataKind',
      'from',
      'to',
    ].any((p) => (params[p] ?? '').isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Quản lý đơn hàng',
          'Theo dõi từng đơn, xử lý giao hàng và kiểm soát thanh toán.',
          actions: [
            AppButton(
              'Tải lại',
              icon: Icons.refresh,
              outlined: true,
              busy: result.isLoading,
              onPressed: () => ref.invalidate(adminOrdersProvider(key)),
            ),
          ],
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
                      labelText: 'Tìm kiếm đơn hàng',
                      hintText:
                          'Mã đơn, người nhận, số điện thoại, email hoặc SKU',
                      prefixIcon: Icon(Icons.search),
                      counterText: '',
                    ),
                  );
                  final submit = AppButton(
                    'Tìm kiếm',
                    icon: Icons.search,
                    onPressed: () => apply({'q': search.text.trim()}),
                  );
                  return c.maxWidth >= 600
                      ? Row(
                          children: [
                            Expanded(child: input),
                            const SizedBox(width: 12),
                            submit,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [input, const SizedBox(height: 12), submit],
                        );
                },
              ),
              const SizedBox(height: 20),
              if (params['customerId'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Đang lọc đơn của khách hàng ID: ${params['customerId']}',
                    style: T.small,
                  ),
                ),
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 12,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: c.maxWidth < 540 ? c.maxWidth : 210,
                      child: _select('Phân loại', 'dataKind', {
                        '': 'Đơn kinh doanh',
                        'test': 'Đơn thử nghiệm',
                        'all': 'Tất cả dữ liệu',
                      }),
                    ),
                    SizedBox(
                      width: c.maxWidth < 540 ? c.maxWidth : 210,
                      child: _select('Phương thức', 'provider', {
                        '': 'Mọi phương thức',
                        ...adminPaymentProviders,
                      }),
                    ),
                    SizedBox(
                      width: c.maxWidth < 540 ? c.maxWidth : 240,
                      child: _select('Thanh toán', 'paymentStatus', {
                        '': 'Mọi thanh toán',
                        ...adminPaymentStatuses,
                      }),
                    ),
                    AppButton(
                      params['from'] == null && params['to'] == null
                          ? 'Ngày đặt · UTC+7'
                          : '${params['from'] ?? 'Từ đầu'} → ${params['to'] ?? 'Đến nay'}',
                      outlined: true,
                      icon: Icons.date_range_outlined,
                      onPressed: dates,
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
            for (final status in {'': 'Tất cả', ...adminOrderStatuses}.entries)
              ChoiceChip(
                showCheckmark: false,
                label: Text(
                  '${status.value}${result.value?.statusCounts.isNotEmpty == true ? ' (${status.key.isEmpty ? result.value!.statusCounts.values.fold(0, (a, b) => a + b) : result.value!.statusCounts[status.key] ?? 0})' : ''}',
                ),
                selected: (params['status'] ?? '') == status.key,
                onSelected: (_) => apply({'status': status.key}),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (canStaff(ref.watch(staffRoleProvider), 'payments.manage'))
          const OverduePayments(),
        AdminAsync(
          value: result,
          reload: () => ref.invalidate(adminOrdersProvider(key)),
          builder: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) => Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        '${adminNumber(data.total)} đơn hàng${filtered ? ' phù hợp bộ lọc' : ''}',
                        style: T.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(
                      width: c.maxWidth < 260 ? c.maxWidth : 235,
                      child: _select(
                        'Sắp xếp',
                        'sort',
                        adminOrderSorts,
                        fallback: 'newest',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (data.items.isEmpty)
                AdminCard(
                  child: StatePanel(
                    title: filtered
                        ? 'Không tìm thấy đơn hàng'
                        : page > 1
                        ? 'Trang này không có đơn hàng'
                        : 'Chưa có đơn hàng',
                    message: filtered
                        ? 'Thử từ khóa khác hoặc bỏ bớt điều kiện lọc.'
                        : 'Đơn hàng mới sẽ xuất hiện tại đây sau khi khách đặt hàng.',
                    action: page > 1
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
                  builder: (context, c) => c.maxWidth >= 1000
                      ? _table(data.items, c.maxWidth)
                      : Column(
                          children: [
                            for (final item in data.items) _card(item),
                          ],
                        ),
                ),
              const SizedBox(height: 16),
              AdminPagination(
                page: data,
                loading: result.isLoading,
                onPage: (n) => apply({'page': '$n'}, preservePage: true),
                onPageSize: (n) => apply({'limit': '$n'}),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _select(
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
    items: [
      for (final option in options.entries)
        DropdownMenuItem(
          value: option.key,
          child: Text(option.value, style: T.body),
        ),
    ],
    onChanged: (value) => apply({param: value}),
  );
  Widget _identity(AdminRecord item) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${item['code'] ?? item['id']}',
        style: T.body.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(adminOrderDate(item['createdAt']), style: T.small),
    ],
  );
  Widget _customer(AdminRecord item) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '${item['addressSnapshot']?['recipient'] ?? item['user']?['name'] ?? 'Khách hàng'}',
        style: T.body,
      ),
      Text('${item['addressSnapshot']?['phone'] ?? ''}', style: T.small),
    ],
  );
  Widget _payment(AdminRecord item) {
    final payment = item['payment'] as Map? ?? {};
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        adminPaymentBadge(payment),
        const SizedBox(height: 4),
        Text(
          adminPaymentProviders[payment['provider']] ?? 'Chưa xác định',
          style: T.small,
        ),
      ],
    );
  }

  Widget _card(AdminRecord item) => AdminCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [_identity(item), AdminStatus.order(item['status'])],
        ),
        const Divider(height: 28, color: T.line),
        _customer(item),
        if ((item['items'] as List? ?? []).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${item['items'][0]['name']}${(item['_count']?['items'] ?? (item['items'] as List).length) > 1 ? ' · ${item['_count']?['items'] ?? (item['items'] as List).length} mặt hàng' : ''}',
              style: T.small,
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _payment(item),
            Text(
              adminMoney(item['total']),
              style: T.body.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => open(item),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Xem đơn hàng'),
          ),
        ),
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
          horizontalMargin: 16,
          columnSpacing: 18,
          dataRowMinHeight: 100,
          dataRowMaxHeight: double.infinity,
          columns: const [
            DataColumn(label: Text('Mã đơn / Ngày đặt')),
            DataColumn(label: Text('Người nhận')),
            DataColumn(label: Text('Tổng tiền')),
            DataColumn(label: Text('Thanh toán')),
            DataColumn(label: Text('Trạng thái')),
            DataColumn(label: Text('Chi tiết')),
          ],
          rows: [
            for (final item in items)
              DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 165,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: _identity(item),
                      ),
                    ),
                  ),
                  DataCell(SizedBox(width: 175, child: _customer(item))),
                  DataCell(
                    Text(
                      adminMoney(item['total']),
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(_payment(item)),
                  DataCell(AdminStatus.order(item['status'])),
                  DataCell(
                    IconButton(
                      tooltip: 'Xem đơn hàng',
                      onPressed: () => open(item),
                      icon: const Icon(Icons.arrow_forward, size: 20),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
