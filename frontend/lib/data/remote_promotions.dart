import '../core/network/api_client.dart';
import 'commerce_json.dart';

class PromotionQuote {
  PromotionQuote(Object? value) {
    final data = commerceMap(value);
    if (data['code'] is! String ||
        !RegExp(r'^[A-Z0-9_-]{3,32}$').hasMatch(data['code']) ||
        data['cartVersion'] is! int ||
        data['cartVersion'] < 0) {
      throw invalidCommerce;
    }
    code = data['code'];
    cartVersion = data['cartVersion'];
    discount = vnd(data['discount']);
    subtotal = vnd(data['subtotal']);
    shipping = vnd(data['shipping']);
    total = vnd(data['total']);
    if (discount > subtotal || total != subtotal + shipping - discount) {
      throw invalidCommerce;
    }
  }
  late final String code;
  late final int discount, subtotal, shipping, total, cartVersion;
}

class RemotePromotionRepository {
  RemotePromotionRepository(this.api);
  final ApiClient api;
  Future<PromotionQuote> preview(
    String code, {
    required bool express,
    required int cartVersion,
  }) async {
    final normalized = code.trim().toUpperCase();
    final quote = PromotionQuote(
      await api.request(
        'POST',
        'promotions/preview',
        body: {
          'code': normalized,
          'shippingMethod': express ? 'express' : 'standard',
          'cartVersion': cartVersion,
        },
      ),
    );
    if (quote.code != normalized || quote.cartVersion != cartVersion) {
      throw invalidCommerce;
    }
    return quote;
  }
}
