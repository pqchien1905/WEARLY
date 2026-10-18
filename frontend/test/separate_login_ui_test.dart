import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/widgets/store_shell.dart';
import 'package:nep_storefront/features/admin/admin_shell.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;

void main() {
  Future<(ProviderContainer, GoRouter)> mount(
    WidgetTester tester,
    String path, {
    bool reject = false,
  }) async {
    final shopper = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return jsonResponse(loginJson('customer'));
        }
        throw StateError('Admin UI must not query the customer API: ${r.url}');
      }),
    );
    final staff = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/auth/admin/login')) {
          return reject
              ? jsonResponse({
                  'error': {'code': 'FORBIDDEN', 'message': 'Denied'},
                }, 403)
              : jsonResponse(loginJson('admin'));
        }
        if (r.url.path.endsWith('/auth/logout')) return jsonResponse({});
        throw StateError('Unexpected private request: ${r.url}');
      }),
    );
    final c = ProviderContainer(
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(shopper),
        sessionTokensProvider.overrideWithValue(shopper.tokens),
        adminApiClientProvider.overrideWithValue(staff),
        adminSessionTokensProvider.overrideWithValue(staff.tokens),
      ],
    );
    addTearDown(() {
      c.dispose();
      shopper.close();
      staff.close();
    });
    await c
        .read(accountProvider.notifier)
        .signIn('', 'customer@example.com', 'valid-password');
    final router = createRouter(initialLocation: path);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    return (c, router);
  }

  for (final width in [375.0, 1440.0]) {
    testWidgets(
      'admin deep link shows standalone login at $width and returns after authentication',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (c, router) = await mount(tester, '/admin/settings');
        expect(router.routeInformationProvider.value.uri.path, '/admin/login');
        expect(
          router.routeInformationProvider.value.uri.queryParameters['next'],
          '/admin/settings',
        );
        expect(find.byType(StoreShell), findsNothing);
        expect(find.byType(StoreFooter), findsNothing);
        expect(find.byType(AdminShell), findsNothing);
        expect(find.text('Đăng nhập khách hàng'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'),
          'administrator.with.a.long.email@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Mật khẩu'),
          'valid-password',
        );
        await tester.tap(find.byTooltip('Hiện mật khẩu'));
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.widgetWithText(TextFormField, 'Mật khẩu'),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isFalse,
        );
        final submit = find.widgetWithText(FilledButton, 'Đăng nhập quản trị');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          '/admin/settings',
        );
        expect(c.read(accountProvider)?.email, 'customer@example.com');
        expect(c.read(adminAccountProvider)?.role, 'ADMIN');
        await tester.tap(find.byTooltip('Đăng xuất quản trị'));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/admin/login');
        expect(c.read(accountProvider)?.email, 'customer@example.com');
        expect(c.read(adminAccountProvider), isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'admin form validates and keeps customer login when role is rejected',
    (tester) async {
      final (c, router) = await mount(tester, '/admin/login');
      final submit = find.widgetWithText(FilledButton, 'Đăng nhập quản trị');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(
        find.text('Nhập email hợp lệ, ví dụ ban@example.com.'),
        findsOneWidget,
      );
      expect(c.read(adminAccountProvider), isNull);
      router.go('/login');
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập khách hàng'), findsOneWidget);
      expect(find.byType(StoreShell), findsOneWidget);
    },
  );

  testWidgets(
    'customer credentials cannot enter admin or replace the shopper session',
    (tester) async {
      final (c, router) = await mount(tester, '/admin/login', reject: true);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'customer@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'),
        'valid-password',
      );
      final submit = find.widgetWithText(FilledButton, 'Đăng nhập quản trị');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/admin/login');
      expect(c.read(adminAccountProvider), isNull);
      expect(c.read(accountProvider)?.email, 'customer@example.com');
      expect(
        find.text(
          'Tài khoản này chưa có quyền quản trị. Vui lòng dùng tài khoản được cửa hàng cấp quyền.',
        ),
        findsOneWidget,
      );
    },
  );
}
