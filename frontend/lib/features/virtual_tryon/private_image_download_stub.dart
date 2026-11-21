import 'dart:typed_data';

const supportsPrivateImageDownload = false;
Future<void> downloadPrivateImage(Uint8List bytes, String name) async =>
    throw UnsupportedError(
      'Image download is available in the web storefront.',
    );
