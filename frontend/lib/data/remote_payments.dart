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

/// Gateways that confirm payment themselves; COD and free orders do not.
const onlinePaymentProviders = ['vnpay', 'momo', 'zalopay'];
const paymentProviderNames = {
  'cod': 'COD',
  'free': 'Miễn thanh toán',
  'vnpay': 'VNPay',
  'momo': 'MoMo',
  'zalopay': 'ZaloPay',
};

/// Checkout choice label → API payment method.
const checkoutPaymentMethods = {
  'COD': 'cod',
  'VNPay sandbox': 'vnpay',
  'MoMo sandbox': 'momo',
  'ZaloPay sandbox': 'zalopay',
};
String paymentProviderName(String? provider) =>
    paymentProviderNames[provider] ?? 'COD';
String paymentMethodFor(String label) => checkoutPaymentMethods[label] ?? 'cod';

bool _gatewayPage(Uri uri, String provider) => switch (provider) {
  'vnpay' =>
    uri.host == 'sandbox.vnpayment.vn' && uri.path == '/paymentv2/vpcpay.html',
  'momo' => uri.host == 'test-payment.momo.vn',
  'zalopay' => uri.host == 'zalopay.vn' || uri.host.endsWith('.zalopay.vn'),
  _ => false,
};

/// Only HTTPS sandbox pages of the known gateways may be opened.
Uri sandboxPaymentUrl(String url, [String? provider]) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !(provider == null
          ? onlinePaymentProviders.any((p) => _gatewayPage(uri, p))
          : _gatewayPage(uri, provider))) {
    throw const ApiException(
      'INVALID_PAYMENT_URL',
      'Đường dẫn thanh toán thử nghiệm không hợp lệ.',
    );
  }
  return uri;
}

class PaymentState {
  PaymentState(Object? data, String orderId) {
    final map = commerceMap(data);
    final provider = map['provider'] ?? 'vnpay';
    if (map['orderId'] != orderId ||
        map['sandbox'] != true ||
        !onlinePaymentProviders.contains(provider) ||
        !paymentStatuses.contains(map['paymentStatus']) ||
        map['reviewRequired'] is! bool) {
      throw invalidCommerce;
    }
    this.provider = provider as String;
    status = map['paymentStatus'];
    reviewRequired = map['reviewRequired'];
    checkoutUrl = map['checkoutUrl'] == null
        ? null
        : sandboxPaymentUrl(map['checkoutUrl'] as String, this.provider);
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
  late final String provider;
  late final String status;
  late final bool reviewRequired;
  late final Uri? checkoutUrl;
  String? attemptStatus;
  DateTime? expiresAt;
}

/// Online gateways the server has enabled. COD is always available.
class PaymentMethods {
  const PaymentMethods({
    this.vnpay = false,
    this.momo = false,
    this.zalopay = false,
  });
  final bool vnpay, momo, zalopay;
  bool enabled(String method) => switch (method) {
    'cod' => true,
    'vnpay' => vnpay,
    'momo' => momo,
    'zalopay' => zalopay,
    _ => false,
  };
}

class RemotePaymentRepository {
  RemotePaymentRepository(this.api);
  final ApiClient api;
  Future<PaymentMethods> available() async {
    final data = commerceMap(
      await api.request('GET', 'payments/methods', authenticated: false),
    );
    bool flag(String key) {
      final value = data[key] ?? false;
      if (value is! bool) throw invalidCommerce;
      return value;
    }

    if (data['cod'] != true ||
        data['sandbox'] != true ||
        data['vnpay'] is! bool) {
      throw invalidCommerce;
    }
    return PaymentMethods(
      vnpay: flag('vnpay'),
      momo: flag('momo'),
      zalopay: flag('zalopay'),
    );
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
