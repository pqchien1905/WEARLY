import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/core/network/local_browser_origin.dart';

void main() {
  test('loopback redirect preserves port, base path, query and deep link', () {
    final destination = localBrowserRedirect(
      Uri.parse(
        'http://127.0.0.1:8080/store/?lang=vi#/login?next=%2Faccount%2Forders',
      ),
      Uri.parse('http://localhost:3000/api/v1'),
    );
    expect(
      destination.toString(),
      'http://localhost:8080/store/?lang=vi#/login?next=%2Faccount%2Forders',
    );
    expect(
      localBrowserRedirect(destination!, Uri.parse('http://localhost:3000')),
      isNull,
      reason: 'A canonical page must not redirect again',
    );
  });

  test('uses the configured API host, including an IP-based local setup', () {
    expect(
      localBrowserRedirect(
        Uri.parse('http://localhost:4183/#/reset-password?token=fixture'),
        Uri.parse('http://127.0.0.1:3100/api/v1'),
      ).toString(),
      'http://127.0.0.1:4183/#/reset-password?token=fixture',
    );
    expect(
      localBrowserRedirect(
        Uri.parse('http://[::1]:8080/#/admin'),
        Uri.parse('http://localhost:3000/api/v1'),
      ).toString(),
      'http://localhost:8080/#/admin',
    );
  });

  test(
    'does not redirect matching hosts, remote sites, HTTPS or credentials',
    () {
      for (final (page, api) in [
        ('http://localhost:8080', 'http://localhost:3000'),
        ('http://127.0.0.1:4183', 'http://127.0.0.1:3100'),
        ('https://shop.example.com', 'https://api.example.com'),
        ('http://shop.example.com', 'http://localhost:3000'),
        ('http://localhost:8080', 'http://api.example.com'),
        ('https://127.0.0.1:8080', 'http://localhost:3000'),
        ('http://127.0.0.1:8080', 'https://localhost:3000'),
        ('http://127.0.0.1:8080', 'http://user:password@localhost:3000'),
        ('file:///app/index.html', 'http://localhost:3000'),
      ]) {
        expect(localBrowserRedirect(Uri.parse(page), Uri.parse(api)), isNull);
      }
    },
  );
}
