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
typedef AdminDetailKey = ({String kind, String id});
final adminListProvider = FutureProvider.autoDispose
    .family<AdminPage, AdminListKey>(
      (ref, key) => ref.watch(adminRepositoryProvider).list(key.kind, key.page),
    );
final adminDetailProvider = FutureProvider.autoDispose
    .family<AdminRecord, AdminDetailKey>(
      (ref, key) => ref.watch(adminRepositoryProvider).detail(key.kind, key.id),
    );
final adminSummaryProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).summary(),
);
final adminReferencesProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).references(),
);
final adminContentProvider = FutureProvider.autoDispose<AdminRecord>(
  (ref) => ref.watch(adminRepositoryProvider).content(),
);

void refreshAdmin(WidgetRef ref) {
  ref.invalidate(adminRefundStateProvider);
  ref.invalidate(adminListProvider);
  ref.invalidate(adminDetailProvider);
  ref.invalidate(adminSummaryProvider);
}
