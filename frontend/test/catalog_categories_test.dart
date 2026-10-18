import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'remote_session_test.dart' show jsonResponse;

void main() {
  test(
    'public categories use API, omit tokens, refresh names and preserve empty/error',
    () async {
      var name = 'Mùa thu', reads = 0, status = 200;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.url.path, '/api/v1/categories');
          expect(r.headers['authorization'], isNull);
          reads++;
          return jsonResponse(
            name.isEmpty
                ? []
                : [
                    {'slug': 'mua-thu', 'name': name},
                  ],
            status,
          );
        }),
      );
      api.tokens.set(accessToken: 'private', refreshToken: 'private');
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      expect(await container.read(catalogCategoriesProvider.future), {
        '': 'Tất cả',
        'mua-thu': 'Mùa thu',
      });
      name = 'Thu đông';
      container.read(catalogRevisionProvider.notifier).refresh();
      expect(
        (await container.read(catalogCategoriesProvider.future))['mua-thu'],
        name,
      );
      name = '';
      container.invalidate(catalogCategoriesProvider);
      expect(await container.read(catalogCategoriesProvider.future), {
        '': 'Tất cả',
      });
      status = 503;
      container.invalidate(catalogCategoriesProvider);
      await expectLater(
        container.read(catalogCategoriesProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(reads, 4);
    },
  );
}
