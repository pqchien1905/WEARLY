import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote_reviews.dart';
import 'account_state.dart';
import 'api_providers.dart';
export '../data/remote_reviews.dart';

final reviewRevisionProvider =
    NotifierProvider<ReviewRevision, Map<String, int>>(ReviewRevision.new);

class ReviewRevision extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => {};
  void refresh(String id) {
    if (ref.mounted) state = {...state, id: (state[id] ?? 0) + 1};
  }
}

typedef ReviewPageKey = ({String productId, int page});
final publicReviewsProvider = FutureProvider.autoDispose
    .family<ReviewPage, ReviewPageKey>((ref, key) {
      ref.watch(reviewRevisionProvider.select((state) => state[key.productId]));
      return PublicReviewRepository(
        ref.watch(apiClientProvider),
      ).list(key.productId, key.page);
    });
final ownerReviewRepositoryProvider =
    Provider.autoDispose<OwnerReviewRepository?>((ref) {
      if (!ref.watch(remoteApiProvider) || ref.watch(accountProvider) == null) {
        return null;
      }
      final revision = ref.read(reviewRevisionProvider.notifier);
      final repo = OwnerReviewRepository(
        ref.watch(apiClientProvider),
        onSettled: revision.refresh,
      );
      ref.onDispose(repo.dispose);
      return repo;
    });
final myReviewProvider = FutureProvider.autoDispose.family<MyReview?, String>((
  ref,
  id,
) {
  ref.watch(reviewRevisionProvider.select((state) => state[id]));
  return ref.watch(ownerReviewRepositoryProvider)?.mine(id);
});

typedef OwnedReviewKey = ({int page, String query, int? rating});
final ownedReviewsProvider = FutureProvider.autoDispose
    .family<OwnedReviewPage?, OwnedReviewKey>((ref, key) {
      ref.watch(reviewRevisionProvider);
      return ref
          .watch(ownerReviewRepositoryProvider)
          ?.history(key.page, query: key.query, rating: key.rating);
    }, retry: (_, _) => null);
