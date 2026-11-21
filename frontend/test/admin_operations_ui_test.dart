import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_account_test.dart' show sessionJson;
import 'remote_session_test.dart' show jsonResponse;
import 'staff_test.dart' show staff;

void main() {
  testWidgets(
    'staff search and expanded permission guide survive resizing to mobile',
    (t) async {
      t.view.physicalSize = const Size(1440, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            final session = sessionJson();
            (session['user'] as Map)['role'] = 'ADMIN';
            return jsonResponse(session);
          }
          final items = [
            for (
              var i = 0;
              i < (r.url.queryParameters['email'] == null ? 5 : 1);
              i++
            )
              staff(id: 'staff-$i'),
          ];
          return jsonResponse({
            'items': items,
            'total': items.length,
            'page': 1,
            'limit': 10,
          });
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
          .signIn('', 'admin', 'password');
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: NepApp(router: createRouter(initialLocation: '/admin/staff')),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Email tài khoản'),
        'kho@example.test',
      );
      await t.tap(find.text('Tìm tài khoản'));
      await t.pumpAndSettle();
      await t.tap(find.text('Đổi quyền'));
      await t.pumpAndSettle();
      await t.tap(find.text('Đóng'));
      await t.pumpAndSettle();
      await t.tap(find.text('Hiển thị nhân sự'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Hướng dẫn phân quyền'));
      await t.tap(find.text('Hướng dẫn phân quyền'));
      await t.pumpAndSettle();
      t.view.physicalSize = const Size(375, 900);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Đổi quyền').first);
      await t.tap(find.text('Đổi quyền').first);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
