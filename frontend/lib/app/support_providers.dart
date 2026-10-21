import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../data/remote_support.dart';
import 'account_state.dart';
import 'api_providers.dart';

final supportRepositoryProvider = Provider((ref) {
  final repo = RemoteSupportRepository(ref.watch(apiClientProvider));
  ref.onDispose(repo.dispose);
  return repo;
});
final adminSupportRepositoryProvider = Provider((ref) {
  final user = ref.watch(adminAccountProvider.select((u) => (u?.id, u?.role)));
  if (!ref.watch(remoteApiProvider) || user.$2 != 'ADMIN') {
    throw const ApiException(
      'FORBIDDEN',
      'Chưa có quyền quản trị.',
      status: 403,
    );
  }
  final repo = RemoteSupportRepository(
    ref.watch(adminApiClientProvider),
    admin: true,
  );
  ref.onDispose(repo.dispose);
  return repo;
});
final supportListProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String?>(
      (ref, cursor) =>
          ref.watch(adminSupportRepositoryProvider).list(cursor: cursor),
    );
final supportDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) => ref.watch(adminSupportRepositoryProvider).detail(id),
    );
final adminMailProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(adminSupportRepositoryProvider).mail(),
);
