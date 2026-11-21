import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_reviews.dart';
import 'package:nep_storefront/domain/staff_permissions.dart';
import 'package:nep_storefront/features/product_detail/review_editor.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> review({bool hidden = false}) => {
  'id': 'r1',
  'rating': 2,
  'comment': 'Nội dung quảng cáo lặp lại',
  'createdAt': '2026-11-01T00:00:00.000Z',
  'updatedAt': '2026-11-02T00:00:00.000Z',
  'hiddenAt': hidden ? '2026-11-03T00:00:00.000Z' : null,
  'hiddenReason': hidden ? 'Spam' : null,
  'product': {'id': 'p1', 'name': 'Áo sơ mi lụa', 'slug': 'ao-so-mi'},
  'user': {'id': 'u1', 'name': 'Khách thử', 'email': 'khach@example.test'},
};

void main() {
  Future<List<http.Request>> mount(
    WidgetTester t, {
    double width = 1440,
    String role = 'MANAGER',
    bool hidden = false,
  }) async {
    t.view.physicalSize = Size(width, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    var current = review(hidden: hidden);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          final s = sessionJson();
          (s['user'] as Map)['role'] = role;
          return jsonResponse(s);
        }
        requests.add(r);
        if (r.method == 'PATCH') {
          final body = jsonDecode(r.body) as Map;
          current = review(hidden: body['hidden'] == true);
          return jsonResponse(current);
        }
        return jsonResponse({
          'items': [current],
          'total': 1,
          'page': 1,
          'limit': 20,
          'counts': {'all': 4, 'visible': 3, 'hidden': 1},
        });
      }),
    );
    final scope = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        adminApiClientProvider.overrideWithValue(api),
        adminSessionTokensProvider.overrideWithValue(api.tokens),
      ],
    );
    addTearDown(() {
      scope.dispose();
      api.close();
    });
    await scope
        .read(adminAccountProvider.notifier)
        .signIn('', 'admin', 'password');
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: NepApp(router: createRouter(initialLocation: '/admin/reviews')),
      ),
    );
    await t.pumpAndSettle();
    return requests;
  }

  Future<void> click(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  test('review moderation follows content management permissions', () {
    expect(canVisitAdmin('ADMIN', '/admin/reviews'), isTrue);
    expect(canVisitAdmin('MANAGER', '/admin/reviews'), isTrue);
    expect(canVisitAdmin('SUPPORT', '/admin/reviews'), isFalse);
    expect(canVisitAdmin('WAREHOUSE', '/admin/reviews'), isFalse);
  });

  for (final width in [375.0, 1440.0]) {
    testWidgets('lists reviews with filters at ${width}px', (t) async {
      final requests = await mount(t, width: width);
      expect(find.text('Đánh giá sản phẩm'), findsWidgets);
      expect(find.text('Nội dung quảng cáo lặp lại'), findsOneWidget);
      expect(find.text('Đã ẩn (1)'), findsOneWidget);
      expect(requests.first.url.path, '/api/v1/admin/reviews');
      expect(requests.first.url.queryParameters, {
        'page': '1',
        'limit': '20',
        'visibility': 'all',
      });
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('hiding requires a reason and sends the reviewed version', (
    t,
  ) async {
    final requests = await mount(t);
    await click(t, find.widgetWithText(OutlinedButton, 'Ẩn đánh giá'));
    expect(find.text('Lý do (khách sẽ thấy)'), findsOneWidget);
    await click(t, find.widgetWithText(FilledButton, 'Ẩn đánh giá'));
    expect(find.text('Vui lòng nhập thông tin.'), findsOneWidget);
    expect(requests.where((r) => r.method == 'PATCH'), isEmpty);
    await t.enterText(find.byType(TextFormField).last, '  Spam  ');
    await click(t, find.widgetWithText(FilledButton, 'Ẩn đánh giá'));
    final patch = requests.singleWhere((r) => r.method == 'PATCH');
    expect(patch.url.path, '/api/v1/admin/reviews/r1/visibility');
    expect(jsonDecode(patch.body), {
      'hidden': true,
      'reason': 'Spam',
      'expectedUpdatedAt': '2026-11-02T00:00:00.000Z',
    });
    expect(find.textContaining('Lý do: Spam'), findsOneWidget);
    expect(find.text('Hiện lại'), findsOneWidget);
  });

  testWidgets('restoring a hidden review sends no reason', (t) async {
    final requests = await mount(t, hidden: true);
    await click(t, find.text('Hiện lại').first);
    await click(t, find.text('Hiện lại').last);
    final patch = requests.singleWhere((r) => r.method == 'PATCH');
    expect(jsonDecode(patch.body), {
      'hidden': false,
      'expectedUpdatedAt': '2026-11-02T00:00:00.000Z',
    });
  });

  testWidgets('support staff cannot open review moderation', (t) async {
    final requests = await mount(t, role: 'SUPPORT');
    expect(find.text('Nội dung quảng cáo lặp lại'), findsNothing);
    expect(requests.where((r) => r.url.path.contains('reviews')), isEmpty);
  });

  test('owner reviews carry moderation state; public ones stay visible', () {
    final owned = ProductReview.fromJson(review(hidden: true));
    expect(owned.hidden, isTrue);
    expect(owned.hiddenReason, 'Spam');
    final public = ProductReview.fromJson({
      for (final e in review().entries)
        if (!e.key.startsWith('hidden')) e.key: e.value,
    });
    expect(public.hidden, isFalse);
  });

  testWidgets('authors see why their review is hidden', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReviewModerationNotice(reason: 'Spam')),
      ),
    );
    expect(
      find.textContaining('đang bị ẩn khỏi trang sản phẩm: Spam'),
      findsOneWidget,
    );
  });
}
