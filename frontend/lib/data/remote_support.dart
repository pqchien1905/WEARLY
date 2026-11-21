import 'package:uuid/uuid.dart';
import '../core/network/api_client.dart';
import 'commerce_json.dart';

const supportStatusNames = {
  'OPEN': 'Đang mở',
  'ANSWERED': 'Đã trả lời',
  'CLOSED': 'Đã đóng',
};
const mailStatusNames = {
  'HELD': 'Chờ duyệt lại',
  'CANCELLED': 'Đã hủy gửi',
  'PENDING': 'Chờ gửi thư',
  'PROCESSING': 'Đang gửi thư',
  'SENT': 'Đã gửi thư',
  'FAILED': 'Gửi thư thất bại',
};
const invalidSupport = ApiException(
  'INVALID_RESPONSE',
  'Không đọc được dữ liệu hỗ trợ. Hãy tải lại.',
);

class SupportReceipt {
  SupportReceipt(Object? value) {
    final d = commerceMap(value);
    if (d['id'] is! String ||
        DateTime.tryParse(d['createdAt']?.toString() ?? '') == null) {
      throw invalidSupport;
    }
    id = d['id'];
    createdAt = DateTime.parse(d['createdAt']);
  }
  late final String id;
  late final DateTime createdAt;
}

class RemoteSupportRepository {
  RemoteSupportRepository(this.api, {this.admin = false});
  final ApiClient api;
  final bool admin;
  bool _disposed = false;
  Map<String, Object?>? _pendingContact;
  final _pendingReplies = <String, Map<String, Object?>>{};
  SupportReceipt? lastReceipt;
  Map<String, Object?>? get pendingContact =>
      _pendingContact == null ? null : Map.unmodifiable(_pendingContact!);
  Map<String, Object?>? pendingReply(String id) => _pendingReplies[id] == null
      ? null
      : Map.unmodifiable(_pendingReplies[id]!);
  void dispose() {
    _disposed = true;
    _pendingContact = null;
    _pendingAccount = null;
    _pendingFollowUps.clear();
    _pendingReplies.clear();
    lastReceipt = null;
  }

  void clearReceipt() {
    lastReceipt = null;
  }

  void _check({bool staff = false}) {
    if (_disposed) throw sessionChanged;
    if (staff && !admin) {
      throw const ApiException(
        'FORBIDDEN',
        'Chưa có quyền quản trị.',
        status: 403,
      );
    }
  }

  Future<SupportReceipt> create({
    required String name,
    required String email,
    required String message,
  }) async {
    _check();
    _pendingContact ??= {
      'requestKey': const Uuid().v4(),
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'message': message.trim(),
    };
    try {
      final result = SupportReceipt(
        await api.request(
          'POST',
          'support',
          body: _pendingContact,
          authenticated: false,
        ),
      );
      _check();
      _pendingContact = null;
      lastReceipt = result;
      return result;
    } on ApiException catch (e) {
      if ([400, 401, 403, 404, 409, 422].contains(e.status)) {
        _pendingContact = null;
      }
      rethrow;
    }
  }

  Map<String, Object?>? _pendingAccount;
  Map<String, Object?>? get pendingAccountRequest =>
      _pendingAccount == null ? null : Map.unmodifiable(_pendingAccount!);

  /// Signed-in customers: the ticket is linked to the account, whose name
  /// and email the server uses.
  Future<SupportReceipt> createForAccount(String message) async {
    _check();
    _pendingAccount ??= {
      'requestKey': const Uuid().v4(),
      'message': message.trim(),
    };
    try {
      final result = SupportReceipt(
        await api.request('POST', 'users/me/support', body: _pendingAccount),
      );
      _check();
      _pendingAccount = null;
      lastReceipt = result;
      return result;
    } on ApiException catch (e) {
      if ([400, 401, 403, 404, 409, 422].contains(e.status)) {
        _pendingAccount = null;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> mine({int page = 1, int limit = 10}) async {
    _check();
    final d = commerceMap(
      await api.get(
        'users/me/support',
        query: {'page': '$page', 'limit': '$limit'},
      ),
    );
    _check();
    if (d['items'] is! List || d['total'] is! int) throw invalidSupport;
    for (final row in d['items'] as List) {
      if (row is! Map ||
          row['id'] is! String ||
          row['message'] is! String ||
          !supportStatusNames.containsKey(row['status'])) {
        throw invalidSupport;
      }
    }
    return d;
  }

  Future<Map<String, dynamic>> mineDetail(String id) async {
    _check();
    final d = commerceMap(
      await api.get('users/me/support/${Uri.encodeComponent(id)}'),
    );
    _check();
    if (d['id'] != id ||
        d['message'] is! String ||
        !supportStatusNames.containsKey(d['status']) ||
        d['replies'] is! List) {
      throw invalidSupport;
    }
    return d;
  }

  final _pendingFollowUps = <String, Map<String, Object?>>{};
  Map<String, Object?>? pendingFollowUp(String id) =>
      _pendingFollowUps[id] == null
      ? null
      : Map.unmodifiable(_pendingFollowUps[id]!);

  Future<SupportReceipt> followUp(String id, String message) async {
    _check();
    _pendingFollowUps.putIfAbsent(
      id,
      () => {'requestKey': const Uuid().v4(), 'message': message.trim()},
    );
    try {
      final receipt = SupportReceipt(
        await api.request(
          'POST',
          'users/me/support/${Uri.encodeComponent(id)}/replies',
          body: _pendingFollowUps[id],
        ),
      );
      _check();
      _pendingFollowUps.remove(id);
      return receipt;
    } on ApiException catch (e) {
      if ([400, 401, 403, 404, 409, 422].contains(e.status)) {
        _pendingFollowUps.remove(id);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> list({
    String? userId,
    String? cursor,
    String? status,
    int page = 1,
    int limit = 10,
  }) async {
    _check(staff: true);
    final d = commerceMap(
      await api.get(
        'admin/support',
        query: {
          'cursor': ?cursor,
          'status': ?status,
          'userId': ?userId,
          'page': '$page',
          'limit': '$limit',
        },
      ),
    );
    _check(staff: true);
    if (d['items'] is! List ||
        (d['nextCursor'] != null && d['nextCursor'] is! String)) {
      throw invalidSupport;
    }
    return d;
  }

  Future<Map<String, dynamic>> detail(String id) async {
    _check(staff: true);
    final d = commerceMap(
      await api.get('admin/support/${Uri.encodeComponent(id)}'),
    );
    _check(staff: true);
    if (d['id'] != id ||
        !supportStatusNames.containsKey(d['status']) ||
        d['version'] is! int ||
        d['replies'] is! List) {
      throw invalidSupport;
    }
    for (final key in ['name', 'email', 'message']) {
      if (d[key] is! String) throw invalidSupport;
    }
    return d;
  }

  Future<SupportReceipt> reply(
    String id, {
    required int version,
    required String message,
  }) async {
    _check(staff: true);
    _pendingReplies.putIfAbsent(
      id,
      () => {
        'requestKey': const Uuid().v4(),
        'expectedVersion': version,
        'message': message.trim(),
      },
    );
    try {
      final receipt = SupportReceipt(
        await api.request(
          'POST',
          'admin/support/${Uri.encodeComponent(id)}/replies',
          body: _pendingReplies[id],
        ),
      );
      _check(staff: true);
      _pendingReplies.remove(id);
      return receipt;
    } on ApiException catch (e) {
      if ([400, 401, 403, 404, 409, 422].contains(e.status)) {
        _pendingReplies.remove(id);
      }
      rethrow;
    }
  }

  Future<void> status(
    String id, {
    required int version,
    required String status,
  }) async {
    _check(staff: true);
    await api.request(
      'PATCH',
      'admin/support/${Uri.encodeComponent(id)}',
      body: {'expectedVersion': version, 'status': status},
    );
    _check(staff: true);
  }

  Future<Map<String, dynamic>> mail({int page = 1, int limit = 10}) async {
    _check(staff: true);
    final d = commerceMap(
      await api.get('admin/mail', query: {'page': '$page', 'limit': '$limit'}),
    );
    _check(staff: true);
    if (d['enabled'] is! bool || d['counts'] is! Map || d['items'] is! List) {
      throw invalidSupport;
    }
    return d;
  }
}
