import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_account_details.dart';
import 'package:nep_storefront/domain/account_details.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'remote_style_preferences_test.dart' show styleJson;

void main() {
  test(
    'style failure after address creation does not lose confirmed address',
    () async {
      final rows = <Map<String, Object?>>[];
      var writes = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/style')) {
            return rows.isEmpty
                ? jsonResponse(styleJson())
                : jsonResponse({}, 503);
          }
          if (r.method == 'POST') {
            writes++;
            rows.add({
              'id': 'confirmed-address',
              ...jsonDecode(r.body) as Map<String, dynamic>,
            });
            return jsonResponse(rows.single, 201);
          }
          return jsonResponse(rows);
        }),
      );
      addTearDown(api.close);
      final result = await RemoteAccountDetailsRepository(api).saveAddress(
        const DeliveryAddress(
          id: '',
          label: 'Nhà',
          recipient: 'An',
          phone: '0901234567',
          address: '12 Nguyễn Huệ',
        ),
      );
      expect(result.addresses.single.id, 'confirmed-address');
      expect(result.defaultAddressId, 'confirmed-address');
      expect(writes, 1);
    },
  );
  test(
    'address create, update and default/delete reflect server UUIDs and Vietnamese data',
    () async {
      final rows = <Map<String, Object?>>[];
      var nextId = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/style')) return jsonResponse(styleJson());
          if (r.method == 'GET') return jsonResponse(rows);
          if (r.method == 'DELETE') {
            rows.removeWhere((a) => a['id'] == r.url.path.split('/').last);
            if (rows.isNotEmpty && !rows.any((a) => a['isDefault'] == true)) {
              rows.first['isDefault'] = true;
            }
            return jsonResponse({'deleted': true});
          }
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          if (body['isDefault'] == true) {
            for (final row in rows) {
              row['isDefault'] = false;
            }
          }
          if (r.method == 'POST') {
            rows.add({
              'id': 'address-${++nextId}',
              'isDefault': false,
              ...body,
            });
            return jsonResponse(rows.last, 201);
          }
          final row = rows.firstWhere(
            (a) => a['id'] == r.url.path.split('/').last,
          );
          row.addAll(body);
          return jsonResponse(row);
        }),
      );
      final repo = RemoteAccountDetailsRepository(api);
      final first = await repo.saveAddress(
        const DeliveryAddress(
          id: '',
          label: 'Nhà',
          recipient: 'Nguyễn An',
          phone: '0901234567',
          address: '12 Nguyễn Huệ, TP.HCM',
        ),
      );
      expect(first.defaultAddressId, 'address-1');
      expect(first.addresses.single.recipient, 'Nguyễn An');
      await repo.saveAddress(
        const DeliveryAddress(
          id: '',
          label: 'Công ty',
          recipient: 'An',
          phone: '0901234567',
          address: '22 Lê Lợi, TP.HCM',
        ),
      );
      expect(
        (await repo.setDefault('address-2')).defaultAddressId,
        'address-2',
      );
      final updated = await repo.saveAddress(
        const DeliveryAddress(
          id: 'address-2',
          label: 'Văn phòng',
          recipient: 'An',
          phone: '0901234567',
          address: '24 Lê Lợi, TP.HCM',
        ),
      );
      expect(
        updated.addresses.firstWhere((a) => a.id == 'address-2').address,
        '24 Lê Lợi, TP.HCM',
      );
      final removed = await repo.deleteAddress('address-2');
      expect(removed.addresses.single.id, 'address-1');
      expect(removed.defaultAddressId, 'address-1');
      api.close();
    },
  );
  test(
    'an address repository from the old identity cannot send a new-user request',
    () async {
      var requests = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((_) async {
          requests++;
          return jsonResponse([]);
        }),
      );
      api.tokens.set(accessToken: 'a', refreshToken: 'ra');
      final repo = RemoteAccountDetailsRepository(api);
      api.tokens.set(accessToken: 'b', refreshToken: 'rb');
      await expectLater(repo.read(), throwsA(isA<ApiException>()));
      expect(requests, 0);
      api.close();
    },
  );
  test('a rejected address mutation is not reported as saved', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(
        (r) async => r.method == 'GET'
            ? jsonResponse(r.url.path.endsWith('/style') ? styleJson() : [])
            : jsonResponse({}, 400),
      ),
    );
    await expectLater(
      RemoteAccountDetailsRepository(api).saveAddress(
        const DeliveryAddress(
          id: '',
          label: 'Nhà',
          recipient: 'An',
          phone: 'invalid',
          address: '12 Nguyễn Huệ',
        ),
      ),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
    );
    api.close();
  });
  test('rejected style persistence fails explicitly', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((_) async => jsonResponse({}, 400)),
    );
    await expectLater(
      RemoteAccountDetailsRepository(api).saveStyle(const StylePreferences()),
      throwsA(isA<ApiException>()),
    );
    api.close();
  });
}
