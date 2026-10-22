import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/commerce_json.dart';
import 'api_providers.dart';
import 'store_details.dart';

class PublishedContent {
  const PublishedContent({
    required this.banner,
    required this.policy,
    this.details,
  });
  final String banner, policy;
  final StoreDetails? details;
}

final contentRevisionProvider = NotifierProvider<ContentRevision, int>(
  ContentRevision.new,
);

class ContentRevision extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() {
    if (ref.mounted) state++;
  }
}

final publishedContentProvider = FutureProvider.autoDispose<PublishedContent?>((
  ref,
) async {
  ref.watch(contentRevisionProvider);
  if (!ref.watch(remoteApiProvider)) return null;
  final result = commerceMap(
    await ref
        .watch(apiClientProvider)
        .request('GET', 'content', authenticated: false),
  );
  if (result['content'] == null) return null;
  final content = commerceMap(result['content']);
  return PublishedContent(
    banner: content['banner'] as String,
    policy: content['policy'] as String,
    details: StoreDetails.fromJson(content['details']),
  );
});
