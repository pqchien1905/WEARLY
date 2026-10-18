import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/remote_wishlist.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_catalog_test.dart' show productJson;
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;

Map<String, Object?> snapshot({bool saved = true, bool unavailable = false}) =>
    {
      'items': saved
          ? [
              {
                'productId': 'product-id',
                'product': unavailable ? null : productJson(),
              },
            ]
          : [],
      'limit': 200,
    };

void main() {
  test(
    'cart save cannot acknowledge a favorite while its removal is pending',
    () async {
      final pending = Completer<http.Response>(), started = Completer<void>();
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'DELETE') {
            started.complete();
            return pending.future;
          }
          return jsonResponse(snapshot());
        }),
      );
      final c = RemoteWishlistController(api, signedIn: true);
      addTearDown(() {
        c.dispose();
        api.close();
      });
      await c.refresh();
      final removal = c.toggle('product-id');
      await started.future;
      await expectLater(c.save('product-id'), throwsA(isA<ApiException>()));
      pending.complete(jsonResponse(snapshot(saved: false)));
      await removal;
      expect(c.items, isEmpty);
    },
  );
  test(
    'loads private products, saves idempotently and removes unavailable entries',
    () async {
      var saved = false, puts = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            saved = true;
            puts++;
          }
          if (r.method == 'DELETE') saved = false;
          return jsonResponse(snapshot(saved: saved, unavailable: puts > 0));
        }),
      );
      final c = RemoteWishlistController(api, signedIn: true);
      addTearDown(() {
        c.dispose();
        api.close();
      });
      await c.refresh();
      expect(c.loaded, isTrue);
      expect(c.items, isEmpty);
      await c.save('product-id');
      await c.save('product-id');
      expect(puts, 1);
      expect(c.items.containsKey('product-id'), isTrue);
      expect(c.items['product-id'], isNull);
      await c.toggle('product-id');
      expect(c.items, isEmpty);
    },
  );
  test(
    'unknown write outcome requires refresh without a stale inverse toggle',
    () async {
      var saved = false, mutations = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method != 'GET') {
            saved = true;
            mutations++;
            throw http.ClientException('Lost response');
          }
          return jsonResponse(snapshot(saved: saved));
        }),
      );
      final c = RemoteWishlistController(api, signedIn: true);
      addTearDown(() {
        c.dispose();
        api.close();
      });
      await c.refresh();
      await expectLater(c.toggle('product-id'), throwsA(isA<ApiException>()));
      expect(c.loaded, isFalse);
      expect(c.error, isNotNull);
      expect(c.items, isEmpty);
      await c.toggle('product-id');
      expect(mutations, 1);
      expect(c.items.containsKey('product-id'), isTrue);
      expect(c.loaded, isTrue);
    },
  );
  test(
    'failed reads do not become an empty wishlist and allow explicit retry',
    () async {
      var fail = true;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient(
          (_) async => fail ? jsonResponse({}, 503) : jsonResponse(snapshot()),
        ),
      );
      final c = RemoteWishlistController(api, signedIn: true);
      addTearDown(() {
        c.dispose();
        api.close();
      });
      await expectLater(c.refresh(), throwsA(isA<ApiException>()));
      expect(c.loaded, isFalse);
      expect(c.error, isNotNull);
      fail = false;
      await c.refresh();
      expect(c.items['product-id']?.name, 'Áo cotton');
    },
  );
  test('late read and write cannot restore a disposed account cache', () async {
    for (final write in [false, true]) {
      final pending = Completer<http.Response>(), started = Completer<void>();
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (write && r.method == 'GET') {
            return jsonResponse(snapshot(saved: false));
          }
          started.complete();
          return pending.future;
        }),
      );
      final c = RemoteWishlistController(api, signedIn: true);
      if (write) await c.refresh();
      final operation = write ? c.save('product-id') : c.refresh();
      final rejected = expectLater(operation, throwsA(isA<ApiException>()));
      await started.future;
      c.dispose();
      pending.complete(jsonResponse(snapshot()));
      await rejected;
      expect(c.items, isEmpty);
      api.close();
    }
  });
  test(
    'same account relogin starts clean and admin-only login does not load shopper wishlist',
    () async {
      var reads = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            return jsonResponse(loginJson('customer'));
          }
          if (r.url.path.endsWith('/logout')) return jsonResponse({});
          reads++;
          return jsonResponse(snapshot());
        }),
      );
      final staff = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async => jsonResponse(loginJson('admin'))),
      );
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
          sessionTokensProvider.overrideWithValue(api.tokens),
          adminApiClientProvider.overrideWithValue(staff),
          adminSessionTokensProvider.overrideWithValue(staff.tokens),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
        staff.close();
      });
      await container
          .read(adminAccountProvider.notifier)
          .signIn('', 'admin@example.com', 'valid-password');
      expect(container.read(remoteWishlistProvider).signedIn, isFalse);
      expect(reads, 0);
      await container
          .read(accountProvider.notifier)
          .signIn('', 'customer@example.com', 'valid-password');
      final before = container.read(remoteWishlistProvider);
      await before.refresh();
      expect(before.items, isNotEmpty);
      await container.read(accountProvider.notifier).signOut();
      expect(container.read(remoteWishlistProvider).items, isEmpty);
      await container
          .read(accountProvider.notifier)
          .signIn('', 'customer@example.com', 'valid-password');
      final after = container.read(remoteWishlistProvider);
      expect(identical(before, after), isFalse);
      await after.refresh();
      expect(after.items, isNotEmpty);
      expect(container.read(adminAccountProvider), isNotNull);
    },
  );
}
