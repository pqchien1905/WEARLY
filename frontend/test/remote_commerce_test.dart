import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/commerce_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_commerce.dart';
import 'package:nep_storefront/domain/commerce.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'remote_account_test.dart' show sessionJson;

Map<String, Object?> cartJson({int quantity = 1, int version = 1}) => {
  'id': 'cart-1',
  'version': version,
  'subtotal': '${490000 * quantity}',
  'currency': 'VND',
  'items': [
    if (quantity > 0)
      {
        'id': 'item-uuid',
        'sku': 'WRL-1-MAIN-M',
        'slug': 'nep-1',
        'name': 'Áo cotton',
        'image': 'assets/images/shirt.jpg',
        'size': 'M',
        'color': 'Trắng',
        'unitPrice': '490000',
        'quantity': quantity,
        'available': 12,
      },
  ],
};
Map<String, Object?> orderJson({
  String id = 'order-1',
  String status = 'PENDING',
}) => {
  'id': id,
  'status': status,
  'currency': 'VND',
  'subtotal': '490000',
  'shipping': '30000',
  'total': '520000',
  'createdAt': '2026-10-18T10:00:00.000Z',
  'version': 0,
  'addressSnapshot': {
    'recipient': 'Nguyễn An',
    'phone': '0901234567',
    'address': '12 Nguyễn Huệ, TP.HCM',
  },
  'payment': {
    'provider': 'cod',
    'status': status == 'CANCELLED' ? 'CANCELLED' : 'PENDING',
  },
  'items': [
    {
      'id': 'order-item',
      'sku': 'WRL-1-MAIN-M',
      'slug': 'nep-1',
      'name': 'Áo cotton',
      'image': 'assets/images/shirt.jpg',
      'size': 'M',
      'color': 'Trắng',
      'unitPrice': '490000',
      'quantity': 1,
    },
  ],
};
const draft = CheckoutDraft(
  name: 'Nguyễn An',
  email: 'an@example.com',
  phone: '0901234567',
  address: '12 Nguyễn Huệ, TP.HCM',
  addressId: 'address-1',
  payment: 'COD',
);

void main() {
  test(
    'logout replaces personal caches and rejects old controller writes',
    () async {
      var cartWrites = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/auth/login')) {
            return jsonResponse(sessionJson());
          }
          if (r.url.path.endsWith('/auth/logout')) return jsonResponse({});
          if (r.url.path.endsWith('/orders')) {
            return jsonResponse({
              'items': [orderJson()],
              'total': 1,
              'page': 1,
              'limit': 100,
            });
          }
          if (r.method == 'POST') cartWrites++;
          return jsonResponse(cartJson());
        }),
      );
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
          sessionTokensProvider.overrideWithValue(api.tokens),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      final subscription = container.listen(commerceProvider, (_, _) {});
      addTearDown(subscription.close);
      expect(container.read(commerceProvider).requiresLogin, isTrue);
      await container
          .read(accountProvider.notifier)
          .signIn('', 'an@example.com', 'example-password');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final old = container.read(commerceProvider);
      await old.refresh();
      expect(old.items, hasLength(1));
      expect(old.orders, hasLength(1));
      await container.read(accountProvider.notifier).signOut();
      await container.pump();
      expect(container.read(commerceProvider).items, isEmpty);
      expect(container.read(commerceProvider).orders, isEmpty);
      await expectLater(
        old.add('nep-1', 'WRL-1-MAIN-M', 1),
        throwsA(isA<ApiException>()),
      );
      expect(cartWrites, 0);
    },
  );
  test(
    'cart mutations use server item IDs, quantities and exact monetary strings',
    () async {
      final sent = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          sent.add(r);
          return jsonResponse(
            cartJson(
              quantity: r.method == 'DELETE'
                  ? 0
                  : r.method == 'PATCH'
                  ? 2
                  : 1,
            ),
          );
        }),
      );
      final cart = RemoteCartRepository(api);
      await cart.add('nep-1', 'WRL-1-MAIN-M', 1);
      expect(jsonDecode(sent.first.body), {
        'sku': 'WRL-1-MAIN-M',
        'quantity': 1,
      });
      expect(cart.subtotal, 490000);
      await cart.update('WRL-1-MAIN-M', 2);
      expect(sent.last.url.path, '/api/v1/cart/items/item-uuid');
      expect(cart.subtotal, 980000);
      await cart.remove('WRL-1-MAIN-M');
      expect(cart.items, isEmpty);
      api.close();
    },
  );
  test('a failed removal preserves the last confirmed cart', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(
        (r) async => r.method == 'DELETE'
            ? jsonResponse({}, 503)
            : jsonResponse(cartJson()),
      ),
    );
    final cart = RemoteCartRepository(api);
    await cart.refresh();
    await expectLater(
      cart.remove('WRL-1-MAIN-M'),
      throwsA(isA<ApiException>()),
    );
    expect(cart.items.single.quantity, 1);
    expect(cart.locked, isFalse);
    api.close();
  });
  test(
    'cart writes serialize and disposed identity cannot publish late data',
    () async {
      var active = 0, maximum = 0, quantity = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          active++;
          if (active > maximum) maximum = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          quantity++;
          active--;
          return jsonResponse(cartJson(quantity: quantity));
        }),
      );
      final cart = RemoteCartRepository(api);
      await Future.wait([
        cart.add('nep-1', 'WRL-1-MAIN-M', 1),
        cart.add('nep-1', 'WRL-1-MAIN-M', 1),
      ]);
      expect(maximum, 1);
      expect(cart.items.single.quantity, 2);
      final pending = cart.add('nep-1', 'WRL-1-MAIN-M', 1);
      final rejected = expectLater(pending, throwsA(isA<ApiException>()));
      cart.dispose();
      await rejected;
      expect(cart.items, isEmpty);
      api.close();
    },
  );
  test(
    'uncertain checkout retries the exact request, prevents cart edits and accepts one order',
    () async {
      final sent = <http.Request>[];
      var deleteCalls = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/orders')) {
            sent.add(r);
            if (sent.length == 1) throw http.ClientException('lost response');
            return jsonResponse(orderJson(), 201);
          }
          if (r.method == 'DELETE') deleteCalls++;
          return jsonResponse(cartJson(quantity: sent.isEmpty ? 1 : 0));
        }),
      );
      final cart = RemoteCartRepository(api);
      final orders = RemoteOrderRepository(api, cart, email: 'an@example.com');
      await cart.refresh();
      await expectLater(orders.checkout(draft), throwsA(isA<ApiException>()));
      expect(orders.hasPendingCheckout, isTrue);
      expect(cart.locked, isTrue);
      await expectLater(
        cart.add('nep-1', 'WRL-1-MAIN-M', 1),
        throwsA(isA<ApiException>()),
      );
      final order = await orders.checkout(draft);
      expect(
        sent.last.headers['Idempotency-Key'],
        sent.first.headers['Idempotency-Key'],
      );
      expect(sent.last.body, sent.first.body);
      expect(jsonDecode(sent.last.body), {
        'addressId': 'address-1',
        'shippingMethod': 'standard',
        'expectedSubtotal': '490000',
        'cartVersion': 1,
      });
      expect(order.total, 520000);
      expect(order.draft.payment, contains('Chưa thu tiền'));
      expect(cart.items, isEmpty);
      expect(deleteCalls, 0);
      expect(orders.orders.length, 1);
      expect(cart.locked, isFalse);
      api.close();
    },
  );
  test(
    'definite checkout rejection unlocks the cart and next attempt gets a new key',
    () async {
      final keys = <String?>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            keys.add(r.headers['Idempotency-Key']);
            return jsonResponse({}, 409);
          }
          return jsonResponse(cartJson());
        }),
      );
      final cart = RemoteCartRepository(api);
      final orders = RemoteOrderRepository(api, cart);
      await cart.refresh();
      await expectLater(orders.checkout(draft), throwsA(isA<ApiException>()));
      expect(cart.locked, isFalse);
      expect(orders.hasPendingCheckout, isFalse);
      await expectLater(orders.checkout(draft), throwsA(isA<ApiException>()));
      expect(keys.first, isNot(keys.last));
      api.close();
    },
  );
  test(
    'history pagination and cancellation map server status and owned snapshots',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/cancel')) {
            return jsonResponse(orderJson(status: 'CANCELLED'));
          }
          final page = int.parse(r.url.queryParameters['page']!);
          return jsonResponse({
            'items': [orderJson(id: 'order-$page')],
            'total': 2,
            'page': page,
            'limit': 1,
          });
        }),
      );
      final orders = RemoteOrderRepository(api, RemoteCartRepository(api));
      await orders.refresh();
      expect(orders.hasMore, isTrue);
      await orders.loadMore();
      expect(orders.orders.map((o) => o.id), ['order-1', 'order-2']);
      expect(orders.hasMore, isFalse);
      await orders.setStatus('order-1', 'Đã hủy');
      expect(orders.orders.first.status, 'Đã hủy');
      expect(orders.orders.first.draft.address, '12 Nguyễn Huệ, TP.HCM');
      api.close();
    },
  );
  test(
    'unknown or fractional money cannot be silently rounded into checkout',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient(
          (_) async => jsonResponse({...cartJson(), 'subtotal': '490000.5'}),
        ),
      );
      final cart = RemoteCartRepository(api);
      await expectLater(cart.refresh(), throwsA(isA<ApiException>()));
      expect(cart.items, isEmpty);
      api.close();
    },
  );
}
