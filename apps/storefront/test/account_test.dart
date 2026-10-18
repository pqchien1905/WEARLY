import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/data/mock_account.dart';

void main() {
  test(
    'reset invalidates an in-flight sign in even after provider rebuild',
    () async {
      final container = ProviderContainer(
        overrides: [
          accountRepositoryProvider.overrideWithValue(
            MockAccountRepository(latency: const Duration(milliseconds: 10)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final pending = container
          .read(accountProvider.notifier)
          .signIn('Old profile', 'old@example.com', 'password-demo');
      container.invalidate(accountProvider);
      expect(container.read(accountProvider), isNull);
      await pending;
      expect(container.read(accountProvider), isNull);
    },
  );
  test(
    'mock auth validates credentials and can simulate network failure',
    () async {
      final repo = MockAccountRepository(latency: Duration.zero);
      await expectLater(
        repo.signIn(name: 'Demo', email: 'invalid', password: 'password-demo'),
        throwsArgumentError,
      );
      repo.offline = true;
      await expectLater(
        repo.signIn(
          name: 'Demo',
          email: 'demo@example.com',
          password: 'password-demo',
        ),
        throwsStateError,
      );
      repo.offline = false;
      expect(
        (await repo.signIn(
          name: 'Demo',
          email: 'demo@example.com',
          password: 'password-demo',
        )).email,
        'demo@example.com',
      );
    },
  );
  test(
    'sign out prevents a pending sign in from restoring the session',
    () async {
      final container = ProviderContainer(
        overrides: [
          accountRepositoryProvider.overrideWithValue(
            MockAccountRepository(latency: const Duration(milliseconds: 10)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(accountProvider.notifier);
      final pending = controller.signIn(
        'Demo',
        'demo@example.com',
        'password-demo',
      );
      await controller.signOut();
      await pending;
      expect(container.read(accountProvider), isNull);
    },
  );
  testWidgets('login failure stays actionable and retry opens profile', (
    tester,
  ) async {
    final repo = MockAccountRepository(
      latency: const Duration(milliseconds: 100),
    )..offline = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(repo)],
        child: NepApp(router: createRouter(initialLocation: '/login')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'demo@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mật khẩu demo'),
      'password-demo',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Đăng nhập demo'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập demo'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Không kết nối được tài khoản demo'),
      findsOneWidget,
    );
    repo.offline = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập demo'));
    await tester.pumpAndSettle();
    expect(find.text('Chào Khách Wearly.'), findsOneWidget);
  });
}
