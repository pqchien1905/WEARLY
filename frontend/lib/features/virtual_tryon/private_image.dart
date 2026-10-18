import 'dart:typed_data';
import 'package:flutter/painting.dart';

Future<void> evictPrivateImage(Uint8List? bytes) async {
  if (bytes != null) {
    await MemoryImage(bytes).evict();
  }
}
