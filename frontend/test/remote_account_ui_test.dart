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
  for (final browserScope in <String?>[null, 'customer']) {
    testWidgets(
      'duplicate registration explains email conflict and allows retry ($browserScope)',
      (tester) async {
        var registrations = 0;
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          browserScope: browserScope,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/refresh')) return jsonResponse({}, 401);
            if (r.url.path.endsWith('/register')) {
              registrations++;
              final body = jsonDecode(r.body) as Map;
              if (body['email'] == 'existing@example.com') {
                return jsonResponse({
                  'error': {
                    'code': 'EMAIL_ALREADY_EXISTS',
                    'message': 'An account with this email already exists',
                  },
                }, 409);
              }
              expect(body['email'], 'an@example.com');
              final session = sessionJson();
              if (browserScope != null) session.remove('refreshToken');
              return jsonResponse(session, 201);
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
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên của bạn'),
          'Nguyễn An',
        );
        final email = find.widgetWithText(TextFormField, 'Email');
        await tester.enterText(email, 'existing@example.com');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Mật khẩu'),
          'example-password',
        );
        await tester.enterText(
          find.byKey(const ValueKey('register-confirm')),
          'example-password',
        );
        final submit = find.widgetWithText(FilledButton, 'Tạo tài khoản');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(registrations, 1);
        expect(
          find.text(
            'Email này đã được đăng ký. Vui lòng đăng nhập hoặc chọn "Quên mật khẩu?" để khôi phục tài khoản.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Dữ liệu đã thay đổi. Tải lại trước khi tiếp tục.'),
          findsNothing,
        );
        expect(find.text('Đã có tài khoản? Đăng nhập'), findsOneWidget);
        expect(find.text('Quên mật khẩu?'), findsOneWidget);
        expect(api.tokens.accessToken, isNull);
        expect(
          tester.widget<TextFormField>(email).controller!.text,
          'existing@example.com',
        );
        await tester.enterText(email, 'an@example.com');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(registrations, 2);
        expect(find.text('Chào Nguyễn An.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
        'short7c',
      );
      final submit = find.widgetWithText(FilledButton, 'Tạo tài khoản');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(registrations, 0);
      expect(find.textContaining('8 đến 128'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'example-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('register-confirm')),
        'different-password',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(registrations, 0);
      expect(find.text('Hai mật khẩu chưa khớp.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('register-confirm')),
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
