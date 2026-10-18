import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/network/session_tokens.dart';

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  for (final newerUser in [false, true]) {
    test(
      'late refresh cannot restore or overwrite a session (new user: $newerUser)',
      () async {
        final started = Completer<void>();
        final response = Completer<http.Response>();
        final tokens = SessionTokens()
          ..set(accessToken: 'old', refreshToken: 'old-refresh');
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          tokens: tokens,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/auth/refresh')) {
              started.complete();
              return response.future;
            }
            return jsonResponse({}, 401);
          }),
        );
        final pending = api.get('users/me');
        final rejection = expectLater(pending, throwsA(isA<ApiException>()));
        await started.future;
        tokens.clear();
        if (newerUser) {
          tokens.set(accessToken: 'new-user', refreshToken: 'new-user-refresh');
        }
        response.complete(
          jsonResponse({
            'accessToken': 'rotated-old',
            'refreshToken': 'rotated-old-refresh',
          }),
        );
        await rejection;
        expect(tokens.accessToken, newerUser ? 'new-user' : isNull);
        api.close();
      },
    );
  }

  test(
    'mutation retry preserves idempotency headers and request body',
    () async {
      final tokens = SessionTokens()
        ..set(accessToken: 'old', refreshToken: 'refresh');
      final sent = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokens: tokens,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return jsonResponse({
              'accessToken': 'new',
              'refreshToken': 'new-refresh',
            });
          }
          sent.add(request);
          return jsonResponse({}, sent.length == 1 ? 401 : 201);
        }),
      );
      await api.request(
        'POST',
        'orders',
        headers: {'Idempotency-Key': 'order-attempt'},
        body: {'addressId': 'address-1'},
      );
      expect(sent.length, 2);
      expect(
        sent.map((r) => r.headers['Idempotency-Key']),
        everyElement('order-attempt'),
      );
      expect(sent.first.body, sent.last.body);
      api.close();
    },
  );
  test('concurrent unauthorized requests share one refresh rotation', () async {
    final tokens = SessionTokens()
      ..set(accessToken: 'old', refreshToken: 'refresh-1');
    var refreshes = 0;
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokens: tokens,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          expect(jsonDecode(request.body), {'refreshToken': 'refresh-1'});
          return jsonResponse({
            'accessToken': 'new',
            'refreshToken': 'refresh-2',
          });
        }
        return request.headers['Authorization'] == 'Bearer new'
            ? jsonResponse({'name': 'An'})
            : jsonResponse({}, 401);
      }),
    );
    final values = await Future.wait([api.get('users/me'), api.get('cart')]);
    expect(values, [
      {'name': 'An'},
      {'name': 'An'},
    ]);
    expect(refreshes, 1);
    expect(tokens.refreshToken, 'refresh-2');
    api.close();
  });

  test(
    'a late unauthorized response cannot clear a newer signed-in user',
    () async {
      final response = Completer<http.Response>();
      final tokens = SessionTokens()
        ..set(accessToken: 'user-a', refreshToken: 'refresh-a');
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokens: tokens,
        client: MockClient((_) => response.future),
      );
      final pending = api.get('users/me');
      final rejection = expectLater(pending, throwsA(isA<ApiException>()));
      tokens.set(accessToken: 'user-b', refreshToken: 'refresh-b');
      response.complete(jsonResponse({}, 401));
      await rejection;
      expect(tokens.accessToken, 'user-b');
      api.close();
    },
  );
}
