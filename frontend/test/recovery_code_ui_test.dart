import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/features/account/forgot_password_page.dart';
import 'remote_session_test.dart' show jsonResponse;

void main() {
  for (final width in [375.0, 1280.0]) {
    testWidgets(
      'recovery accepts pasted codes, validates and resets in place at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var requests = 0, verifications = 0, resets = 0;
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          client: MockClient((r) async {
            if (r.url.path.contains('/auth/')) {
              expect(r.headers.containsKey('authorization'), isFalse);
              expect(r.url.query, isEmpty);
            }
            final body = r.body.isEmpty ? null : jsonDecode(r.body) as Map;
            if (r.url.path.endsWith('/forgot-password')) {
              requests++;
              expect(body, {'email': 'customer@example.test'});
              return jsonResponse({'accepted': true}, 202);
            }
            if (r.url.path.endsWith('/verify-reset-code')) {
              verifications++;
              if (body!['code'] != '012345') {
                return jsonResponse({
                  'error': {'code': 'RESET_CODE_INVALID'},
                }, 400);
              }
              return jsonResponse({'resetToken': 'a' * 43, 'expiresIn': 600});
            }
            if (r.url.path.endsWith('/reset-password')) {
              resets++;
              expect(body, {
                'token': 'a' * 43,
                'password': 'New-password-2026',
              });
              return jsonResponse({'changed': true});
            }
            return jsonResponse({'content': null});
          }),
        );
        addTearDown(api.close);
        final router = createRouter(initialLocation: '/forgot-password');
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
        Future<void> press(String label) async {
          final button = find.widgetWithText(FilledButton, label);
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }

        await press('Gửi mã xác nhận');
        expect(requests, 0);
        await tester.enterText(
          find.byKey(const ValueKey('recovery-email')),
          ' Customer@Example.test ',
        );
        await press('Gửi mã xác nhận');
        expect(requests, 1);
        expect(find.text('Gửi lại mã sau 60s'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('recovery-code')),
          '123',
        );
        await press('Xác nhận mã');
        expect(verifications, 0);
        await tester.enterText(
          find.byKey(const ValueKey('recovery-code')),
          '111111',
        );
        await press('Xác nhận mã');
        expect(find.textContaining('Mã không đúng'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('recovery-code')),
          '01 23 45',
        );
        await press('Xác nhận mã');
        expect(verifications, 2);
        await tester.enterText(
          find.byKey(const ValueKey('recovery-password')),
          'New-password-2026',
        );
        await tester.enterText(
          find.byKey(const ValueKey('recovery-confirmation')),
          'different',
        );
        await press('Lưu mật khẩu mới');
        expect(resets, 0);
        await tester.enterText(
          find.byKey(const ValueKey('recovery-confirmation')),
          'New-password-2026',
        );
        await press('Lưu mật khẩu mới');
        expect(resets, 1);
        expect(find.text('Mật khẩu đã được thay đổi'), findsOneWidget);
        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/forgot-password',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('leaving during reset safely ignores a late response', (
    tester,
  ) async {
    final completed = Completer<void>();
    var resetStarted = false;
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/forgot-password')) {
          return jsonResponse({'accepted': true}, 202);
        }
        if (r.url.path.endsWith('/verify-reset-code')) {
          return jsonResponse({'resetToken': 'a' * 43, 'expiresIn': 600});
        }
        resetStarted = true;
        await completed.future;
        return jsonResponse({'changed': true});
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ForgotPasswordPage()),
          ),
        ),
      ),
    );
    Future<void> enter(String key, String text) async =>
        tester.enterText(find.byKey(ValueKey(key)), text);
    Future<void> press(String text) async {
      final button = find.widgetWithText(FilledButton, text);
      await tester.ensureVisible(button);
      await tester.tap(button);
    }

    await enter('recovery-email', 'customer@example.test');
    await press('Gửi mã xác nhận');
    await tester.pumpAndSettle();
    await enter('recovery-code', '012345');
    await press('Xác nhận mã');
    await tester.pumpAndSettle();
    await enter('recovery-password', 'New-password-2026');
    await enter('recovery-confirmation', 'New-password-2026');
    await press('Lưu mật khẩu mới');
    await tester.pump();
    expect(resetStarted, isTrue);
    await tester.pumpWidget(const SizedBox());
    completed.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resend waits sixty seconds and changing email clears the previous code',
    (tester) async {
      var requests = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/forgot-password')) {
            requests++;
            return jsonResponse({'accepted': true}, 202);
          }
          return jsonResponse({'content': null});
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remoteApiProvider.overrideWithValue(true),
            apiClientProvider.overrideWithValue(api),
          ],
          child: NepApp(
            router: createRouter(initialLocation: '/forgot-password'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recovery-email')),
        'customer@example.test',
      );
      final send = find.widgetWithText(FilledButton, 'Gửi mã xác nhận');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      final disabled = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Gửi lại mã sau 60s'),
      );
      expect(disabled.onPressed, isNull);
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      final resend = find.widgetWithText(TextButton, 'Gửi lại mã');
      await tester.ensureVisible(resend);
      await tester.tap(resend);
      await tester.pumpAndSettle();
      expect(requests, 2);
      await tester.enterText(
        find.byKey(const ValueKey('recovery-code')),
        '123456',
      );
      final edit = find.widgetWithText(TextButton, 'Đổi email');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recovery-code')), findsNothing);
      expect(find.byKey(const ValueKey('recovery-email')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
