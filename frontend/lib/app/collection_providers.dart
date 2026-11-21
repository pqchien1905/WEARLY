import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote_collections.dart';
import 'api_providers.dart';
import 'providers.dart';
export '../data/remote_collections.dart';

final collectionsRepositoryProvider = Provider(
  (ref) => CollectionsRepository(ref.watch(apiClientProvider)),
);
final collectionsProvider = FutureProvider.family<CollectionListing, String>((
  ref,
  query,
) {
  ref.watch(catalogRevisionProvider);
  return ref.watch(collectionsRepositoryProvider).list(query);
});
final collectionDetailProvider = FutureProvider.autoDispose
    .family<CollectionDetail?, String>((ref, location) {
      ref.watch(catalogRevisionProvider);
      return ref.watch(collectionsRepositoryProvider).detail(location);
    });
