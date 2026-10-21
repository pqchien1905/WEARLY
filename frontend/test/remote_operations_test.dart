import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_operations.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> operationsJson({bool available = true}) => {
  'observedAt': '2026-10-22T03:00:00Z',
  'database': {
    'status': available ? 'ok' : 'unavailable',
    'schemaReady': available ? true : null,
    'migrations': available ? 26 : null,
  },
  'redis': {
    'status': available ? 'ok' : 'unavailable',
    'queues': available
        ? {
            'tryOn': {
              'waiting': 3,
              'active': 0,
              'delayed': 0,
              'failed': 1,
              'oldestWaitingAt': '2026-10-22T02:00:00Z',
            },
            'recovery': null,
          }
        : null,
  },
  'worker': {'status': 'unavailable', 'lastAt': null},
  'storage': {'status': 'ok'},
  'mail': {'status': 'disabled'},
  'providers': {
    'gemini': {
      'configured': false,
      'stylistModel': 'gemini-fixture-text',
      'tryOnModel': 'gemini-fixture-image',
    },
    'vnpay': {'configured': false, 'sandbox': true},
    'shipping': {'mode': 'local', 'sandbox': true},
  },
  'work': available
      ? {
          'outbox': {'pending': 2, 'oldestPendingAt': '2026-10-22T02:50:00Z'},
          'ai': <String, dynamic>{
            'reserved': 2,
            'processing': 0,
            'stale': 1,
            'todayCount': 3,
            'todayEstimatedVnd': '3500',
            'dayStartedAt': '2026-10-22T00:00:00Z',
            'failuresSinceAt': '2026-10-21T03:00:00Z',
            'failures': [
              {'kind': 'TRY_ON', 'code': 'PROVIDER_TIMEOUT', 'count': 1},
            ],
          },
          'mail': {'pending': 0, 'processing': 0, 'failed': 0},
          'cleanup': {'imagesPending': 1},
        }
      : null,
};

void main() {
  test('missing measurements remain unknown while real zero is retained', () {
    final absent = OperationsSnapshot.fromJson(
      operationsJson(available: false),
    );
    expect(absent.work, isNull);
    expect(absent.tryOnQueue, isNull);
    final good = OperationsSnapshot.fromJson(operationsJson());
    expect(good.work!.processing, 0);
    expect(good.tryOnQueue!.waiting, 3);
    expect(good.workerLive, isFalse);
  });
  test('aggregate VND remains exact beyond JavaScript safe integer', () {
    final data = operationsJson();
    data['work']['ai']['todayEstimatedVnd'] = '9007199254740993';
    expect(
      OperationsSnapshot.fromJson(data).work!.estimatedVnd,
      '9007199254740993',
    );
    expect(operationsMoney('9007199254740993'), '9.007.199.254.740.993 ₫');
  });
  test(
    'rejects malformed totals instead of displaying zero or a rounded amount',
    () {
      for (final bad in [-1, 'NaN', 3.5, null]) {
        final data = operationsJson();
        data['work']['ai']['todayCount'] = bad;
        expect(
          () => OperationsSnapshot.fromJson(data),
          throwsA(isA<ApiException>()),
        );
      }
      final data = operationsJson();
      data['work']['ai']['todayEstimatedVnd'] = 3500;
      expect(
        () => OperationsSnapshot.fromJson(data),
        throwsA(isA<ApiException>()),
      );
    },
  );
  Future<ProviderContainer> setup(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    String role = 'ADMIN',
    bool mobile = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(mobile ? 375 : 1440, mobile ? 812 : 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/auth/admin/login')) {
          final data = sessionJson();
          (data['user'] as Map)['role'] = role;
          return jsonResponse(data);
        }
        return handler(r);
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
        .signIn('', 'an@example.com', 'password');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(
          router: createRouter(initialLocation: '/admin/ai-monitoring'),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return container;
  }

  testWidgets(
    'mobile diagnostics distinguish unavailable and disabled without inventing counts',
    (tester) async {
      await setup(
        tester,
        (r) async => jsonResponse(operationsJson(available: false)),
        mobile: true,
      );
      expect(find.text('Vận hành & AI'), findsWidgets);
      expect(find.text('Chưa có số liệu công việc.'), findsOneWidget);
      expect(
        find.textContaining('Không có tín hiệu worker gần đây'),
        findsOneWidget,
      );
      expect(find.text('Tắt'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('shows estimated cost and UTC window with live queue counts', (
    tester,
  ) async {
    await setup(tester, (r) async => jsonResponse(operationsJson()));
    expect(find.text('3.500 ₫'), findsOneWidget);
    expect(find.textContaining('Ước tính'), findsWidgets);
    expect(find.textContaining('UTC'), findsWidgets);
    expect(find.textContaining('Chưa cấu hình'), findsWidgets);
    expect(find.textContaining('Đang chờ: 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('manual retry recovers a failed read without starting work', (
    tester,
  ) async {
    var reads = 0;
    final methods = <String>[];
    await setup(tester, (r) async {
      methods.add(r.method);
      reads++;
      return reads == 1
          ? jsonResponse({
              'error': {'code': 'UNAVAILABLE', 'message': 'Chưa kết nối.'},
            }, 503)
          : jsonResponse(operationsJson());
    });
    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();
    expect(find.text('3.500 ₫'), findsOneWidget);
    expect(methods, ['GET', 'GET']);
  });
  testWidgets('manager deep link never requests private operations', (
    tester,
  ) async {
    final paths = <String>[];
    await setup(tester, (r) async {
      paths.add(r.url.path);
      return jsonResponse(operationsJson());
    }, role: 'MANAGER');
    expect(find.text('Bạn chưa có quyền truy cập'), findsOneWidget);
    expect(paths.where((p) => p.endsWith('/admin/operations')), isEmpty);
    expect(find.text('Vận hành & AI'), findsNothing);
  });
  testWidgets('late diagnostics disappear after the admin session is cleared', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final container = await setup(tester, (r) => pending.future, settle: false);
    container.read(adminSessionTokensProvider).clear();
    await tester.pump();
    pending.complete(jsonResponse(operationsJson()));
    await tester.pumpAndSettle();
    expect(find.text('3.500 ₫'), findsNothing);
    expect(find.text('Đăng nhập quản trị'), findsWidgets);
  });
}
