import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_account.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'remote_session_test.dart' show jsonResponse;

Map<String, Object?> sessionJson() => {
  'user': {
    'id': 'user-1',
    'name': 'Nguyễn An',
    'email': 'an@example.com',
    'phone': null,
    'role': 'CUSTOMER',
  },
  'accessToken': 'access-1',
  'refreshToken': 'refresh-1',
  'expiresIn': 900,
};
void main() {
  test(
    'invalidating remote account state cannot leave credentials from a pending login',
    () async {
      final response = Completer<http.Response>();
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((_) => response.future),
      );
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          sessionTokensProvider.overrideWithValue(api.tokens),
          apiClientProvider.overrideWithValue(api),
        ],
      );
      final pending = container
          .read(accountProvider.notifier)
          .signIn('', 'an@example.com', 'example-password');
      final finished = pending.catchError((_) {});
      container.invalidate(accountProvider);
      expect(container.read(accountProvider), isNull);
      response.complete(jsonResponse(sessionJson()));
      await finished;
      expect(api.tokens.accessToken, isNull);
      container.dispose();
      api.close();
    },
  );
  test(
    'registration maps the real user and retains tokens only in the shared session',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/auth/register');
          expect(jsonDecode(r.body), {
            'name': 'Nguyễn An',
            'email': 'an@example.com',
            'password': 'example-password',
          });
          return jsonResponse(sessionJson(), 201);
        }),
      );
      final repo = RemoteAccountRepository(api);
      final user = await repo.signIn(
        name: 'Nguyễn An',
        email: 'an@example.com',
        password: 'example-password',
        register: true,
      );
      expect(user.id, 'user-1');
      expect(user.phone, '');
      expect(api.tokens.accessToken, 'access-1');
      api.close();
    },
  );
  test(
    'logout cancels a pending login even if its HTTP response succeeds',
    () async {
      final response = Completer<http.Response>();
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((_) => response.future),
      );
      final repo = RemoteAccountRepository(api);
      final pending = repo.signIn(
        name: '',
        email: 'an@example.com',
        password: 'example-password',
      );
      final rejection = expectLater(pending, throwsA(isA<ApiException>()));
      await repo.signOut();
      response.complete(jsonResponse(sessionJson()));
      await rejection;
      expect(api.tokens.accessToken, isNull);
      api.close();
    },
  );
  test(
    'logout clears locally immediately and revokes with the previous bearer',
    () async {
      final response = Completer<http.Response>();
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/auth/logout');
          expect(r.headers['Authorization'], 'Bearer access-1');
          return response.future;
        }),
      );
      api.tokens.set(accessToken: 'access-1', refreshToken: 'refresh-1');
      final pending = RemoteAccountRepository(api).signOut();
      expect(api.tokens.accessToken, isNull);
      response.complete(jsonResponse({'loggedOut': true}));
      await pending;
      api.close();
    },
  );
  test(
    'profile sends only supported fields and never claims to save an address',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.method, 'PATCH');
          expect(jsonDecode(r.body), {'name': 'An', 'phone': '0901234567'});
          return jsonResponse({
            'id': 'user-1',
            'name': 'An',
            'email': 'an@example.com',
            'phone': '0901234567',
            'role': 'CUSTOMER',
          });
        }),
      );
      final user = await RemoteAccountRepository(api).save(
        const UserProfile(
          name: 'An',
          email: 'an@example.com',
          phone: '0901234567',
        ),
      );
      expect(user.phone, '0901234567');
      expect(user.id, 'user-1');
      api.close();
    },
  );
  test('password reset explicitly reports missing integration', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((_) async => throw StateError('No API call expected')),
    );
    await expectLater(
      RemoteAccountRepository(api).requestPasswordReset('an@example.com'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'NOT_AVAILABLE'),
      ),
    );
    api.close();
  });
}
