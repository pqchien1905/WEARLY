import '../core/network/api_client.dart';
import '../domain/commerce.dart';
import 'remote_payments.dart';

const invalidCommerce = ApiException(
  'INVALID_RESPONSE',
  'Dữ liệu giỏ hàng hoặc đơn hàng chưa hợp lệ. Vui lòng tải lại.',
);

int vnd(Object? value) {
  if (value is! String || !RegExp(r'^\d{1,14}$').hasMatch(value)) {
    throw invalidCommerce;
  }
  return int.parse(value);
}

Map<String, dynamic> commerceMap(Object? value) {
  if (value is! Map<String, dynamic>) throw invalidCommerce;
  return value;
}

CartItem commerceItem(Object? value, {bool cart = false}) {
  final data = commerceMap(value);
  for (final key in ['id', 'slug', 'sku', 'name', 'image', 'color', 'size']) {
    if (data[key] is! String) throw invalidCommerce;
  }
  final quantity = data['quantity'];
  final stock = cart ? data['available'] : quantity;
  if (quantity is! int || quantity < 1 || stock is! int || stock < 0) {
    throw invalidCommerce;
  }
  return CartItem(
    id: data['id'],
    slug: data['slug'],
    sku: data['sku'],
    name: data['name'],
    image: data['image'],
    color: data['color'],
    size: data['size'],
    unitPrice: vnd(data['unitPrice']),
    originalUnitPrice: data['originalUnitPrice'] == null
        ? null
        : vnd(data['originalUnitPrice']),
    promotionName: data['promotionName'] as String?,
    quantity: quantity,
    stock: stock,
  );
}

const orderStatusNames = {
  'PENDING': 'Chờ xác nhận',
  'CONFIRMED': 'Đã xác nhận',
  'SHIPPED': 'Đang giao',
  'DELIVERED': 'Đã giao',
  'CANCELLED': 'Đã hủy',
  'RETURNED': 'Đã hoàn về kho',
};
const shipmentStatusNames = {
  'IN_TRANSIT': 'Đang vận chuyển',
  'OUT_FOR_DELIVERY': 'Đang giao đến khách',
  'DELIVERY_FAILED': 'Giao thất bại',
  'DELIVERED': 'Đã giao',
  'RETURNED': 'Đã hoàn về kho',
};
List<OrderEvent> commerceEvents(Object? value, Map<String, String> states) {
  if (value is! List) throw invalidCommerce;
  return List.unmodifiable(
    value.map((entry) {
      final e = commerceMap(entry),
          date = DateTime.tryParse(entry['createdAt']?.toString() ?? '');
      if (!states.containsKey(e['status']) ||
          e['note'] is! String ||
          date == null) {
        throw invalidCommerce;
      }
      return OrderEvent(status: e['status'], note: e['note'], createdAt: date);
    }),
  );
}

Shipment? commerceShipment(Object? value) {
  if (value == null) return null;
  final s = commerceMap(value);
  if (s['carrier'] != 'local_simulator' ||
      s['trackingCode'] is! String ||
      !RegExp(r'^LOCAL-[0-9A-F-]{36}$').hasMatch(s['trackingCode']) ||
      !shipmentStatusNames.containsKey(s['status'])) {
    throw invalidCommerce;
  }
  final events = commerceEvents(s['events'], shipmentStatusNames);
  if (events.isEmpty || events.last.status != s['status']) {
    throw invalidCommerce;
  }
  return Shipment(
    carrier: s['carrier'],
    trackingCode: s['trackingCode'],
    status: s['status'],
    events: events,
  );
}

Order commerceOrder(Object? value, {required String email}) {
  final data = commerceMap(value);
  final address = commerceMap(data['addressSnapshot']);
  final payment = commerceMap(data['payment']);
  if (data['currency'] != 'VND' ||
      data['id'] is! String ||
      data['items'] is! List ||
      !['standard', 'express'].contains(data['shippingMethod']) ||
      address['recipient'] is! String ||
      address['phone'] is! String ||
      address['address'] is! String) {
    throw invalidCommerce;
  }
  final status = switch (data['status']) {
    'PENDING' => 'Chờ xác nhận',
    'CONFIRMED' => 'Đã xác nhận',
    'SHIPPED' => 'Đang giao',
    'DELIVERED' => 'Đã giao',
    'CANCELLED' => 'Đã hủy',
    'RETURNED' => 'Đã hoàn về kho',
    _ => throw invalidCommerce,
  };
  final paymentStatus = switch (payment['status']) {
    'PENDING' =>
      onlinePaymentProviders.contains(payment['provider'])
          ? 'Chờ thanh toán'
          : 'Chưa thu tiền',
    'PAID' => 'Đã thanh toán',
    'PARTIALLY_REFUNDED' => 'Đã hoàn một phần',
    'CANCELLED' => 'Đã hủy',
    'FAILED' => 'Thanh toán thất bại',
    'REFUNDED' => 'Đã hoàn tiền',
    _ => throw invalidCommerce,
  };
  if (!paymentProviderNames.containsKey(payment['provider'])) {
    throw invalidCommerce;
  }
  final discount = vnd(data['discount'] ?? '0');
  final couponCode = data['couponCode'];
  if (couponCode != null && couponCode is! String) throw invalidCommerce;
  if (discount > 0 && couponCode == null) throw invalidCommerce;
  final createdAt = DateTime.tryParse(data['createdAt']?.toString() ?? '');
  if (createdAt == null) throw invalidCommerce;
  final code = data['code'];
  if (code != null &&
      (code is! String || !RegExp(r'^[A-Z0-9]{6,20}$').hasMatch(code))) {
    throw invalidCommerce;
  }
  final order = Order(
    id: data['id'],
    code: code as String? ?? '',
    isSample: address['sampleData'] == true,
    pinLatitude: (address['latitude'] as num?)?.toDouble(),
    pinLongitude: (address['longitude'] as num?)?.toDouble(),
    status: status,
    paymentProvider: payment['provider'],
    paymentStatus: payment['status'],
    hasOnlineCollection: (payment['attempts'] as List? ?? []).any(
      (a) => a is Map && a['status'] == 'PAID',
    ),
    discount: discount,
    couponCode: couponCode,
    createdAt: createdAt,
    shipment: commerceShipment(data['shipment']),
    history: commerceEvents(data['history'] ?? [], orderStatusNames),
    shipping: vnd(data['shipping']),
    items: List<CartItem>.unmodifiable(
      (data['items'] as List).map((item) => commerceItem(item)),
    ),
    draft: CheckoutDraft(
      name: address['recipient'],
      email: email,
      phone: address['phone'],
      address: address['address'],
      payment: payment['provider'] == 'free'
          ? 'Không cần thanh toán'
          : '${onlinePaymentProviders.contains(payment['provider']) ? '${paymentProviderName(payment['provider'])} sandbox' : 'COD'} · $paymentStatus',
      paymentMethod: payment['provider'],
      discount: discount,
      couponCode: couponCode,
      express: data['shippingMethod'] == 'express',
    ),
  );
  if (order.items.isEmpty ||
      discount > order.subtotal ||
      (payment['provider'] == 'free' &&
          (order.total != 0 || payment['amount'] != '0')) ||
      order.subtotal != vnd(data['subtotal']) ||
      order.total != vnd(data['total'])) {
    throw invalidCommerce;
  }
  return order;
}
