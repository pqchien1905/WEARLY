import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../data/remote_support.dart';
import 'account_state.dart';
import 'api_providers.dart';
import '../domain/staff_permissions.dart';

final supportRepositoryProvider = Provider((ref) {
  // A new account (or signing out) never inherits another's pending request.
  ref.watch(accountProvider.select((u) => u?.id));
  final repo = RemoteSupportRepository(ref.watch(apiClientProvider));
  ref.onDispose(repo.dispose);
  return repo;
});
final mySupportProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>(
      (ref, page) => ref.watch(supportRepositoryProvider).mine(page: page),
    );
final mySupportDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) => ref.watch(supportRepositoryProvider).mineDetail(id),
    );
final customerSupportProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, userId) => ref
          .watch(adminSupportRepositoryProvider)
          .list(userId: userId, limit: 20),
    );
final adminSupportRepositoryProvider = Provider((ref) {
  final user = ref.watch(adminAccountProvider.select((u) => (u?.id, u?.role)));
  if (!ref.watch(remoteApiProvider) || !canStaff(user.$2, 'support.manage')) {
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

final supportPagesProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({int page, int limit})>(
      (ref, key) => ref
          .watch(adminSupportRepositoryProvider)
          .list(page: key.page, limit: key.limit),
    );
final supportInboxProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({int page, int limit, String? status})>(
      (ref, key) => ref
          .watch(adminSupportRepositoryProvider)
          .list(page: key.page, limit: key.limit, status: key.status),
    );
final adminMailPagesProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({int page, int limit})>(
      (ref, key) => ref
          .watch(adminSupportRepositoryProvider)
          .mail(page: key.page, limit: key.limit),
    );
