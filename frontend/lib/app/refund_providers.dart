import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../data/remote_refunds.dart';
import 'account_state.dart';
import 'api_providers.dart';
import '../domain/staff_permissions.dart';

final refundRepositoryProvider = Provider((ref) {
  ref.watch(accountProvider.select((u) => (u?.id, u?.email)));
  final repo = RemoteRefundRepository(ref.watch(apiClientProvider));
  ref.onDispose(repo.dispose);
  return repo;
});
final adminRefundRepositoryProvider = Provider((ref) {
  final user = ref.watch(
    adminAccountProvider.select((u) => (u?.id, u?.email, u?.role)),
  );
  if (!ref.watch(remoteApiProvider) || !canStaff(user.$3, 'payments.manage')) {
    throw const ApiException(
      'FORBIDDEN',
      'Tài khoản chưa có quyền quản trị.',
      status: 403,
    );
  }
  final repo = RemoteRefundRepository(
    ref.watch(adminApiClientProvider),
    admin: true,
  );
  ref.onDispose(repo.dispose);
  return repo;
});
final refundStateProvider = FutureProvider.autoDispose
    .family<RefundState, String>(
      (ref, id) => ref.watch(refundRepositoryProvider).state(id),
    );
final adminRefundStateProvider = FutureProvider.autoDispose
    .family<RefundState, String>(
      (ref, id) => ref.watch(adminRefundRepositoryProvider).state(id),
    );
