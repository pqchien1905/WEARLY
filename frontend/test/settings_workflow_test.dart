import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/features/account/account_actions.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_commerce_test.dart' show cartJson;
import 'remote_session_test.dart' show jsonResponse;

class Fixture {
  bool failRead = false, failLogout = false;
  int reads = 0, logouts = 0;
  Completer<void>? holdRead, holdLogout;
  final recoveryCalls = <String>[];
  final changeCalls = <String>[];
  Map<String, Object?> profile = {
    ...sessionJson()['user'] as Map<String, Object?>,
  };
  late ProviderContainer container;
  late GoRouter router;

  Future<void> mount(
    WidgetTester tester, {
    bool guest = false,
    double width = 1440,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      browserScope: 'customer',
      client: MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/login')) {
          return jsonResponse({...sessionJson(), 'user': profile});
        }
        if (path.endsWith('/users/me')) {
          reads++;
          final snapshot = {...profile};
          if (holdRead != null) await holdRead!.future;
          return failRead ? jsonResponse({}, 503) : jsonResponse(snapshot);
        }
        if (path.endsWith('/logout')) {
          logouts++;
          if (holdLogout != null) await holdLogout!.future;
          return failLogout
              ? jsonResponse({}, 503)
              : jsonResponse({'loggedOut': true});
        }
        if (path.endsWith('/forgot-password')) {
          recoveryCalls.add('send');
          expect(jsonDecode(r.body), {'email': 'an@example.com'});
          return jsonResponse({'accepted': true}, 202);
        }
        if (path.endsWith('/verify-reset-code')) {
          recoveryCalls.add('verify');
          expect(jsonDecode(r.body), {
            'email': 'an@example.com',
            'code': '123456',
          });
          return jsonResponse({'resetToken': 'a' * 43});
        }
        if (path.endsWith('/reset-password')) {
          recoveryCalls.add('reset');
          expect(jsonDecode(r.body), {
            'token': 'a' * 43,
            'password': 'Changed-password-2026',
          });
          return jsonResponse({'changed': true});
        }
        if (path.endsWith('/change-password')) {
          final body = jsonDecode(r.body) as Map;
          changeCalls.add(body['currentPassword'] as String);
          return body['currentPassword'] == 'valid-password'
              ? jsonResponse({'changed': true})
              : jsonResponse({
                  'error': {'code': 'CURRENT_PASSWORD_INVALID'},
                }, 400);
        }
        if (path.endsWith('/cart')) return jsonResponse(cartJson(quantity: 0));
        if (path.endsWith('/orders')) {
          return jsonResponse({
            'items': [],
            'total': 0,
            'page': 1,
            'limit': 100,
          });
        }
        if (path.endsWith('/wishlist')) {
          return jsonResponse({'items': [], 'limit': 200});
        }
        return jsonResponse({'content': null});
      }),
    );
    container = ProviderContainer(
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(api),
        sessionTokensProvider.overrideWithValue(api.tokens),
        browserSessionBootstrapProvider.overrideWith((_) async {}),
      ],
    );
    addTearDown(() {
      container.dispose();
      api.close();
    });
    if (!guest) {
      await container
          .read(accountProvider.notifier)
          .signIn('', 'an@example.com', 'valid-password');
    }
    router = createRouter(initialLocation: '/account/settings');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder button(String label) => find.widgetWithText(TextButton, label);

void main() {
  testWidgets(
    'signed-in password change validates, reports a wrong current password and keeps the session',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(tester, find.widgetWithText(FilledButton, 'Đổi mật khẩu'));
      expect(find.text('Mật khẩu hiện tại'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Lưu mật khẩu mới');
      await tester.enterText(
        find.byKey(const ValueKey('change-current')),
        'wrong-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('change-next')),
        'Changed-password-2026',
      );
      await tester.enterText(
        find.byKey(const ValueKey('change-confirm')),
        'Mismatch-password-2026',
      );
      await tap(tester, save);
      expect(find.text('Hai mật khẩu chưa khớp.'), findsOneWidget);
      expect(f.changeCalls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('change-confirm')),
        'Changed-password-2026',
      );
      await tap(tester, save);
      expect(f.changeCalls, ['wrong-password']);
      expect(find.text('Mật khẩu hiện tại chưa đúng.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('change-current')),
        'valid-password',
      );
      await tap(tester, save);
      expect(f.changeCalls, ['wrong-password', 'valid-password']);
      expect(find.text('Lưu mật khẩu mới'), findsNothing);
      expect(
        find.text(
          'Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất khỏi tài khoản.',
        ),
        findsOneWidget,
      );
      expect(f.container.read(accountProvider), isNotNull);
      expect(f.logouts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'guest settings keeps return path and never loads personal data',
    (tester) async {
      final f = Fixture();
      await f.mount(tester, guest: true);
      expect(find.text('Đăng nhập để tiếp tục'), findsOneWidget);
      expect(f.reads, 0);
      await tap(tester, find.widgetWithText(FilledButton, 'Đăng nhập'));
      expect(
        f.router.routeInformationProvider.value.uri.queryParameters['next'],
        '/account/settings',
      );
    },
  );

  testWidgets(
    'failed refresh keeps profile; retry updates the shared account and absent phone is explicit',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(find.text('Chưa thêm số điện thoại'), findsOneWidget);
      f.failRead = true;
      await tap(tester, button('Tải lại thông tin'));
      expect(find.text('an@example.com'), findsOneWidget);
      expect(
        find.textContaining('Chưa cập nhật được thông tin.'),
        findsOneWidget,
      );
      f.failRead = false;
      f.profile['name'] = 'Nguyễn Minh An';
      f.profile['phone'] = '0901234567';
      await tap(tester, button('Thử lại'));
      expect(find.text('Đã cập nhật thông tin tài khoản.'), findsOneWidget);
      expect(f.container.read(accountProvider)!.name, 'Nguyễn Minh An');
      expect(find.text('0901234567'), findsOneWidget);
      expect(f.reads, 2);
    },
  );

  testWidgets(
    'refresh deduplicates stale callbacks and survives responsive reparenting',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      f.holdRead = Completer<void>();
      final action = tester
          .widget<TextButton>(button('Tải lại thông tin'))
          .onPressed!;
      action();
      action();
      await tester.pump();
      expect(f.reads, 1);
      tester.view.physicalSize = const Size(375, 1100);
      await tester.pump();
      expect(tester.widget<TextButton>(button('Đang tải…')).onPressed, isNull);
      f.holdRead!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Đã cập nhật thông tin tài khoản.'), findsOneWidget);
      expect(f.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a late profile read cannot replace the next account', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    f.holdRead = Completer<void>();
    tester.widget<TextButton>(button('Tải lại thông tin')).onPressed!();
    await tester.pump();
    f.profile = {
      ...f.profile,
      'id': 'other-user',
      'name': 'Khách khác',
      'email': 'other@example.com',
    };
    await f.container
        .read(accountProvider.notifier)
        .signIn('', 'other@example.com', 'valid-password');
    f.holdRead!.complete();
    await tester.pumpAndSettle();
    expect(find.text('an@example.com'), findsNothing);
    expect(find.text('other@example.com'), findsOneWidget);
    expect(f.container.read(accountProvider)!.id, 'other-user');
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy email confirms success and handles unavailable clipboard', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    var unavailable = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (unavailable) throw PlatformException(code: 'denied');
            expect(call.arguments, {'text': 'an@example.com'});
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tap(tester, button('Sao chép email'));
    expect(find.text('Đã sao chép email.'), findsOneWidget);
    unavailable = true;
    await tap(tester, button('Sao chép email'));
    expect(find.textContaining('Chưa sao chép được.'), findsOneWidget);
  });

  testWidgets(
    'all logout buttons share pending state, survive resize, retain errors and retry',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      f.holdLogout = Completer<void>();
      f.failLogout = true;
      final actions = tester
          .widgetList<TextButton>(button('Đăng xuất'))
          .map((w) => w.onPressed!)
          .toList();
      for (final action in actions) {
        action();
      }
      await tester.pump();
      expect(f.logouts, 1);
      expect(
        tester
            .widgetList<TextButton>(button('Đang đăng xuất…'))
            .every((w) => w.onPressed == null),
        isTrue,
      );
      tester.view.physicalSize = const Size(375, 1100);
      await tester.pump();
      expect(
        tester.widget<TextButton>(button('Đang đăng xuất…').last).onPressed,
        isNull,
      );
      f.holdLogout!.complete();
      await tester.pumpAndSettle();
      expect(f.container.read(accountProvider), isNotNull);
      expect(f.container.read(accountSignOutProvider).error, signOutError);
      expect(find.text(signOutError), findsWidgets);
      f.failLogout = false;
      f.holdLogout = null;
      await tap(tester, button('Đăng xuất').last);
      expect(f.logouts, 2);
      expect(f.container.read(accountProvider), isNull);
      expect(f.router.routeInformationProvider.value.uri.path, '/login');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logout finishes navigation after its original button was removed by resize',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      f.holdLogout = Completer<void>();
      tester.widget<TextButton>(button('Đăng xuất').last).onPressed!();
      await tester.pump();
      tester.view.physicalSize = const Size(375, 1100);
      await tester.pump();
      f.holdLogout!.complete();
      await tester.pumpAndSettle();
      expect(f.router.routeInformationProvider.value.uri.path, '/login');
      expect(f.logouts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'password change entered from settings completes verification and clears the customer session',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      await tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Dùng mã qua email'),
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('recovery-email')))
            .controller!
            .text,
        'an@example.com',
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Gửi mã xác nhận'));
      await tester.enterText(
        find.byKey(const ValueKey('recovery-code')),
        '123456',
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Xác nhận mã'));
      await tester.enterText(
        find.byKey(const ValueKey('recovery-password')),
        'Changed-password-2026',
      );
      await tester.enterText(
        find.byKey(const ValueKey('recovery-confirmation')),
        'Changed-password-2026',
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Lưu mật khẩu mới'));
      expect(find.text('Mật khẩu đã được thay đổi'), findsOneWidget);
      expect(f.container.read(accountProvider), isNull);
      expect(f.recoveryCalls, ['send', 'verify', 'reset']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('long profile and links fit 320px at 200 percent text scale', (
    tester,
  ) async {
    final f = Fixture();
    f.profile['email'] = '${'verylongemail' * 5}@example.com';
    f.profile['name'] = 'Nguyễn Minh Quang Chiến Nguyễn Minh Quang Chiến';
    await f.mount(tester, width: 320, scale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Quản lý ảnh thử đồ'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
