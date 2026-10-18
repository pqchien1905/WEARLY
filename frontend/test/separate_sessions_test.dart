import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_session_test.dart' show jsonResponse;

Map<String, Object?> loginJson(String area, {String? role}) => {
  'user': {
    'id': '$area-user',
    'name': area,
    'email': '$area@example.com',
    'phone': '',
    'role': role ?? (area == 'admin' ? 'ADMIN' : 'CUSTOMER'),
  },
  'accessToken': '$area-access',
  'refreshToken': '$area-refresh',
  'expiresIn': 900,
};

void main() {
  ProviderContainer setup(ApiClient customer, ApiClient admin) {
    final container = ProviderContainer(
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(customer),
        sessionTokensProvider.overrideWithValue(customer.tokens),
        adminApiClientProvider.overrideWithValue(admin),
        adminSessionTokensProvider.overrideWithValue(admin.tokens),
      ],
    );
    addTearDown(() {
      container.dispose();
      customer.close();
      admin.close();
    });
    return container;
  }

  test(
    'admin and shopper logins, requests and logouts use independent sessions',
    () async {
      final seen = <String>[];
      ApiClient client(String area) => ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          seen.add(
            '$area ${r.method} ${r.url.path} ${r.headers['authorization']}',
          );
          if (r.url.path.endsWith('/login')) {
            return jsonResponse(loginJson(area));
          }
          return jsonResponse({});
        }),
      );
      final customer = client('customer'), admin = client('admin');
      final c = setup(customer, admin);
      await c
          .read(accountProvider.notifier)
          .signIn('', 'customer@example.com', 'valid-password');
      await c
          .read(adminAccountProvider.notifier)
          .signIn('', 'admin@example.com', 'valid-password');
      expect(c.read(accountProvider)?.email, 'customer@example.com');
      expect(c.read(adminAccountProvider)?.email, 'admin@example.com');
      await admin.get('admin/users');
      await customer.get('cart');
      expect(seen, contains('admin POST /api/v1/auth/admin/login null'));
      expect(
        seen,
        contains('admin GET /api/v1/admin/users Bearer admin-access'),
      );
      expect(
        seen,
        contains('customer GET /api/v1/cart Bearer customer-access'),
      );
      await c.read(adminAccountProvider.notifier).signOut();
      expect(c.read(accountProvider), isNotNull);
      expect(customer.tokens.accessToken, 'customer-access');
      await c
          .read(adminAccountProvider.notifier)
          .signIn('', 'admin@example.com', 'valid-password');
      await c.read(accountProvider.notifier).signOut();
      expect(c.read(adminAccountProvider), isNotNull);
      expect(admin.tokens.accessToken, 'admin-access');
    },
  );
  test(
    'wrong-role staff response never installs tokens or changes shopper identity',
    () async {
      final customer = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async => jsonResponse(loginJson('customer'))),
      );
      final admin = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient(
          (r) async => jsonResponse(loginJson('admin', role: 'CUSTOMER')),
        ),
      );
      final c = setup(customer, admin);
      await c
          .read(accountProvider.notifier)
          .signIn('', 'customer@example.com', 'valid-password');
      await expectLater(
        c
            .read(adminAccountProvider.notifier)
            .signIn('', 'customer@example.com', 'valid-password'),
        throwsA(isA<ApiException>()),
      );
      expect(c.read(adminAccountProvider), isNull);
      expect(admin.tokens.accessToken, isNull);
      expect(c.read(accountProvider)?.email, 'customer@example.com');
    },
  );
  test(
    'expired admin refresh clears only admin and late login cannot restore it',
    () async {
      var expire = false;
      final customer = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async => jsonResponse(loginJson('customer'))),
      );
      final admin = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient(
          (r) async =>
              expire ? jsonResponse({}, 401) : jsonResponse(loginJson('admin')),
        ),
      );
      final c = setup(customer, admin);
      await c
          .read(accountProvider.notifier)
          .signIn('', 'customer@example.com', 'valid-password');
      await c
          .read(adminAccountProvider.notifier)
          .signIn('', 'admin@example.com', 'valid-password');
      expire = true;
      await expectLater(admin.get('admin/users'), throwsA(isA<ApiException>()));
      expect(c.read(adminAccountProvider), isNull);
      expect(c.read(accountProvider), isNotNull);
      expect(customer.tokens.accessToken, 'customer-access');
    },
  );
  test(
    'a late admin sign-in cannot restore a signed-out staff session',
    () async {
      final response = Completer<http.Response>(), started = Completer<void>();
      final customer = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async => jsonResponse(loginJson('customer'))),
      );
      final admin = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) {
          started.complete();
          return response.future;
        }),
      );
      final c = setup(customer, admin);
      final login = c
          .read(adminAccountProvider.notifier)
          .signIn('', 'admin@example.com', 'valid-password');
      final rejected = expectLater(login, throwsA(isA<ApiException>()));
      await started.future;
      await c.read(adminAccountProvider.notifier).signOut();
      response.complete(jsonResponse(loginJson('admin')));
      await rejected;
      expect(c.read(adminAccountProvider), isNull);
      expect(admin.tokens.accessToken, isNull);
    },
  );
}
