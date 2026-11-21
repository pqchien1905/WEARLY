import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../core/network/api_client.dart';
import 'commerce_json.dart';
import 'remote_payments.dart';

const refundStatusNames = {
  'REVIEW': 'Cần xác minh kết quả hoàn',
  'PROCESSING': 'Cổng thanh toán đang xử lý hoàn',
  'SUCCEEDED': 'Đã hoàn tiền',
  'FAILED': 'Yêu cầu hoàn bị từ chối',
};

class RefundRecord {
  RefundRecord(Object? value) {
    final d = commerceMap(value);
    if (d['id'] is! String ||
        !refundStatusNames.containsKey(d['status']) ||
        !['cod', ...onlinePaymentProviders].contains(d['provider'])) {
      throw invalidCommerce;
    }
    id = d['id'];
    status = d['status'];
    provider = d['provider'];
    amount = vnd(d['amount']);
    if (amount <= 0) throw invalidCommerce;
    for (final key in [
      'reference',
      'providerTransactionNo',
      'attemptId',
      'providerRequestId',
    ]) {
      if (d[key] != null && d[key] is! String) throw invalidCommerce;
    }
    reference = d['reference'];
    attemptId = d['attemptId'];
    providerRequestId = d['providerRequestId'];
    transactionNo = d['providerTransactionNo'];
    final time = DateTime.tryParse(d['createdAt']?.toString() ?? '');
    if (time == null) throw invalidCommerce;
    createdAt = time;
    completedAt = d['completedAt'] == null
        ? null
        : DateTime.tryParse(d['completedAt'].toString());
    if (status == 'SUCCEEDED' && completedAt == null) throw invalidCommerce;
  }
  late final String id, status, provider;
  late final int amount;
  late final String? reference, transactionNo;
  late final String? attemptId, providerRequestId;
  late final DateTime createdAt;
  late final DateTime? completedAt;
}

class RefundSource {
  RefundSource(Object? value) {
    final d = commerceMap(value);
    if ((d['attemptId'] != null && d['attemptId'] is! String) ||
        d['primary'] is! bool) {
      throw invalidCommerce;
    }
    attemptId = d['attemptId'];
    provider = d['provider'] as String?;
    primary = d['primary'];
    if (d['pending'] != null && d['pending'] is! bool) throw invalidCommerce;
    pending = d['pending'] ?? false;
    collected = vnd(d['collected']);
    entitled = vnd(d['entitled']);
    refunded = vnd(d['refunded']);
    reserved = vnd(d['reserved']);
    available = vnd(d['available']);
    if (refunded > reserved ||
        reserved > entitled ||
        entitled > collected ||
        available != entitled - reserved) {
      throw invalidCommerce;
    }
  }
  late final String? attemptId;
  late final String? provider;
  late final bool primary;
  late final bool pending;
  late final int collected, entitled, refunded, reserved, available;
}

class RefundState {
  RefundState(Object? value) {
    final d = commerceMap(value);
    if (d['orderId'] is! String ||
        d['version'] is! int ||
        d['version'] < 0 ||
        d['refunds'] is! List ||
        !(d['provider'] == null ||
            paymentProviderNames.containsKey(d['provider'])) ||
        (d['paymentStatus'] != null &&
            !paymentStatuses.contains(d['paymentStatus']))) {
      throw invalidCommerce;
    }
    orderId = d['orderId'];
    version = d['version'];
    provider = d['provider'];
    paymentStatus = d['paymentStatus'];
    refunded = vnd(d['refunded']);
    refunds = List.unmodifiable((d['refunds'] as List).map(RefundRecord.new));
    sources = List.unmodifiable(
      (d['sources'] as List? ?? []).map(RefundSource.new),
    );
    if (refunds.map((r) => r.id).toSet().length != refunds.length ||
        sources.map((s) => s.attemptId).toSet().length != sources.length ||
        refunds
                .where((r) => r.status == 'SUCCEEDED')
                .fold(0, (int s, r) => s + r.amount) !=
            refunded) {
      throw invalidCommerce;
    }
  }
  late final String orderId;
  late final String? provider, paymentStatus;
  late final int version, refunded;
  late final List<RefundRecord> refunds;
  late final List<RefundSource> sources;
}

class RemoteRefundRepository {
  RemoteRefundRepository(this.api, {this.admin = false})
    : _generation = api.tokens.generation;
  final ApiClient api;
  final bool admin;
  final int _generation;
  bool _disposed = false;
  final _pending = <String, Map<String, Object?>>{};
  void dispose() {
    _disposed = true;
    _pending.clear();
  }

  void _check() {
    if (_disposed || api.tokens.generation != _generation) throw sessionChanged;
  }

  String path(String id) =>
      '${admin ? 'admin/' : ''}orders/${Uri.encodeComponent(id)}/refunds';
  bool hasPending(String id) => _pending.containsKey(id);
  ({int amount, String? reference})? pendingDraft(String id) {
    final b = _pending[id];
    return b == null
        ? null
        : (
            amount: int.parse(b['expectedAmount'] as String),
            reference: b['reference'] as String?,
          );
  }

  Future<RefundState> state(String id) async {
    _check();
    final data = await api.get(path(id));
    _check();
    final result = RefundState(data);
    if (result.orderId != id) throw invalidCommerce;
    return result;
  }

  Future<RefundRecord> create(
    String id, {
    required RefundSource source,
    required int version,
    String? reference,
  }) async {
    _check();
    if (!admin) {
      throw const ApiException(
        'FORBIDDEN',
        'Chỉ nhân viên có quyền được ghi nhận hoàn tiền.',
        status: 403,
      );
    }
    _pending.putIfAbsent(
      id,
      () => {
        'requestKey': const Uuid().v4(),
        'expectedVersion': version,
        'expectedAmount': '${source.available}',
        if (source.attemptId != null) 'paymentAttemptId': source.attemptId,
        if (reference != null) 'reference': reference.trim(),
      },
    );
    return retry(id);
  }

  Future<RefundRecord> retry(String id) async {
    _check();
    final body = _pending[id];
    if (body == null) throw invalidCommerce;
    try {
      final data = await api.request(
        'POST',
        path(id),
        body: jsonDecode(jsonEncode(body)) as Map<String, dynamic>,
      );
      _check();
      final result = RefundRecord(data);
      _pending.remove(id);
      return result;
    } on ApiException catch (e) {
      if ([400, 401, 403, 404, 409, 422].contains(e.status)) {
        _pending.remove(id);
      }
      rethrow;
    }
  }

  Future<RefundRecord> query(
    String id,
    String refundId, {
    String? transactionNo,
  }) async {
    _check();
    if (!admin) {
      throw const ApiException(
        'FORBIDDEN',
        'Không có quyền truy vấn.',
        status: 403,
      );
    }
    final data = await api.request(
      'POST',
      '${path(id)}/${Uri.encodeComponent(refundId)}/query',
      body: {'transactionNo': ?transactionNo},
    );
    _check();
    return RefundRecord(data);
  }
}
