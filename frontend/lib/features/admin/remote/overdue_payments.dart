import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/api_providers.dart';
import '../../../data/remote_payments.dart';
import 'admin_widgets.dart';

final overduePaymentsProvider = FutureProvider.autoDispose<List>(
  (ref) async =>
      await ref.watch(adminApiClientProvider).get('admin/payments/overdue')
          as List,
);

class OverduePayments extends ConsumerStatefulWidget {
  const OverduePayments({super.key});
  @override
  ConsumerState<OverduePayments> createState() => _OverduePaymentsState();
}

class _OverduePaymentsState extends ConsumerState<OverduePayments> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    onExpansionChanged: (value) => setState(() => expanded = value),
    title: const Text('Đơn online quá thời gian giữ hàng'),
    children: [
      if (expanded)
        AdminAsync(
          value: ref.watch(overduePaymentsProvider),
          reload: () => ref.invalidate(overduePaymentsProvider),
          builder: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Hệ thống xác minh trước khi trả tồn kho. Nếu chưa rõ kết quả, đơn tiếp tục được giữ. Danh sách tối đa 100 đơn cũ nhất.',
                ),
              ),
              if (rows.isEmpty)
                const ListTile(title: Text('Không có đơn quá hạn.')),
              for (final row in rows)
                ListTile(
                  title: Text(
                    '${row['code']} · ${paymentProviderName(row['payment']['provider'])}',
                  ),
                  subtitle: Text('Đặt lúc ${row['createdAt']}'),
                  trailing: TextButton(
                    onPressed: () => context.go('/admin/orders/${row['id']}'),
                    child: const Text('Xem đơn'),
                  ),
                ),
              TextButton(
                onPressed: () => ref.invalidate(overduePaymentsProvider),
                child: const Text('Tải lại danh sách'),
              ),
            ],
          ),
        ),
    ],
  );
}
