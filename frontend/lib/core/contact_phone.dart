String normalizedContactPhone(String value) => value
    .replaceAll(RegExp(r'[\s().-]'), '')
    .replaceFirst(RegExp(r'^00'), '+')
    .replaceFirst(RegExp(r'^\+84'), '0')
    .replaceFirst(RegExp(r'^84(?=\d{9}$)'), '0');

String? contactPhoneValidation(String? value) {
  final phone = normalizedContactPhone(value ?? '');
  return phone.isEmpty || RegExp(r'^\+?\d{7,15}$').hasMatch(phone)
      ? null
      : 'Nhập số điện thoại 7–15 chữ số hoặc để trống.';
}
