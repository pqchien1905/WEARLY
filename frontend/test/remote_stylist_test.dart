import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_stylist.dart';
import 'package:nep_storefront/domain/ai.dart';
import 'package:nep_storefront/features/ai_stylist/remote_stylist_page.dart';
import 'remote_catalog_test.dart' show productJson;
import 'remote_session_test.dart' show jsonResponse;

const requestKey = '9ed89dca-9bf0-43a3-8afb-dce7814213fe';
Map<String, Object?> stylistStatus({
  bool configured = true,
  int remaining = 20,
}) => {
  'stylist': {
    'configured': configured,
    'model': 'gemini-fixture',
    'used': 20 - remaining,
    'limit': 20,
    'remaining': remaining,
    'estimatedUsedVnd': '${(20 - remaining) * 500}',
    'estimatedPerRequestVnd': '500',
    'resetsAt': '2026-10-23T00:00:00Z',
    'costIsEstimate': true,
  },
};
Map<String, Object?> stylistReceipt({
  String status = 'completed',
  String? errorCode,
}) => {
  'id': 'receipt-id',
  'requestKey': requestKey,
  'status': status,
  'errorCode': errorCode,
  'createdAt': '2026-10-22T10:00:00Z',
  'estimatedCostVnd': '500',
  'model': 'gemini-fixture',
  'result': status == 'completed'
      ? {
          'message': 'Phối đồ cho ngày đi làm.',
          'currency': 'VND',
          'total': '490000',
          'picks': [
            {
              'sku': 'WRL-1-MAIN-M',
              'price': '490000',
              'product': productJson(),
            },
          ],
        }
      : null,
};
void main() {
  ApiClient client(Future<http.Response> Function(http.Request) handler) {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(handler),
    );
    api.tokens.set(accessToken: 'access', userId: 'customer');
    addTearDown(api.close);
    return api;
  }

  Future<void> mount(
    WidgetTester t,
    ApiClient api, {
    double width = 800,
  }) async {
    t.view.resetPhysicalSize();
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 1000);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          remoteApiProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: RemoteStylistPage()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pumpAndSettle();
  }

  Future<void> fill(WidgetTester t) async {
    await t.enterText(
      find.widgetWithText(TextField, 'Bạn muốn phối đồ cho dịp nào?'),
      'Đi làm, đơn giản',
    );
    final consent = find.byType(CheckboxListTile);
    await t.ensureVisible(consent);
    await t.pumpAndSettle();
    await t.tap(consent);
    await t.pumpAndSettle();
  }

  test(
    'repository sends consent and exact key and reads receipt without another POST',
    () async {
      final methods = <String>[];
      final api = client((r) async {
        methods.add(r.method);
        if (r.method == 'POST') {
          expect(r.headers['Idempotency-Key'], requestKey);
          expect(jsonDecode(r.body), containsPair('consent', true));
          expect(jsonDecode(r.body), containsPair('budget', 800000));
        } else {
          expect(r.url.path, endsWith('/$requestKey'));
        }
        return jsonResponse(stylistReceipt());
      });
      final repo = RemoteStylistRepository(api);
      final result = await repo.create(
        requestKey,
        const StylistRequest(prompt: 'Đi làm', budget: 800000),
        consent: true,
      );
      expect(result.total, 490000);
      expect(result.picks.single.variant.sku, 'WRL-1-MAIN-M');
      await repo.get(requestKey);
      expect(methods, ['POST', 'GET']);
    },
  );
  test(
    'repository rejects a selected price that differs from the SKU',
    () async {
      final data = stylistReceipt();
      (data['result'] as Map)['total'] = '1';
      final repo = RemoteStylistRepository(
        client((_) async => jsonResponse(data)),
      );
      await expectLater(repo.get(requestKey), throwsA(isA<ApiException>()));
    },
  );
  test(
    'late result after account change cannot return private suggestions',
    () async {
      final pending = Completer<http.Response>();
      final api = client((_) => pending.future);
      final repo = RemoteStylistRepository(api);
      final result = repo.get(requestKey);
      final denied = expectLater(
        result,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      api.tokens.clear();
      pending.complete(jsonResponse(stylistReceipt()));
      await denied;
    },
  );
  testWidgets(
    'missing Gemini configuration shows status without generating demo output',
    (t) async {
      var writes = 0;
      await mount(
        t,
        client((r) async {
          if (r.method == 'POST') writes++;
          return jsonResponse(stylistStatus(configured: false));
        }),
      );
      expect(find.text('Gemini chưa được cấu hình'), findsOneWidget);
      expect(writes, 0);
      expect(find.text('Kịch bản kiểm thử demo'), findsNothing);
    },
  );
  testWidgets(
    'consent gates generation and selected SKU price is visible at375px',
    (t) async {
      var writes = 0;
      await mount(
        t,
        client((r) async {
          if (r.method == 'POST') {
            writes++;
            return jsonResponse(stylistReceipt());
          }
          return jsonResponse(stylistStatus());
        }),
        width: 375,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Nhờ Gemini gợi ý'),
            )
            .onPressed,
        isNull,
      );
      await fill(t);
      await tap(t, 'Nhờ Gemini gợi ý');
      expect(writes, 1);
      expect(find.text('Tổng trang phục: 490.000 ₫'), findsOneWidget);
      expect(find.textContaining('M · Trắng'), findsOneWidget);
      expect(find.textContaining('500 ₫'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'lost reply recovers the same key with GET and no repeated generation',
    (t) async {
      var writes = 0;
      String? key;
      await mount(
        t,
        client((r) async {
          if (r.method == 'POST') {
            writes++;
            key = r.headers['Idempotency-Key'];
            throw http.ClientException('response lost');
          }
          if (r.url.path.endsWith('/status')) {
            return jsonResponse(stylistStatus());
          }
          expect(r.url.path, endsWith('/$key'));
          return jsonResponse(stylistReceipt());
        }),
      );
      await fill(t);
      await tap(t, 'Nhờ Gemini gợi ý');
      await tap(t, 'Kiểm tra / thử lại yêu cầu');
      expect(writes, 1);
      expect(find.text('Tổng trang phục: 490.000 ₫'), findsOneWidget);
    },
  );
  testWidgets('terminal failure needs an explicit new request and a new key', (
    t,
  ) async {
    final keys = <String>[];
    await mount(
      t,
      client((r) async {
        if (r.method == 'POST') {
          keys.add(r.headers['Idempotency-Key']!);
          return jsonResponse(
            keys.length == 1
                ? stylistReceipt(
                    status: 'failed',
                    errorCode: 'AI_PROVIDER_RATE_LIMIT',
                  )
                : stylistReceipt(),
          );
        }
        return jsonResponse(stylistStatus());
      }),
    );
    await fill(t);
    await tap(t, 'Nhờ Gemini gợi ý');
    expect(keys, hasLength(1));
    await tap(t, 'Yêu cầu mới');
    expect(keys.toSet(), hasLength(2));
    expect(t.takeException(), isNull);
  });
  testWidgets('pending request polls its receipt without another generation', (
    t,
  ) async {
    var writes = 0, reads = 0;
    await mount(
      t,
      client((r) async {
        if (r.method == 'POST') {
          writes++;
          return jsonResponse(stylistReceipt(status: 'processing'));
        }
        if (r.url.path.endsWith('/status')) {
          return jsonResponse(stylistStatus());
        }
        reads++;
        return jsonResponse(stylistReceipt());
      }),
    );
    await fill(t);
    await tap(t, 'Nhờ Gemini gợi ý');
    expect(writes, 1);
    expect(reads, 0);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(reads, 1);
    expect(writes, 1);
    expect(find.text('Tổng trang phục: 490.000 ₫'), findsOneWidget);
  });

  testWidgets('retry after a missing receipt preserves key and frozen input', (
    t,
  ) async {
    final keys = <String>[], bodies = <String>[];
    await mount(
      t,
      client((r) async {
        if (r.method == 'POST') {
          keys.add(r.headers['Idempotency-Key']!);
          bodies.add(r.body);
          if (keys.length == 1) throw http.ClientException('not accepted');
          return jsonResponse(stylistReceipt());
        }
        return r.url.path.endsWith('/status')
            ? jsonResponse(stylistStatus())
            : jsonResponse({}, 404);
      }),
    );
    await fill(t);
    await tap(t, 'Nhờ Gemini gợi ý');
    expect(
      t
          .widget<TextField>(
            find.widgetWithText(TextField, 'Bạn muốn phối đồ cho dịp nào?'),
          )
          .enabled,
      isFalse,
    );
    await tap(t, 'Kiểm tra / thử lại yêu cầu');
    expect(keys, hasLength(2));
    expect(keys.toSet(), hasLength(1));
    expect(bodies.toSet(), hasLength(1));
  });

  testWidgets('disposing a pending screen suppresses its late result', (
    t,
  ) async {
    final response = Completer<http.Response>();
    await mount(
      t,
      client(
        (r) async => r.method == 'POST'
            ? response.future
            : jsonResponse(stylistStatus()),
      ),
    );
    await fill(t);
    final button = find.widgetWithText(FilledButton, 'Nhờ Gemini gợi ý');
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: Text('Other account')));
    response.complete(jsonResponse(stylistReceipt()));
    await t.pumpAndSettle();
    expect(find.text('Other account'), findsOneWidget);
    expect(find.text('Tổng trang phục: 490.000 ₫'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('daily limit disables new requests without hiding usage', (
    t,
  ) async {
    await mount(
      t,
      client((_) async => jsonResponse(stylistStatus(remaining: 0))),
    );
    expect(find.textContaining('20 / 20'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Nhờ Gemini gợi ý'),
          )
          .onPressed,
      isNull,
    );
  });
}
