class DeliveryAddress {
  const DeliveryAddress({
    required this.id,
    required this.label,
    required this.recipient,
    required this.phone,
    required this.address,
  });
  final String id, label, recipient, phone, address;
}

class StylePreferences {
  const StylePreferences({
    this.size = 'M',
    this.style = '',
    this.color = '',
    this.budget = 1500000,
  });
  final String size, style, color;
  final int budget;
  static const sizes = ['XS', 'S', 'M', 'L', 'XL', 'XXL'];
  static const styles = ['', 'Tối giản', 'Thanh lịch', 'Thư giãn'];
  static const colors = [
    '',
    'Trắng',
    'Đen',
    'Mận',
    'Xanh',
    'Nâu',
    'Hồng đất',
    'Tím',
    'Đỏ',
  ];
  static const budgets = [800000, 1500000, 2500000];
}

class AccountDetails {
  AccountDetails({
    List<DeliveryAddress> addresses = const [],
    this.defaultAddressId,
    this.style = const StylePreferences(),
  }) : addresses = List.unmodifiable(addresses);
  final List<DeliveryAddress> addresses;
  final String? defaultAddressId;
  final StylePreferences style;
  DeliveryAddress? get defaultAddress =>
      addresses.where((a) => a.id == defaultAddressId).firstOrNull;
}

abstract interface class AccountDetailsRepository {
  Future<AccountDetails> read();
  Future<AccountDetails> saveAddress(DeliveryAddress address);
  Future<AccountDetails> deleteAddress(String id);
  Future<AccountDetails> setDefault(String id);
  Future<AccountDetails> saveStyle(StylePreferences preferences);
}
