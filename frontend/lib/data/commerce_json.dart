import '../core/network/api_client.dart';
import '../domain/commerce.dart';

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
    quantity: quantity,
    stock: stock,
  );
}

Order commerceOrder(Object? value, {required String email}) {
  final data = commerceMap(value);
  final address = commerceMap(data['addressSnapshot']);
  final payment = commerceMap(data['payment']);
  if (data['currency'] != 'VND' ||
      data['id'] is! String ||
      data['items'] is! List ||
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
    _ => throw invalidCommerce,
  };
  final paymentStatus = switch (payment['status']) {
    'PENDING' => 'Chưa thu tiền',
    'PAID' => 'Đã thanh toán',
    'CANCELLED' => 'Đã hủy',
    'FAILED' => 'Thanh toán thất bại',
    _ => throw invalidCommerce,
  };
  if (payment['provider'] != 'cod') throw invalidCommerce;
  final createdAt = DateTime.tryParse(data['createdAt']?.toString() ?? '');
  if (createdAt == null) throw invalidCommerce;
  final order = Order(
    id: data['id'],
    status: status,
    createdAt: createdAt,
    shipping: vnd(data['shipping']),
    items: List<CartItem>.unmodifiable(
      (data['items'] as List).map((item) => commerceItem(item)),
    ),
    draft: CheckoutDraft(
      name: address['recipient'],
      email: email,
      phone: address['phone'],
      address: address['address'],
      payment: 'COD · $paymentStatus',
      express: vnd(data['shipping']) == 50000,
    ),
  );
  if (order.items.isEmpty ||
      order.subtotal != vnd(data['subtotal']) ||
      order.total != vnd(data['total'])) {
    throw invalidCommerce;
  }
  return order;
}
