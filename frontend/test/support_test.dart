import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/support_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_support.dart';
import 'package:nep_storefront/features/info/support_pages.dart';
import 'package:nep_storefront/features/admin/remote/support_page.dart';

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);
const receipt = {'id': 'ticket-1', 'createdAt': '2026-10-22T00:00:00.000Z'};
void main() {
  test('throttled retry retains a possibly committed contact key', () async {
    final writes = <Map<String, dynamic>>[];
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        writes.add(jsonDecode(r.body));
        return writes.length == 1
            ? response({}, 503)
            : writes.length == 2
            ? response({}, 429)
            : response(receipt, 201);
      }),
    );
    addTearDown(api.close);
    final repo = RemoteSupportRepository(api);
    for (var i = 0; i < 2; i++) {
      await expectLater(
        repo.create(
          name: 'An',
          email: 'an@example.test',
          message: 'Please help with size',
        ),
        throwsA(isA<ApiException>()),
      );
    }
    expect(repo.pendingContact, isNotNull);
    await repo.create(
      name: 'An',
      email: 'an@example.test',
      message: 'Please help with size',
    );
    expect(writes[2], writes[0]);
  });
  for (final committed in [true, false]) {
    testWidgets(
      'pending reply can reconcile after close, committed=$committed',
      (tester) async {
        var posts = 0, closed = false;
        final writes = <Map<String, dynamic>>[];
        final ticket = {
          'id': 'ticket-1',
          'name': 'An',
          'email': 'an@example.test',
          'message': 'Please help choose a size.',
          'status': 'CLOSED',
          'version': 2,
          'replies': <Object>[],
        };
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          client: MockClient((r) async {
            if (r.method == 'POST') {
              writes.add(jsonDecode(r.body));
              posts++;
              return posts == 1
                  ? response({}, 503)
                  : committed
                  ? response(receipt, 201)
                  : response({
                      'code': 'SUPPORT_CLOSED',
                      'message': 'Reopen first',
                    }, 409);
            }
            closed = true;
            return response(ticket);
          }),
        );
        addTearDown(api.close);
        final repo = RemoteSupportRepository(api, admin: true);
        await expectLater(
          repo.reply('ticket-1', version: 0, message: 'Original pending reply'),
          throwsA(isA<ApiException>()),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [adminSupportRepositoryProvider.overrideWithValue(repo)],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RemoteSupportDetail(id: 'ticket-1'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(closed, true);
        final retry = find.text('Gửi lại cùng trả lời');
        expect(retry, findsOneWidget);
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(writes[1], writes[0]);
        expect(repo.pendingReply('ticket-1'), isNull);
        if (!committed) {
          await tester.ensureVisible(find.text('Tải lại yêu cầu'));
          await tester.tap(find.text('Tải lại yêu cầu'));
          await tester.pumpAndSettle();
        }
        final reopen = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Mở lại yêu cầu'),
        );
        expect(reopen.onPressed, isNotNull);
      },
    );
  }
  test(
    'public contact keeps the original key and payload after uncertain response',
    () async {
      final writes = <Map<String, dynamic>>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.headers.containsKey('authorization'), false);
          writes.add(jsonDecode(r.body));
          return writes.length == 1
              ? response({'message': 'Temporary failure'}, 503)
              : response(receipt, 201);
        }),
      );
      addTearDown(api.close);
      api.tokens.set(accessToken: 'private', refreshToken: 'refresh');
      final repo = RemoteSupportRepository(api);
      await expectLater(
        repo.create(
          name: ' An ',
          email: ' AN@EXAMPLE.TEST ',
          message: 'Please help with size',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(repo.pendingContact?['email'], 'an@example.test');
      final saved = await repo.create(
        name: 'Changed',
        email: 'different@example.test',
        message: 'Different content',
      );
      expect(saved.id, 'ticket-1');
      expect(writes[1], writes[0]);
      expect(repo.pendingContact, isNull);
    },
  );
  testWidgets(
    'contact restores frozen draft on remount and only confirms a stored receipt',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          writes.add(jsonDecode(r.body));
          return writes.length == 1
              ? response({}, 503)
              : response(receipt, 201);
        }),
      );
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      Future<void> mount() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: SingleChildScrollView(child: ContactPage())),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      for (final e in {
        'Tên của bạn': 'An',
        'Email liên hệ': 'an@example.test',
        'Nội dung cần hỗ trợ': 'Tôi cần chọn size áo phù hợp.',
      }.entries) {
        final f = find.widgetWithText(TextFormField, e.key);
        await tester.ensureVisible(f);
        await tester.enterText(f, e.value);
      }
      final send = find.text('Gửi yêu cầu hỗ trợ');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(find.text('Đã lưu yêu cầu hỗ trợ'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mount();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Tên của bạn'),
            )
            .controller!
            .text,
        'An',
      );
      final retry = find.text('Gửi lại cùng yêu cầu');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Đã lưu yêu cầu hỗ trợ'), findsOneWidget);
      expect(find.textContaining('ticket-1'), findsOneWidget);
      expect(writes[1], writes[0]);
    },
  );
  test(
    'admin reply conflict releases the pending payload and preserves server version checks',
    () async {
      final writes = <Map<String, dynamic>>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          writes.add(jsonDecode(r.body));
          return writes.length == 1
              ? response({'code': 'VERSION_CONFLICT', 'message': 'Reload'}, 409)
              : response(receipt, 201);
        }),
      );
      addTearDown(api.close);
      final repo = RemoteSupportRepository(api, admin: true);
      await expectLater(
        repo.reply('ticket-1', version: 2, message: 'First response'),
        throwsA(isA<ApiException>()),
      );
      expect(repo.pendingReply('ticket-1'), isNull);
      await repo.reply('ticket-1', version: 3, message: 'Updated response');
      expect(writes[1]['expectedVersion'], 3);
      expect(writes[1]['requestKey'], isNot(writes[0]['requestKey']));
    },
  );
  testWidgets(
    'admin shows pending/failed mail and saves a reply with the displayed version',
    (tester) async {
      var replied = false;
      Map<String, dynamic>? body;
      final ticket = {
        'id': 'ticket-1',
        'name': 'An',
        'email': 'an@example.test',
        'message': 'Tôi cần hỗ trợ chọn size.',
        'status': 'OPEN',
        'version': 2,
        'createdAt': '2026-10-22T00:00:00Z',
        'replies': [
          {
            'id': 'r1',
            'message': 'Đã tiếp nhận',
            'createdAt': '2026-10-22T00:00:00Z',
            'mail': {'status': 'PENDING'},
          },
          {
            'id': 'r2',
            'message': 'Thử gửi',
            'createdAt': '2026-10-22T00:00:00Z',
            'mail': {'status': 'FAILED'},
          },
        ],
      };
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            replied = true;
            body = jsonDecode(r.body);
            ticket['status'] = 'ANSWERED';
            ticket['version'] = 3;
            return response(receipt, 201);
          }
          return response(ticket);
        }),
      );
      final repo = RemoteSupportRepository(api, admin: true);
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminSupportRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RemoteSupportDetail(id: 'ticket-1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chờ gửi thư'), findsOneWidget);
      expect(find.text('Gửi thư thất bại'), findsOneWidget);
      final field = find.widgetWithText(TextFormField, 'Nội dung trả lời');
      await tester.ensureVisible(field);
      await tester.enterText(
        field,
        'Bạn có thể đối chiếu bảng size ở trang sản phẩm.',
      );
      final send = find.text('Lưu và gửi trả lời');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(replied, true);
      expect(body!['expectedVersion'], 2);
      expect(find.text('Đã lưu trả lời; thư đang được xử lý.'), findsOneWidget);
    },
  );
}
