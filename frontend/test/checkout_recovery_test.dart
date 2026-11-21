import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/checkout_pending_store.dart';
import 'package:nep_storefront/data/remote_commerce.dart';
import 'package:nep_storefront/domain/commerce.dart';
import 'remote_commerce_test.dart' show cartJson, draft, orderJson;
import 'remote_session_test.dart' show jsonResponse;

/// A server whose order endpoint fails the first [failures] POSTs (lost
/// responses after commit), then answers with the committed order.
({ApiClient api, List<http.Request> posts, void Function(int) setFailures})
server({int failures = 0, int failStatus = 0}) {
  var remaining = failures;
  final posts = <http.Request>[];
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((r) async {
      if (r.method == 'POST' && r.url.path.endsWith('/orders')) {
        posts.add(r);
        if (remaining > 0) {
          remaining--;
          if (failStatus == 0) throw http.ClientException('response lost');
          return jsonResponse({}, failStatus);
        }
        return jsonResponse(orderJson(), 201);
      }
      return jsonResponse(cartJson(quantity: posts.isEmpty ? 1 : 0));
    }),
  );
  return (api: api, posts: posts, setFailures: (n) => remaining = n);
}

void main() {
  test(
    'a lost response is re-sent with the same key and yields one order',
    () async {
      final s = server(failures: 2);
      addTearDown(s.api.close);
      final store = MemoryCheckoutPendingStore();
      final cart = RemoteCartRepository(s.api);
      final orders = RemoteOrderRepository(
        s.api,
        cart,
        owner: 'user-1',
        pendingStore: store,
        retryDelay: Duration.zero,
      );
      await cart.refresh();
      final order = await orders.checkout(draft);
      expect(order.total, 520000);
      expect(s.posts, hasLength(3));
      expect(
        s.posts.map((r) => r.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(s.posts.map((r) => r.body).toSet(), hasLength(1));
      expect(orders.hasPendingCheckout, isFalse);
      expect(cart.locked, isFalse);
      expect(store.values, isEmpty);
    },
  );

  test('5xx responses are retried but a definitive rejection is not', () async {
    final s = server(failures: 1, failStatus: 502);
    addTearDown(s.api.close);
    final cart = RemoteCartRepository(s.api);
    final orders = RemoteOrderRepository(
      s.api,
      cart,
      retryDelay: Duration.zero,
    );
    await cart.refresh();
    await orders.checkout(draft);
    expect(s.posts, hasLength(2));

    final rejected = server(failures: 5, failStatus: 409);
    addTearDown(rejected.api.close);
    final store = MemoryCheckoutPendingStore();
    final cart2 = RemoteCartRepository(rejected.api);
    final orders2 = RemoteOrderRepository(
      rejected.api,
      cart2,
      owner: 'user-1',
      pendingStore: store,
      retryDelay: Duration.zero,
    );
    await cart2.refresh();
    await expectLater(orders2.checkout(draft), throwsA(isA<ApiException>()));
    expect(rejected.posts, hasLength(1));
    expect(orders2.hasPendingCheckout, isFalse);
    expect(store.values, isEmpty);
  });

  test(
    'a reload restores the unresolved checkout instead of allowing a new order',
    () async {
      final s = server(failures: 10);
      addTearDown(s.api.close);
      final store = MemoryCheckoutPendingStore();
      final cart = RemoteCartRepository(s.api);
      final first = RemoteOrderRepository(
        s.api,
        cart,
        owner: 'user-1',
        pendingStore: store,
        autoRetries: 1,
        retryDelay: Duration.zero,
      );
      await cart.refresh();
      await expectLater(first.checkout(draft), throwsA(isA<ApiException>()));
      expect(first.hasPendingCheckout, isTrue);
      expect(store.values.keys, ['user-1']);
      first.dispose();

      // Simulated page reload: new repositories, same browser storage.
      s.setFailures(0);
      final reloadedCart = RemoteCartRepository(s.api);
      final reloaded = RemoteOrderRepository(
        s.api,
        reloadedCart,
        owner: 'user-1',
        pendingStore: store,
        retryDelay: Duration.zero,
      );
      expect(reloaded.hasPendingCheckout, isTrue);
      expect(reloaded.pendingCheckout!.draft.addressId, draft.addressId);
      expect(reloadedCart.locked, isTrue);
      await expectLater(
        reloadedCart.add('nep-1', 'WRL-1-MAIN-M', 1),
        throwsA(isA<ApiException>()),
      );
      // Even a different draft only re-checks the original request.
      final order = await reloaded.checkout(
        const CheckoutDraft(
          name: 'x',
          email: 'x@example.com',
          phone: '0',
          address: 'x',
        ),
      );
      expect(order.total, 520000);
      expect(
        s.posts.map((r) => r.headers['Idempotency-Key']).toSet(),
        hasLength(1),
      );
      expect(s.posts.map((r) => r.body).toSet(), hasLength(1));
      expect(store.values, isEmpty);
      expect(reloadedCart.locked, isFalse);

      // Another account on the same browser never inherits the guard.
      store.save(
        'user-1',
        StoredCheckout(
          key: 'a' * 48,
          body: {'addressId': draft.addressId},
          snapshot: PendingCheckout(draft: draft, subtotal: 1, shipping: 0),
          savedAt: DateTime.now(),
        ).encode(),
      );
      final other = RemoteOrderRepository(
        s.api,
        RemoteCartRepository(s.api),
        owner: 'user-2',
        pendingStore: store,
      );
      expect(other.hasPendingCheckout, isFalse);
    },
  );

  test('stored checkouts reject malformed, foreign and expired data', () {
    final valid = StoredCheckout(
      key: 'b' * 48,
      body: {'addressId': 'address-1', 'paymentMethod': 'momo'},
      snapshot: PendingCheckout(
        draft: draft,
        subtotal: 490000,
        shipping: 30000,
      ),
      savedAt: DateTime.now(),
    );
    final decoded = StoredCheckout.decode(valid.encode())!;
    expect(decoded.key, valid.key);
    expect(decoded.body['paymentMethod'], 'momo');
    expect(decoded.snapshot.draft.paymentMethod, draft.paymentMethod);
    for (final bad in [
      null,
      'not json',
      valid.encode().replaceFirst('b' * 48, 'short-key'),
      valid.encode().replaceFirst(
        '"addressId":"address-1"',
        '"addressId":"other"',
      ),
    ]) {
      expect(StoredCheckout.decode(bad), isNull);
    }
    expect(
      StoredCheckout.decode(
        valid.encode(),
        now: DateTime.now().add(const Duration(hours: 25)),
      ),
      isNull,
    );
  });
}
