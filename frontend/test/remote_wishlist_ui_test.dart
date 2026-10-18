import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;
import 'remote_catalog_test.dart' show productJson;

void main() {
  Future<ProviderContainer> mount(
    WidgetTester tester, {
    bool guest = false,
    bool fail = false,
    int count = 1,
    String path = '/wishlist',
  }) async {
    final entries = [
      for (var i = 0; i < count; i++)
        {
          'productId': 'p$i',
          'product': i == 0 ? {...productJson(), 'id': 'p0'} : null,
        },
    ];
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return jsonResponse(loginJson('customer'));
        }
        if (r.url.path.endsWith('/logout')) return jsonResponse({});
        if (r.url.path.endsWith('/cart')) {
          return jsonResponse({
            'items': [],
            'subtotal': {'amount': '0', 'currency': 'VND'},
            'version': 0,
          });
        }
        if (r.url.path.contains('/wishlist')) {
          if (fail) return jsonResponse({}, 503);
          if (r.method == 'DELETE') {
            entries.removeWhere(
              (e) => e['productId'] == r.url.pathSegments.last,
            );
          }
          return jsonResponse({'items': entries, 'limit': 200});
        }
        if (r.url.path.endsWith('/products/nep-1')) {
          return jsonResponse(productJson());
        }
        if (r.url.path.endsWith('/products')) {
          return jsonResponse({'items': [], 'total': 0});
        }
        return jsonResponse({});
      }),
    );
    final c = ProviderContainer(
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(api),
        sessionTokensProvider.overrideWithValue(api.tokens),
      ],
    );
    addTearDown(() {
      c.dispose();
      api.close();
    });
    if (!guest) {
      await c
          .read(accountProvider.notifier)
          .signIn('', 'customer@example.com', 'valid-password');
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: NepApp(router: createRouter(initialLocation: path)),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  for (final width in [375.0, 1440.0]) {
    testWidgets(
      'wishlist removes saved product and clears after logout at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = await mount(tester);
        expect(find.text('Áo cotton'), findsOneWidget);
        final remove = find.byTooltip('Bỏ yêu thích Áo cotton');
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(find.text('Tủ đồ yêu thích còn trống'), findsOneWidget);
        await c.read(accountProvider.notifier).signOut();
        await tester.pumpAndSettle();
        expect(find.text('Đăng nhập để tiếp tục'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'guest heart opens customer login and preserves product return path',
    (tester) async {
      await mount(tester, guest: true, path: '/products/nep-1');
      final heart = find.byTooltip('Lưu yêu thích');
      await tester.ensureVisible(heart);
      await tester.tap(heart);
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập khách hàng'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Đăng nhập quản trị'),
        findsNothing,
      );
    },
  );
  testWidgets('wishlist read failure displays retry instead of empty state', (
    tester,
  ) async {
    await mount(tester, fail: true);
    expect(find.text('Chưa tải được danh sách yêu thích'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Tải lại'), findsOneWidget);
    expect(find.text('Tủ đồ yêu thích còn trống'), findsNothing);
  });
  testWidgets(
    'removing last unavailable item on page two returns to remaining page',
    (tester) async {
      await mount(tester, count: 13, path: '/wishlist?page=2');
      expect(find.text('Sản phẩm không còn mở bán'), findsOneWidget);
      final remove = find.widgetWithText(TextButton, 'Bỏ yêu thích');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('Áo cotton'), findsOneWidget);
      expect(find.text('Trang 1 / 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
