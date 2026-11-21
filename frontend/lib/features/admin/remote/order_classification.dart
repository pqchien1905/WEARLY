import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/api_providers.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';

class OrderClassification extends ConsumerStatefulWidget {
  const OrderClassification({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  ConsumerState<OrderClassification> createState() =>
      _OrderClassificationState();
}

class _OrderClassificationState extends ConsumerState<OrderClassification> {
  bool busy = false;
  Future<void> change() async {
    final isTest = widget.data['isTest'] == true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isTest ? 'Đưa đơn vào báo cáo' : 'Đánh dấu đơn thử nghiệm'),
        content: Text(
          isTest
              ? 'Đơn này sẽ được tính trong báo cáo kinh doanh.'
              : 'Đơn thử nghiệm được giữ nguyên lịch sử và tồn kho, nhưng không tính vào báo cáo kinh doanh. Có thể đổi lại phân loại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(adminApiClientProvider)
          .request(
            'PATCH',
            'admin/orders/${widget.data['id']}/classification',
            body: {
              'isTest': !isTest,
              'expectedVersion': widget.data['version'],
            },
          );
      if (mounted) refreshAdmin(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppButton(
    widget.data['isTest'] == true
        ? 'Đơn thử · đưa vào báo cáo'
        : 'Đánh dấu đơn thử',
    outlined: true,
    busy: busy,
    onPressed: busy ? null : change,
  );
}
