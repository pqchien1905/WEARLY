import 'dart:typed_data';

String? validateImage(Uint8List bytes) {
  if (bytes.length > 8 * 1024 * 1024) {
    return 'Ảnh vượt 8 MB. Hãy chọn ảnh nhỏ hơn.';
  }
  final png =
      bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10;
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
  return png || jpeg ? null : 'Chỉ nhận ảnh JPEG hoặc PNG hợp lệ.';
}
