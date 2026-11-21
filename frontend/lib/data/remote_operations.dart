import '../core/network/api_client.dart';

const _invalid = ApiException(
  'INVALID_RESPONSE',
  'Số liệu vận hành chưa hợp lệ. Vui lòng tải lại.',
);
String _state(Map data) {
  final state = data['status'];
  if (!['ok', 'unavailable', 'disabled'].contains(state)) throw _invalid;
  return state as String;
}

int _count(Object? n) {
  if (n is! int || n < 0 || n > 9007199254740991) throw _invalid;
  return n;
}

DateTime _date(Object? value) {
  if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw _invalid;
  }
  return DateTime.parse(value).toUtc();
}

DateTime? _optionalDate(Object? value) => value == null ? null : _date(value);
String operationsMoney(String value) =>
    '${value.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} ₫';

class OperationsQueue {
  OperationsQueue(Map data)
    : waiting = _count(data['waiting']),
      active = _count(data['active']),
      delayed = _count(data['delayed']),
      failed = _count(data['failed']),
      oldestWaitingAt = _optionalDate(data['oldestWaitingAt']);
  final int waiting, active, delayed, failed;
  final DateTime? oldestWaitingAt;
}

class OperationsWork {
  OperationsWork(Map data)
    : outboxPending = _count(data['outbox']['pending']),
      outboxOldest = _optionalDate(data['outbox']['oldestPendingAt']),
      reserved = _count(data['ai']['reserved']),
      processing = _count(data['ai']['processing']),
      stale = _count(data['ai']['stale']),
      todayCount = _count(data['ai']['todayCount']),
      estimatedVnd = data['ai']['todayEstimatedVnd'] as String,
      dayStartedAt = _date(data['ai']['dayStartedAt']),
      failuresSinceAt = _date(data['ai']['failuresSinceAt']),
      mailPending = _count(data['mail']['pending']),
      mailProcessing = _count(data['mail']['processing']),
      mailFailed = _count(data['mail']['failed']),
      imagesPending = _count(data['cleanup']['imagesPending']),
      failures = List.unmodifiable(
        (data['ai']['failures'] as List).map((item) {
          if (!['STYLIST', 'TRY_ON', 'OTHER'].contains(item['kind']) ||
              item['code'] is! String ||
              !RegExp(r'^[A-Z_]{1,60}$').hasMatch(item['code'])) {
            throw _invalid;
          }
          return (
            kind: item['kind'] as String,
            code: item['code'] as String,
            count: _count(item['count']),
          );
        }),
      ) {
    if (!RegExp(r'^\d{1,32}$').hasMatch(estimatedVnd)) throw _invalid;
  }
  final int outboxPending,
      reserved,
      processing,
      stale,
      todayCount,
      mailPending,
      mailProcessing,
      mailFailed,
      imagesPending;
  final String estimatedVnd;
  final DateTime dayStartedAt, failuresSinceAt;
  final DateTime? outboxOldest;
  final List<({String kind, String code, int count})> failures;
}

class OperationsSnapshot {
  OperationsSnapshot._(Map data)
    : observedAt = _date(data['observedAt']),
      databaseState = _state(data['database']),
      schemaReady = data['database']['schemaReady'] as bool?,
      migrations = data['database']['migrations'] == null
          ? null
          : _count(data['database']['migrations']),
      redisState = _state(data['redis']),
      storageState = _state(data['storage']),
      mailState = _state(data['mail']),
      workerLive = _state(data['worker']) == 'ok',
      lastHeartbeat = _optionalDate(data['worker']['lastAt']),
      tryOnQueue = data['redis']['queues'] == null
          ? null
          : OperationsQueue(data['redis']['queues']['tryOn']),
      recoveryQueue = data['redis']['queues']?['recovery'] == null
          ? null
          : OperationsQueue(data['redis']['queues']['recovery']),
      work = data['work'] == null ? null : OperationsWork(data['work']),
      geminiConfigured = data['providers']['gemini']['configured'] as bool,
      vnpayConfigured = data['providers']['vnpay']['configured'] as bool,
      momoConfigured = data['providers']['momo']?['configured'] == true,
      zalopayConfigured = data['providers']['zalopay']?['configured'] == true,
      stylistModel = data['providers']['gemini']['stylistModel'] as String,
      tryOnModel = data['providers']['gemini']['tryOnModel'] as String {
    if (!RegExp(r'^gemini-[a-z0-9.-]{1,70}$').hasMatch(stylistModel) ||
        !RegExp(r'^gemini-[a-z0-9.-]{1,70}$').hasMatch(tryOnModel) ||
        data['providers']['vnpay']['sandbox'] != true ||
        data['providers']['shipping']['mode'] != 'local' ||
        data['providers']['shipping']['sandbox'] != true) {
      throw _invalid;
    }
    if ((databaseState != 'ok' || schemaReady != true) && work != null ||
        redisState != 'ok' && (tryOnQueue != null || recoveryQueue != null)) {
      throw _invalid;
    }
  }
  factory OperationsSnapshot.fromJson(Object? data) {
    try {
      return OperationsSnapshot._(data as Map);
    } catch (_) {
      throw _invalid;
    }
  }
  final DateTime observedAt;
  final String databaseState,
      redisState,
      storageState,
      mailState,
      stylistModel,
      tryOnModel;
  final bool? schemaReady;
  final int? migrations;
  final bool workerLive,
      geminiConfigured,
      vnpayConfigured,
      momoConfigured,
      zalopayConfigured;
  final DateTime? lastHeartbeat;
  final OperationsQueue? tryOnQueue, recoveryQueue;
  final OperationsWork? work;
}

class OperationsRepository {
  OperationsRepository(this.api);
  final ApiClient api;
  Future<OperationsSnapshot> snapshot() async =>
      OperationsSnapshot.fromJson(await api.get('admin/operations'));
}
