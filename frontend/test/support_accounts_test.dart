import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/features/account/support_page.dart';
import 'package:nep_storefront/features/admin/remote/support_page.dart';
import 'package:nep_storefront/features/info/remote_contact_page.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;

const ticketId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> thread({String status = 'ANSWERED'}) => {
  'id': ticketId,
  'message': 'Tôi cần đổi size áo sơ mi.',
  'status': status,
  'createdAt': '2026-11-20T03:00:00.000Z',
  'updatedAt': '2026-11-20T04:00:00.000Z',
  'replies': [
    {
      'id': 'a',
      'message': 'Bạn có thể đổi trong 7 ngày.',
      'fromCustomer': false,
      'createdAt': '2026-11-20T04:00:00.000Z',
    },
    {
      'id': 'b',
      'message': 'Cảm ơn shop.',
      'fromCustomer': true,
      'createdAt': '2026-11-20T05:00:00.000Z',
    },
  ],
};

Future<List<http.Request>> mount(
  WidgetTester t,
  String location, {
  bool signedIn = true,
  bool admin = false,
  String status = 'ANSWERED',
}) async {
  t.view.physicalSize = const Size(1280, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  Future<http.Response> handle(http.Request r) async {
    if (r.url.path.endsWith('/login')) {
      return jsonResponse(loginJson(admin ? 'admin' : 'customer'));
    }
    requests.add(r);
    final path = r.url.path.replaceFirst('/api/v1/', '');
    if (path == 'content') return jsonResponse({'content': null});
    if (r.method == 'POST') {
      return jsonResponse({
        'id': ticketId,
        'createdAt': '2026-11-21T00:00:00.000Z',
      }, 201);
    }
    if (path == 'users/me/support/$ticketId') {
      return jsonResponse(thread(status: status));
    }
    if (path == 'users/me/support' || path == 'admin/support') {
      return jsonResponse({
        'items': [
          {
            ...thread(status: status)..remove('replies'),
            '_count': {'replies': 2},
            'version': 2,
            'name': 'customer',
            'email': 'customer@example.com',
          },
        ],
        'total': 1,
        'page': 1,
        'limit': admin ? 20 : 10,
      });
    }
    return jsonResponse({}, 404);
  }

  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient(handle),
  );
  final adminApi = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient(handle),
  );
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      remoteApiProvider.overrideWithValue(true),
      apiClientProvider.overrideWithValue(api),
      sessionTokensProvider.overrideWithValue(api.tokens),
      adminApiClientProvider.overrideWithValue(adminApi),
      adminSessionTokensProvider.overrideWithValue(adminApi.tokens),
    ],
  );
  Widget page(Widget child) =>
      Scaffold(body: SingleChildScrollView(child: child));
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/account/support',
        builder: (_, _) => page(const SupportRequestsPage()),
      ),
      GoRoute(
        path: '/account/support/:id',
        builder: (_, s) =>
            page(SupportRequestsPage(id: s.pathParameters['id'])),
      ),
      GoRoute(
        path: '/contact',
        builder: (_, _) => page(const RemoteContactPage()),
      ),
      GoRoute(
        path: '/admin/customer',
        builder: (_, _) =>
            page(const CustomerSupportTickets(userId: 'customer-user')),
      ),
      GoRoute(
        path: '/admin/support/:id',
        builder: (_, s) => Text('Admin ticket ${s.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(() {
    router.dispose();
    container.dispose();
    api.close();
    adminApi.close();
  });
  if (signedIn && !admin) {
    await container
        .read(accountProvider.notifier)
        .signIn('', 'customer@example.com', 'password');
  }
  if (admin) {
    await container
        .read(adminAccountProvider.notifier)
        .signIn('', 'admin', 'password');
  }
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: buildTheme(), routerConfig: router),
    ),
  );
  await t.pumpAndSettle();
  return requests;
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('customers list their requests and open the thread', (t) async {
    final requests = await mount(t, '/account/support');
    expect(requests.first.url.path, '/api/v1/users/me/support');
    expect(find.text('Tôi cần đổi size áo sơ mi.'), findsOneWidget);
    expect(find.text('Đã trả lời'), findsOneWidget);
    await tap(t, find.text('Tôi cần đổi size áo sơ mi.'));
    expect(find.text('Cửa hàng WEARLY'), findsOneWidget);
    expect(find.text('Bạn'), findsOneWidget);
    expect(find.text('Bạn có thể đổi trong 7 ngày.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a follow-up sends only the message with a request key', (
    t,
  ) async {
    final requests = await mount(t, '/account/support/$ticketId');
    await tap(t, find.text('Gửi tin nhắn'));
    expect(find.text('Nhập từ 3 đến 3000 ký tự.'), findsOneWidget);
    await t.enterText(find.byType(TextFormField), '  Size M nhé  ');
    await tap(t, find.text('Gửi tin nhắn'));
    final post = requests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/v1/users/me/support/$ticketId/replies');
    final body = jsonDecode(post.body) as Map;
    expect(body.keys.toSet(), {'requestKey', 'message'});
    expect(body['message'], 'Size M nhé');
  });

  testWidgets('a closed request asks for a new one instead of a reply', (
    t,
  ) async {
    await mount(t, '/account/support/$ticketId', status: 'CLOSED');
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('Yêu cầu đã đóng'), findsOneWidget);
  });

  testWidgets('signed-in contact requests are linked to the account', (
    t,
  ) async {
    final requests = await mount(t, '/contact');
    expect(find.text('Tên của bạn'), findsNothing);
    expect(find.text('Email liên hệ'), findsNothing);
    expect(find.textContaining('customer@example.com'), findsWidgets);
    await t.enterText(
      find.byType(TextFormField),
      'Tôi muốn hỏi về chính sách đổi hàng.',
    );
    await tap(t, find.text('Gửi yêu cầu hỗ trợ'));
    final post = requests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/v1/users/me/support');
    expect((jsonDecode(post.body) as Map).keys.toSet(), {
      'requestKey',
      'message',
    });
    expect(find.text('Xem trong tài khoản'), findsOneWidget);
  });

  testWidgets('guest contact requests still use the public form', (t) async {
    final requests = await mount(t, '/contact', signedIn: false);
    expect(find.text('Tên của bạn'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(0), 'Khách');
    await t.enterText(find.byType(TextFormField).at(1), 'guest@example.com');
    await t.enterText(
      find.byType(TextFormField).at(2),
      'Tôi muốn hỏi về chính sách đổi hàng.',
    );
    await tap(t, find.text('Gửi yêu cầu hỗ trợ'));
    final post = requests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/v1/support');
    expect(find.text('Xem trong tài khoản'), findsNothing);
  });

  testWidgets('admin customer profile lists the linked tickets', (t) async {
    final requests = await mount(t, '/admin/customer', admin: true);
    final list = requests.singleWhere(
      (r) => r.url.path == '/api/v1/admin/support',
    );
    expect(list.url.queryParameters['userId'], 'customer-user');
    expect(find.text('Đã trả lời · 2 phản hồi'), findsOneWidget);
    await tap(t, find.text('Đã trả lời · 2 phản hồi'));
    expect(find.text('Admin ticket $ticketId'), findsOneWidget);
  });
}
