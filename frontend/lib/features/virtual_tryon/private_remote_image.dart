import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_tryon.dart';
import 'private_image.dart';

/// Private bytes exist only in this mounted viewer and Flutter's evictable cache.
class PrivateRemoteImage extends StatefulWidget {
  const PrivateRemoteImage({
    super.key,
    required this.load,
    required this.label,
  });
  final Future<Uint8List> Function() load;
  final String label;
  @override
  State<PrivateRemoteImage> createState() => _PrivateRemoteImageState();
}

class _PrivateRemoteImageState extends State<PrivateRemoteImage> {
  Uint8List? bytes;
  String? error;
  bool loading = true;
  int version = 0;
  @override
  void initState() {
    super.initState();
    unawaited(read());
  }

  @override
  void dispose() {
    version++;
    unawaited(evictPrivateImage(bytes));
    bytes = null;
    super.dispose();
  }

  Future<void> read() async {
    final current = ++version;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.load();
      if (!mounted || version != current) return;
      unawaited(evictPrivateImage(bytes));
      setState(() => bytes = value);
    } catch (e) {
      if (mounted && version == current) setState(() => error = tryonError(e));
    } finally {
      if (mounted && version == current) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (loading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (bytes != null)
        Image.memory(
          bytes!,
          fit: BoxFit.contain,
          height: 360,
          semanticLabel: widget.label,
          errorBuilder: (_, _, _) =>
              const Text('Chưa hiển thị được ảnh riêng tư.'),
        ),
      if (error != null) ...[
        Text(error!),
        const SizedBox(height: 12),
        AppButton(
          'Tải lại ảnh',
          outlined: true,
          onPressed: loading ? null : read,
        ),
      ],
    ],
  );
}
