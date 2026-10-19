import '../core/network/api_client.dart';
import '../domain/account_details.dart';

class RemoteAccountDetailsRepository implements AccountDetailsRepository {
  RemoteAccountDetailsRepository(this.api, {this.onLateStyleCompletion})
    : _generation = api.tokens.generation;
  final ApiClient api;
  final int _generation;
  final void Function()? onLateStyleCompletion;

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    void Function()? onLateCompletion,
  }) async {
    if (api.tokens.generation != _generation) throw sessionChanged;
    final result = await api.request(
      method,
      path,
      body: body,
      onLateCompletion: onLateCompletion,
    );
    if (api.tokens.generation != _generation) throw sessionChanged;
    return result;
  }

  @override
  Future<AccountDetails> read() async {
    final data = await Future.wait([
      _request('GET', 'users/me/addresses'),
      _request('GET', 'users/me/style'),
    ]);
    return _details(data[0] as List, _style(data[1]));
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

  AccountDetails _details(List rows, StylePreferences style) {
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
      addresses: addresses,
      defaultAddressId:
          rows.where((a) => a['isDefault'] == true).firstOrNull?['id']
              as String?,
    );
  }

  @override
  Future<AccountDetails> saveAddress(DeliveryAddress address) async {
    final creating = address.id.isEmpty;
    final first = creating && (await read()).addresses.isEmpty;
    await _request(
      creating ? 'POST' : 'PATCH',
      creating
          ? 'users/me/addresses'
          : 'users/me/addresses/${Uri.encodeComponent(address.id)}',
      body: {
        'label': address.label.trim(),
        'recipient': address.recipient.trim(),
        'phone': address.phone.trim(),
        'address': address.address.trim(),
        if (first) 'isDefault': true,
      },
    );
    return read();
  }

  @override
  Future<AccountDetails> deleteAddress(String id) async {
    await _request('DELETE', 'users/me/addresses/${Uri.encodeComponent(id)}');
    final result = await read();
    if (result.defaultAddressId == null && result.addresses.isNotEmpty) {
      return setDefault(result.addresses.first.id);
    }
    return result;
  }

  @override
  Future<AccountDetails> setDefault(String id) async {
    await _request(
      'PATCH',
      'users/me/addresses/${Uri.encodeComponent(id)}',
      body: {'isDefault': true},
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
