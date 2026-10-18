import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_ai.dart';
import '../domain/ai.dart';
import 'providers.dart';

final stylistRepositoryProvider = Provider<StylistRepository>(
  (ref) => MockStylistRepository(ref.watch(productRepositoryProvider)),
);
final tryOnRepositoryProvider = Provider.autoDispose<TryOnRepository>((ref) {
  final repo = MockTryOnRepository();
  ref.onDispose(repo.cancel);
  return repo;
});
