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
import 'package:nep_storefront/core/widgets/primitives.dart';
import 'package:nep_storefront/features/account/address_page.dart';
import 'address_retries_test.dart' show savedAddress;
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;
import 'remote_style_preferences_test.dart' show styleJson;

Future<ProviderContainer> mountBook(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle, {
  bool guest = false,
}) async {
  var logins = 0;
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((r) async {
      if (r.url.path.endsWith('/login')) {
        final value = sessionJson(),
            user = Map<String, Object?>.from(sessionJson()['user'] as Map);
        user['id'] = 'user-${++logins}';
        user['email'] = 'user-$logins@example.test';
        return jsonResponse({
          ...value,
          'user': user,
          'accessToken': 'user-$logins',
        });
      }
      if (r.url.path.endsWith('/logout')) return jsonResponse({});
      if (r.url.path.endsWith('/style')) return jsonResponse(styleJson());
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
  final router = GoRouter(
    initialLocation: '/account/addresses',
    routes: [
      GoRoute(
        path: '/account/addresses',
        builder: (_, _) =>
            const Scaffold(body: SingleChildScrollView(child: AddressPage())),
      ),
      GoRoute(
        path: '/login',
        builder: (_, s) =>
            Scaffold(body: Text('Return: ${s.uri.queryParameters['next']}')),
      ),
    ],
  );
  addTearDown(() {
    router.dispose();
    container.dispose();
    api.close();
  });
  if (!guest) {
    await container
        .read(accountProvider.notifier)
        .signIn('', 'user@example.test', 'password');
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router, theme: buildTheme()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapBook(WidgetTester tester, String label) async {
  await tester.pump();
  final f = find.text(label);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder formField(String title) => find.widgetWithText(TextFormField, title);

void main() {
  testWidgets(
    'guest login returns to the address book without fetching private data',
    (tester) async {
      var reads = 0;
      await mountBook(tester, (_) async {
        reads++;
        return jsonResponse([]);
      }, guest: true);
      await tapBook(tester, 'Đăng nhập');
      expect(find.text('Return: /account/addresses'), findsOneWidget);
      expect(reads, 0);
    },
  );
  testWidgets(
    'unchanged edits do not save or refetch; drafts survive resizing and confirm discard',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reads = 0;
      await mountBook(tester, (_) async {
        reads++;
        return jsonResponse([savedAddress()]);
      });
      await tapBook(tester, 'Chỉnh sửa');
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Lưu địa chỉ'))
            .onPressed,
        isNull,
      );
      await tapBook(tester, 'Hủy');
      expect(reads, 1);
      await tapBook(tester, 'Chỉnh sửa');
      await tester.enterText(formField('Người nhận'), 'Bản nháp riêng');
      tester.view.physicalSize = const Size(375, 900);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(formField('Người nhận')).controller!.text,
        'Bản nháp riêng',
      );
      await tapBook(tester, 'Hủy');
      expect(find.text('Bỏ thay đổi chưa lưu?'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(formField('Người nhận')).controller!.text,
        'Bản nháp riêng',
      );
      await tapBook(tester, 'Hủy');
      await tapBook(tester, 'Bỏ thay đổi');
      expect(reads, 1);
      expect(find.text('An'), findsOneWidget);
    },
  );
  testWidgets(
    'refresh failure preserves addresses and locks changes until a manual retry',
    (tester) async {
      var reads = 0;
      final pending = Completer<http.Response>();
      await mountBook(tester, (_) async {
        if (++reads == 2) return pending.future;
        return jsonResponse([savedAddress()]);
      });
      await tester.ensureVisible(find.text('Tải lại'));
      await tester.tap(find.text('Tải lại'));
      await tester.pump();
      expect(find.text('12 Nguyễn Huệ'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Thêm địa chỉ'))
            .onPressed,
        isNull,
      );
      pending.complete(jsonResponse({}, 503));
      await tester.pumpAndSettle();
      expect(find.text('Chưa cập nhật được sổ địa chỉ'), findsOneWidget);
      expect(find.text('12 Nguyễn Huệ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(reads, 2);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Chỉnh sửa'),
            )
            .onPressed,
        isNull,
      );
      await tapBook(tester, 'Thử lại');
      expect(find.text('Chưa cập nhật được sổ địa chỉ'), findsNothing);
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Thêm địa chỉ'))
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'uncertain edit keeps its draft and reconciles without resending PATCH',
    (tester) async {
      var row = savedAddress(), writes = 0;
      await mountBook(tester, (r) async {
        if (r.method == 'PATCH') {
          writes++;
          row = {...row, ...jsonDecode(r.body) as Map<String, dynamic>};
          return jsonResponse({}, 503);
        }
        return jsonResponse([row]);
      });
      await tapBook(tester, 'Chỉnh sửa');
      await tester.enterText(formField('Người nhận'), 'Tên đã lưu');
      await tapBook(tester, 'Lưu địa chỉ');
      expect(find.text('Kiểm tra lại'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(formField('Người nhận')).controller!.text,
        'Tên đã lưu',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Tên đã lưu'), findsOneWidget);
      expect(writes, 1);
    },
  );
  testWidgets(
    'default action rejects repeat clicks and reloads after a lost response',
    (tester) async {
      var secondDefault = false, writes = 0;
      final pending = Completer<http.Response>();
      await mountBook(tester, (r) async {
        if (r.method == 'PATCH') {
          writes++;
          secondDefault = true;
          return pending.future;
        }
        return jsonResponse([
          {...savedAddress(), 'isDefault': !secondDefault},
          {
            ...savedAddress(),
            'id': 'address-2',
            'label': 'Văn phòng',
            'isDefault': secondDefault,
          },
        ]);
      });
      final callback = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Đặt làm mặc định'),
          )
          .onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(writes, 1);
      expect(find.text('Đang xử lý địa chỉ…'), findsOneWidget);
      pending.complete(jsonResponse({}, 503));
      await tester.pumpAndSettle();
      final office = find.byKey(const ValueKey('account-address-address-2'));
      expect(
        find.descendant(of: office, matching: find.text('Mặc định')),
        findsOneWidget,
      );
      expect(writes, 1);
    },
  );
  for (final deleting in [false, true]) {
    testWidgets(
      'changing session hides the ${deleting ? 'delete confirmation' : 'editor'} and blocks old writes',
      (tester) async {
        var writes = 0;
        final container = await mountBook(tester, (r) async {
          if (r.method != 'GET') writes++;
          return jsonResponse(
            r.headers['Authorization'] == 'Bearer user-1'
                ? [savedAddress()]
                : [],
          );
        });
        await tapBook(tester, deleting ? 'Xóa' : 'Chỉnh sửa');
        await container.read(accountProvider.notifier).signOut();
        await tester.pumpAndSettle();
        await container
            .read(accountProvider.notifier)
            .signIn('', 'other@example.test', 'password');
        await tester.pumpAndSettle();
        expect(find.text('Phiên tài khoản đã thay đổi'), findsOneWidget);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('12 Nguyễn Huệ'), findsNothing);
        expect(find.text('Xác nhận'), findsNothing);
        await tapBook(tester, 'Đóng');
        expect(find.text('Chưa có địa chỉ nhận hàng'), findsOneWidget);
        expect(writes, 0);
      },
    );
  }
}
