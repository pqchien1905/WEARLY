import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/auth_routes.dart';

void main() {
  test('return paths stay in their own login area', () {
    expect(
      loginDestination('/admin/orders/123?page=2', admin: true),
      '/admin/orders/123?page=2',
    );
    expect(
      loginDestination('/checkout?step=address'),
      '/checkout?step=address',
    );
    for (final next in [
      null,
      'https://evil.test/admin',
      '//evil.test/admin',
      '/\\evil.test',
      '/admin/../login',
      '/%61dmin',
      '/admin/%2e%2e/login',
      '/admin/login',
      '/admin/login?next=/admin',
      '/login',
    ]) {
      expect(loginDestination(next, admin: true), '/admin', reason: '$next');
    }
    for (final next in [
      '/admin',
      '/admin/orders/123',
      '/%61dmin',
      '/shop/../admin',
      '//evil.test',
      '/login',
      '/register',
      '/forgot-password',
    ]) {
      expect(loginDestination(next), '/account', reason: next);
    }
  });
}
