import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/widgets/store_shell.dart';
import 'package:nep_storefront/features/catalog/catalog_page.dart';
import 'package:nep_storefront/domain/catalog.dart';
import 'package:nep_storefront/features/info/collection_page.dart';
import 'remote_catalog_test.dart' show productJson;
import 'collections_test.dart' show collectionJson;

http.Response json(Object? data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<void> mount(
  WidgetTester tester,
  Widget child,
  Future<http.Response> Function(http.Request) handler,
) async {
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    client: MockClient(handler),
  );
  addTearDown(api.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real catalog exposes shoe/Freesize and actual style filters without fixture sizes',
    (tester) async {
      String? key, value;
      await mount(
        tester,
        FilterControls(
          query: const ProductQuery(),
          onChange: (k, v) {
            key = k;
            value = v;
          },
          onClear: () {},
        ),
        (r) async {
          expect(r.url.path, '/api/v1/products/facets');
          return json({
            'colors': ['Đen'],
            'sizes': ['37', 'Freesize'],
            'styles': ['Cá tính'],
          });
        },
      );
      expect(find.text('XS'), findsNothing);
      expect(find.text('Freesize'), findsOneWidget);
      await tester.ensureVisible(find.text('37'));
      await tester.tap(find.text('37'));
      await tester.pump();
      expect(key, 'size');
      expect(value, '37');
      expect(find.text('Cá tính'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'collections use matching API products with arbitrary slugs, not seed IDs',
    (tester) async {
      await mount(tester, const CollectionPage(slug: 'everyday'), (r) async {
        expect(r.url.path, '/api/v1/collections/everyday');
        return json({
          'collection': collectionJson(slug: 'everyday'),
          'page': 1,
          'limit': 12,
          'items': [
            {
              ...productJson(),
              'slug': 'ao-moi-trong-kho',
              'name': 'Áo mới trong kho',
            },
          ],
          'total': 1,
        });
      });
      expect(find.text('Áo mới trong kho'), findsOneWidget);
      expect(find.text('Bộ sưu tập đang được cập nhật'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'newsletter requires consent, reports failure, retains email and suppresses duplicate submits',
    (tester) async {
      var writes = 0;
      final pending = Completer<http.Response>();
      await mount(tester, const StoreFooter(), (r) async {
        if (r.method == 'GET') return json({'content': null});
        expect(r.url.path, '/api/v1/content/newsletter');
        expect(r.headers['authorization'], isNull);
        expect(jsonDecode(r.body), {
          'email': 'reader@example.com',
          'consent': true,
        });
        writes++;
        if (writes == 1) {
          return json({
            'error': {'code': 'UNAVAILABLE'},
          }, 503);
        }
        return pending.future;
      });
      final field = find.widgetWithText(TextFormField, 'Email của bạn');
      final submit = find.widgetWithText(OutlinedButton, 'Đăng ký nhận tin');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'reader@example.com');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(
        find.text('Bạn cần đồng ý nhận tin trước khi đăng ký.'),
        findsOneWidget,
      );
      final consent = find.byType(CheckboxListTile);
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pump();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        'reader@example.com',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);
      expect(writes, 2);
      pending.complete(json({'accepted': true}, 201));
      await tester.pumpAndSettle();
      expect(find.text('Đã đăng ký'), findsOneWidget);
      expect(tester.widget<TextFormField>(field).controller!.text, '');
      expect(tester.takeException(), isNull);
    },
  );
}
