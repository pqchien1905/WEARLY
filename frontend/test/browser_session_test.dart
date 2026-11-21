import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/network/browser_auth_recovery_store.dart';
import 'package:nep_storefront/data/remote_account.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'separate_sessions_test.dart' show loginJson;

Map<String, Object?> browserJson([String user = 'customer']) =>
    loginJson(user)..remove('refreshToken');

void main() {
  ApiClient client(
    Future<http.Response> Function(http.Request) handler, {
    String scope = 'customer',
    Duration timeout = const Duration(seconds: 15),
    BrowserAuthRecoveryStore? recovery,
  }) {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      browserScope: scope,
      timeout: timeout,
      browserRecovery: recovery,
      client: MockClient(handler),
    );
    addTearDown(api.close);
    return api;
  }

  test('browser login keeps only access and identity in memory', () async {
    final api = client((r) async {
      expect(r.url.path, '/api/v1/auth/browser/customer/login');
      expect(r.headers['X-Wearly-Browser'], '1');
      expect(r.headers['Authorization'], isNull);
      return jsonResponse(browserJson());
    });
    final user = await RemoteAccountRepository(api).signIn(
      name: '',
      email: 'customer@example.com',
      password: 'valid-password',
    );
    expect(user.id, 'customer-user');
    expect(api.tokens.userId, user.id);
    expect(api.tokens.refreshToken, isNull);
    expect(api.tokens.accessToken, 'customer-access');
  });

  test(
    'parallel browser 401 responses share renewal and preserve mutation payload',
    () async {
      var renewals = 0;
      final mutations = <http.Request>[];
      final api = client((r) async {
        if (r.url.path.endsWith('/refresh')) {
          renewals++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return jsonResponse(browserJson()..['accessToken'] = 'new-access');
        }
        mutations.add(r);
        return jsonResponse(
          {},
          r.headers['Authorization'] == 'Bearer old' ? 401 : 200,
        );
      });
      api.tokens.set(accessToken: 'old', userId: 'customer-user');
      await Future.wait(
        List.generate(
          2,
          (_) => api.request(
            'POST',
            'orders',
            body: {'quantity': 2},
            headers: {'Idempotency-Key': 'attempt'},
          ),
        ),
      );
      expect(renewals, 1);
      expect(mutations, hasLength(4));
      expect(mutations.map((r) => r.body).toSet(), hasLength(1));
      expect(
        mutations.every((r) => r.headers['Idempotency-Key'] == 'attempt'),
        isTrue,
      );
      expect(api.tokens.refreshToken, isNull);
    },
  );

  test('a new cookie owner cannot replay the old account mutation', () async {
    var writes = 0;
    final api = client((r) async {
      if (r.url.path.endsWith('/refresh')) {
        return jsonResponse(browserJson('other'));
      }
      writes++;
      return jsonResponse({}, 401);
    });
    api.tokens.set(accessToken: 'old', userId: 'customer-user');
    await expectLater(
      api.request('POST', 'orders', body: {'addressId': 'old-user-address'}),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    expect(writes, 1);
    expect(api.tokens.accessToken, isNull);
  });

  test(
    'transient renewal failures retain identity for a safe later retry',
    () async {
      var attempts = 0;
      final api = client((r) async {
        if (r.url.path.endsWith('/refresh')) {
          attempts++;
          return attempts == 1
              ? jsonResponse({}, 503)
              : jsonResponse(browserJson());
        }
        return jsonResponse(
          {},
          r.headers['Authorization'] == 'Bearer old' ? 401 : 200,
        );
      });
      api.tokens.set(accessToken: 'old', userId: 'customer-user');
      await expectLater(api.get('orders'), throwsA(isA<ApiException>()));
      expect(api.tokens.userId, 'customer-user');
      expect(api.tokens.accessToken, 'old');
      await api.get('orders');
      expect(attempts, 2);
    },
  );

  test('an invalid browser session clears local identity', () async {
    final api = client((_) async => jsonResponse({}, 401));
    api.tokens.set(accessToken: 'old', userId: 'customer-user');
    await expectLater(api.get('orders'), throwsA(isA<ApiException>()));
    expect(api.tokens.accessToken, isNull);
    expect(api.tokens.userId, isNull);
  });

  test('late bootstrap cannot replace a newer sign-in', () async {
    final response = Completer<http.Response>(), started = Completer<void>();
    final api = client((r) async {
      if (r.url.path.endsWith('/refresh')) {
        started.complete();
        return response.future;
      }
      return jsonResponse(browserJson('other'));
    });
    final repo = RemoteAccountRepository(api);
    final restoring = repo.restore();
    final rejected = expectLater(restoring, throwsA(isA<ApiException>()));
    await started.future;
    final signingIn = repo.signIn(
      name: '',
      email: 'other@example.com',
      password: 'valid-password',
    );
    response.complete(jsonResponse(browserJson()));
    await rejected;
    await signingIn;
    expect(api.tokens.userId, 'other-user');
  });

  test(
    'timed-out login completes before revocation and never resurrects after logout',
    () async {
      final response = Completer<http.Response>(), started = Completer<void>();
      final calls = <String>[];
      final api = client((r) async {
        calls.add(r.url.path.split('/').last);
        if (r.url.path.endsWith('/login')) {
          started.complete();
          return response.future;
        }
        return jsonResponse({'loggedOut': true});
      }, timeout: const Duration(milliseconds: 25));
      final repo = RemoteAccountRepository(api);
      final pending = repo.signIn(
        name: '',
        email: 'customer@example.com',
        password: 'valid-password',
      );
      await started.future;
      await expectLater(
        pending,
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      final loggingOut = repo.signOut();
      expect(calls, ['login']);
      response.complete(jsonResponse(browserJson()));
      await loggingOut;
      expect(calls.first, 'login');
      expect(calls.skip(1), everyElement('logout'));
      expect(calls.length, greaterThanOrEqualTo(2));
      expect(api.tokens.accessToken, isNull);
    },
  );

  test(
    'discarded login is revoked before a queued newer login is sent',
    () async {
      final first = Completer<http.Response>(), started = Completer<void>();
      final actions = <String>[];
      var logins = 0;
      final api = client((r) async {
        final action = r.url.path.split('/').last;
        actions.add(action);
        if (action == 'logout') return jsonResponse({'loggedOut': true});
        if (++logins == 1) {
          started.complete();
          return first.future;
        }
        return jsonResponse(browserJson('other'));
      });
      final repo = RemoteAccountRepository(api);
      final one = repo.signIn(
        name: '',
        email: 'customer@example.com',
        password: 'valid-password',
      );
      final rejected = expectLater(one, throwsA(isA<ApiException>()));
      await started.future;
      final two = repo.signIn(
        name: '',
        email: 'other@example.com',
        password: 'valid-password',
      );
      first.complete(jsonResponse(browserJson()));
      await rejected;
      await two;
      expect(actions, ['login', 'logout', 'login']);
      expect(api.tokens.userId, 'other-user');
    },
  );

  test('browser logout failure retains a visible retryable account', () async {
    var failed = true;
    final api = client(
      (r) async => r.url.path.endsWith('/logout')
          ? jsonResponse({}, failed ? 503 : 200)
          : jsonResponse(browserJson()),
    );
    final container = ProviderContainer(
      overrides: [
        remoteApiProvider.overrideWithValue(true),
        apiClientProvider.overrideWithValue(api),
        sessionTokensProvider.overrideWithValue(api.tokens),
      ],
    );
    addTearDown(container.dispose);
    final account = container.read(accountProvider.notifier);
    await account.restore();
    await expectLater(account.signOut(), throwsA(isA<ApiException>()));
    expect(container.read(accountProvider)?.id, 'customer-user');
    expect(api.tokens.accessToken, isNotNull);
    failed = false;
    await account.signOut();
    expect(container.read(accountProvider), isNull);
    expect(api.tokens.accessToken, isNull);
  });

  for (final transportFailure in [false, true]) {
    test('abandoned login cleanup remains retryable after '
        '${transportFailure ? "transport" : "HTTP"} failure', () async {
      final response = Completer<http.Response>();
      final cleanup = Completer<void>();
      var failed = true, refreshes = 0;
      final api = client((r) async {
        if (r.url.path.endsWith('/login')) return response.future;
        if (r.url.path.endsWith('/logout')) {
          if (!cleanup.isCompleted) cleanup.complete();
          if (failed && transportFailure) throw http.ClientException('offline');
          return jsonResponse({}, failed ? 503 : 200);
        }
        refreshes++;
        return failed ? jsonResponse(browserJson()) : jsonResponse({}, 401);
      }, timeout: const Duration(milliseconds: 25));
      final repo = RemoteAccountRepository(api);
      await expectLater(
        repo.signIn(
          name: '',
          email: 'customer@example.com',
          password: 'valid-password',
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      response.complete(jsonResponse(browserJson()));
      await cleanup.future;
      await expectLater(repo.restore(), throwsA(isA<ApiException>()));
      expect(refreshes, 0, reason: 'An abandoned cookie must not be restored');
      failed = false;
      expect(await repo.restore(), isNull);
      expect(refreshes, 1);
      expect(api.tokens.accessToken, isNull);
    });
  }

  testWidgets(
    'reload blocks abandoned-session restore and offers cleanup retry',
    (tester) async {
      final recovery = MemoryBrowserAuthRecoveryStore()
        ..mark('unfinished-login');
      var failed = true, refreshes = 0, cleanups = 0;
      final customer = client((r) async {
        if (r.url.path.endsWith('/logout')) {
          cleanups++;
          return jsonResponse({}, failed ? 503 : 200);
        }
        if (r.url.path.endsWith('/refresh')) refreshes++;
        return jsonResponse({}, 401);
      }, recovery: recovery);
      final staff = client((_) async => jsonResponse({}, 401), scope: 'admin');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            browserSessionsEnabledProvider.overrideWithValue(true),
            remoteApiProvider.overrideWithValue(true),
            apiClientProvider.overrideWithValue(customer),
            sessionTokensProvider.overrideWithValue(customer.tokens),
            adminApiClientProvider.overrideWithValue(staff),
            adminSessionTokensProvider.overrideWithValue(staff.tokens),
          ],
          child: NepApp(router: createRouter(initialLocation: '/account')),
        ),
      );
      await tester.pumpAndSettle();
      expect(cleanups, greaterThan(0));
      final attemptsBeforeRetry = cleanups;
      expect(refreshes, 0);
      expect(recovery.read(), 'unfinished-login');
      expect(find.text('Chưa khôi phục được phiên đăng nhập'), findsOneWidget);
      failed = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Thử khôi phục lại'));
      await tester.pumpAndSettle();
      expect(cleanups, attemptsBeforeRetry + 1);
      expect(refreshes, 1);
      expect(recovery.read(), isNull);
      expect(find.text('Đăng nhập để tiếp tục'), findsOneWidget);
      expect(customer.tokens.accessToken, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'startup waits for both identities before mounting a private route',
    (tester) async {
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/account/orders';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final customerResponse = Completer<http.Response>(),
          staffResponse = Completer<http.Response>();
      var reads = 0;
      final customer = client((r) async {
        if (r.url.path.endsWith('/refresh')) return customerResponse.future;
        if (r.url.path.endsWith('/orders')) {
          reads++;
          return jsonResponse({
            'items': [],
            'total': 0,
            'page': 1,
            'limit': 20,
          });
        }
        return jsonResponse({});
      });
      final staff = client((_) => staffResponse.future, scope: 'admin');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            browserSessionsEnabledProvider.overrideWithValue(true),
            remoteApiProvider.overrideWithValue(true),
            apiClientProvider.overrideWithValue(customer),
            sessionTokensProvider.overrideWithValue(customer.tokens),
            adminApiClientProvider.overrideWithValue(staff),
            adminSessionTokensProvider.overrideWithValue(staff.tokens),
          ],
          child: NepApp(
            router: createRouter(initialLocation: '/account/orders'),
          ),
        ),
      );
      await tester.pump();
      expect(reads, 0);
      expect(find.text('Đăng nhập để tiếp tục'), findsNothing);
      customerResponse.complete(jsonResponse(browserJson()));
      await tester.pump();
      expect(reads, 0);
      staffResponse.complete(jsonResponse({}, 401));
      await tester.pumpAndSettle();
      expect(reads, greaterThan(0));
      expect(find.text('Đăng nhập để tiếp tục'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'startup network failure offers restore retry before private reads',
    (tester) async {
      var failed = true, reads = 0;
      final customer = client((r) async {
        if (r.url.path.endsWith('/refresh')) {
          return failed ? jsonResponse({}, 503) : jsonResponse(browserJson());
        }
        if (r.url.path.endsWith('/orders')) {
          reads++;
          return jsonResponse({
            'items': [],
            'total': 0,
            'page': 1,
            'limit': 20,
          });
        }
        return jsonResponse({});
      });
      final staff = client((_) async => jsonResponse({}, 401), scope: 'admin');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            browserSessionsEnabledProvider.overrideWithValue(true),
            remoteApiProvider.overrideWithValue(true),
            apiClientProvider.overrideWithValue(customer),
            sessionTokensProvider.overrideWithValue(customer.tokens),
            adminApiClientProvider.overrideWithValue(staff),
            adminSessionTokensProvider.overrideWithValue(staff.tokens),
          ],
          child: NepApp(
            router: createRouter(initialLocation: '/account/orders'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.text('Chưa khôi phục được phiên đăng nhập'), findsOneWidget);
      failed = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Thử khôi phục lại'));
      await tester.pumpAndSettle();
      expect(reads, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
}
