import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/features/account/account_profile_page.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;

Finder field(String label) => find.widgetWithText(TextFormField, label);
Finder get submit => find.widgetWithText(FilledButton, 'Lưu hồ sơ');
Finder get undo => find.widgetWithText(OutlinedButton, 'Hoàn tác thay đổi');
String fieldValue(WidgetTester t, String label) =>
    t.widget<TextFormField>(field(label)).controller!.text;

Future<ProviderContainer> mountProfile(
  WidgetTester t,
  Future<http.Response> Function(http.Request) handle, {
  double width = 1440,
  double scale = 1,
  String? initialName,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 1100);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((r) async {
      if (r.url.path.endsWith('/login')) {
        final session = sessionJson();
        final user = session['user'] as Map;
        if (initialName != null) user['name'] = initialName;
        final email = (jsonDecode(r.body) as Map)['email'];
        if (email == 'other@example.com') {
          user['id'] = 'user-2';
          user['email'] = email;
          user['name'] = 'Tài khoản mới';
        }
        return jsonResponse(session);
      }
      return handle(r);
    }),
  );
  final container = ProviderContainer(
    overrides: [
      remoteApiProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(api),
      sessionTokensProvider.overrideWithValue(api.tokens),
    ],
  );
  addTearDown(api.close);
  addTearDown(container.dispose);
  await t.runAsync(
    () => container
        .read(accountProvider.notifier)
        .signIn('', 'an@example.com', 'example-password'),
  );
  final router = GoRouter(
    initialLocation: '/account',
    routes: [
      GoRoute(
        path: '/account',
        builder: (_, _) =>
            const Scaffold(body: SingleChildScrollView(child: AccountPage())),
      ),
      for (final route in [
        '/account/orders',
        '/account/addresses',
        '/account/style',
        '/account/try-ons',
        '/wishlist',
        '/account/settings',
        '/login',
      ])
        GoRoute(
          path: route,
          builder: (_, _) => Scaffold(body: Text('Route $route')),
        ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

Future<void> tap(WidgetTester t, Finder target, {bool settle = true}) async {
  await t.pump();
  await t.ensureVisible(target);
  await t.tap(target);
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
}

http.Response savedProfile(String name, String phone) => jsonResponse({
  ...(sessionJson()['user'] as Map),
  'name': name,
  'phone': phone,
});

void main() {
  testWidgets(
    'dirty state, undo, normalized save and clearing optional phone',
    (t) async {
      final writes = <Map>[];
      await mountProfile(t, (r) async {
        final body = jsonDecode(r.body) as Map;
        writes.add(body);
        return savedProfile(body['name'], body['phone']);
      });
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      expect(
        t
            .widget<TextField>(
              find.descendant(
                of: field('Email đăng nhập'),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await t.enterText(field('Họ và tên'), '  Nguyễn An  ');
      await t.pump();
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.enterText(field('Họ và tên'), '  An mới  ');
      await t.enterText(field('Điện thoại (không bắt buộc)'), '0901234567');
      await t.pump();
      expect(find.text('Bạn có thay đổi chưa lưu.'), findsOneWidget);
      await tap(t, undo);
      expect(fieldValue(t, 'Họ và tên'), 'Nguyễn An');
      expect(fieldValue(t, 'Điện thoại (không bắt buộc)'), '');
      expect(writes, isEmpty);
      await t.enterText(field('Họ và tên'), '  An mới  ');
      await t.enterText(field('Điện thoại (không bắt buộc)'), '0901234567');
      await tap(t, submit);
      expect(writes.single, {'name': 'An mới', 'phone': '0901234567'});
      expect(fieldValue(t, 'Họ và tên'), 'An mới');
      expect(find.text('Thông tin mới đã được lưu.'), findsOneWidget);
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.enterText(field('Họ và tên'), 'Bản nháp');
      await tap(t, undo);
      expect(fieldValue(t, 'Họ và tên'), 'An mới');
      await t.enterText(field('Điện thoại (không bắt buộc)'), '');
      await tap(t, submit);
      expect(writes.last['phone'], '');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('invalid fields never reach API and undo clears errors', (
    t,
  ) async {
    var writes = 0;
    await mountProfile(t, (_) async {
      writes++;
      return savedProfile('An', '');
    });
    await t.enterText(field('Họ và tên'), ' ');
    await t.enterText(field('Điện thoại (không bắt buộc)'), '123');
    await tap(t, submit);
    expect(
      find.text('Nhập số điện thoại 7–15 chữ số hoặc để trống.'),
      findsOneWidget,
    );
    await t.enterText(field('Họ và tên'), 'A' * 101);
    await tap(t, submit);
    expect(find.text('Họ và tên không quá 100 ký tự.'), findsOneWidget);
    expect(writes, 0);
    await tap(t, undo);
    expect(find.text('Họ và tên không quá 100 ký tự.'), findsNothing);
    expect(
      find.text('Nhập số điện thoại 7–15 chữ số hoặc để trống.'),
      findsNothing,
    );
    expect(fieldValue(t, 'Họ và tên'), 'Nguyễn An');
  });

  testWidgets('save failure retains draft and retry persists it', (t) async {
    var writes = 0;
    await mountProfile(t, (r) async {
      if (++writes == 1) {
        return jsonResponse({
          'error': {'code': 'SERVICE_UNAVAILABLE'},
        }, 503);
      }
      final body = jsonDecode(r.body) as Map;
      return savedProfile(body['name'], body['phone']);
    });
    await t.enterText(field('Họ và tên'), 'Tên chưa lưu');
    await tap(t, submit);
    expect(find.textContaining('Chưa lưu được hồ sơ.'), findsOneWidget);
    expect(fieldValue(t, 'Họ và tên'), 'Tên chưa lưu');
    await tap(t, submit);
    expect(writes, 2);
    expect(find.text('Thông tin mới đã được lưu.'), findsOneWidget);
  });

  testWidgets('pending save locks fields, shortcuts and duplicate submission', (
    t,
  ) async {
    final response = Completer<http.Response>();
    var writes = 0;
    await mountProfile(t, (_) {
      writes++;
      return response.future;
    });
    await t.enterText(field('Họ và tên'), 'Tên đang lưu');
    await tap(t, submit, settle: false);
    await t.pump();
    expect(t.widget<FilledButton>(submit).onPressed, isNull);
    expect(t.widget<OutlinedButton>(undo).onPressed, isNull);
    expect(
      t
          .widget<TextField>(
            find.descendant(
              of: field('Họ và tên'),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    expect(
      t
          .widget<ListTile>(find.widgetWithText(ListTile, 'Xem lịch sử thử đồ'))
          .onTap,
      isNull,
    );
    await t.tap(submit);
    expect(writes, 1);
    response.complete(savedProfile('Tên đang lưu', ''));
    await t.pumpAndSettle();
    expect(find.text('Thông tin mới đã được lưu.'), findsOneWidget);
  });

  testWidgets('late save from another account cannot affect current editor', (
    t,
  ) async {
    final response = Completer<http.Response>();
    final container = await mountProfile(t, (_) => response.future);
    await t.enterText(field('Họ và tên'), 'Bản nháp cũ');
    await tap(t, submit, settle: false);
    await t.runAsync(
      () => container
          .read(accountProvider.notifier)
          .signIn('', 'other@example.com', 'example-password'),
    );
    await t.pumpAndSettle();
    expect(fieldValue(t, 'Họ và tên'), 'Tài khoản mới');
    response.complete(savedProfile('Bản nháp cũ', ''));
    await t.pumpAndSettle();
    expect(fieldValue(t, 'Họ và tên'), 'Tài khoản mới');
    expect(find.text('Thông tin mới đã được lưu.'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('external profile update does not overwrite a draft silently', (
    t,
  ) async {
    final container = await mountProfile(
      t,
      (_) async => savedProfile('Tên cập nhật', '0901234567'),
    );
    await t.enterText(field('Họ và tên'), 'Bản nháp');
    await t.runAsync(
      () => container
          .read(accountProvider.notifier)
          .save(
            const UserProfile(
              id: 'user-1',
              name: 'Tên cập nhật',
              email: 'an@example.com',
              phone: '0901234567',
            ),
          ),
    );
    await t.pumpAndSettle();
    expect(fieldValue(t, 'Họ và tên'), 'Bản nháp');
    expect(find.textContaining('Hồ sơ vừa được cập nhật.'), findsOneWidget);
    expect(t.widget<FilledButton>(submit).onPressed, isNull);
    await tap(t, undo);
    expect(fieldValue(t, 'Họ và tên'), 'Tên cập nhật');
    expect(fieldValue(t, 'Điện thoại (không bắt buộc)'), '0901234567');
  });

  for (final size in [
    (320.0, 1.0),
    (375.0, 2.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (1920.0, 1.0),
    (2560.0, 1.0),
  ]) {
    testWidgets('profile supports ${size.$1}px and text scale ${size.$2}', (
      t,
    ) async {
      await mountProfile(
        t,
        (_) async => savedProfile('An', ''),
        width: size.$1,
        scale: size.$2,
        initialName: 'Nguyễn Hoàng Phương Anh',
      );
      await t.enterText(field('Họ và tên'), 'Tên mới');
      await tap(t, undo);
      final shortcut = find.widgetWithText(ListTile, 'Xem lịch sử thử đồ');
      await tap(t, shortcut);
      expect(find.text('Route /account/try-ons'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
