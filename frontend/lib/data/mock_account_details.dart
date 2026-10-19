import '../domain/account_details.dart';

class MockAccountDetailsRepository implements AccountDetailsRepository {
  MockAccountDetailsRepository({
    this.latency = const Duration(milliseconds: 250),
  });
  final Duration latency;
  bool offline = false;
  var _value = AccountDetails();
  var _sequence = 0;

  Future<void> _wait() async {
    await Future<void>.delayed(latency);
    if (offline) throw StateError('Chưa lưu được thay đổi. Hãy thử lại.');
  }

  @override
  Future<AccountDetails> read() async {
    await _wait();
    return _value;
  }

  @override
  Future<AccountDetails> saveAddress(
    DeliveryAddress input, {
    String? creationKey,
  }) async {
    if (input.label.trim().isEmpty ||
        input.recipient.trim().isEmpty ||
        !RegExp(r'^0\d{9}$').hasMatch(input.phone.trim()) ||
        input.address.trim().length < 8) {
      throw ArgumentError('Kiểm tra tên người nhận, số điện thoại và địa chỉ.');
    }
    await _wait();
    final existing = _value.addresses.any((a) => a.id == input.id);
    if (input.id.isNotEmpty && !existing) {
      throw StateError('Địa chỉ này đã bị xóa.');
    }
    if (!existing && _value.addresses.length >= 5) {
      throw StateError(
        'Tối đa 5 địa chỉ trong phiên demo. Hãy sửa hoặc xóa một địa chỉ.',
      );
    }
    final saved = DeliveryAddress(
      id: existing ? input.id : 'address-${++_sequence}',
      label: input.label.trim(),
      recipient: input.recipient.trim(),
      phone: input.phone.trim(),
      address: input.address.trim(),
    );
    _value = AccountDetails(
      addresses: existing
          ? [
              for (final a in _value.addresses)
                if (a.id == saved.id) saved else a,
            ]
          : [..._value.addresses, saved],
      defaultAddressId: _value.defaultAddressId ?? saved.id,
      style: _value.style,
    );
    return _value;
  }

  @override
  Future<AccountDetails> deleteAddress(String id) async {
    await _wait();
    final next = _value.addresses.where((a) => a.id != id).toList();
    _value = AccountDetails(
      addresses: next,
      style: _value.style,
      defaultAddressId: _value.defaultAddressId == id
          ? next.firstOrNull?.id
          : _value.defaultAddressId,
    );
    return _value;
  }

  @override
  Future<AccountDetails> setDefault(String id) async {
    await _wait();
    if (!_value.addresses.any((a) => a.id == id)) {
      throw StateError('Địa chỉ này không còn tồn tại.');
    }
    _value = AccountDetails(
      addresses: _value.addresses,
      defaultAddressId: id,
      style: _value.style,
    );
    return _value;
  }

  @override
  Future<AccountDetails> saveStyle(StylePreferences preferences) async {
    if (!StylePreferences.sizes.contains(preferences.size) ||
        !StylePreferences.styles.contains(preferences.style) ||
        !StylePreferences.colors.contains(preferences.color) ||
        !StylePreferences.budgets.contains(preferences.budget)) {
      throw ArgumentError('Lựa chọn phong cách chưa hợp lệ.');
    }
    await _wait();
    _value = AccountDetails(
      addresses: _value.addresses,
      defaultAddressId: _value.defaultAddressId,
      style: preferences,
    );
    return _value;
  }
}
