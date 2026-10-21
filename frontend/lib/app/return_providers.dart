import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote_returns.dart';
import 'account_state.dart';
import 'api_providers.dart';

final returnRepositoryProvider = Provider((ref) {
  ref.watch(accountProvider);
  return RemoteReturnRepository(ref.watch(apiClientProvider));
});
final returnStateProvider = FutureProvider.autoDispose
    .family<ReturnState, String>(
      (ref, id) => ref.watch(returnRepositoryProvider).state(id),
    );
