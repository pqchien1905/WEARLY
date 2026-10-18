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
import 'package:nep_storefront/features/product_detail/product_reviews.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;
import 'reviews_test.dart' show reviewJson, reviewPageJson;

void main() {
  Future<ProviderContainer> mount(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handle, {
    bool guest = false,
    bool staffOnly = false,
  }) async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          return jsonResponse(loginJson('customer'));
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
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(api),
        sessionTokensProvider.overrideWithValue(api.tokens),
        adminApiClientProvider.overrideWithValue(adminApi),
        adminSessionTokensProvider.overrideWithValue(adminApi.tokens),
      ],
    );
    final router = GoRouter(
      initialLocation: '/products/shirt',
      routes: [
        GoRoute(
          path: '/products/shirt',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: ProductReviews(productId: 'p1', slug: 'shirt'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => Scaffold(
            body: Text('Return: ${state.uri.queryParameters['next']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(() {
      container.dispose();
      api.close();
      adminApi.close();
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

  testWidgets(
    'editor accepts backend-valid emoji content and shows the saved review',
    (tester) async {
      final content = '😀' * 1500;
      Map<String, dynamic>? own;
      var writes = 0;
      await mount(tester, (r) async {
        if (r.method == 'GET') {
          return jsonResponse(
            r.url.path.endsWith('/me')
                ? {'canReview': true, 'review': own}
                : reviewPageJson([if (own != null) own!]),
          );
        }
        writes++;
        expect((jsonDecode(r.body) as Map)['comment'], content);
        own = reviewJson(comment: content);
        return jsonResponse(own!);
      });
      await tester.tap(find.text('Viết đánh giá'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chọn 4 sao'));
      await tester.enterText(find.byType(TextFormField), content);
      await tester.tap(find.text('Gửi đánh giá'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Sửa đánh giá'), findsOneWidget);
      expect(find.text(content), findsOneWidget);
    },
  );
  testWidgets('staff-only login does not unlock buyer reviews', (tester) async {
    var privateReads = 0;
    await mount(tester, (r) async {
      if (r.url.path.endsWith('/me')) privateReads++;
      return jsonResponse(reviewPageJson([]));
    }, staffOnly: true);
    expect(find.text('Đăng nhập để đánh giá'), findsOneWidget);
    expect(privateReads, 0);
  });
  testWidgets('guest login returns to the existing product route', (
    tester,
  ) async {
    await mount(
      tester,
      (_) async => jsonResponse(reviewPageJson([])),
      guest: true,
    );
    await tester.tap(find.text('Đăng nhập để đánh giá'));
    await tester.pumpAndSettle();
    expect(find.text('Return: /products/shirt'), findsOneWidget);
  });
  testWidgets('deleting own last-page review returns to first page', (
    tester,
  ) async {
    final rows = [
      for (var i = 0; i < 6; i++)
        {...reviewJson(comment: 'Review $i'), 'id': 'r$i'},
    ];
    Map<String, dynamic>? mine = rows.last;
    await mount(tester, (r) async {
      if (r.method == 'DELETE') {
        rows.removeLast();
        mine = null;
        return jsonResponse({'deleted': true});
      }
      if (r.url.path.endsWith('/me')) {
        return jsonResponse({'canReview': true, 'review': mine});
      }
      final page = int.parse(r.url.queryParameters['page']!);
      return jsonResponse(
        reviewPageJson(
          rows.skip((page - 1) * 5).take(5).toList(),
          page: page,
          total: rows.length,
        ),
      );
    });
    await tester.ensureVisible(find.text('Đánh giá tiếp'));
    await tester.tap(find.text('Đánh giá tiếp'));
    await tester.pumpAndSettle();
    expect(find.text('Review 5'), findsOneWidget);
    await tester.ensureVisible(find.text('Xóa đánh giá'));
    await tester.tap(find.text('Xóa đánh giá'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Xóa đánh giá'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review 0'), findsOneWidget);
    expect(find.text('Review 5'), findsNothing);
    expect(find.text('Đánh giá trước'), findsNothing);
  });
  for (final width in [375.0, 1440.0]) {
    testWidgets('buyer creates edits deletes review at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? own;
      final methods = <String>[];
      await mount(tester, (r) async {
        if (r.method == 'GET') {
          return r.url.path.endsWith('/me')
              ? jsonResponse({'canReview': true, 'review': own})
              : jsonResponse(reviewPageJson([if (own != null) own!]));
        }
        methods.add(r.method);
        if (r.method == 'DELETE') {
          own = null;
          return jsonResponse({'deleted': true});
        }
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        own = reviewJson(rating: body['rating'], comment: body['comment']);
        return jsonResponse(own!);
      });
      expect(find.text('Chưa có đánh giá'), findsOneWidget);
      await tester.tap(find.text('Viết đánh giá'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi đánh giá'));
      await tester.pumpAndSettle();
      expect(methods, isEmpty);
      await tester.tap(find.byTooltip('Chọn 4 sao'));
      await tester.enterText(find.byType(TextFormField), '  Cotton mềm  ');
      await tester.tap(find.text('Gửi đánh giá'));
      await tester.pumpAndSettle();
      expect(own!['comment'], 'Cotton mềm');
      await tester.tap(find.text('Sửa đánh giá'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Mặc rất thoải mái');
      await tester.tap(find.text('Lưu đánh giá'));
      await tester.pumpAndSettle();
      expect(own!['comment'], 'Mặc rất thoải mái');
      await tester.tap(find.text('Xóa đánh giá'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Xóa đánh giá'),
        ),
      );
      await tester.pumpAndSettle();
      expect(methods, ['POST', 'PATCH', 'DELETE']);
      expect(find.text('Chưa có đánh giá'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('guest session never requests buyer eligibility', (tester) async {
    var privateReads = 0;
    await mount(tester, (r) async {
      if (r.url.path.endsWith('/me')) privateReads++;
      return jsonResponse(reviewPageJson([]));
    }, guest: true);
    expect(find.text('Đăng nhập để đánh giá'), findsOneWidget);
    expect(privateReads, 0);
  });
  testWidgets('ineligible buyer, read failure and retry are explicit', (
    tester,
  ) async {
    var fail = true;
    await mount(tester, (r) async {
      if (r.url.path.endsWith('/me')) {
        return jsonResponse({'canReview': false, 'review': null});
      }
      return fail ? jsonResponse({}, 503) : jsonResponse(reviewPageJson([]));
    });
    expect(
      find.text('Bạn có thể đánh giá sau khi đơn hàng được giao.'),
      findsOneWidget,
    );
    expect(find.text('Viết đánh giá'), findsNothing);
    fail = false;
    await tester.tap(find.text('Tải lại đánh giá'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có đánh giá'), findsOneWidget);
  });
  testWidgets('uncertain save requires reload and never resubmits', (
    tester,
  ) async {
    var writes = 0;
    Map<String, dynamic>? own;
    await mount(tester, (r) async {
      if (r.method == 'GET') {
        return jsonResponse(
          r.url.path.endsWith('/me')
              ? {'canReview': true, 'review': own}
              : reviewPageJson([if (own != null) own!]),
        );
      }
      writes++;
      own = reviewJson();
      throw http.ClientException('lost response');
    });
    await tester.tap(find.text('Viết đánh giá'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chọn 4 sao'));
    await tester.enterText(find.byType(TextFormField), 'Cotton mềm');
    await tester.tap(find.text('Gửi đánh giá'));
    await tester.pumpAndSettle();
    expect(find.text('Gửi đánh giá'), findsNothing);
    await tester.tap(find.text('Kiểm tra lại'));
    await tester.pumpAndSettle();
    expect(find.text('Sửa đánh giá'), findsOneWidget);
    expect(writes, 1);
  });
  testWidgets(
    'logout while saving discards private form and reconciles public result',
    (tester) async {
      final pending = Completer<http.Response>();
      Map<String, dynamic>? own;
      final container = await mount(tester, (r) async {
        if (r.method == 'GET') {
          return jsonResponse(
            r.url.path.endsWith('/me')
                ? {'canReview': true, 'review': own}
                : reviewPageJson([if (own != null) own!]),
          );
        }
        own = reviewJson();
        return pending.future;
      });
      await tester.tap(find.text('Viết đánh giá'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chọn 4 sao'));
      await tester.enterText(find.byType(TextFormField), 'Cotton mềm');
      await tester.tap(find.text('Gửi đánh giá'));
      await tester.pump();
      await container.read(accountProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      pending.complete(jsonResponse(own!));
      await tester.pumpAndSettle();
      expect(find.text('Sửa đánh giá'), findsNothing);
      expect(find.text('Đăng nhập để đánh giá'), findsOneWidget);
      expect(find.text('Cotton mềm'), findsOneWidget);
    },
  );
}
