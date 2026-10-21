import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../core/network/api_client.dart';
import 'commerce_json.dart';

const returnStatusNames = {
  'REQUESTED': 'Chờ duyệt trả hàng',
  'APPROVED': 'Đã duyệt, chờ nhận hàng',
  'REJECTED': 'Yêu cầu bị từ chối',
  'RECEIVED': 'Đã nhận hàng khách trả',
};
const returnEligibilityMessages = {
  'AVAILABLE': 'Có thể gửi yêu cầu trong 7 ngày từ lúc giao hàng.',
  'NOT_DELIVERED': 'Chỉ có thể yêu cầu trả hàng sau khi đơn đã giao.',
  'PAYMENT_NOT_SETTLED':
      'Cửa hàng cần xác nhận khoản thanh toán trước khi xử lý trả hàng. Vui lòng liên hệ hỗ trợ nếu bạn đã trả tiền.',
  'DELIVERY_DATE_UNKNOWN':
      'Chưa có ngày giao hàng được xác minh. Vui lòng liên hệ hỗ trợ.',
  'WINDOW_EXPIRED': 'Đã hết thời hạn gửi yêu cầu trả hàng 7 ngày.',
  'OPEN_RETURN': 'Đang có yêu cầu trả hàng chờ xử lý cho đơn này.',
  'NOTHING_LEFT': 'Toàn bộ số lượng đã được nhận trả.',
};

class ReturnQuote {
  ReturnQuote(Object? value) {
    final data = commerceMap(value);
    amount = vnd(data['amount']);
    if (data['items'] is! List) throw invalidCommerce;
    items = List.unmodifiable(
      (data['items'] as List).map((value) {
        final item = commerceMap(value);
        if (item['orderItemId'] is! String ||
            item['quantity'] is! int ||
            (item['quantity'] as int) < 1) {
          throw invalidCommerce;
        }
        return (
          id: item['orderItemId'] as String,
          quantity: item['quantity'] as int,
          amount: vnd(item['amount']),
        );
      }),
    );
    if (items.isEmpty ||
        items.map((i) => i.id).toSet().length != items.length ||
        items.fold(0, (int sum, i) => sum + i.amount) != amount) {
      throw invalidCommerce;
    }
  }
  late final int amount;
  late final List<({String id, int quantity, int amount})> items;
}

class ReturnCase extends ReturnQuote {
  ReturnCase(Object? value) : super(value) {
    final data = commerceMap(value);
    for (final key in [
      'id',
      'orderId',
      'reason',
      'decisionNote',
      'receiptNote',
    ]) {
      if (data[key] is! String) throw invalidCommerce;
    }
    if (!returnStatusNames.containsKey(data['status']) ||
        data['version'] is! int ||
        (data['version'] as int) < 0) {
      throw invalidCommerce;
    }
    id = data['id'];
    orderId = data['orderId'];
    reason = data['reason'];
    status = data['status'];
    version = data['version'];
    decisionNote = data['decisionNote'];
    receiptNote = data['receiptNote'];
    final time = DateTime.tryParse(data['createdAt']?.toString() ?? '');
    if (time == null) throw invalidCommerce;
    createdAt = time;
  }
  late final String id, orderId, reason, status, decisionNote, receiptNote;
  late final int version;
  late final DateTime createdAt;
}

class ReturnState {
  ReturnState(Object? value) {
    final data = commerceMap(value), rules = commerceMap(data['eligibility']);
    if (rules['canRequest'] is! bool ||
        !returnEligibilityMessages.containsKey(rules['reason']) ||
        rules['items'] is! List ||
        data['requests'] is! List) {
      throw invalidCommerce;
    }
    canRequest = rules['canRequest'];
    reason = rules['reason'];
    if (canRequest != (reason == 'AVAILABLE')) throw invalidCommerce;
    deadline = rules['deadline'] == null
        ? null
        : DateTime.tryParse(rules['deadline'].toString());
    if (canRequest && deadline == null) throw invalidCommerce;
    remaining = Map.unmodifiable(
      Map.fromEntries(
        (rules['items'] as List).map((value) {
          final item = commerceMap(value);
          if (item['orderItemId'] is! String ||
              item['remaining'] is! int ||
              (item['remaining'] as int) < 0) {
            throw invalidCommerce;
          }
          return MapEntry(
            item['orderItemId'] as String,
            item['remaining'] as int,
          );
        }),
      ),
    );
    requests = List.unmodifiable(
      (data['requests'] as List).map(ReturnCase.new),
    );
  }
  late final bool canRequest;
  late final String reason;
  late final DateTime? deadline;
  late final Map<String, int> remaining;
  late final List<ReturnCase> requests;
}

class RemoteReturnRepository {
  RemoteReturnRepository(this.api) : _generation = api.tokens.generation;
  final ApiClient api;
  final int _generation;
  final _pending = <String, Map<String, Object?>>{};
  void _check() {
    if (api.tokens.generation != _generation) throw sessionChanged;
  }

  bool hasPending(String id) => _pending.containsKey(id);
  ({String reason, int amount, Map<String, int> quantities})? pendingDraft(
    String id,
  ) {
    final body = _pending[id];
    if (body == null) return null;
    return (
      reason: body['reason'] as String,
      amount: int.parse(body['expectedAmount'] as String),
      quantities: Map.unmodifiable({
        for (final item in body['items'] as List)
          item['orderItemId'] as String: item['quantity'] as int,
      }),
    );
  }

  String path(String id) => 'orders/${Uri.encodeComponent(id)}/returns';
  Future<ReturnState> state(String id) async {
    _check();
    final data = await api.get(path(id));
    _check();
    return ReturnState(data);
  }

  Future<ReturnQuote> preview(
    String id,
    List<Map<String, Object?>> items,
  ) async {
    _check();
    final data = await api.request(
      'POST',
      '${path(id)}/quote',
      body: {'items': items},
    );
    _check();
    return ReturnQuote(data);
  }

  Future<ReturnCase> submit(
    String id, {
    required String reason,
    required List<Map<String, Object?>> items,
    required int expectedAmount,
  }) async {
    _check();
    final body = _pending.putIfAbsent(
      id,
      () => Map<String, Object?>.from(
        jsonDecode(
              jsonEncode({
                'requestKey': const Uuid().v4(),
                'reason': reason,
                'items': items,
                'expectedAmount': '$expectedAmount',
              }),
            )
            as Map,
      ),
    );
    try {
      final data = await api.request('POST', path(id), body: body);
      _check();
      final result = ReturnCase(data);
      if (result.orderId != id) throw invalidCommerce;
      _pending.remove(id);
      return result;
    } on ApiException catch (e) {
      if ([400, 401, 403, 404, 409, 422].contains(e.status)) {
        _pending.remove(id);
      }
      rethrow;
    }
  }
}
