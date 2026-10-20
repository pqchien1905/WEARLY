import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/content_provider.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/widgets/store_content.dart';
import 'package:nep_storefront/features/admin/remote/admin_providers.dart';
import 'package:nep_storefront/features/admin/remote/content_page.dart';
import 'package:nep_storefront/features/info/info_page.dart';
import 'package:nep_storefront/features/info/support_pages.dart';
import 'remote_session_test.dart' show jsonResponse;

void main() {
  Future<(ApiClient, ProviderContainer)> mount(
    WidgetTester tester,
    Widget child,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(handler),
    );
    api.tokens.set(accessToken: 'test-admin', refreshToken: 'test-refresh');
    final repository = AdminRepository(api);
    addTearDown(() {
      repository.dispose();
      api.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        retry: (count, error) => null,
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
          adminRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      api,
      ProviderScope.containerOf(tester.element(find.byType(Scaffold))),
    );
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.pump();
    final button =
        find.widgetWithText(OutlinedButton, label).evaluate().isNotEmpty
        ? find.widgetWithText(OutlinedButton, label)
        : find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'saved drafts remain separate and publish only the observed saved revision',
    (tester) async {
      tester.view.physicalSize = const Size(375, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var state = <String, dynamic>{
        'id': null,
        'banner': 'Initial',
        'policy': '',
        'version': 0,
        'published': null,
      };
      final writes = <http.Request>[];
      await mount(tester, const RemoteContentPage(), (r) async {
        if (r.method != 'GET') {
          writes.add(r);
          final body = jsonDecode(r.body) as Map;
          expect(body['expectedVersion'], state['version']);
          if (r.method == 'PUT') {
            state = {
              ...state,
              'id': 'content-1',
              'banner': body['banner'],
              'policy': body['policy'],
              'version': (state['version'] as int) + 1,
            };
          } else {
            expect(body.keys.toList(), ['expectedVersion']);
            state = {
              ...state,
              'version': 2,
              'published': {
                'banner': state['banner'],
                'policy': state['policy'],
                'version': 2,
              },
            };
          }
        }
        return jsonResponse(state);
      });
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tiêu đề campaign'),
        'Campaign <plain>',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nội dung chính sách'),
        'Published policy text',
      );
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Xuất bản nội dung'),
            )
            .onPressed,
        isNull,
      );
      await press(tester, 'Lưu bản nháp');
      expect(writes.length, 1);
      expect(writes.single.method, 'PUT');
      expect(
        find.textContaining('Bản nháp chỉ quản trị viên nhìn thấy.'),
        findsOneWidget,
      );
      await press(tester, 'Xuất bản nội dung');
      expect(writes.length, 2);
      expect(writes.last.url.path, '/api/v1/admin/content/publish');
      expect(find.text('Published policy text'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving the content editor during publication does not apply a stale session response',
    (tester) async {
      final response = Completer<http.Response>();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      var writes = 0;
      final (api, container) = await mount(
        tester,
        ValueListenableBuilder(
          valueListenable: visible,
          builder: (context, show, _) =>
              show ? const RemoteContentPage() : const Text('Signed out'),
        ),
        (r) async {
          if (r.method == 'POST') {
            writes++;
            return response.future;
          }
          return jsonResponse({
            'id': 'c1',
            'version': 1,
            'banner': 'Saved',
            'policy': 'Saved policy',
            'published': null,
          });
        },
      );
      final before = container.read(contentRevisionProvider);
      final publish = find.widgetWithText(OutlinedButton, 'Xuất bản nội dung');
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pump();
      api.tokens.clear();
      visible.value = false;
      await tester.pump();
      response.complete(
        jsonResponse({
          'version': 2,
          'published': {
            'banner': 'Saved',
            'policy': 'Saved policy',
            'version': 2,
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Signed out'), findsOneWidget);
      expect(find.text('Đã xuất bản nội dung.'), findsNothing);
      expect(container.read(contentRevisionProvider), before + 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conflicting content write cannot repeat until current draft is reloaded',
    (tester) async {
      var reads = 0, writes = 0;
      await mount(tester, const RemoteContentPage(), (r) async {
        if (r.method == 'GET') {
          reads++;
          return jsonResponse({
            'id': 'c1',
            'version': reads == 1 ? 1 : 2,
            'banner': reads == 1 ? 'Original' : 'Other editor',
            'policy': 'Saved policy',
            'published': null,
          });
        }
        writes++;
        return jsonResponse({
          'error': {'code': 'VERSION_CONFLICT', 'message': 'Changed elsewhere'},
        }, 409);
      });
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tiêu đề campaign'),
        'My edit',
      );
      await press(tester, 'Lưu bản nháp');
      expect(writes, 1);
      expect(
        find.text('Dữ liệu đã thay đổi. Tải lại trước khi tiếp tục.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Lưu bản nháp'),
            )
            .onPressed,
        isNull,
      );
      expect(writes, 1);
      await press(tester, 'Tải lại bản đã lưu');
      expect(find.text('Other editor'), findsOneWidget);
      expect(
        find.text('Dữ liệu đã thay đổi. Tải lại trước khi tiếp tục.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'public content is plain text, unauthenticated and never falls back on an error',
    (tester) async {
      var reads = 0;
      await mount(
        tester,
        const StoreContentText(field: 'policy', fallback: 'Demo fallback'),
        (r) async {
          expect(r.url.path, '/api/v1/content');
          expect(r.headers['authorization'], isNull);
          reads++;
          return reads == 1
              ? jsonResponse({
                  'error': {'code': 'UNAVAILABLE', 'message': 'Offline'},
                }, 503)
              : jsonResponse({
                  'content': {
                    'banner': 'Title',
                    'policy': '<script>plain text</script>',
                  },
                  'draftPolicy': 'PRIVATE',
                });
        },
      );
      expect(find.text('Demo fallback'), findsNothing);
      await press(tester, 'Tải lại nội dung');
      expect(find.text('<script>plain text</script>'), findsOneWidget);
      expect(find.text('PRIVATE'), findsNothing);
    },
  );

  testWidgets(
    'remote privacy and FAQ explain persisted orders and link published policy',
    (tester) async {
      await mount(
        tester,
        const InfoPage(path: '/privacy'),
        (r) async => jsonResponse({}),
      );
      expect(find.text('Dữ liệu khi kết nối cửa hàng'), findsOneWidget);
      expect(find.textContaining('mất khi tải lại ứng dụng'), findsNothing);
      await mount(tester, const FaqPage(), (r) async => jsonResponse({}));
      await tester.tap(find.text('Đặt hàng ở đây được xử lý thế nào?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('được lưu trên máy chủ'), findsOneWidget);
      expect(find.text('Xem chính sách cửa hàng'), findsOneWidget);
    },
  );
}
