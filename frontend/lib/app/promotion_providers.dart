import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote_promotions.dart';
import 'api_providers.dart';

final promotionRepositoryProvider = Provider(
  (ref) => RemotePromotionRepository(ref.watch(apiClientProvider)),
);
