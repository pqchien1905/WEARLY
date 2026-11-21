import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';
import 'admin_presentation.dart';

String customerCode(Object? value) {
  final id = '$value';
  return id.length > 8 ? '${id.substring(0, 8).toUpperCase()}…' : id;
}

String customersBack(String? source) {
  final uri = Uri.tryParse(source ?? '');
  return uri != null &&
          !uri.hasScheme &&
          !uri.hasAuthority &&
          !uri.hasFragment &&
          uri.path == '/admin/customers'
      ? uri.toString()
      : '/admin/customers';
}

Widget customerStatus(bool active) => AdminStatus(
  active ? 'Đang hoạt động' : 'Đã khóa',
  color: active ? T.success : T.danger,
);

typedef CustomerMetric = ({
  String label,
  String value,
  String note,
  IconData icon,
  VoidCallback? action,
});

class CustomerMetrics extends StatelessWidget {
  const CustomerMetrics({super.key, required this.items, this.compact = false});
  final bool compact;
  final List<CustomerMetric> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 1000
          ? 4
          : c.maxWidth >= 550 ||
                (compact &&
                    c.maxWidth >= 300 &&
                    MediaQuery.textScalerOf(context).scale(14) <= 17)
          ? 2
          : 1;
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            for (var start = 0; start < items.length; start += columns)
              Padding(
                padding: EdgeInsets.only(
                  bottom: start + columns < items.length ? 16 : 0,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var index = start;
                        index < start + columns;
                        index++
                      ) ...[
                        if (index > start) const SizedBox(width: 16),
                        Expanded(
                          child: index < items.length
                              ? _metric(items[index])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
  Widget _metric(CustomerMetric item) => Material(
    color: T.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: T.radius,
      side: BorderSide(color: T.line),
    ),
    child: InkWell(
      onTap: item.action,
      borderRadius: T.radius,
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item.label, style: T.small)),
                const SizedBox(width: 8),
                Icon(item.icon, color: T.accent, size: 20),
              ],
            ),
            SizedBox(height: compact ? 8 : 16),
            Text(
              item.value,
              style: T.body.copyWith(fontSize: 25, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(item.note, style: T.small),
          ],
        ),
      ),
    ),
  );
}
