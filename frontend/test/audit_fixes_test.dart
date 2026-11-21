import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/refund_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_refunds.dart';
import 'package:nep_storefront/features/admin/remote/refund_actions.dart';
import 'package:nep_storefront/features/admin/remote/reconcile_button.dart';
import 'package:nep_storefront/features/admin/remote/newsletter_page.dart';
import 'package:nep_storefront/features/account/newsletter_unsubscribe_page.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'refunds_test.dart' show stateJson;

void main() {
  testWidgets(
    'newsletter management loads with the staff session and fits a mobile screen',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/campaigns')) return jsonResponse([]);
          expect(r.url.queryParameters['limit'], '20');
          return jsonResponse({
            'items': [],
            'total': 0,
            'active': 0,
            'page': 1,
            'limit': 20,
          });
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: RemoteNewsletterPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chưa có người đăng ký.'), findsOneWidget);
      expect(find.text('Lưu bản nháp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reconciliation uses the admin session and the selected original attempt',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/admin/payments/orders/order-1/reconcile');
          requests.add(jsonDecode(r.body));
          return jsonResponse({'paymentStatus': 'PAID'}, 201);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(
              body: ReconcilePaymentButton(
                orderId: 'order-1',
                attemptId: 'old-momo',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Xác minh giao dịch'));
      await tester.pumpAndSettle();
      expect(requests, [
        {'attemptId': 'old-momo'},
      ]);
      expect(find.text('Đã cập nhật kết quả xác minh.'), findsOneWidget);
    },
  );
  testWidgets(
    'a COD order refunds an additional MoMo collection through MoMo',
    (tester) async {
      final state = stateJson();
      (state['sources'] as List)[0] = <String, Object?>{
        ...Map<String, Object?>.from((state['sources'] as List)[0] as Map),
        'provider': 'momo',
        'attemptId': 'late-momo',
        'primary': false,
      };
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async => jsonResponse(state)),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRefundRepositoryProvider.overrideWithValue(
              RemoteRefundRepository(api, admin: true),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AdminRefundActions(orderId: 'order-1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hoàn qua MoMo sandbox'), findsOneWidget);
      await tester.tap(find.text('Hoàn qua MoMo sandbox'));
      await tester.pumpAndSettle();
      expect(find.text('Gửi yêu cầu hoàn sandbox'), findsOneWidget);
      expect(find.text('Mã biên nhận hoàn tiền'), findsNothing);
    },
  );
  testWidgets(
    'unsubscribe waits for explicit action and works without signing in',
    (tester) async {
      var writes = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/content/newsletter/unsubscribe');
          expect(jsonDecode(r.body), {'token': 'token-1'});
          expect(r.headers['Authorization'], isNull);
          writes++;
          return jsonResponse({'accepted': true}, 201);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: Scaffold(body: NewsletterUnsubscribePage(token: 'token-1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.tap(find.text('Ngừng nhận bản tin'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.textContaining('Đã ghi nhận yêu cầu.'), findsOneWidget);
    },
  );
}
