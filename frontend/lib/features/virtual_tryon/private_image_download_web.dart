import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';

const supportsPrivateImageDownload = true;
@JS('URL.revokeObjectURL')
external void _revoke(String url);

Future<void> downloadPrivateImage(Uint8List bytes, String name) async {
  final png = bytes.isNotEmpty && bytes.first == 137;
  final file = XFile.fromData(
    bytes,
    name: '$name.${png ? 'png' : 'jpg'}',
    mimeType: png ? 'image/png' : 'image/jpeg',
  );
  try {
    await file.saveTo(file.name);
  } finally {
    // Give the browser time to start the download, then release the private Blob.
    final url = file.path;
    Timer(const Duration(seconds: 1), () => _revoke(url));
  }
}
