import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_details.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_account_details.dart';
import 'package:nep_storefront/features/account/address_page.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'remote_style_preferences_test.dart' show styleJson;
import 'remote_account_test.dart' show sessionJson;

const draft = DeliveryAddress(
  id: '',
  label: 'Nhà',
  recipient: 'An',
  phone: '0901234567',
  address: '12 Nguyễn Huệ',
);
const key = 'address-test-request-key-2026';
Map<String, dynamic> savedAddress() => {
  'id': 'address-1',
  'label': 'Nhà',
  'recipient': 'An',
  'phone': '0901234567',
  'address': '12 Nguyễn Huệ',
  'isDefault': true,
};

void main() {
  for (final explicitRefresh in [false, true]) {
    test(
      'late completion during retry recovers even with explicit refresh=$explicitRefresh',
      () async {
        final original = Completer<http.Response>(),
            retry = Completer<http.Response>();
        final rows = <Map<String, dynamic>>[];
        String? originalBody;
        var posts = 0;
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          timeout: const Duration(milliseconds: 100),
          client: MockClient((r) async {
            if (r.url.path.endsWith('/login')) {
              return jsonResponse(sessionJson());
            }
            if (r.url.path.endsWith('/style')) return jsonResponse(styleJson());
            if (r.method != 'POST') return jsonResponse(rows);
            posts++;
            originalBody ??= r.body;
            if (r.body != originalBody) return jsonResponse({}, 409);
            if (rows.isEmpty) rows.add(savedAddress());
            if (posts == 1) return original.future;
            if (posts == 2) return retry.future;
            return jsonResponse(rows.single, 201);
          }),
        );
        final container = ProviderContainer(
          overrides: [
            remoteApiProvider.overrideWithValue(true),
            apiClientProvider.overrideWithValue(api),
            sessionTokensProvider.overrideWithValue(api.tokens),
          ],
        );
        addTearDown(() {
          container.dispose();
          api.close();
        });
        await container
            .read(accountProvider.notifier)
            .signIn('', 'an@example.com', 'password');
        final subscription = container.listen(
          accountDetailsProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await container.read(accountDetailsProvider.future);
        final controller = container.read(accountDetailsProvider.notifier);
        await expectLater(
          controller.saveAddress(draft, creationKey: key),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
        );
        final outcome = controller
            .saveAddress(draft, creationKey: key)
            .then<Object?>((_) => null, onError: (Object e) => e);
        await Future<void>.delayed(Duration.zero);
        expect(posts, 2);
        original.complete(jsonResponse(rows.single, 201));
        await Future<void>.delayed(Duration.zero);
        if (explicitRefresh) container.invalidate(accountDetailsProvider);
        await container.read(accountDetailsProvider.future);
        retry.complete(jsonResponse(rows.single, 201));
        final result = await outcome;
        if (explicitRefresh) {
          expect(result, isA<StateError>());
          await controller.saveAddress(draft, creationKey: key);
          expect(posts, 3);
        } else {
          expect(result, isNull);
        }
        expect(
          container
              .read(accountDetailsProvider)
              .requireValue
              .addresses
              .single
              .id,
          'address-1',
        );
      },
    );
  }
  for (final failure in ['lost response', 'follow-up read']) {
    test(
      'create retry preserves exact key and first default after $failure',
      () async {
        final rows = <Map<String, dynamic>>[];
        final bodies = <String>[], keys = <String?>[];
        var failRead = false;
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          client: MockClient((r) async {
            if (r.url.path.endsWith('/style')) return jsonResponse(styleJson());
            if (r.method == 'POST') {
              keys.add(r.headers['Idempotency-Key']);
              bodies.add(r.body);
              if (rows.isEmpty) rows.add(savedAddress());
              if (bodies.length == 1) {
                if (failure == 'lost response') return jsonResponse({}, 503);
                failRead = true;
              }
              return jsonResponse(rows.single, 201);
            }
            if (failRead) {
              failRead = false;
              return jsonResponse({}, 503);
            }
            return jsonResponse(rows);
          }),
        );
        addTearDown(api.close);
        final repo = RemoteAccountDetailsRepository(api);
        await expectLater(
          repo.saveAddress(draft, creationKey: key),
          throwsA(isA<ApiException>()),
        );
        final result = await repo.saveAddress(draft, creationKey: key);
        expect(result.addresses.single.id, 'address-1');
        expect(keys, [key, key]);
        expect(bodies[1], bodies[0]);
        expect(jsonDecode(bodies[1])['isDefault'], true);
      },
    );
  }
  test(
    'pending address draft cannot change payload under the same key',
    () async {
      var posts = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            return jsonResponse({}, 503);
          }
          return jsonResponse(r.url.path.endsWith('/style') ? styleJson() : []);
        }),
      );
      addTearDown(api.close);
      final repo = RemoteAccountDetailsRepository(api);
      await expectLater(
        repo.saveAddress(draft, creationKey: key),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        repo.saveAddress(
          const DeliveryAddress(
            id: '',
            label: 'Khác',
            recipient: 'An',
            phone: '0901234567',
            address: '12 Nguyễn Huệ',
          ),
          creationKey: key,
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'PENDING_ADDRESS'),
        ),
      );
      expect(posts, 1);
    },
  );
  test(
    'late create completion invalidates only its original session',
    () async {
      final late = Completer<http.Response>();
      var settled = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        timeout: const Duration(milliseconds: 15),
        client: MockClient(
          (r) async => r.method == 'POST'
              ? late.future
              : jsonResponse(r.url.path.endsWith('/style') ? styleJson() : []),
        ),
      );
      addTearDown(api.close);
      final repo = RemoteAccountDetailsRepository(
        api,
        onLateAddressCompletion: () => settled++,
      );
      await expectLater(
        repo.saveAddress(draft, creationKey: key),
        throwsA(isA<ApiException>()),
      );
      api.tokens.set(accessToken: 'new', refreshToken: 'new-refresh');
      late.complete(jsonResponse(savedAddress(), 201));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(settled, 0);
      await expectLater(
        repo.saveAddress(draft, creationKey: key),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
    },
  );
  testWidgets(
    'uncertain create freezes fields and retries one request then closes',
    (tester) async {
      final rows = <Map<String, dynamic>>[];
      final keys = <String?>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) return jsonResponse(sessionJson());
          if (r.url.path.endsWith('/style')) return jsonResponse(styleJson());
          if (r.method == 'POST') {
            keys.add(r.headers['Idempotency-Key']);
            if (rows.isEmpty) rows.add(savedAddress());
            return keys.length == 1
                ? jsonResponse({}, 503)
                : jsonResponse(rows.single, 201);
          }
          return jsonResponse(rows);
        }),
      );
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
          sessionTokensProvider.overrideWithValue(api.tokens),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      await container
          .read(accountProvider.notifier)
          .signIn('', 'an@example.com', 'password');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: AddressPage())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm địa chỉ'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final entry in [
        'Nhà',
        'An',
        '0901234567',
        '12 Nguyễn Huệ',
      ].asMap().entries) {
        await tester.enterText(fields.at(entry.key), entry.value);
      }
      await tester.ensureVisible(find.text('Lưu địa chỉ'));
      await tester.tap(find.text('Lưu địa chỉ'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TextField>(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(TextField),
              ),
            )
            .every((f) => f.readOnly),
        true,
      );
      expect(find.text('Thử lại yêu cầu này'), findsOneWidget);
      await tester.ensureVisible(find.text('Thử lại yêu cầu này'));
      await tester.tap(find.text('Thử lại yêu cầu này'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(keys.first, matches(RegExp(r'^[a-f0-9]{48}$')));
      expect(keys[1], keys[0]);
      expect(
        container.read(accountDetailsProvider).requireValue.addresses.single.id,
        'address-1',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
