import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../core/network/api_client.dart';
import '../core/network/session_tokens.dart';
import 'config.dart';
import '../data/tryon_pending_store.dart';
import '../data/tryon_pending_native.dart'
    if (dart.library.js_interop) '../data/tryon_pending_web.dart';

final remoteApiProvider = Provider<bool>((ref) => BrandConfig.useRemoteApi);
final apiBaseUrlProvider = Provider<String>((ref) => BrandConfig.apiBaseUrl);
final tryOnPendingStoreProvider = Provider<TryOnPendingStore>(
  (ref) => tryOnPendingStore(ref.watch(apiBaseUrlProvider)),
);
final browserSessionsEnabledProvider = Provider<bool>((ref) => kIsWeb);
final sessionTokensProvider = Provider<SessionTokens>((ref) {
  final tokens = SessionTokens();
  ref.onDispose(tokens.dispose);
  return tokens;
});
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    tokens: ref.watch(sessionTokensProvider),
    browserScope: ref.watch(browserSessionsEnabledProvider) ? 'customer' : null,
  );
  ref.onDispose(client.close);
  return client;
});

final adminSessionTokensProvider = Provider<SessionTokens>((ref) {
  final tokens = SessionTokens();
  ref.onDispose(tokens.dispose);
  return tokens;
});
final adminApiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    tokens: ref.watch(adminSessionTokensProvider),
    browserScope: ref.watch(browserSessionsEnabledProvider) ? 'admin' : null,
  );
  ref.onDispose(client.close);
  return client;
});
