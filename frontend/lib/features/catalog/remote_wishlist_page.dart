import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/remote_wishlist.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../../domain/catalog.dart';
import '../account/account_navigation.dart';
import '../account/account_components.dart';

part 'wishlist_filters.dart';
part 'wishlist_grid.dart';

class RemoteWishlistPage extends ConsumerStatefulWidget {
  const RemoteWishlistPage({super.key});
  @override
  ConsumerState<RemoteWishlistPage> createState() => _RemoteWishlistPageState();
}

class _RemoteWishlistPageState extends ConsumerState<RemoteWishlistPage> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final wishlist = ref.read(remoteWishlistProvider);
      if (wishlist.signedIn &&
          wishlist.loaded &&
          !wishlist.loading &&
          !wishlist.busy) {
        wishlist.refresh().catchError((_) {});
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _navigate(Map<String, String?> changes, {bool replace = false}) {
    final uri = GoRouterState.of(context).uri;
    final query = Map<String, String>.of(uri.queryParameters);
    for (final entry in changes.entries) {
      if (entry.value == null || entry.value!.isEmpty) {
        query.remove(entry.key);
      } else {
        query[entry.key] = entry.value!;
      }
    }
    final target = uri.replace(queryParameters: query).toString();
    if (replace) {
      context.replace(target);
    } else {
      context.go(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wishlist = ref.watch(remoteWishlistProvider);
    final uri = GoRouterState.of(context).uri;
    final query = uri.queryParameters['q'] ?? '';
    if (_search.text != query) {
      _search.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    final stock = _stockLabels.containsKey(uri.queryParameters['stock'])
        ? uri.queryParameters['stock']!
        : 'all';
    final sort = _sortLabels.containsKey(uri.queryParameters['sort'])
        ? uri.queryParameters['sort']!
        : 'newest';
    final records = wishlist.items.entries.toList();
    final words = _searchText(
      query,
    ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final filtered = records.where((entry) {
      final p = entry.value;
      final text = _searchText(
        p == null
            ? 'Sản phẩm không còn mở bán'
            : '${p.name} ${p.material} ${p.style} ${p.colors.join(' ')}',
      );
      return (stock == 'all' || _stockOf(p) == stock) &&
          words.every(text.contains);
    }).toList();
    if (sort != 'newest') {
      final positions = {
        for (var i = 0; i < records.length; i++) records[i].key: i,
      };
      filtered.sort((a, b) {
        if (a.value == null || b.value == null) {
          return a.value == null && b.value == null
              ? positions[a.key]!.compareTo(positions[b.key]!)
              : a.value == null
              ? 1
              : -1;
        }
        final price = sort == 'price_asc'
            ? a.value!.price.compareTo(b.value!.price)
            : b.value!.price.compareTo(a.value!.price);
        return price == 0
            ? positions[a.key]!.compareTo(positions[b.key]!)
            : price;
      });
    }
    final pages = math.max(1, (filtered.length / 12).ceil());
    final requested = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
    final page = requested.clamp(1, pages);
    if (wishlist.loaded &&
        !wishlist.loading &&
        uri.queryParameters.containsKey('page') &&
        (requested != page || page == 1)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GoRouterState.of(context).uri == uri) {
          _navigate({'page': page == 1 ? null : '$page'}, replace: true);
        }
      });
    }
    final enabled = wishlist.loaded && !wishlist.loading && !wishlist.busy;
    Future<void> refresh() async {
      try {
        await wishlist.refresh();
      } catch (_) {
        /* Render the error below. */
      }
    }

    void clear() =>
        _navigate({'q': null, 'stock': null, 'sort': null, 'page': null});
    return AccountFrame(
      title: 'Những món đồ bạn thích.',
      current: '/wishlist',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!wishlist.hasSnapshot && wishlist.loading)
            const LoadingPanel()
          else if (!wishlist.hasSnapshot)
            StatePanel(
              title: 'Chưa tải được danh sách yêu thích',
              message: wishlist.error ?? 'Tải lại để xem sản phẩm đã lưu.',
              action: AppButton('Tải lại', onPressed: refresh),
            )
          else ...[
            AccountToolbar(
              label: '${records.length} sản phẩm đã lưu',
              actions: [
                TextButton.icon(
                  onPressed: () => context.go('/shop'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('Khám phá thêm'),
                ),
                TextButton.icon(
                  onPressed: wishlist.busy || wishlist.loading ? null : refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(wishlist.loading ? 'Đang tải…' : 'Tải lại'),
                ),
              ],
            ),
            if (wishlist.loading) const LinearProgressIndicator(minHeight: 2),
            if (wishlist.error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: AccountNotice(
                  text: 'Chưa cập nhật được danh sách. ${wishlist.error}',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: wishlist.loading ? null : refresh,
                  child: const Text('Thử lại'),
                ),
              ),
            ],
            if (wishlist.busy) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: const Text('Đang cập nhật yêu thích…', style: T.small),
              ),
            ],
            const SizedBox(height: 24),
            if (records.isEmpty)
              AccountEmptyState(
                title: 'Tủ đồ yêu thích còn trống',
                icon: Icons.favorite_border,
                message:
                    'Nhấn biểu tượng trái tim trên một sản phẩm để lưu lại.',
                action: AppButton(
                  'Khám phá cửa hàng',
                  onPressed: () => context.go('/shop'),
                ),
              )
            else ...[
              _WishlistFilters(
                search: _search,
                stock: stock,
                sort: sort,
                records: records,
                onSearch: (value) =>
                    _navigate({'q': value, 'page': null}, replace: true),
                onStock: (value) => _navigate({
                  'stock': value == 'all' ? null : value,
                  'page': null,
                }),
                onSort: (value) => _navigate({
                  'sort': value == 'newest' ? null : value,
                  'page': null,
                }),
                onClear: clear,
              ),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: Text(
                  filtered.isEmpty
                      ? 'Không có sản phẩm phù hợp'
                      : 'Hiển thị ${(page - 1) * 12 + 1}–${math.min(page * 12, filtered.length)} trong ${filtered.length} sản phẩm',
                  style: T.small,
                ),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                AccountEmptyState(
                  title: 'Chưa tìm thấy món đồ phù hợp',
                  message:
                      'Thử từ khóa khác hoặc đặt lại bộ lọc để xem các sản phẩm đã lưu.',
                  action: AppButton(
                    'Đặt lại bộ lọc',
                    outlined: true,
                    onPressed: clear,
                  ),
                )
              else ...[
                _WishlistGrid(
                  records: filtered.skip((page - 1) * 12).take(12).toList(),
                  enabled: enabled,
                  onRemove: (id) async {
                    try {
                      await wishlist.toggle(id);
                    } catch (_) {
                      /* Inline recovery keeps the saved list visible. */
                    }
                  },
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (pages > 1)
                      AppButton(
                        'Trang trước',
                        outlined: true,
                        onPressed: page > 1
                            ? () => _navigate({
                                'page': page == 2 ? null : '${page - 1}',
                              })
                            : null,
                      ),
                    Text('Trang $page / $pages', style: T.small),
                    if (pages > 1)
                      AppButton(
                        'Trang sau',
                        outlined: true,
                        onPressed: page < pages
                            ? () => _navigate({'page': '${page + 1}'})
                            : null,
                      ),
                  ],
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
