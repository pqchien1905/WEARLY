import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../core/network/api_client.dart';
import '../data/remote_catalog.dart';
import '../domain/catalog.dart';
import 'account_state.dart';
import 'api_providers.dart';

final remoteWishlistProvider = ChangeNotifierProvider<RemoteWishlistController>(
  (ref) {
    final user = ref.watch(accountProvider.select((u) => (u?.id, u?.email)));
    return RemoteWishlistController(
      ref.watch(apiClientProvider),
      signedIn: user.$1 != null,
    );
  },
);

class RemoteWishlistController extends ChangeNotifier {
  RemoteWishlistController(this.api, {required this.signedIn})
    : _generation = api.tokens.generation {
    if (signedIn) {
      Future.microtask(() {
        if (!_disposed && !loaded && !loading) refresh().catchError((_) {});
      });
    }
  }
  final ApiClient api;
  final bool signedIn;
  final int _generation;
  Map<String, Product?> _items = {};
  Map<String, Product?> get items => Map.unmodifiable(_items);
  bool loaded = false, loading = false, busy = false, _disposed = false;
  bool hasSnapshot = false;
  String? error;
  Future<void>? _refreshing;

  void _check() {
    if (_disposed || api.tokens.generation != _generation) throw sessionChanged;
    if (!signedIn) {
      throw const ApiException(
        'LOGIN_REQUIRED',
        'Đăng nhập để lưu sản phẩm yêu thích.',
      );
    }
  }

  Map<String, Product?> _decode(Object? response) {
    try {
      final result = <String, Product?>{};
      for (final row in (response as Map)['items'] as List) {
        final id = row['productId'] as String;
        final product = row['product'] == null
            ? null
            : RemoteProductRepository.productFromJson(
                row['product'] as Map<String, dynamic>,
              );
        if (id.isEmpty ||
            result.containsKey(id) ||
            product != null && product.id != id) {
          throw const FormatException();
        }
        result[id] = product;
      }
      return result;
    } catch (_) {
      throw const ApiException(
        'INVALID_RESPONSE',
        'Chưa đọc được danh sách yêu thích. Hãy tải lại.',
      );
    }
  }

  Future<void> refresh() {
    _check();
    if (_refreshing != null) return _refreshing!;
    if (busy) return Future.value();
    late final Future<void> pending;
    pending = _load().whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
    _refreshing = pending;
    return pending;
  }

  Future<void> _load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final value = _decode(await api.get('wishlist'));
      _check();
      _items = value;
      loaded = true;
      hasSnapshot = true;
    } catch (e) {
      if (!_disposed) {
        error = '$e';
        loaded = false;
      }
      rethrow;
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> toggle(String id) async {
    _check();
    // Unknown state is reconciled only. Do not turn a retry of a lost save
    // response into the inverse DELETE after discovering it succeeded.
    if (!loaded || loading) {
      await refresh();
      return;
    }
    await _set(id, !_items.containsKey(id));
  }

  Future<void> save(String id) async {
    _check();
    if (!loaded || loading) await refresh();
    _check();
    _checkIdle();
    if (_items.containsKey(id)) return;
    await _set(id, true);
  }

  Future<void> _set(String id, bool saved) async {
    _check();
    _checkIdle();
    busy = true;
    error = null;
    notifyListeners();
    try {
      final value = _decode(
        await api.request(
          saved ? 'PUT' : 'DELETE',
          'wishlist/${Uri.encodeComponent(id)}',
          onLateCompletion: _reconcileLateWrite,
        ),
      );
      _check();
      _items = value;
      loaded = true;
      hasSnapshot = true;
    } catch (e) {
      if (!_disposed) {
        loaded = false;
        error = e is ApiException && e.code == 'WISHLIST_LIMIT'
            ? 'Danh sách đã đủ 200 sản phẩm. Bỏ bớt một sản phẩm rồi lưu lại.'
            : 'Chưa xác nhận được thay đổi. Tải lại danh sách trước khi tiếp tục.';
      }
      rethrow;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _reconcileLateWrite() async {
    // A manual read may have started before the timed-out write committed.
    // Finish that read, then fetch a snapshot after the completion.
    try {
      await _refreshing;
    } catch (_) {
      /* Retry below. */
    }
    if (!_disposed && api.tokens.generation == _generation) {
      try {
        await refresh();
      } catch (_) {
        /* Explicit retry remains available. */
      }
    }
  }

  void _checkIdle() {
    if (busy) {
      throw const ApiException('BUSY', 'Đang lưu thay đổi. Vui lòng đợi.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _items = {};
    super.dispose();
  }
}
