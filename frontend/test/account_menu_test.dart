import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/widgets/account_menu.dart';
import 'package:nep_storefront/data/mock_account.dart';
import 'package:nep_storefront/features/account/account_settings_page.dart';
import 'package:nep_storefront/features/account/forgot_password_page.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;

final trigger = find.byKey(const ValueKey('account-menu-trigger'));
Finder item(String label) => find.widgetWithText(MenuItemButton, label);

Future<ProviderContainer> account(
  WidgetTester tester, {
  bool signedIn = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      accountRepositoryProvider.overrideWithValue(
        MockAccountRepository(latency: Duration.zero),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (signedIn) {
    await tester.runAsync(
      () => container
          .read(accountProvider.notifier)
          .signIn('Nguyễn An', 'an@example.com', 'demo-password'),
    );
  }
  return container;
}

Future<GoRouter> menuApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(
          body: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: AccountMenu(path: state.uri.path),
              ),
              Expanded(child: child),
            ],
          ),
        ),
        routes: [
          for (final path in [
            '/',
            '/account',
            '/account/orders',
            '/wishlist',
            '/account/settings',
            '/login',
            '/register',
          ])
            GoRoute(
              path: path,
              builder: (_, _) => Center(child: Text('Page $path')),
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'hover opens menu, crossing gap and dwelling inside keeps it open, leaving closes it',
    (tester) async {
      await menuApp(tester, await account(tester));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 500));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(trigger));
      await tester.pumpAndSettle();
      for (final label in [
        'Hồ sơ',
        'Đơn đặt hàng',
        'Yêu thích',
        'Cài đặt tài khoản',
        'Đăng xuất',
      ]) {
        expect(item(label), findsOneWidget);
      }
      expect(find.text('Kinh nghiệm'), findsNothing);
      expect(find.text('Đăng nhập'), findsNothing);
      await mouse.moveTo(tester.getBottomLeft(trigger) + const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(tester.getCenter(item('Cài đặt tài khoản')));
      await tester.pump(const Duration(seconds: 1));
      expect(item('Cài đặt tài khoản'), findsOneWidget);
      await mouse.moveTo(const Offset(10, 500));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(item('Hồ sơ'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'each menu destination works and guest has login instead of logout',
    (tester) async {
      final router = await menuApp(
        tester,
        await account(tester, signedIn: false),
      );
      for (final entry in [
        ('Hồ sơ', '/account'),
        ('Đơn đặt hàng', '/account/orders'),
        ('Yêu thích', '/wishlist'),
        ('Cài đặt tài khoản', '/account/settings'),
        ('Đăng nhập', '/login'),
        ('Tạo tài khoản', '/register'),
      ]) {
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        expect(item('Đăng xuất'), findsNothing);
        await tester.tap(item(entry.$1));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, entry.$2);
        expect(item('Hồ sơ'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard arrows select menu items, Escape restores focus, outside tap dismisses',
    (tester) async {
      final router = await menuApp(tester, await account(tester));
      tester.widget<IconButton>(trigger).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MenuItemButton>(item('Hồ sơ')).focusNode!.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/account/orders');
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(item('Hồ sơ'), findsNothing);
      expect(tester.widget<IconButton>(trigger).focusNode!.hasFocus, isTrue);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 500));
      await tester.pumpAndSettle();
      expect(item('Hồ sơ'), findsNothing);
    },
  );

  testWidgets('logout ends customer session and opens login', (tester) async {
    final container = await account(tester);
    final router = await menuApp(tester, container);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(item('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(container.read(accountProvider), isNull);
    expect(router.routeInformationProvider.value.uri.path, '/login');
  });

  for (final width in [320.0, 375.0, 768.0, 1440.0]) {
    testWidgets('settings and touch menu fit at $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await account(tester);
      final router = createRouter(initialLocation: '/account/settings');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: NepApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountSettingsPage), findsOneWidget);
      expect(find.text('an@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(item('Cài đặt tài khoản'));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(width));
      await tester.tap(item('Hồ sơ'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/account');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'settings opens password change with the signed-in email and sends recovery code',
    (tester) async {
      var sent = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/login')) {
            return jsonResponse(sessionJson());
          }
          if (request.url.path.endsWith('/forgot-password')) {
            sent++;
            expect(jsonDecode(request.body), {'email': 'an@example.com'});
            return jsonResponse({'accepted': true}, 202);
          }
          return jsonResponse({'content': null});
        }),
      );
      addTearDown(api.close);
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
          sessionTokensProvider.overrideWithValue(api.tokens),
          browserSessionBootstrapProvider.overrideWith((ref) async {}),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container
            .read(accountProvider.notifier)
            .signIn('', 'an@example.com', 'test-password'),
      );
      final router = GoRouter(
        initialLocation: '/account/settings',
        routes: [
          GoRoute(
            path: '/account/settings',
            builder: (_, _) => const Scaffold(
              body: SingleChildScrollView(child: AccountSettingsPage()),
            ),
          ),
          GoRoute(
            path: '/forgot-password',
            builder: (_, state) => Scaffold(
              body: SingleChildScrollView(
                child: ForgotPasswordPage(
                  fromAccount: state.uri.queryParameters['from'] == 'account',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final change = find.widgetWithText(OutlinedButton, 'Dùng mã qua email');
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('recovery-email')))
            .controller!
            .text,
        'an@example.com',
      );
      expect(find.text('Trở về cài đặt tài khoản'), findsOneWidget);
      final send = find.widgetWithText(FilledButton, 'Gửi mã xác nhận');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(sent, 1);
      expect(find.text('Kiểm tra email của bạn'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
