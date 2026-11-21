import 'dart:convert';
import '../core/network/api_client.dart';
import '../domain/account_details.dart';

class RemoteAccountDetailsRepository implements AccountDetailsRepository {
  RemoteAccountDetailsRepository(
    this.api, {
    this.onLateStyleCompletion,
    this.onLateAddressCompletion,
  }) : _generation = api.tokens.generation;
  final ApiClient api;
  final int _generation;
  final void Function()? onLateStyleCompletion;
  final void Function()? onLateAddressCompletion;
  final _addressAttempts =
      <String, ({String input, Map<String, Object?> body})>{};
  bool _creatingAddress = false;
  void _lateAddress() {
    if (api.tokens.generation == _generation) onLateAddressCompletion?.call();
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? headers,
    void Function()? onLateCompletion,
  }) async {
    if (api.tokens.generation != _generation) throw sessionChanged;
    final result = await api.request(
      method,
      path,
      body: body,
      headers: headers,
      onLateCompletion: onLateCompletion,
    );
    if (api.tokens.generation != _generation) throw sessionChanged;
    return result;
  }

  @override
  Future<AccountDetails> read() async {
    Object? styleError;
    Future<StylePreferences> readStyle() async {
      try {
        return _style(await _request('GET', 'users/me/style'));
      } on ApiException catch (error) {
        if (error.code == 'SESSION_CHANGED') rethrow;
        styleError = error;
        return const StylePreferences();
      }
    }

    final data = await Future.wait([
      _request('GET', 'users/me/addresses'),
      readStyle(),
    ]);
    if (api.tokens.generation != _generation) throw sessionChanged;
    return _details(
      data[0] as List,
      data[1] as StylePreferences,
      styleError: styleError,
    );
  }

  StylePreferences _style(Object? value) {
    try {
      final json = value as Map;
      final budget = json['budget'] as String;
      final version = json['version'] as int;
      if (!StylePreferences.sizes.contains(json['size']) ||
          !StylePreferences.styles.contains(json['style']) ||
          !StylePreferences.colors.contains(json['color']) ||
          !StylePreferences.budgets.any((v) => '$v' == budget) ||
          version < 0) {
        throw const FormatException();
      }
      return StylePreferences(
        size: json['size'] as String,
        style: json['style'] as String,
        color: json['color'] as String,
        budget: int.parse(budget),
        version: version,
      );
    } catch (_) {
      throw const ApiException(
        'INVALID_RESPONSE',
        'Chưa đọc được hồ sơ phong cách. Vui lòng tải lại.',
      );
    }
  }

  AccountDetails _details(
    List rows,
    StylePreferences style, {
    Object? styleError,
  }) {
    final addresses = rows
        .map(
          (a) => DeliveryAddress(
            id: a['id'] as String,
            label: a['label'] as String? ?? '',
            recipient: a['recipient'] as String,
            phone: a['phone'] as String,
            address: a['address'] as String,
          ),
        )
        .toList();
    return AccountDetails(
      style: style,
      styleError: styleError,
      addresses: addresses,
      defaultAddressId:
          rows.where((a) => a['isDefault'] == true).firstOrNull?['id']
              as String?,
    );
  }

  @override
  Future<AccountDetails> saveAddress(
    DeliveryAddress address, {
    String? creationKey,
  }) async {
    if (api.tokens.generation != _generation) throw sessionChanged;
    final creating = address.id.isEmpty;
    final input = <String, Object?>{
      'label': address.label.trim(),
      'recipient': address.recipient.trim(),
      'phone': address.phone.trim(),
      'address': address.address.trim(),
    };
    if (!creating) {
      await _request(
        'PATCH',
        'users/me/addresses/${Uri.encodeComponent(address.id)}',
        body: input,
        onLateCompletion: _lateAddress,
      );
      return read();
    }
    if (_creatingAddress) {
      throw const ApiException('BUSY', 'Vui lòng chờ lưu địa chỉ hoàn tất.');
    }
    _creatingAddress = true;
    final key = creationKey ?? newAddressCreationKey();
    var confirmed = false;
    try {
      var attempt = _addressAttempts[key];
      final signature = jsonEncode(input);
      if (attempt != null && attempt.input != signature) {
        throw const ApiException(
          'PENDING_ADDRESS',
          'Thử lại đúng yêu cầu địa chỉ đang chờ xác nhận.',
        );
      }
      if (attempt == null) {
        final first = (await read()).addresses.isEmpty;
        attempt = (
          input: signature,
          body: {...input, if (first) 'isDefault': true},
        );
        _addressAttempts[key] = attempt;
      }
      await _request(
        'POST',
        'users/me/addresses',
        body: attempt.body,
        headers: {'Idempotency-Key': key},
        onLateCompletion: () {
          // An active retry will read the address book itself. Invalidating its
          // controller here would reject that valid write as an older result.
          if (api.tokens.generation == _generation && !_creatingAddress) {
            onLateAddressCompletion?.call();
          }
        },
      );
      confirmed = true;
      final details = await read();
      // Keep this key bound to its original payload for the session, even if
      // the controller later discards this result after a concurrent refresh.
      return details;
    } on ApiException catch (error) {
      if (!confirmed && error.status == 400) _addressAttempts.remove(key);
      rethrow;
    } finally {
      _creatingAddress = false;
    }
  }

  @override
  Future<AccountDetails> deleteAddress(String id) async {
    await _request(
      'DELETE',
      'users/me/addresses/${Uri.encodeComponent(id)}',
      onLateCompletion: _lateAddress,
    );
    return read();
  }

  @override
  Future<AccountDetails> setDefault(String id) async {
    await _request(
      'PATCH',
      'users/me/addresses/${Uri.encodeComponent(id)}',
      body: {'isDefault': true},
      onLateCompletion: _lateAddress,
    );
    return read();
  }

  @override
  Future<AccountDetails> saveStyle(StylePreferences preferences) async {
    final result = await _request(
      'PUT',
      'users/me/style',
      body: {
        'size': preferences.size,
        'style': preferences.style,
        'color': preferences.color,
        'budget': '${preferences.budget}',
        'expectedVersion': preferences.version,
      },
      onLateCompletion: () {
        if (api.tokens.generation == _generation) onLateStyleCompletion?.call();
      },
    );
    final saved = _style(result);
    return _details(await _request('GET', 'users/me/addresses') as List, saved);
  }
}
