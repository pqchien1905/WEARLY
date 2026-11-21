import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';
import '../../../core/network/api_client.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'order_presentation.dart';
import 'inventory_widgets.dart';
import 'inventory_overview.dart';

class RemoteInventoryDetail extends ConsumerStatefulWidget {
  const RemoteInventoryDetail({super.key, required this.id, this.returnTo});
  final String id;
  final String? returnTo;
  @override
  ConsumerState<RemoteInventoryDetail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<RemoteInventoryDetail> {
  final from = TextEditingController(), to = TextEditingController();
  final form = GlobalKey<FormState>();
  String? synced;
  Map<String, String> get params =>
      GoRouterState.of(context).uri.queryParameters;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = '${params['fromDate']}|${params['toDate']}';
    if (key != synced) {
      from.text = params['fromDate'] ?? '';
      to.text = params['toDate'] ?? '';
      synced = key;
    }
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  void apply(Map<String, String?> changes, {bool keepPage = false}) {
    final next = {...params};
    if (!keepPage) next.remove('page');
    for (final e in changes.entries) {
      if (e.value == null || e.value!.isEmpty) {
        next.remove(e.key);
      } else {
        next[e.key] = e.value!;
      }
    }
    context.go(
      Uri(
        path: '/admin/inventory/${widget.id}',
        queryParameters: next,
      ).toString(),
    );
  }

  String? date(String? value) {
    if (value == null || value.isEmpty) return null;
    final d = DateTime.tryParse(value);
    return !RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(value) ||
            d == null ||
            d.toIso8601String().substring(0, 10) != value
        ? 'Nhập ngày YYYY-MM-DD hợp lệ.'
        : null;
  }

  Future<void> pickDate(TextEditingController controller) async {
    final fallback = DateTime.now().toUtc().add(const Duration(hours: 7));
    final initial = date(controller.text) == null
        ? DateTime.tryParse(controller.text) ?? fallback
        : fallback;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
      helpText: 'Chọn ngày (UTC+7)',
      cancelText: 'Hủy',
      confirmText: 'Chọn',
      fieldLabelText: 'Ngày',
    );
    if (mounted && selected != null) {
      controller.text = selected.toIso8601String().substring(0, 10);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (kind: 'inventory', id: widget.id),
        value = ref.watch(
          adminDetailProvider((kind: 'inventory', id: widget.id)),
        );
    void reload() => refreshAdmin(ref);
    if (value.error case ApiException(status: 404)) {
      return StatePanel(
        title: 'Không tìm thấy bản ghi kho',
        message: 'Kiểm tra đường dẫn hoặc quay về danh sách.',
        action: AppButton(
          'Về danh sách kho',
          onPressed: () => context.go(inventoryBack(widget.returnTo)),
        ),
      );
    }
    final query = Uri(
      queryParameters: {
        'page': params['page'] ?? '1',
        'limit': '10',
        if (params['type'] != null) 'type': params['type']!,
        if (params['fromDate'] != null) 'from': params['fromDate']!,
        if (params['toDate'] != null) 'to': params['toDate']!,
      },
    ).query;
    final history = ref.watch(
      adminInventoryHistoryProvider((id: widget.id, query: query)),
    );
    final loaded = history.asData?.value;
    if (loaded != null &&
        !history.isLoading &&
        (int.tryParse(params['page'] ?? '1') ?? 1) != loaded.page) {
      final original = GoRouterState.of(context).uri.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GoRouterState.of(context).uri.toString() == original) {
          context.replace(
            Uri(
              path: '/admin/inventory/${widget.id}',
              queryParameters: {...params, 'page': '${loaded.page}'},
            ).toString(),
          );
        }
      });
    }
    final role = ref.watch(staffRoleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Chi tiết tồn kho',
          'Số lượng khả dụng và lịch sử biến động theo SKU.',
          actions: [
            AppButton(
              'Về danh sách kho',
              outlined: true,
              onPressed: () => context.go(inventoryBack(widget.returnTo)),
            ),
            AppButton(
              'Tải lại',
              outlined: true,
              icon: Icons.refresh,
              onPressed: reload,
            ),
          ],
        ),
        AdminAsync(
          value: value,
          reload: () => ref.invalidate(adminDetailProvider(key)),
          builder: (row) => InventoryOverview(row: row),
        ),
        const AdminHeading(
          'Lịch sử biến động',
          'Ghi nhận từ giao dịch thực tế. Lịch sử chỉ được xem, không sửa hoặc xóa.',
        ),
        AdminCard(
          child: Form(
            key: form,
            child: LayoutBuilder(
              builder: (context, c) {
                final width = c.maxWidth < 650
                    ? c.maxWidth
                    : (c.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(params['type']),
                        initialValue:
                            const [
                              'in',
                              'out',
                              'admin',
                              'order',
                              'cancel',
                              'return',
                            ].contains(params['type'])
                            ? params['type']
                            : '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Loại biến động',
                        ),
                        items:
                            const {
                                  '': 'Tất cả biến động',
                                  'in': 'Tăng kho',
                                  'out': 'Giảm kho',
                                  'admin': 'Điều chỉnh thủ công',
                                  'order': 'Đặt hàng',
                                  'cancel': 'Hủy đơn',
                                  'return': 'Hoàn trả',
                                }.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) => apply({'type': v}),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextFormField(
                        controller: from,
                        decoration: InputDecoration(
                          labelText: 'Từ ngày',
                          hintText: 'YYYY-MM-DD',
                          suffixIcon: IconButton(
                            tooltip: 'Chọn ngày bắt đầu',
                            onPressed: () => pickDate(from),
                            icon: const Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                        validator: date,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextFormField(
                        controller: to,
                        decoration: InputDecoration(
                          labelText: 'Đến ngày',
                          hintText: 'YYYY-MM-DD',
                          suffixIcon: IconButton(
                            tooltip: 'Chọn ngày kết thúc',
                            onPressed: () => pickDate(to),
                            icon: const Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                        validator: (v) =>
                            date(v) ??
                            (v != null &&
                                    v.isNotEmpty &&
                                    from.text.isNotEmpty &&
                                    from.text.compareTo(v) > 0
                                ? 'Ngày kết thúc phải sau ngày bắt đầu.'
                                : null),
                      ),
                    ),
                    AppButton(
                      'Lọc lịch sử',
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          apply({'fromDate': from.text, 'toDate': to.text});
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () {
                        form.currentState?.reset();
                        from.clear();
                        to.clear();
                        apply({'type': null, 'fromDate': null, 'toDate': null});
                      },
                      child: const Text('Xóa bộ lọc lịch sử'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Người thực hiện và số lượng trước/sau hiển thị khi có nhật ký liên kết. Dữ liệu cũ không đủ thông tin được để trống, không suy diễn.',
            style: T.small,
          ),
        ),
        AdminAsync(
          value: history,
          reload: reload,
          builder: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page.summary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Biến động trong bộ lọc', style: T.small),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          AdminStatus(
                            'Tăng ${adminNumber(page.summary['incoming'])}',
                            color: T.success,
                          ),
                          AdminStatus(
                            'Giảm ${adminNumber(page.summary['outgoing'])}',
                            color: T.warning,
                          ),
                          AdminStatus(
                            'Chênh lệch ${adminNumber(page.summary['net'])} đơn vị',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (page.items.isEmpty)
                const StatePanel(
                  title: 'Chưa có biến động phù hợp',
                  message: 'Thử đổi bộ lọc hoặc khoảng ngày.',
                )
              else
                for (final movement in page.items) movementCard(movement, role),
              InventoryPager(
                page: page,
                go: (n) => apply({'page': '$n'}, keepPage: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget movementCard(AdminRecord m, String? role) {
    final d = m['delta'] as int, a = m['adjustment'], reason = '${m['reason']}';
    final label = reason.startsWith('ADMIN: ')
        ? switch (a?['operation']) {
            'in' => 'Nhập kho',
            'out' => 'Xuất kho',
            'count' => 'Kiểm kê tồn kho',
            _ => 'Điều chỉnh thủ công',
          }
        : switch (reason) {
            'ORDER' => 'Đặt hàng',
            'CANCEL' => 'Hủy đơn',
            'CUSTOMER_RETURN' => 'Khách trả hàng',
            'SHIPMENT_RETURN' => 'Giao hàng hoàn về',
            _ => reason,
          };
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminStatus(
                '${d > 0 ? '+' : ''}${adminNumber(d)} đơn vị',
                color: d > 0 ? T.success : T.warning,
              ),
              Text(label, style: T.body.copyWith(fontWeight: FontWeight.w600)),
              Text(adminOrderDate(m['createdAt']), style: T.small),
            ],
          ),
          const SizedBox(height: 10),
          if (a != null)
            Text(
              'Trước: ${a['before'] ?? '—'} → Sau: ${a['after'] ?? '—'} · Người thực hiện: ${a['actor'] ?? 'Không còn thông tin'}',
              style: T.body,
            ),
          if (reason.startsWith('ADMIN: '))
            Text('Lý do: ${reason.substring(7)}', style: T.small),
          if (m['order'] != null)
            canStaff(role, 'orders.read')
                ? TextButton(
                    onPressed: () =>
                        context.go('/admin/orders/${m['order']['id']}'),
                    child: Text('Đơn ${m['order']['code']}'),
                  )
                : Text('Đơn ${m['order']['code']}', style: T.small),
        ],
      ),
    );
  }
}
