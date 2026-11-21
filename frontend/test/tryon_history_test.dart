import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/features/virtual_tryon/remote_tryon_history.dart';
import 'remote_tryon_test.dart' show remoteJob;
import 'remote_session_test.dart' show jsonResponse;

Map<String, Object?> historyJob(
  String id,
  String status, {
  bool expired = false,
}) => {
  ...remoteJob(status: status),
  'id': id,
  'size': 'M',
  'color': 'Trắng',
  'expiresAt': DateTime.now()
      .toUtc()
      .add(Duration(hours: expired ? -1 : 1))
      .toIso8601String(),
  'product': {
    'name': 'Áo sơ mi cotton dáng rộng',
    'slug': 'shirt',
    'image': null,
    'tryOnSupported': true,
  },
  if (status == 'failed') 'errorCode': 'AI_PROVIDER_UNAVAILABLE',
};

Future<void> mountHistory(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle, {
  double width = 1440,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient(handle),
  );
  api.tokens.set(accessToken: 'access', userId: 'customer');
  addTearDown(api.close);
  final router = GoRouter(
    initialLocation: '/account/try-ons',
    routes: [
      GoRoute(
        path: '/account/try-ons',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: RemoteTryOnHistory()),
        ),
      ),
      GoRoute(
        path: '/products/:slug',
        builder: (_, s) =>
            Scaffold(body: Text('Product ${s.pathParameters['slug']}')),
      ),
      GoRoute(
        path: '/virtual-try-on',
        builder: (_, s) =>
            Scaffold(body: Text('Try ${s.uri.queryParameters['product']}')),
      ),
      GoRoute(
        path: '/virtual-try-on/:id',
        builder: (_, s) =>
            Scaffold(body: Text('Job ${s.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
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
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  final target = find.text(label).first;
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'filters distinguish ready, pending, failed and expired results',
    (t) async {
      await mountHistory(
        t,
        (_) async => jsonResponse({
          'items': [
            historyJob('ready', 'completed'),
            historyJob('pending', 'pending'),
            historyJob('failed', 'failed'),
            historyJob('expired', 'completed', expired: true),
          ],
        }),
      );
      expect(find.text('Xem ảnh thử đồ'), findsOneWidget);
      await tap(t, 'Chưa thành công (1)');
      expect(find.text('Chưa tạo được ảnh'), findsOneWidget);
      expect(find.text('Xem ảnh thử đồ'), findsNothing);
      await tap(t, 'Không còn ảnh (1)');
      expect(find.text('Ảnh đã hết hạn'), findsOneWidget);
      await tap(t, 'Đang xử lý (1)');
      await tap(t, 'Theo dõi yêu cầu');
      expect(find.text('Job pending'), findsOneWidget);
    },
  );
  testWidgets(
    'delete can be cancelled and removes every job using the same image after confirmation',
    (t) async {
      var deletes = 0;
      await mountHistory(t, (r) async {
        if (r.method == 'DELETE') {
          deletes++;
          return jsonResponse({'ok': true});
        }
        return jsonResponse({
          'items': [historyJob('a', 'completed'), historyJob('b', 'failed')],
        });
      });
      await tap(t, 'Chưa thành công (1)');
      await tap(t, 'Xóa ảnh và các kết quả');
      expect(
        find.textContaining('đang được dùng trong 2 lượt thử'),
        findsOneWidget,
      );
      await tap(t, 'Giữ lại');
      expect(deletes, 0);
      await tap(t, 'Xóa ảnh và các kết quả');
      await tap(t, 'Xác nhận xóa');
      expect(deletes, 1);
      expect(find.text('Góc thử đồ đang chờ bạn'), findsOneWidget);
      expect(find.text('Xem ảnh thử đồ'), findsNothing);
    },
  );
  testWidgets(
    'load errors retry, and refresh failures preserve labelled stale data',
    (t) async {
      var failing = true;
      await mountHistory(
        t,
        (_) async => failing
            ? jsonResponse({}, 503)
            : jsonResponse({
                'items': [historyJob('a', 'failed')],
              }),
      );
      expect(find.text('Chưa tải được lịch sử thử đồ'), findsOneWidget);
      expect(find.text('Góc thử đồ đang chờ bạn'), findsNothing);
      failing = false;
      await tap(t, 'Thử lại');
      expect(find.text('Áo sơ mi cotton dáng rộng'), findsOneWidget);
      failing = true;
      await tap(t, 'Làm mới lịch sử');
      expect(
        find.text('Danh sách bên dưới là dữ liệu đã tải trước đó.'),
        findsOneWidget,
      );
      expect(find.text('Áo sơ mi cotton dáng rộng'), findsOneWidget);
    },
  );
  testWidgets('pending jobs refresh without creating another request', (
    t,
  ) async {
    var reads = 0, writes = 0;
    await mountHistory(t, (r) async {
      if (r.method != 'GET') writes++;
      return jsonResponse({
        'items': [historyJob('a', ++reads == 1 ? 'pending' : 'completed')],
      });
    });
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();
    expect(find.text('Đã tạo ảnh thử đồ'), findsOneWidget);
    expect(reads, 2);
    expect(writes, 0);
    await t.pump(const Duration(seconds: 10));
    expect(reads, 2);
  });
  testWidgets('product and retry actions open the matching garment', (t) async {
    await mountHistory(
      t,
      (_) async => jsonResponse({
        'items': [historyJob('a', 'failed')],
      }),
    );
    await tap(t, 'Thử lại trang phục');
    expect(find.text('Try shirt'), findsOneWidget);
  });
  testWidgets('history repository reads product metadata', (t) async {
    await mountHistory(
      t,
      (_) async => http.Response(
        jsonEncode({
          'items': [historyJob('a', 'failed')],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    expect(find.text('Trắng · Size M'), findsOneWidget);
    await tap(t, 'Xem trang phục');
    expect(find.text('Product shirt'), findsOneWidget);
  });
  for (final (width, scale) in [
    (320.0, 1.0),
    (375.0, 2.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (2560.0, 1.0),
  ]) {
    testWidgets('history is readable at $width and text scale $scale', (
      t,
    ) async {
      await mountHistory(
        t,
        (_) async => jsonResponse({
          'items': [historyJob('a', 'failed')],
        }),
        width: width,
        scale: scale,
      );
      await tap(t, 'Xóa ảnh và các kết quả');
      await tap(t, 'Giữ lại');
      expect(t.takeException(), isNull);
      if (width >= 1440) {
        expect(
          find.byKey(const ValueKey('tryon-history-table')),
          findsOneWidget,
        );
      }
    });
  }
}
