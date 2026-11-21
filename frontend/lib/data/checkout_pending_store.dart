import 'dart:convert';
import '../domain/commerce.dart';

/// A checkout whose outcome is unknown: the exact request (idempotency key and
/// body) plus what the customer confirmed. Persisting it means a page reload
/// can only re-check that same request, never place a second order. It holds
/// no tokens or payment credentials.
class StoredCheckout {
  const StoredCheckout({
    required this.key,
    required this.body,
    required this.snapshot,
    required this.savedAt,
  });
  final String key;
  final Map<String, Object?> body;
  final PendingCheckout snapshot;
  final DateTime savedAt;

  /// Older unresolved attempts are dropped; the server keeps the idempotency
  /// record, so re-checking from order history still finds a committed order.
  static const maxAge = Duration(hours: 24);

  String encode() {
    final d = snapshot.draft;
    return jsonEncode({
      'key': key,
      'body': body,
      'savedAt': savedAt.toUtc().toIso8601String(),
      'subtotal': snapshot.subtotal,
      'shipping': snapshot.shipping,
      'draft': {
        'name': d.name,
        'email': d.email,
        'phone': d.phone,
        'address': d.address,
        'express': d.express,
        'payment': d.payment,
        'paymentMethod': d.paymentMethod,
        'couponCode': d.couponCode,
        'discount': d.discount,
        'addressId': d.addressId,
      },
    });
  }

  /// Returns null for anything missing, malformed or expired.
  static StoredCheckout? decode(String? value, {DateTime? now}) {
    if (value == null || value.length > 8192) return null;
    try {
      final row = jsonDecode(value) as Map<String, Object?>;
      final key = row['key'] as String;
      final body = Map<String, Object?>.from(row['body'] as Map);
      final savedAt = DateTime.parse(row['savedAt'] as String);
      final d = Map<String, Object?>.from(row['draft'] as Map);
      final subtotal = row['subtotal'] as int,
          shipping = row['shipping'] as int;
      final age = (now ?? DateTime.now()).difference(savedAt);
      if (!RegExp(r'^[a-f0-9]{48}$').hasMatch(key) ||
          age.isNegative ||
          age > maxAge ||
          subtotal < 0 ||
          shipping < 0 ||
          body['addressId'] != d['addressId']) {
        return null;
      }
      return StoredCheckout(
        key: key,
        body: body,
        savedAt: savedAt,
        snapshot: PendingCheckout(
          subtotal: subtotal,
          shipping: shipping,
          draft: CheckoutDraft(
            name: d['name'] as String,
            email: d['email'] as String,
            phone: d['phone'] as String,
            address: d['address'] as String,
            express: d['express'] as bool,
            payment: d['payment'] as String,
            paymentMethod: d['paymentMethod'] as String,
            couponCode: d['couponCode'] as String?,
            discount: d['discount'] as int,
            addressId: d['addressId'] as String?,
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Per-account storage for at most one unresolved checkout.
abstract interface class CheckoutPendingStore {
  String? read(String owner);
  void save(String owner, String value);
  void clear(String owner);
}

class MemoryCheckoutPendingStore implements CheckoutPendingStore {
  final values = <String, String>{};
  @override
  String? read(String owner) => values[owner];
  @override
  void save(String owner, String value) => values[owner] = value;
  @override
  void clear(String owner) => values.remove(owner);
}
