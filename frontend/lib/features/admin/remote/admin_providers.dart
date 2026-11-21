import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/account_state.dart';
import '../../../domain/staff_permissions.dart';
export '../../../domain/staff_permissions.dart';
import '../../../app/api_providers.dart';
import '../../../app/refund_providers.dart';
import '../../../core/network/api_client.dart';
import '../../../data/remote_admin.dart';
export '../../../data/remote_admin.dart';

final adminRepositoryProvider = Provider.autoDispose<AdminRepository>((ref) {
  final user = ref.watch(
    adminAccountProvider.select((u) => (u?.id, u?.email, u?.role)),
  );
  if (!ref.watch(remoteApiProvider) || !isStaff(user.$3)) {
    throw const ApiException(
      'FORBIDDEN',
      'Tài khoản chưa có quyền quản trị.',
      status: 403,
    );
  }
  final repository = AdminRepository(ref.watch(adminApiClientProvider));
  ref.onDispose(repository.dispose);
  return repository;
});
final staffRoleProvider = Provider<String?>(
  (ref) => ref.watch(adminAccountProvider.select((u) => u?.role)),
);
typedef AdminListKey = ({String kind, int page});
typedef AdminSearchKey = ({String kind, int page, String query, String status});
final adminSearchProvider = FutureProvider.autoDispose
    .family<AdminPage, AdminSearchKey>(
      (ref, key) => ref
          .watch(adminRepositoryProvider)
          .list(key.kind, key.page, query: key.query, status: key.status),
    );
typedef AdminDetailKey = ({String kind, String id});
final adminOrdersProvider = FutureProvider.autoDispose
    .family<AdminOrderPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .orders(Uri.splitQueryString(query)),
    );
final adminListProvider = FutureProvider.autoDispose
    .family<AdminPage, AdminListKey>(
      (ref, key) => ref.watch(adminRepositoryProvider).list(key.kind, key.page),
    );
final adminDetailProvider = FutureProvider.autoDispose
    .family<AdminRecord, AdminDetailKey>(
      (ref, key) => ref.watch(adminRepositoryProvider).detail(key.kind, key.id),
    );
final adminCustomersProvider = FutureProvider.autoDispose
    .family<AdminPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .customers(Uri.splitQueryString(query)),
    );
final adminCustomerSummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).customerSummary(),
);
final adminProductsProvider = FutureProvider.autoDispose
    .family<AdminPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .products(Uri.splitQueryString(query)),
    );
final adminProductSummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).productSummary(),
);
final adminInventoryProvider = FutureProvider.autoDispose
    .family<AdminInventoryPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .inventory(Uri.splitQueryString(query)),
    );
final adminInventorySummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).inventorySummary(),
);
final adminInventoryHistoryProvider = FutureProvider.autoDispose
    .family<AdminInventoryPage, ({String id, String query})>(
      (ref, key) => ref
          .watch(adminRepositoryProvider)
          .inventoryHistory(key.id, Uri.splitQueryString(key.query)),
    );
final adminSummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).summary(),
);
final adminReferencesProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).references(),
);
final adminCategoriesProvider = FutureProvider.autoDispose
    .family<AdminPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .categories(Uri.splitQueryString(query)),
    );
final adminCategorySummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).categorySummary(),
);
final adminBrandsProvider = FutureProvider.autoDispose
    .family<AdminPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .brands(Uri.splitQueryString(query)),
    );
final adminBrandSummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).brandSummary(),
);
final adminCollectionsProvider = FutureProvider.autoDispose
    .family<AdminPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .collections(Uri.splitQueryString(query)),
    );
final adminCollectionSummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).collectionSummary(),
);
final adminCollectionStylesProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).collectionStyles(),
);
final adminCollectionCoversProvider = FutureProvider.autoDispose
    .family<AdminPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .collectionCovers(Uri.splitQueryString(query)),
    );
final adminContentHistoryProvider = FutureProvider.autoDispose
    .family<AdminPage, int>(
      (ref, page) => ref.watch(adminRepositoryProvider).contentHistory(page),
    );
final adminContentProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).content(),
);

final adminPromotionsProvider = FutureProvider.autoDispose
    .family<AdminPage, String>(
      (ref, query) => ref
          .watch(adminRepositoryProvider)
          .promotions(Uri.splitQueryString(query)),
    );
final adminPromotionSummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).promotionSummary(),
);
final adminPromotionHistoryProvider = FutureProvider.autoDispose
    .family<AdminPage, ({String id, int page})>(
      (ref, key) =>
          ref.watch(adminRepositoryProvider).promotionHistory(key.id, key.page),
    );
void refreshAdmin(WidgetRef ref) {
  ref.invalidate(adminPromotionsProvider);
  ref.invalidate(adminPromotionSummaryProvider);
  ref.invalidate(adminPromotionHistoryProvider);
  ref.invalidate(adminCollectionsProvider);
  ref.invalidate(adminCollectionSummaryProvider);
  ref.invalidate(adminCollectionStylesProvider);
  ref.invalidate(adminCollectionCoversProvider);
  ref.invalidate(adminBrandsProvider);
  ref.invalidate(adminBrandSummaryProvider);
  ref.invalidate(adminCategoriesProvider);
  ref.invalidate(adminCategorySummaryProvider);
  ref.invalidate(adminInventoryProvider);
  ref.invalidate(adminInventorySummaryProvider);
  ref.invalidate(adminInventoryHistoryProvider);
  ref.invalidate(adminProductsProvider);
  ref.invalidate(adminProductSummaryProvider);
  ref.invalidate(adminCustomersProvider);
  ref.invalidate(adminCustomerSummaryProvider);
  ref.invalidate(adminRefundStateProvider);
  ref.invalidate(adminListProvider);
  ref.invalidate(adminSearchProvider);
  ref.invalidate(adminOrdersProvider);
  ref.invalidate(adminDetailProvider);
  ref.invalidate(adminSummaryProvider);
}
