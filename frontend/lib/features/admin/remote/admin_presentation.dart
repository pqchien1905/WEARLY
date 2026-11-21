import 'package:flutter/material.dart';
import '../../../core/design/tokens.dart';

const adminOrderStatuses = {
  'PENDING': 'Chờ xác nhận',
  'CONFIRMED': 'Đã xác nhận',
  'SHIPPED': 'Đang giao',
  'DELIVERED': 'Đã giao',
  'CANCELLED': 'Đã hủy',
  'RETURNED': 'Đã hoàn về kho',
};

String adminNumber(Object? value) => (value ?? 0).toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]}.',
);
String adminMoney(Object? value) => '${adminNumber(value)} ₫';
String adminDate(Object? value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '—';
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)}/${date.year} · ${pad(date.hour)}:${pad(date.minute)}';
}

class AdminStatus extends StatelessWidget {
  const AdminStatus(this.label, {super.key, this.color = T.muted});
  final String label;
  final Color color;
  factory AdminStatus.order(String status) => AdminStatus(
    adminOrderStatuses[status] ?? status,
    color: switch (status) {
      'PENDING' => T.warning,
      'DELIVERED' => T.success,
      'CANCELLED' || 'RETURNED' => T.danger,
      _ => T.accent,
    },
  );
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: T.radius,
    ),
    child: Text(
      label,
      style: T.small.copyWith(color: color, fontWeight: FontWeight.w500),
    ),
  );
}

class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          title,
          style: T.body.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        ?action,
      ],
    ),
  );
}
