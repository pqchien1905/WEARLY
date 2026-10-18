import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;

void main() {
  testWidgets(
    'remote registration validates API password length and shows the saved profile',
    (tester) async {
      var registrations = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/auth/register')) {
            registrations++;
            expect((jsonDecode(r.body) as Map)['password'], 'example-password');
            return jsonResponse(sessionJson(), 201);
          }
          if (r.url.path.endsWith('/cart')) {
            return jsonResponse({
              'id': 'cart-1',
              'version': 0,
              'items': [],
              'subtotal': '0',
              'currency': 'VND',
            });
          }
          if (r.url.path.endsWith('/orders')) {
            return jsonResponse({
              'items': [],
              'total': 0,
              'page': 1,
              'limit': 100,
            });
          }
          return jsonResponse([]);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteApiProvider.overrideWithValue(true),
            apiClientProvider.overrideWithValue(api),
            sessionTokensProvider.overrideWithValue(api.tokens),
          ],
          child: NepApp(router: createRouter(initialLocation: '/register')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Mật khẩu'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên của bạn'),
        'Nguyễn An',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'an@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'shortpwd8',
      );
      final submit = find.widgetWithText(FilledButton, 'Tạo tài khoản');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(registrations, 0);
      expect(find.textContaining('12'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'example-password',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(registrations, 1);
      expect(find.text('Chào Nguyễn An.'), findsOneWidget);
      expect(find.text('Lưu hồ sơ'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Địa chỉ (không bắt buộc)'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
