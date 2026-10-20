import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/auth_routes.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_account.dart';
import 'package:nep_storefront/features/account/reset_password_page.dart';

void main() {
  test(
    'malformed success invalidates original sessions; late responses preserve a subsequent login',
    () async {
      final response = Completer<http.Response>();
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => response.future),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      final shopper = container.read(sessionTokensProvider),
          admin = container.read(adminSessionTokensProvider);
      shopper.set(accessToken: 'old', refreshToken: 'old-refresh');
      admin.set(accessToken: 'old-admin', refreshToken: 'old-admin-refresh');
      await expectLater(
        container
            .read(passwordRecoveryProvider)
            .reset('a' * 43, 'New-password-2026'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      expect(shopper.accessToken, isNull);
      expect(admin.accessToken, isNull);
      shopper.set(accessToken: 'new-session', refreshToken: 'new-refresh');
      response.complete(http.Response('{"changed":true}', 200));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(shopper.accessToken, 'new-session');

      final malformed = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((_) async => http.Response('{', 200)),
      );
      final other = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(malformed)],
      );
      addTearDown(() {
        other.dispose();
        malformed.close();
      });
      other
          .read(sessionTokensProvider)
          .set(accessToken: 'old', refreshToken: 'old-refresh');
      await expectLater(
        other
            .read(passwordRecoveryProvider)
            .reset('a' * 43, 'New-password-2026'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
      expect(other.read(sessionTokensProvider).accessToken, isNull);
    },
  );
  test(
    'request uses the public endpoint and never attaches an existing session',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/auth/forgot-password');
          expect(r.headers.containsKey('authorization'), false);
          expect(jsonDecode(r.body), {'email': 'customer@example.test'});
          return http.Response('{"accepted":true}', 202);
        }),
      );
      addTearDown(api.close);
      api.tokens.set(accessToken: 'session', refreshToken: 'refresh');
      await RemoteAccountRepository(
        api,
      ).requestPasswordReset(' customer@example.test ');
      expect(loginDestination('/reset-password?token=secret'), '/account');
    },
  );
  testWidgets(
    'reset removes the link token from routing and submits only once with confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(375, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final token = 'a' * 43;
      final writes = <http.Request>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          writes.add(r);
          return http.Response('{"changed":true}', 200);
        }),
      );
      addTearDown(api.close);
      final router = createRouter(
        initialLocation: '/reset-password?token=$token',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteApiProvider.overrideWithValue(true),
            apiClientProvider.overrideWithValue(api),
          ],
          child: NepApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/reset-password',
      );
      expect(find.byType(ResetPasswordPage), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Changed-password-2026',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Mismatch');
      final button = find.widgetWithText(FilledButton, 'Đặt lại mật khẩu');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Changed-password-2026',
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single.url.path, '/api/v1/auth/reset-password');
      expect(writes.single.url.query, isEmpty);
      expect(writes.single.headers.containsKey('authorization'), false);
      expect(jsonDecode(writes.single.body), {
        'token': token,
        'password': 'Changed-password-2026',
      });
      expect(find.text('Mật khẩu đã được thay đổi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
