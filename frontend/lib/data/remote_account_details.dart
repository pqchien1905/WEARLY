import '../core/network/api_client.dart';
import '../domain/account_details.dart';

class RemoteAccountDetailsRepository implements AccountDetailsRepository {
  RemoteAccountDetailsRepository(this.api)
    : _generation = api.tokens.generation;
  final ApiClient api;
  final int _generation;

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (api.tokens.generation != _generation) throw sessionChanged;
    final result = await api.request(method, path, body: body);
    if (api.tokens.generation != _generation) throw sessionChanged;
    return result;
  }

  @override
  Future<AccountDetails> read() async {
    final rows = await _request('GET', 'users/me/addresses') as List;
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
    throw const ApiException(
      'NOT_AVAILABLE',
      'Lưu phong cách chưa được kết nối. Sổ địa chỉ vẫn sử dụng bình thường.',
    );
  }
}
