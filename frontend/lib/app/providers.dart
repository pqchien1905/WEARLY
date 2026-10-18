import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/catalog.dart';
import '../data/mock_catalog.dart';
import '../data/remote_catalog.dart';
import '../data/fixtures/catalog_fixture.dart' as fixture;
import 'config.dart';
import 'api_providers.dart';

final catalogCategoriesProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  ref.watch(catalogRevisionProvider);
  if (!ref.watch(remoteApiProvider) && !BrandConfig.useRemoteCatalog) {
    return fixture.categories;
  }
  final data = await ref
      .watch(apiClientProvider)
      .request('GET', 'categories', authenticated: false);
  return {
    '': 'Tất cả',
    for (final row in data as List)
      (row as Map)['slug'] as String: row['name'] as String,
  };
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  if (!ref.watch(remoteApiProvider) && !BrandConfig.useRemoteCatalog) {
    return MockProductRepository();
  }
  return RemoteProductRepository(ref.watch(apiClientProvider));
});
final catalogColorsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(catalogRevisionProvider);
  return ref.watch(productRepositoryProvider).availableColors();
});
final allProductsProvider = FutureProvider<ProductPage>((ref) {
  ref.watch(catalogRevisionProvider);
  return ref
      .watch(productRepositoryProvider)
      .list(const ProductQuery(limit: 100));
});
final catalogRevisionProvider = NotifierProvider<CatalogRevision, int>(
  CatalogRevision.new,
);

class CatalogRevision extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() {
    if (ref.mounted) state++;
  }
}

final catalogProvider = FutureProvider.family<ProductPage, String>((
  ref,
  query,
) {
  ref.watch(catalogRevisionProvider);
  return ref
      .watch(productRepositoryProvider)
      .list(ProductQuery.fromParams(Uri.splitQueryString(query)));
});
final productProvider = FutureProvider.family<Product?, String>((ref, slug) {
  ref.watch(catalogRevisionProvider);
  return ref.watch(productRepositoryProvider).bySlug(slug);
});
final wishlistProvider = NotifierProvider<Wishlist, Set<String>>(Wishlist.new);

class Wishlist extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};
  void toggle(String id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
  void clear() => state = {};
}
