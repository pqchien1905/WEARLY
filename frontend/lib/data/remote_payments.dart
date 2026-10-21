import '../core/network/api_client.dart';
import 'commerce_json.dart';

const paymentStatuses = [
  'PENDING',
  'PAID',
  'PARTIALLY_REFUNDED',
  'FAILED',
  'CANCELLED',
  'REFUNDED',
];
Uri sandboxPaymentUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'sandbox.vnpayment.vn' ||
      uri.port != 443 ||
      uri.path != '/paymentv2/vpcpay.html' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw const ApiException(
      'INVALID_PAYMENT_URL',
      'Đường dẫn VNPay sandbox không hợp lệ.',
    );
  }
  return uri;
}

class PaymentState {
  PaymentState(Object? data, String orderId) {
    final map = commerceMap(data);
    if (map['orderId'] != orderId ||
        map['sandbox'] != true ||
        !paymentStatuses.contains(map['paymentStatus']) ||
        map['reviewRequired'] is! bool) {
      throw invalidCommerce;
    }
    status = map['paymentStatus'];
    reviewRequired = map['reviewRequired'];
    checkoutUrl = map['checkoutUrl'] == null
        ? null
        : sandboxPaymentUrl(map['checkoutUrl'] as String);
    final attempt = map['attempt'];
    if (attempt != null) {
      final a = commerceMap(attempt);
      if (a['reference'] is! String || !paymentStatuses.contains(a['status'])) {
        throw invalidCommerce;
      }
      attemptStatus = a['status'];
      expiresAt = DateTime.tryParse(a['expiresAt']?.toString() ?? '');
      if (expiresAt == null) throw invalidCommerce;
    }
  }
  late final String status;
  late final bool reviewRequired;
  late final Uri? checkoutUrl;
  String? attemptStatus;
  DateTime? expiresAt;
}

class RemotePaymentRepository {
  RemotePaymentRepository(this.api);
  final ApiClient api;
  Future<bool> available() async {
    final data = commerceMap(
      await api.request('GET', 'payments/methods', authenticated: false),
    );
    if (data['cod'] != true ||
        data['sandbox'] != true ||
        data['vnpay'] is! bool) {
      throw invalidCommerce;
    }
    return data['vnpay'];
  }

  Future<PaymentState> start(String id) async => PaymentState(
    await api.request(
      'POST',
      'payments/orders/${Uri.encodeComponent(id)}/start',
    ),
    id,
  );
  Future<PaymentState> reconcile(String id) async => PaymentState(
    await api.request(
      'POST',
      'payments/orders/${Uri.encodeComponent(id)}/reconcile',
    ),
    id,
  );
}
