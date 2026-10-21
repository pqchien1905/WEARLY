import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/commerce_json.dart';
import 'package:nep_storefront/features/account/order_tracking.dart';
import 'package:nep_storefront/features/admin/remote/admin_pages.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_commerce_test.dart' show orderJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> trackedOrder({String state = 'DELIVERY_FAILED'}) =>
    orderJson()
      ..['status'] = state == 'RETURNED' ? 'RETURNED' : 'SHIPPED'
      ..['version'] = 4
      ..['history'] = [
        {
          'id': 'history-1',
          'status': 'SHIPPED',
          'note': '',
          'createdAt': '2026-10-21T06:00:00.000Z',
        },
      ]
      ..['shipment'] = {
        'carrier': 'local_simulator',
        'trackingCode': 'LOCAL-00000000-0000-4000-8000-000000000001',
        'status': state,
        'events': [
          {
            'id': 'event-1',
            'status': 'IN_TRANSIT',
            'note': '',
            'createdAt': '2026-10-21T06:00:00.000Z',
          },
          {
            'id': 'event-2',
            'status': state,
            'note': 'Khách hẹn giao lại',
            'createdAt': '2026-10-21T07:30:00.000Z',
          },
        ],
      };

void main() {
  test(
    'decodes persistent tracking and returned order without losing history',
    () {
      final data = trackedOrder(state: 'RETURNED');
      final order = commerceOrder(data, email: '');
      expect(order.status, 'Đã hoàn về kho');
      expect(order.shipment!.status, 'RETURNED');
      expect(order.history.single.status, 'SHIPPED');
      expect(
        order.withStatus('Đã hoàn về kho').shipment!.events.last.note,
        'Khách hẹn giao lại',
      );
      (data['shipment'] as Map)['status'] = 'UNKNOWN';
      expect(
        () => commerceOrder(data, email: ''),
        throwsA(isA<ApiException>()),
      );
    },
  );
  testWidgets(
    'customer tracking labels simulation, exposes code, notes and UTC+7 times',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderTracking(
                order: commerceOrder(trackedOrder(), email: ''),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Mô phỏng vận chuyển local'), findsOneWidget);
      expect(find.textContaining('LOCAL-00000000'), findsOneWidget);
      expect(find.text('Khách hẹn giao lại'), findsOneWidget);
      expect(
        find.textContaining('2026-10-21 14:30:00 (UTC+7)'),
        findsOneWidget,
      );
    },
  );
  for (final conflict in [false, true]) {
    testWidgets(
      'admin confirms a physical return with version and handles conflict=$conflict',
      (tester) async {
        var reads = 0, writes = 0, row = trackedOrder();
        Map<String, dynamic>? body;
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          client: MockClient((r) async {
            if (r.url.path.endsWith('/login')) {
              final session = sessionJson();
              (session['user'] as Map)['role'] = 'ADMIN';
              return jsonResponse(session);
            }
            if (r.method == 'POST') {
              writes++;
              body = jsonDecode(r.body);
              expect(
                r.url.path,
                '/api/v1/admin/orders/order-1/shipment-events',
              );
              if (conflict) {
                return jsonResponse({
                  'error': {'code': 'ORDER_STATE_CONFLICT'},
                }, 409);
              }
              row = trackedOrder(state: 'RETURNED');
              return jsonResponse(row, 201);
            }
            reads++;
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
        expect(find.text('Đánh dấu đã giao'), findsNothing);
        expect(find.text('Giao lại'), findsOneWidget);
        final action = find.text('Xác nhận hàng hoàn về kho');
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Chỉ xác nhận khi đã nhận lại toàn bộ hàng'),
          findsOneWidget,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Ghi chú cho khách (tùy chọn)'),
          'Đã nhận đủ hàng',
        );
        await tester.tap(find.text('Lưu thay đổi'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(body!['expectedVersion'], 4);
        expect(body!['status'], 'RETURNED');
        expect(body!['note'], 'Đã nhận đủ hàng');
        expect(body!['eventKey'], matches(RegExp(r'^[0-9a-f-]{36}$')));
        if (conflict) {
          expect(find.text('Lưu thay đổi'), findsNothing);
          await tester.tap(find.text('Tải lại dữ liệu'));
          await tester.pumpAndSettle();
        } else {
          expect(find.text('Đã hoàn về kho'), findsWidgets);
          expect(find.text('Giao lại'), findsNothing);
        }
        expect(reads, greaterThan(1));
      },
    );
  }
}
