import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/network/session_tokens.dart';
import 'config.dart';

final remoteApiProvider = Provider<bool>((ref) => BrandConfig.useRemoteApi);
final apiBaseUrlProvider = Provider<String>((ref) => BrandConfig.apiBaseUrl);
final sessionTokensProvider = Provider<SessionTokens>((ref) {
  final tokens = SessionTokens();
  ref.onDispose(tokens.dispose);
  return tokens;
});
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    tokens: ref.watch(sessionTokensProvider),
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
  );
  ref.onDispose(client.close);
  return client;
});
