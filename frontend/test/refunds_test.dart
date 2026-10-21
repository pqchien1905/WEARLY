import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/refund_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/commerce_json.dart';
import 'package:nep_storefront/data/remote_refunds.dart';
import 'package:nep_storefront/features/account/refund_panel.dart';
import 'package:nep_storefront/features/admin/remote/refund_actions.dart';
import 'remote_commerce_test.dart' show orderJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> refundJson({
  String status = 'REVIEW',
  String provider = 'vnpay',
}) => {
  'id': 'refund-1',
  'amount': '50000',
  'status': status,
  'reference': provider == 'cod' ? 'COD-REFUND-1' : null,
  'providerTransactionNo': status == 'REVIEW' ? null : '98765',
  'createdAt': '2026-10-22T04:00:00Z',
  'completedAt': status == 'SUCCEEDED' ? '2026-10-22T05:00:00Z' : null,
  'provider': provider,
};
Map<String, dynamic> stateJson({
  String provider = 'cod',
  List<dynamic> refunds = const [],
  bool available = true,
}) => {
  'orderId': 'order-1',
  'version': 3,
  'provider': provider,
  'paymentStatus': 'PAID',
  'refunded': refunds.any((r) => r['status'] == 'SUCCEEDED') ? '50000' : '0',
  'refunds': refunds,
  'sources': [
    {
      'attemptId': provider == 'cod' ? null : 'attempt-1',
      'primary': true,
      'collected': '520000',
      'entitled': '50000',
      'refunded': '0',
      'reserved': available ? '0' : '50000',
      'available': available ? '50000' : '0',
    },
  ],
};

void main() {
  test(
    'definitive version conflict clears local pending draft for canonical reload',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient(
          (r) async => jsonResponse({
            'code': 'VERSION_CONFLICT',
            'message': 'Reload',
          }, 409),
        ),
      );
      addTearDown(api.close);
      final repo = RemoteRefundRepository(api, admin: true);
      await expectLater(
        repo.create(
          'order-1',
          source: RefundState(stateJson()).sources.single,
          version: 3,
          reference: 'COD-REFUND-1',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(repo.hasPending('order-1'), isFalse);
    },
  );
  testWidgets(
    'uncertain COD refund can retry its original request after panel remount',
    (tester) async {
      final sent = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            sent.add(r.body);
            if (sent.length == 1) throw http.ClientException('lost response');
            return jsonResponse(
              refundJson(provider: 'cod', status: 'SUCCEEDED'),
              201,
            );
          }
          return jsonResponse(
            stateJson(
              refunds: sent.length < 2
                  ? []
                  : [refundJson(provider: 'cod', status: 'SUCCEEDED')],
              available: sent.length < 2,
            ),
          );
        }),
      );
      final repo = RemoteRefundRepository(api, admin: true),
          container = ProviderContainer(
            overrides: [adminRefundRepositoryProvider.overrideWithValue(repo)],
          );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      Future<void> open(String key) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AdminRefundActions(
                    key: ValueKey(key),
                    orderId: 'order-1',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open('first');
      await tester.tap(find.text('Ghi nhận hoàn COD'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mã biên nhận hoàn tiền'),
        'COD-REFUND-1',
      );
      await tester.tap(find.text('Xác nhận đã hoàn COD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      await open('second');
      await tester.tap(find.text('Thử lại yêu cầu hoàn gốc'));
      await tester.pumpAndSettle();
      expect(sent.length, 2);
      expect(sent[0], sent[1]);
      expect(find.text('Đã hoàn tiền'), findsOneWidget);
    },
  );
  test(
    'refund decoders validate totals and commerce accepts partial refunds',
    () {
      expect(RefundState(stateJson()).sources.single.available, 50000);
      expect(RefundRecord(refundJson()).status, 'REVIEW');
      final invalid = stateJson();
      invalid['refunded'] = '1';
      expect(() => RefundState(invalid), throwsA(isA<ApiException>()));
      final input = orderJson();
      (input['payment'] as Map)['status'] = 'PARTIALLY_REFUNDED';
      expect(
        commerceOrder(input, email: '').paymentStatus,
        'PARTIALLY_REFUNDED',
      );
    },
  );
  test('lost response preserves the exact refund request for retry', () async {
    final sent = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        sent.add(r.body);
        if (sent.length == 1) throw http.ClientException('lost');
        return jsonResponse(
          refundJson(provider: 'cod', status: 'SUCCEEDED'),
          201,
        );
      }),
    );
    addTearDown(api.close);
    final repo = RemoteRefundRepository(api, admin: true),
        s = RefundState(stateJson()).sources.single;
    await expectLater(
      repo.create('order-1', source: s, version: 3, reference: 'COD-REFUND-1'),
      throwsA(isA<ApiException>()),
    );
    expect(repo.hasPending('order-1'), isTrue);
    await repo.create('order-1', source: s, version: 9, reference: 'changed');
    expect(sent[0], sent[1]);
    expect(repo.hasPending('order-1'), isFalse);
    expect(jsonDecode(sent[0])['expectedAmount'], '50000');
  });
  testWidgets('customer sees pending refund without a success claim', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(
        (r) async =>
            jsonResponse(stateJson(refunds: [refundJson()], available: false)),
      ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(body: RefundPanel(orderId: 'order-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cần xác minh kết quả hoàn'), findsOneWidget);
    expect(find.text('Đã hoàn tiền'), findsNothing);
    expect(find.textContaining('50.000'), findsWidgets);
  });
  testWidgets(
    'admin explicitly confirms COD refund and sends current version',
    (tester) async {
      Map<String, dynamic>? body;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            body = jsonDecode(r.body);
            return jsonResponse(
              refundJson(provider: 'cod', status: 'SUCCEEDED'),
              201,
            );
          }
          return jsonResponse(
            stateJson(
              refunds: body == null
                  ? []
                  : [refundJson(provider: 'cod', status: 'SUCCEEDED')],
              available: body == null,
            ),
          );
        }),
      );
      addTearDown(api.close);
      final repo = RemoteRefundRepository(api, admin: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRefundRepositoryProvider.overrideWithValue(repo)],
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
      await tester.tap(find.text('Ghi nhận hoàn COD'));
      await tester.pumpAndSettle();
      expect(find.textContaining('đã trả tiền'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mã biên nhận hoàn tiền'),
        'COD-REFUND-1',
      );
      await tester.tap(find.text('Xác nhận đã hoàn COD'));
      await tester.pumpAndSettle();
      expect(body, containsPair('expectedVersion', 3));
      expect(body, containsPair('reference', 'COD-REFUND-1'));
      expect(find.text('Đã hoàn tiền'), findsOneWidget);
    },
  );
  testWidgets('admin queries an unknown VNPay refund using its refund number', (
    tester,
  ) async {
    Map<String, dynamic>? body;
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          expect(r.url.path, endsWith('/refund-1/query'));
          body = jsonDecode(r.body);
          return jsonResponse(refundJson(status: 'SUCCEEDED'), 201);
        }
        return jsonResponse(
          stateJson(
            provider: 'vnpay',
            refunds: [
              refundJson(status: body == null ? 'REVIEW' : 'SUCCEEDED'),
            ],
            available: false,
          ),
        );
      }),
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
    await tester.tap(find.text('Kiểm tra kết quả hoàn'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mã giao dịch hoàn VNPay'),
      '98765',
    );
    await tester.tap(find.text('Truy vấn VNPay'));
    await tester.pumpAndSettle();
    expect(body, containsPair('transactionNo', '98765'));
    expect(find.text('Đã hoàn tiền'), findsOneWidget);
  });
}
