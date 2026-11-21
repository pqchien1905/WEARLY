import 'package:flutter/material.dart';
import '../../account/order_tracking.dart';
import '../../../core/design/tokens.dart';
import 'admin_presentation.dart';

String adminOrderDate(Object? value) {
  final date = DateTime.tryParse('$value');
  return date == null ? '—' : trackingTime(date);
}

const adminPaymentStatuses = {
  'PENDING': 'Chờ thanh toán / thu tiền',
  'PAID': 'Đã thanh toán',
  'COD_UNSETTLED': 'COD chờ đối soát',
  'PARTIALLY_REFUNDED': 'Hoàn một phần',
  'REFUNDED': 'Đã hoàn tiền',
  'FAILED': 'Thanh toán thất bại',
  'CANCELLED': 'Thanh toán đã hủy',
};
const adminPaymentProviders = {
  'cod': 'COD',
  'vnpay': 'VNPay',
  'momo': 'MoMo',
  'zalopay': 'ZaloPay',
  'free': 'Miễn thanh toán',
};
const adminOrderSorts = {
  'newest': 'Mới nhất',
  'oldest': 'Cũ nhất',
  'total_desc': 'Giá trị cao nhất',
  'total_asc': 'Giá trị thấp nhất',
};

String adminPaymentLabel(Map payment) => payment['status'] == 'PENDING'
    ? payment['provider'] == 'cod'
          ? 'Chưa thu tiền'
          : 'Chờ thanh toán'
    : payment['provider'] == 'free' && payment['status'] == 'PAID'
    ? 'Không cần thanh toán'
    : adminPaymentStatuses[payment['status']] ?? 'Chưa có thanh toán';
Widget adminPaymentBadge(Map payment) => AdminStatus(
  adminPaymentLabel(payment),
  color: switch (payment['status']) {
    'PAID' => T.success,
    'PENDING' => T.warning,
    'FAILED' || 'CANCELLED' => T.danger,
    _ => T.accent,
  },
);

String adminOrdersBack(String? source) {
  final uri = Uri.tryParse(source ?? '');
  return uri != null &&
          !uri.hasScheme &&
          !uri.hasAuthority &&
          (uri.path == '/admin/orders' ||
              RegExp(r'^/admin/customers/[^/]+$').hasMatch(uri.path)) &&
          !uri.hasFragment
      ? uri.toString()
      : '/admin/orders';
}
