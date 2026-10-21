import 'dart:async';

class CartItem {
  const CartItem({
    required this.slug,
    required this.sku,
    required this.name,
    required this.image,
    required this.color,
    required this.size,
    required this.unitPrice,
    required this.quantity,
    required this.stock,
    this.id = '',
  });
  final String id, slug, sku, name, image, color, size;
  final int unitPrice, quantity, stock;
  int get total => unitPrice * quantity;
  CartItem withQuantity(int value) => CartItem(
    id: id,
    slug: slug,
    sku: sku,
    name: name,
    image: image,
    color: color,
    size: size,
    unitPrice: unitPrice,
    quantity: value,
    stock: stock,
  );
}

class CheckoutDraft {
  const CheckoutDraft({
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    this.express = false,
    this.payment = 'COD demo',
    this.paymentMethod = 'cod',
    this.couponCode,
    this.discount = 0,
    this.addressId,
  });
  final String name, email, phone, address, payment, paymentMethod;
  final bool express;
  final String? addressId;
  final String? couponCode;
  final int discount;
}

class OrderEvent {
  const OrderEvent({
    required this.status,
    required this.note,
    required this.createdAt,
  });
  final String status, note;
  final DateTime createdAt;
}

class Shipment {
  const Shipment({
    required this.carrier,
    required this.trackingCode,
    required this.status,
    required this.events,
  });
  final String carrier, trackingCode, status;
  final List<OrderEvent> events;
}

class Order {
  const Order({
    required this.id,
    required this.items,
    required this.draft,
    required this.shipping,
    this.status = 'Chờ xác nhận',
    required this.createdAt,
    this.paymentProvider = 'cod',
    this.paymentStatus = 'PENDING',
    this.discount = 0,
    this.couponCode,
    this.shipment,
    this.history = const [],
  });
  final String id, status, paymentProvider, paymentStatus;
  final List<CartItem> items;
  final CheckoutDraft draft;
  final int shipping;
  final int discount;
  final String? couponCode;
  final DateTime createdAt;
  final Shipment? shipment;
  final List<OrderEvent> history;
  int get subtotal => items.fold(0, (sum, i) => sum + i.total);
  int get total => subtotal + shipping - discount;
  Order withStatus(String value) => Order(
    id: id,
    items: items,
    draft: draft,
    shipping: shipping,
    status: value,
    createdAt: createdAt,
    paymentProvider: paymentProvider,
    paymentStatus: paymentStatus,
    discount: discount,
    couponCode: couponCode,
    shipment: shipment,
    history: history,
  );
}

/// Exact information shown when a checkout attempt was first confirmed.
class PendingCheckout {
  const PendingCheckout({
    required this.draft,
    required this.subtotal,
    required this.shipping,
  });
  final CheckoutDraft draft;
  final int subtotal, shipping;
}

abstract interface class CartRepository {
  bool get locked;
  void setLocked(bool value);
  List<CartItem> get items;
  int get subtotal;
  Future<void> add(String slug, String sku, int quantity);
  Future<void> update(String sku, int quantity);
  FutureOr<void> remove(String sku);
  FutureOr<void> clear();
}

abstract interface class OrderRepository {
  List<Order> get orders;
  Future<Order> checkout(CheckoutDraft draft);
  FutureOr<void> setStatus(String id, String status);
}
