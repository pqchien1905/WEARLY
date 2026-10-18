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
import 'package:nep_storefront/app/review_providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/features/account/reviews_page.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;
import 'reviews_test.dart' show reviewJson;

Map<String, dynamic> ownedJson({
  String id = '1',
  bool hidden = false,
  bool canEdit = true,
}) => {
  ...reviewJson(comment: 'Nội dung của tôi $id'),
  'id': 'r$id',
  'productId': 'p$id',
  'product': hidden ? null : {'name': 'Áo cotton $id', 'slug': 'shirt-$id'},
  'canEdit': !hidden && canEdit,
};
Map<String, dynamic> historyJson(
  List<Map<String, dynamic>> items, {
  int page = 1,
  int? total,
}) => {
  'items': items,
  'total': total ?? items.length,
  'page': page,
  'limit': 5,
};

Future<ProviderContainer> mountHistory(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handle, {
  bool guest = false,
  bool staffOnly = false,
  bool remote = true,
}) async {
  var logins = 0;
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((r) async {
      if (r.url.path.endsWith('/login')) {
        return jsonResponse(loginJson('customer${++logins}'));
      }
      if (r.url.path.endsWith('/logout')) return jsonResponse({});
      return handle(r);
    }),
  );
  final adminApi = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient((_) async => jsonResponse(loginJson('admin'))),
  );
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      remoteApiProvider.overrideWithValue(remote),
      apiClientProvider.overrideWithValue(api),
      sessionTokensProvider.overrideWithValue(api.tokens),
      adminApiClientProvider.overrideWithValue(adminApi),
      adminSessionTokensProvider.overrideWithValue(adminApi.tokens),
    ],
  );
  final router = GoRouter(
    initialLocation: '/account/reviews',
    routes: [
      GoRoute(
        path: '/account/reviews',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(child: CustomerReviewsPage()),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (_, s) =>
            Scaffold(body: Text('Return: ${s.uri.queryParameters['next']}')),
      ),
      GoRoute(
        path: '/products/:slug',
        builder: (_, s) =>
            Scaffold(body: Text('Product: ${s.pathParameters['slug']}')),
      ),
      GoRoute(
        path: '/account/orders',
        builder: (_, _) => const Scaffold(body: Text('Orders')),
      ),
    ],
  );
  addTearDown(() {
    router.dispose();
    container.dispose();
    api.close();
    adminApi.close();
  });
  if (!guest && !staffOnly && remote) {
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

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'history uses shopper authentication, paging and rejects a late old-session read',
    () async {
      final late = Completer<http.Response>();
      var calls = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/users/me/reviews');
          expect(r.headers['Authorization'], 'Bearer customer');
          expect(r.url.queryParameters['page'], '2');
          expect(r.url.queryParameters['limit'], '5');
          if (++calls == 1) {
            return jsonResponse(
              historyJson([ownedJson(hidden: true)], page: 2, total: 6),
            );
          }
          return late.future;
        }),
      );
      addTearDown(api.close);
      api.tokens.set(accessToken: 'customer', refreshToken: 'refresh');
      final repo = OwnerReviewRepository(api, onSettled: (_) {});
      final page = await repo.history(2);
      expect(page.total, 6);
      expect(page.items.single.product, isNull);
      expect(page.items.single.canEdit, isFalse);
      final pending = repo.history(2);
      final rejected = expectLater(
        pending,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      api.tokens.clear();
      repo.dispose();
      late.complete(jsonResponse(historyJson([ownedJson()])));
      await rejected;
    },
  );

  for (final staffOnly in [false, true]) {
    testWidgets(
      'guest or staff-only history preserves customer login return: $staffOnly',
      (tester) async {
        var reads = 0;
        await mountHistory(
          tester,
          (_) async {
            reads++;
            return jsonResponse(historyJson([]));
          },
          guest: true,
          staffOnly: staffOnly,
        );
        expect(reads, 0);
        await tapVisible(tester, find.text('Đăng nhập'));
        expect(find.text('Return: /account/reviews'), findsOneWidget);
      },
    );
  }

  testWidgets('demo history does not invent saved reviews or call API', (
    tester,
  ) async {
    var reads = 0;
    await mountHistory(tester, (_) async {
      reads++;
      return jsonResponse(historyJson([]));
    }, remote: false);
    expect(find.text('Đánh giá cần cửa hàng trực tuyến'), findsOneWidget);
    expect(reads, 0);
  });

  for (final width in [375.0, 1440.0]) {
    testWidgets('owner edits and removes hidden review at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = [ownedJson(), ownedJson(id: '2', hidden: true)];
      var writes = 0;
      await mountHistory(tester, (r) async {
        if (r.method == 'GET') return jsonResponse(historyJson(rows));
        writes++;
        final body = jsonDecode(r.body) as Map;
        expect(body['expectedUpdatedAt'], reviewJson()['updatedAt']);
        if (r.method == 'PATCH') {
          rows[0] = {
            ...rows[0],
            'rating': body['rating'],
            'comment': body['comment'],
          };
          return jsonResponse(rows[0]);
        }
        expect(r.method, 'DELETE');
        expect(r.url.path, '/api/v1/products/p2/reviews/me');
        rows.removeLast();
        return jsonResponse({'deleted': true});
      });
      expect(find.text('Sản phẩm không còn mở bán'), findsOneWidget);
      expect(find.text('Sửa đánh giá'), findsOneWidget);
      await tapVisible(tester, find.text('Sửa đánh giá'));
      await tester.enterText(find.byType(TextFormField), 'Chất vải đẹp hơn');
      await tester.tap(find.byTooltip('Chọn 5 sao'));
      await tapVisible(tester, find.text('Lưu đánh giá'));
      expect(find.text('Chất vải đẹp hơn'), findsOneWidget);
      final hiddenDelete = find.descendant(
        of: find.byKey(const ValueKey('review-r2')),
        matching: find.text('Xóa đánh giá'),
      );
      await tapVisible(tester, hiddenDelete);
      expect(find.textContaining('Bạn vẫn có thể viết lại sau'), findsNothing);
      expect(find.textContaining('không thể hoàn tác'), findsOneWidget);
      await tapVisible(tester, find.text('Đóng'));
      expect(writes, 1);
      await tapVisible(tester, hiddenDelete);
      await tapVisible(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Xóa đánh giá'),
        ),
      );
      expect(writes, 2);
      expect(find.text('Sản phẩm không còn mở bán'), findsNothing);
      expect(find.text('1 đánh giá'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'deleting final page returns to first page and refreshes history',
    (tester) async {
      var removed = false;
      final pages = <int>[];
      await mountHistory(tester, (r) async {
        if (r.method == 'DELETE') {
          removed = true;
          return jsonResponse({'deleted': true});
        }
        final page = int.parse(r.url.queryParameters['page']!);
        pages.add(page);
        return jsonResponse(
          historyJson(
            page == 1
                ? [
                    for (var i = 1; i <= 5; i++)
                      ownedJson(id: '$i', canEdit: false),
                  ]
                : [if (!removed) ownedJson(id: '6', hidden: true)],
            page: page,
            total: removed ? 5 : 6,
          ),
        );
      });
      await tapVisible(tester, find.text('Trang sau'));
      expect(find.text('Nội dung của tôi 6'), findsOneWidget);
      await tapVisible(tester, find.text('Xóa đánh giá'));
      await tapVisible(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Xóa đánh giá'),
        ),
      );
      expect(pages.last, 1);
      expect(find.text('5 đánh giá'), findsOneWidget);
      expect(find.text('Nội dung của tôi 6'), findsNothing);
    },
  );

  testWidgets('read failure can retry into empty history', (tester) async {
    var reads = 0;
    await mountHistory(
      tester,
      (_) async =>
          ++reads == 1 ? jsonResponse({}, 500) : jsonResponse(historyJson([])),
    );
    expect(find.text('Chưa tải được đánh giá'), findsOneWidget);
    await tapVisible(tester, find.text('Tải lại'));
    expect(find.text('Bạn chưa viết đánh giá nào'), findsOneWidget);
    await tapVisible(tester, find.text('Xem đơn hàng'));
    expect(find.text('Orders'), findsOneWidget);
  });

  testWidgets('old pending history cannot appear after switching customer', (
    tester,
  ) async {
    final late = Completer<http.Response>();
    final container = await mountHistory(tester, (r) async {
      if (r.headers['Authorization'] == 'Bearer customer1-access') {
        return late.future;
      }
      return jsonResponse(historyJson([]));
    });
    expect(find.text('Đang tải đánh giá…'), findsOneWidget);
    await container.read(accountProvider.notifier).signOut();
    await tester.pumpAndSettle();
    await container
        .read(accountProvider.notifier)
        .signIn('', 'other@example.test', 'password');
    await tester.pumpAndSettle();
    late.complete(jsonResponse(historyJson([ownedJson()])));
    await tester.pumpAndSettle();
    expect(find.text('Nội dung của tôi 1'), findsNothing);
    expect(find.text('Bạn chưa viết đánh giá nào'), findsOneWidget);
  });

  testWidgets(
    'review revision invalidates private history without keeping stale rows',
    (tester) async {
      var rows = [ownedJson()];
      final container = await mountHistory(
        tester,
        (_) async => jsonResponse(historyJson(rows)),
      );
      expect(find.text('Nội dung của tôi 1'), findsOneWidget);
      rows = [];
      container.read(reviewRevisionProvider.notifier).refresh('p1');
      await tester.pumpAndSettle();
      expect(find.text('Nội dung của tôi 1'), findsNothing);
      expect(find.text('Bạn chưa viết đánh giá nào'), findsOneWidget);
    },
  );
}
