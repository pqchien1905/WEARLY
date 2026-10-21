import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/commerce_json.dart';
import 'package:nep_storefront/data/remote_returns.dart';
import 'package:nep_storefront/features/account/returns_panel.dart';
import 'package:nep_storefront/features/admin/remote/admin_pages.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_commerce_test.dart' show orderJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> returnJson({String status = 'REQUESTED'}) => {
  'id': 'return-1',
  'orderId': 'order-1',
  'status': status,
  'amount': '50000',
  'version': status == 'APPROVED' ? 1 : 0,
  'reason': 'Không vừa kích thước',
  'decisionNote': '',
  'receiptNote': '',
  'createdAt': '2026-10-21T08:00:00Z',
  'decidedAt': null,
  'receivedAt': null,
  'items': [
    {
      'orderItemId': (orderJson()['items'] as List).first['id'],
      'quantity': 1,
      'amount': '50000',
    },
  ],
};
void main() {
  test(
    'uncertain return submission freezes request key, selected quantities, reason and quote',
    () async {
      final bodies = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          bodies.add(r.body);
          if (bodies.length == 1) throw http.ClientException('lost response');
          return jsonResponse(returnJson(), 201);
        }),
      );
      addTearDown(api.close);
      final repo = RemoteReturnRepository(api);
      final items = [
        {'orderItemId': 'item-1', 'quantity': 1},
      ];
      await expectLater(
        repo.submit(
          'order-1',
          reason: 'Original reason',
          items: items,
          expectedAmount: 50000,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(repo.hasPending('order-1'), isTrue);
      await repo.submit(
        'order-1',
        reason: 'Changed reason',
        items: [
          {'orderItemId': 'item-1', 'quantity': 2},
        ],
        expectedAmount: 1,
      );
      expect(bodies[0], bodies[1]);
      expect(repo.hasPending('order-1'), isFalse);
      final body = jsonDecode(bodies[0]);
      expect(body['expectedAmount'], '50000');
      expect(body['requestKey'], isNotEmpty);
    },
  );
  test(
    'return snapshots reject inconsistent entitlement and unknown states',
    () {
      final data = returnJson();
      expect(ReturnCase(data).amount, 50000);
      data['amount'] = '50001';
      expect(() => ReturnCase(data), throwsA(isA<ApiException>()));
      data['amount'] = '50000';
      data['status'] = 'REFUNDED';
      expect(() => ReturnCase(data), throwsA(isA<ApiException>()));
    },
  );
  testWidgets(
    'customer previews, submits and sees a pending return without a refund success claim',
    (tester) async {
      final order = commerceOrder(
        orderJson()..['status'] = 'DELIVERED',
        email: '',
      );
      var sent = false, quotes = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/quote')) {
            quotes++;
            return jsonResponse({
              'amount': '50000',
              'items': returnJson()['items'],
            }, 201);
          }
          if (r.method == 'POST') {
            sent = true;
            expect(jsonDecode(r.body)['expectedAmount'], '50000');
            return jsonResponse(returnJson(), 201);
          }
          return jsonResponse({
            'eligibility': {
              'canRequest': !sent,
              'reason': sent ? 'OPEN_RETURN' : 'AVAILABLE',
              'deadline': '2026-10-28T08:00:00Z',
              'items': [
                {'orderItemId': order.items.first.id, 'remaining': 1},
              ],
            },
            'requests': sent ? [returnJson()] : [],
          });
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ReturnsPanel(order: order)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ValueKey('return-quantity-${order.items.first.id}')),
        '1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lý do trả hàng'),
        'Không vừa kích thước',
      );
      await tester.tap(find.text('Tính tiền hàng dự kiến hoàn'));
      await tester.pumpAndSettle();
      expect(quotes, 1);
      expect(find.textContaining('50.000'), findsWidgets);
      await tester.ensureVisible(find.text('Gửi yêu cầu trả hàng'));
      await tester.tap(find.text('Gửi yêu cầu trả hàng'));
      await tester.pumpAndSettle();
      expect(find.text('Chờ duyệt trả hàng'), findsOneWidget);
      expect(find.text('Đã hoàn tiền'), findsNothing);
    },
  );
  testWidgets(
    'uncertain request can be retried after leaving and reopening the order',
    (tester) async {
      final order = commerceOrder(
        orderJson()..['status'] = 'DELIVERED',
        email: '',
      );
      final bodies = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/quote')) {
            return jsonResponse({
              'amount': '50000',
              'items': returnJson()['items'],
            }, 201);
          }
          if (r.method == 'POST') {
            bodies.add(r.body);
            if (bodies.length == 1) throw http.ClientException('Lost response');
            return jsonResponse(returnJson(), 201);
          }
          return jsonResponse({
            'eligibility': {
              'canRequest': true,
              'reason': 'AVAILABLE',
              'deadline': '2026-10-28T08:00:00Z',
              'items': [
                {'orderItemId': order.items.first.id, 'remaining': 1},
              ],
            },
            'requests': [],
          });
        }),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
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
                  child: ReturnsPanel(key: ValueKey(key), order: order),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await open('first');
      await tester.enterText(
        find.byKey(ValueKey('return-quantity-${order.items.first.id}')),
        '1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lý do trả hàng'),
        'Không vừa kích thước',
      );
      await tester.tap(find.text('Tính tiền hàng dự kiến hoàn'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gửi yêu cầu trả hàng'));
      await tester.tap(find.text('Gửi yêu cầu trả hàng'));
      await tester.pumpAndSettle();
      expect(bodies.length, 1);
      await open('reopened');
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Lý do trả hàng'),
            )
            .controller!
            .text,
        'Không vừa kích thước',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(ValueKey('return-quantity-${order.items.first.id}')),
            )
            .controller!
            .text,
        '1',
      );
      await tester.ensureVisible(find.text('Thử gửi lại yêu cầu gốc'));
      await tester.tap(find.text('Thử gửi lại yêu cầu gốc'));
      await tester.pumpAndSettle();
      expect(bodies.length, 2);
      expect(bodies[0], bodies[1]);
    },
  );
  for (final cancel in [false, true]) {
    testWidgets(
      'admin ${cancel ? 'paid cancellation' : 'physical return receipt'} records version and discloses separate refund',
      (tester) async {
        var row = orderJson()
          ..['version'] = 3
          ..['status'] = cancel ? 'PENDING' : 'DELIVERED';
        row['payment'] = {
          'provider': 'vnpay',
          'status': 'PAID',
          'amount': '520000',
        };
        row['returns'] = cancel ? [] : [returnJson(status: 'APPROVED')];
        Map<String, dynamic>? body;
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          client: MockClient((r) async {
            if (r.url.path.endsWith('/login')) {
              final s = sessionJson();
              (s['user'] as Map)['role'] = 'ADMIN';
              return jsonResponse(s);
            }
            if (r.method == 'POST') {
              body = jsonDecode(r.body);
              if (cancel) {
                expect(r.url.path.endsWith('/cancel'), isTrue);
                row['status'] = 'CANCELLED';
              } else {
                expect(
                  r.url.path.endsWith('/returns/return-1/receive'),
                  isTrue,
                );
                row['returns'] = [returnJson(status: 'RECEIVED')];
              }
              return jsonResponse(
                cancel ? row : (row['returns'] as List).first,
                201,
              );
            }
            return jsonResponse(row);
          }),
        );
        final container = ProviderContainer(
          overrides: [
            remoteApiProvider.overrideWithValue(true),
            adminApiClientProvider.overrideWithValue(api),
            adminSessionTokensProvider.overrideWithValue(api.tokens),
          ],
        );
        addTearDown(() {
          container.dispose();
          api.close();
        });
        await container
            .read(adminAccountProvider.notifier)
            .signIn('', 'admin@example.com', 'password');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RemoteAdminOrder(id: 'order-1'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.text(
          cancel ? 'Hủy đơn trước khi gửi' : 'Nhận hàng khách trả',
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.textContaining('hoàn tiền riêng'), findsWidgets);
        await tester.enterText(
          find.widgetWithText(
            TextFormField,
            cancel ? 'Lý do hủy đơn' : 'Ghi chú cho khách',
          ),
          'Đã xác minh yêu cầu',
        );
        await tester.tap(find.text('Lưu thay đổi'));
        await tester.pumpAndSettle();
        expect(body!['expectedVersion'], cancel ? 3 : 1);
        expect(find.text('Đã hoàn tiền'), findsNothing);
      },
    );
  }
}
