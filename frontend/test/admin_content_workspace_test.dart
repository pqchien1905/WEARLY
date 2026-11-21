import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/store_details.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> content() => {
  'id': 'content-1',
  'banner': 'Bản nháp mùa thu',
  'policy': 'Giao hàng theo đơn đặt',
  'details': {
    ...StoreDetails.defaults,
    'name': 'Wearly Studio',
    'about': 'Câu chuyện cửa hàng',
  },
  'version': 3,
  'hasUnpublishedChanges': true,
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': '2026-10-24T03:00:00Z',
  'published': {
    'banner': 'Chiến dịch đang hiển thị',
    'policy': 'Chính sách công khai',
    'details': {...StoreDetails.defaults, 'name': 'Wearly Studio'},
    'version': 2,
    'publishedAt': '2026-10-23T03:00:00Z',
  },
};
void main() {
  Future<(ProviderContainer, GoRouter)> mount(
    WidgetTester t,
    Future<http.Response> Function(http.Request) handle, {
    double width = 1440,
    double scale = 1,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    t.view.physicalSize = Size(width, 1100);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      timeout: timeout,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/login')) {
          final s = sessionJson();
          (s['user'] as Map)['role'] = 'ADMIN';
          return jsonResponse(s);
        }
        if (r.url.path.endsWith('/logout')) return jsonResponse({});
        if (r.url.path == '/api/v1/content') {
          return jsonResponse({'content': content()['published']});
        }
        if (r.url.path.endsWith('/history')) {
          return jsonResponse({
            'items': [],
            'total': 0,
            'page': 1,
            'limit': 10,
          });
        }
        return handle(r);
      }),
    );
    final scope = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(api),
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
    final router = createRouter(initialLocation: '/admin/content');
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: NepApp(router: router),
      ),
    );
    await t.pumpAndSettle();
    return (scope, router);
  }

  Finder field(String s) => find.widgetWithText(TextFormField, s);
  Finder action(String s) =>
      find.widgetWithText(FilledButton, s).evaluate().isNotEmpty
      ? find.widgetWithText(FilledButton, s)
      : find.widgetWithText(OutlinedButton, s).evaluate().isNotEmpty
      ? find.widgetWithText(OutlinedButton, s)
      : find.widgetWithText(TextButton, s);
  Future<void> click(WidgetTester t, String s) async {
    final f = action(s);
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> group(WidgetTester t, String s) async {
    final f = find.widgetWithText(ChoiceChip, s);
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> fill(WidgetTester t, String label, String value) async {
    await t.ensureVisible(field(label));
    await t.enterText(field(label), value);
    await t.pump();
  }

  for (final (width, scale) in [
    (375.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (375.0, 1.5),
  ]) {
    testWidgets(
      'all content groups, preview and publication review fit $width/$scale',
      (t) async {
        await mount(
          t,
          (r) async => jsonResponse(content()),
          width: width,
          scale: scale,
        );
        for (final label in [
          'Giới thiệu',
          'Liên hệ',
          'Chính sách',
          'Trang chủ',
        ]) {
          await group(t, label);
          expect(t.takeException(), isNull);
        }
        await click(t, 'Xem trước');
        expect(find.text('Xem trước bản nháp đã lưu'), findsOneWidget);
        await click(t, 'Đóng xem trước');
        await click(t, 'Xuất bản nội dung');
        expect(find.text('Xuất bản nội dung?'), findsOneWidget);
        await click(t, 'Tiếp tục chỉnh sửa');
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'validates hidden groups and publishes only after saving and reviewing the exact draft',
    (t) async {
      var state = content();
      final writes = <http.Request>[];
      await mount(t, (r) async {
        if (r.method == 'PUT') {
          writes.add(r);
          final b = jsonDecode(r.body);
          state = {...state, ...b, 'version': 4};
        }
        if (r.method == 'POST') {
          writes.add(r);
          state = {
            ...state,
            'version': 5,
            'published': {
              ...state,
              'version': 5,
              'publishedAt': '2026-10-24T03:00:00Z',
            },
          };
        }
        return jsonResponse(state);
      });
      await fill(t, 'Tiêu đề trang chủ', 'Thay đổi riêng');
      await group(t, 'Liên hệ');
      await fill(t, 'Email cửa hàng (không bắt buộc)', 'invalid');
      await group(t, 'Trang chủ');
      await click(t, 'Lưu bản nháp');
      expect(find.text('Email không hợp lệ.'), findsOneWidget);
      expect(writes, isEmpty);
      await fill(t, 'Email cửa hàng (không bắt buộc)', 'hello@example.test');
      await group(t, 'Chính sách');
      await fill(t, 'Nội dung chính sách', 'Chính sách mới');
      expect(
        t.widget<OutlinedButton>(action('Xuất bản nội dung')).onPressed,
        isNull,
      );
      await click(t, 'Lưu bản nháp');
      expect(writes.length, 1);
      final body = jsonDecode(writes.first.body);
      expect(body['expectedVersion'], 3);
      expect(body['banner'], 'Thay đổi riêng');
      expect(body['details']['email'], 'hello@example.test');
      expect(state['published']['policy'], 'Chính sách công khai');
      await click(t, 'Xuất bản nội dung');
      expect(writes.length, 1);
      expect(find.text('Đang công khai'), findsWidgets);
      await click(t, 'Xác nhận xuất bản');
      expect(jsonDecode(writes.last.body), {'expectedVersion': 4});
      expect(find.text('Đã đồng bộ với bản công khai'), findsOneWidget);
    },
  );
  testWidgets(
    'reload confirmation preserves edits on cancel and adopts canonical state when accepted',
    (t) async {
      var reads = 0;
      await mount(t, (r) async {
        reads++;
        return jsonResponse(
          content()..['banner'] = reads == 1 ? 'Bản ban đầu' : 'Bản từ máy chủ',
        );
      });
      await fill(t, 'Tiêu đề trang chủ', 'Chưa lưu');
      await click(t, 'Tải lại bản đã lưu');
      await click(t, 'Tiếp tục chỉnh sửa');
      expect(reads, 1);
      expect(
        t.widget<TextFormField>(field('Tiêu đề trang chủ')).controller!.text,
        'Chưa lưu',
      );
      await click(t, 'Tải lại bản đã lưu');
      await click(t, 'Tải lại');
      expect(reads, 2);
      expect(
        t.widget<TextFormField>(field('Tiêu đề trang chủ')).controller!.text,
        'Bản từ máy chủ',
      );
    },
  );
  testWidgets('restore is versioned and leaves public snapshot unchanged', (
    t,
  ) async {
    var state = content();
    Map<String, dynamic>? body;
    final before = Map<String, dynamic>.from(state['published']);
    await mount(t, (r) async {
      if (r.method == 'POST') {
        expect(r.url.path.endsWith('/restore'), true);
        body = jsonDecode(r.body);
        state = {...state, ...before, 'version': 4, 'published': before};
      }
      return jsonResponse(state);
    });
    await click(t, 'Khôi phục từ bản công khai');
    await click(t, 'Khôi phục bản nháp');
    expect(body, {'expectedVersion': 3});
    expect(state['published'], before);
    expect(find.text('Đã đồng bộ với bản công khai'), findsOneWidget);
    expect(
      t.widget<OutlinedButton>(action('Xuất bản nội dung')).onPressed,
      isNull,
    );
  });
  testWidgets('route guard keeps unsaved edits until user explicitly leaves', (
    t,
  ) async {
    final (_, router) = await mount(t, (r) async => jsonResponse(content()));
    await fill(t, 'Tiêu đề trang chủ', 'Chưa lưu khi rời trang');
    router.go('/about');
    await t.pumpAndSettle();
    expect(find.text('Rời trang khi chưa lưu?'), findsOneWidget);
    await click(t, 'Tiếp tục chỉnh sửa');
    expect(find.text('Nội dung cửa hàng'), findsOneWidget);
    router.go('/about');
    await t.pumpAndSettle();
    await click(t, 'Rời trang');
    expect(find.text('Nội dung cửa hàng'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'preview and publication review hide private content when session ends',
    (t) async {
      var writes = 0;
      final (scope, _) = await mount(t, (r) async {
        if (r.method == 'POST') writes++;
        return jsonResponse(content());
      });
      await click(t, 'Xuất bản nội dung');
      await scope.read(adminAccountProvider.notifier).signOut();
      await t.pumpAndSettle();
      expect(find.text('Xác nhận xuất bản'), findsNothing);
      expect(find.text('Bản nháp mùa thu'), findsNothing);
      expect(writes, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'private review closes when the same account loses content access',
    (t) async {
      var writes = 0;
      final (scope, _) = await mount(t, (r) async {
        if (r.url.path.endsWith('/users/me')) {
          final user = Map<String, dynamic>.from(sessionJson()['user'] as Map);
          user['role'] = 'WAREHOUSE';
          return jsonResponse(user);
        }
        if (r.method == 'POST') writes++;
        return jsonResponse(content());
      });
      await click(t, 'Xuất bản nội dung');
      await scope.read(adminAccountProvider.notifier).refreshProfile();
      await t.pumpAndSettle();
      expect(find.text('Xác nhận xuất bản'), findsNothing);
      expect(find.text('Bản nháp mùa thu'), findsNothing);
      expect(writes, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('pending save is single-flight and blocks route changes', (
    t,
  ) async {
    final pending = Completer<http.Response>();
    var writes = 0;
    final (_, router) = await mount(t, (r) async {
      if (r.method == 'PUT') {
        writes++;
        return pending.future;
      }
      return jsonResponse(content());
    });
    await fill(t, 'Tiêu đề trang chủ', 'Đang lưu');
    await t.ensureVisible(action('Lưu bản nháp'));
    await t.tap(action('Lưu bản nháp'));
    await t.pump();
    router.go('/about');
    await t.pump();
    expect(find.text('Nội dung cửa hàng'), findsOneWidget);
    expect(writes, 1);
    pending.complete(
      jsonResponse(content()..addAll({'banner': 'Đang lưu', 'version': 4})),
    );
    await t.pumpAndSettle();
    expect(find.text('Đã lưu bản nháp. Chưa xuất bản.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'late save after timeout requires reconciliation and keeps local edits visible',
    (t) async {
      final pending = Completer<http.Response>();
      var writes = 0, reads = 0;
      var state = content();
      await mount(t, (r) async {
        if (r.method == 'PUT') {
          writes++;
          return pending.future;
        }
        reads++;
        return jsonResponse(state);
      }, timeout: const Duration(milliseconds: 300));
      await fill(t, 'Tiêu đề trang chủ', 'Kết quả đến muộn');
      await t.ensureVisible(action('Lưu bản nháp'));
      await t.tap(action('Lưu bản nháp'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.text('Cần tải lại'), findsOneWidget);
      expect(writes, 1);
      state = content()..addAll({'banner': 'Kết quả đến muộn', 'version': 4});
      pending.complete(jsonResponse(state));
      await t.pumpAndSettle();
      expect(
        t.widget<TextFormField>(field('Tiêu đề trang chủ')).controller!.text,
        'Kết quả đến muộn',
      );
      expect(reads, 1);
      await click(t, 'Tải lại bản đã lưu');
      await click(t, 'Tải lại');
      expect(reads, 2);
      expect(find.text('Cần tải lại'), findsNothing);
      expect(writes, 1);
    },
  );
  testWidgets('initial fetch error can be retried without inventing a draft', (
    t,
  ) async {
    var calls = 0;
    await mount(t, (r) async {
      calls++;
      return calls == 1
          ? jsonResponse({
              'error': {'code': 'OFFLINE', 'message': 'Không kết nối được'},
            }, 503)
          : jsonResponse(content());
    });
    expect(find.text('Chưa tải được dữ liệu'), findsOneWidget);
    await click(t, 'Thử tải lại');
    expect(find.text('Nội dung cửa hàng'), findsOneWidget);
  });
}
