import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/account_state.dart';
import '../../../app/api_providers.dart';
import 'operations_snapshot.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/remote_operations.dart';
import 'admin_widgets.dart';

final operationsSnapshotProvider =
    FutureProvider.autoDispose<OperationsSnapshot>((ref) {
      final account = ref.watch(
        adminAccountProvider.select((u) => (u?.id, u?.role)),
      );
      if (!ref.watch(remoteApiProvider) ||
          account.$1 == null ||
          account.$2 != 'ADMIN') {
        throw const ApiException(
          'FORBIDDEN',
          'Tài khoản chưa có quyền truy cập.',
          status: 403,
        );
      }
      return OperationsRepository(ref.watch(adminApiClientProvider)).snapshot();
    }, retry: (_, _) => null);

class RemoteOperationsPage extends ConsumerWidget {
  const RemoteOperationsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void reload() => ref.invalidate(operationsSnapshotProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Vận hành & AI',
          'Theo dõi kết nối dịch vụ, hàng đợi và hoạt động AI của cửa hàng.',
          actions: [
            AppButton(
              'Tải lại số liệu',
              outlined: true,
              icon: Icons.refresh,
              busy: ref.watch(operationsSnapshotProvider).isLoading,
              onPressed: reload,
            ),
          ],
        ),
        AdminAsync(
          value: ref.watch(operationsSnapshotProvider),
          reload: reload,
          builder: (data) => OperationsSnapshotView(data),
        ),
      ],
    );
  }
}
