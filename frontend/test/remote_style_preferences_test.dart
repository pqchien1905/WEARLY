import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/account_details.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/remote_route_gate.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_account_details.dart';
import 'package:nep_storefront/features/account/style_page.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;

Map<String, dynamic> styleJson({String size = 'M', int version = 0}) => {
  'size': size,
  'style': '',
  'color': '',
  'budget': '1500000',
  'version': version,
};

Future<ProviderContainer> mountStyle(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle, {
  bool guest = false,
  bool staffOnly = false,
}) async {
  var logins = 0;
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((r) async {
      if (r.url.path.endsWith('/login')) {
        return jsonResponse(loginJson('customer${++logins}'));
      }
      if (r.url.path.endsWith('/logout')) return jsonResponse({});
      if (r.url.path.endsWith('/addresses')) return jsonResponse([]);
      return handle(r);
    }),
  );
  final staff = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((_) async => jsonResponse(loginJson('admin'))),
  );
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      remoteApiProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(api),
      sessionTokensProvider.overrideWithValue(api.tokens),
      adminApiClientProvider.overrideWithValue(staff),
      adminSessionTokensProvider.overrideWithValue(staff.tokens),
    ],
  );
  final router = GoRouter(
    initialLocation: '/account/style',
    routes: [
      GoRoute(
        path: '/account/style',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(
            child: RemoteRouteGate(path: '/account/style', child: StylePage()),
          ),
        ),
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
    staff.close();
  });
  if (!guest && !staffOnly) {
    await container
        .read(accountProvider.notifier)
        .signIn('', 'buyer@example.test', 'password');
  }
  if (staffOnly) {
    await container
        .read(adminAccountProvider.notifier)
        .signIn('', 'staff@example.test', 'password');
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapStyle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> chooseSize(WidgetTester tester, String size) async {
  await tapStyle(
    tester,
    find.widgetWithText(DropdownButtonFormField<String>, 'Size thường chọn'),
  );
  await tapStyle(tester, find.text(size).last);
}

void main() {
  test(
    'remote style read and save preserve version, VND and address data',
    () async {
      var current = styleJson(version: 4);
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/addresses')) {
            return jsonResponse([
              {
                'id': 'a1',
                'label': 'Nhà',
                'recipient': 'An',
                'phone': '0901234567',
                'address': '12 Test',
                'isDefault': true,
              },
            ]);
          }
          expect(r.url.path, '/api/v1/users/me/style');
          if (r.method == 'PUT') {
            expect(jsonDecode(r.body), {
              'size': 'L',
              'style': 'Thanh lịch',
              'color': 'Đen',
              'budget': '2500000',
              'expectedVersion': 4,
            });
            current = {
              'size': 'L',
              'style': 'Thanh lịch',
              'color': 'Đen',
              'budget': '2500000',
              'version': 5,
            };
          }
          return jsonResponse(current);
        }),
      );
      addTearDown(api.close);
      final repo = RemoteAccountDetailsRepository(api);
      expect((await repo.read()).style.version, 4);
      final saved = await repo.saveStyle(
        const StylePreferences(
          size: 'L',
          style: 'Thanh lịch',
          color: 'Đen',
          budget: 2500000,
          version: 4,
        ),
      );
      expect(saved.style.version, 5);
      expect(saved.style.budget, 2500000);
      expect(saved.defaultAddressId, 'a1');
      expect(saved.addresses.single.recipient, 'An');
    },
  );
  test(
    'invalid style response is explicit and not replaced with defaults',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient(
          (r) async => jsonResponse(
            r.url.path.endsWith('/addresses')
                ? []
                : {...styleJson(), 'budget': 1500000},
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        RemoteAccountDetailsRepository(api).read(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    },
  );
  test(
    'a timed-out style write notifies late completion once without replay',
    () async {
      final late = Completer<http.Response>();
      var writes = 0, settled = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        timeout: const Duration(milliseconds: 15),
        client: MockClient((r) async {
          writes++;
          return late.future;
        }),
      );
      addTearDown(api.close);
      final repo = RemoteAccountDetailsRepository(
        api,
        onLateStyleCompletion: () => settled++,
      );
      await expectLater(
        repo.saveStyle(const StylePreferences()),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      late.complete(jsonResponse(styleJson(version: 1)));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(writes, 1);
      expect(settled, 1);
    },
  );
  test(
    'post-write read failure is not reported as a successful save',
    () async {
      var writes = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            writes++;
            return jsonResponse(styleJson(version: 1));
          }
          return jsonResponse({}, 500);
        }),
      );
      addTearDown(api.close);
      await expectLater(
        RemoteAccountDetailsRepository(api).saveStyle(const StylePreferences()),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)),
      );
      expect(writes, 1);
    },
  );
  for (final staffOnly in [false, true]) {
    testWidgets(
      'style requires customer login and retains return path: $staffOnly',
      (tester) async {
        var reads = 0;
        await mountStyle(
          tester,
          (_) async {
            reads++;
            return jsonResponse(styleJson());
          },
          guest: true,
          staffOnly: staffOnly,
        );
        expect(reads, 0);
        await tapStyle(tester, find.text('Đăng nhập'));
        expect(find.text('Return: /account/style'), findsOneWidget);
      },
    );
  }
  for (final width in [375.0, 1440.0]) {
    testWidgets('style saves twice with advanced version at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var current = styleJson(), writes = 0;
      await mountStyle(tester, (r) async {
        if (r.method == 'PUT') {
          final body = jsonDecode(r.body) as Map;
          expect(body['expectedVersion'], writes++);
          current = {...current, 'size': body['size'], 'version': writes};
        }
        return jsonResponse(current);
      });
      expect(find.text('Lưu & mở Stylist'), findsNothing);
      expect(find.textContaining('Hồ sơ được xóa khi đăng xuất'), findsNothing);
      await chooseSize(tester, 'L');
      await tapStyle(tester, find.text('Lưu hồ sơ phong cách'));
      expect(find.text('Đã lưu hồ sơ phong cách.'), findsOneWidget);
      await chooseSize(tester, 'S');
      await tapStyle(tester, find.text('Lưu hồ sơ phong cách'));
      expect(writes, 2);
      expect(current['size'], 'S');
      expect(tester.takeException(), isNull);
    });
  }
  for (final status in [409, 500]) {
    testWidgets(
      'uncertain or stale save locks until explicit reload: $status',
      (tester) async {
        var current = styleJson(), writes = 0;
        await mountStyle(tester, (r) async {
          if (r.method == 'PUT') {
            writes++;
            current = styleJson(size: 'XL', version: 2);
            return jsonResponse({}, status);
          }
          return jsonResponse(current);
        });
        await chooseSize(tester, 'L');
        await tapStyle(tester, find.text('Lưu hồ sơ phong cách'));
        await tapStyle(tester, find.text('Lưu hồ sơ phong cách'));
        expect(writes, 1);
        expect(find.text('Đã lưu hồ sơ phong cách.'), findsNothing);
        await tapStyle(tester, find.text('Tải lại hồ sơ'));
        expect(find.text('XL'), findsOneWidget);
      },
    );
  }
  testWidgets('late save cannot restore profile after changing customer', (
    tester,
  ) async {
    final late = Completer<http.Response>();
    final c = await mountStyle(tester, (r) async {
      if (r.method == 'PUT') return late.future;
      return jsonResponse(styleJson());
    });
    await chooseSize(tester, 'L');
    await tester.ensureVisible(find.text('Lưu hồ sơ phong cách'));
    await tester.tap(find.text('Lưu hồ sơ phong cách'));
    await tester.pump();
    await c.read(accountProvider.notifier).signOut();
    await tester.pumpAndSettle();
    await c
        .read(accountProvider.notifier)
        .signIn('', 'next@example.test', 'password');
    await tester.pumpAndSettle();
    late.complete(jsonResponse(styleJson(size: 'L', version: 1)));
    await tester.pumpAndSettle();
    expect(find.text('M'), findsOneWidget);
    expect(find.text('Đã lưu hồ sơ phong cách.'), findsNothing);
    expect((await c.read(accountDetailsProvider.future)).style.size, 'M');
  });
}
