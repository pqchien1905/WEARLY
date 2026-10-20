import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/core/network/catalog_image.dart';
import 'package:nep_storefront/core/network/session_tokens.dart';
import 'package:nep_storefront/data/remote_admin.dart';
import 'remote_session_test.dart' show jsonResponse;

void main() {
  const key = '11111111-1111-4111-8111-111111111111';
  final bytes = Uint8List.fromList([255, 216, 255, 10]);
  test(
    'multipart refresh retains bytes and key with admin credentials',
    () async {
      var uploads = 0;
      final tokens = SessionTokens()
        ..set(accessToken: 'old-admin', refreshToken: 'refresh');
      final api = ApiClient(
        baseUrl: 'https://shop.test/custom/api/v1',
        tokens: tokens,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/auth/refresh')) {
            return jsonResponse({
              'accessToken': 'new-admin',
              'refreshToken': 'rotated',
            });
          }
          uploads++;
          expect(r.url.path, '/custom/api/v1/admin/products/p/images');
          expect(r.headers['idempotency-key'], key);
          expect(
            r.headers['authorization'],
            uploads == 1 ? 'Bearer old-admin' : 'Bearer new-admin',
          );
          expect(
            r.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          final body = latin1.decode(r.bodyBytes);
          expect(body, contains('name="alt"'));
          expect(body, contains('image/jpeg'));
          expect(body, contains(latin1.decode(bytes)));
          return uploads == 1
              ? jsonResponse({}, 401)
              : jsonResponse({'id': 'asset'});
        }),
      );
      final result = await AdminRepository(api).uploadImage(
        'p',
        bytes: bytes,
        mimeType: 'image/jpeg',
        alt: 'Áo',
        key: key,
      );
      expect(result['id'], 'asset');
      expect(uploads, 2);
      api.close();
    },
  );
  test('uncertain multipart writes are never automatically retried', () async {
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://shop.test/api/v1',
      client: MockClient((r) async {
        calls++;
        throw http.ClientException('Lost response');
      }),
    );
    await expectLater(
      AdminRepository(api).uploadImage(
        'p',
        bytes: bytes,
        mimeType: 'image/jpeg',
        alt: 'Áo',
        key: key,
      ),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'CONNECTION_ERROR'),
      ),
    );
    expect(calls, 1);
    api.close();
  });
  test(
    'late multipart response cannot cross an administrator session change',
    () async {
      final response = Completer<http.Response>();
      final tokens = SessionTokens()
        ..set(accessToken: 'old', refreshToken: 'old');
      final api = ApiClient(
        baseUrl: 'https://shop.test/api/v1',
        tokens: tokens,
        client: MockClient((r) => response.future),
      );
      final pending = AdminRepository(api).uploadImage(
        'p',
        bytes: bytes,
        mimeType: 'image/jpeg',
        alt: 'Áo',
        key: key,
      );
      final assertion = expectLater(
        pending,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      tokens.set(accessToken: 'new', refreshToken: 'new');
      response.complete(jsonResponse({'id': 'asset'}));
      await assertion;
      expect(tokens.accessToken, 'new');
      api.close();
    },
  );
  test(
    'only exact managed references resolve beneath configured API prefix',
    () {
      expect(
        catalogImageUrl(
          'https://shop.test/custom/api/v1',
          'catalog/images/$key',
        ),
        'https://shop.test/custom/api/v1/catalog/images/$key',
      );
      for (final invalid in [
        'catalog/images/../auth',
        '//evil.test/image',
        'assets/images/a.jpg',
        'catalog/images/$key?token=secret',
        'catalog/images/$key/extra',
      ]) {
        expect(catalogImageUrl('https://shop.test/api/v1', invalid), isNull);
      }
    },
  );
}
