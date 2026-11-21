import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_commerce.dart';
import 'remote_commerce_test.dart' show cartJson, orderJson;
import 'remote_session_test.dart' show jsonResponse;

void main() {
  test(
    'changing the address or payment method replaces the stored order',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          requests.add(r);
          final path = r.url.path;
          if (path.endsWith('/orders/order-1/address')) {
            return jsonResponse(
              orderJson()
                ..['addressSnapshot'] = {
                  'recipient': 'Người nhận mới',
                  'phone': '0912345678',
                  'address': '99 Đường Mới, Hà Nội',
                },
            );
          }
          if (path.endsWith('/payments/orders/order-1/method')) {
            return jsonResponse(
              orderJson()
                ..['payment'] = {
                  'provider': 'zalopay',
                  'amount': '520000',
                  'status': 'PENDING',
                },
            );
          }
          if (path.endsWith('/orders/order-1')) {
            return jsonResponse(orderJson());
          }
          return jsonResponse(cartJson(quantity: 0));
        }),
      );
      addTearDown(api.close);
      final orders = RemoteOrderRepository(api, RemoteCartRepository(api));
      await orders.loadOrder('order-1');

      await orders.changeAddress('order-1', 'address-2');
      final address = requests.last;
      expect(address.method, 'PATCH');
      expect(jsonDecode(address.body), {'addressId': 'address-2'});
      expect(orders.orders.single.draft.address, '99 Đường Mới, Hà Nội');

      await orders.changePaymentMethod('order-1', 'zalopay');
      final method = requests.last;
      expect(method.method, 'PATCH');
      expect(method.url.path, endsWith('/payments/orders/order-1/method'));
      expect(jsonDecode(method.body), {'paymentMethod': 'zalopay'});
      expect(orders.orders.single.paymentProvider, 'zalopay');
    },
  );
}
