import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_tryon.dart';
import 'private_image.dart';
import 'private_image_download.dart';

/// Private bytes exist only in this mounted viewer and Flutter's evictable cache.
class PrivateRemoteImage extends StatefulWidget {
  const PrivateRemoteImage({
    super.key,
    required this.load,
    required this.label,
    this.downloadName,
  });
  final Future<Uint8List> Function() load;
  final String label;
  final String? downloadName;
  @override
  State<PrivateRemoteImage> createState() => _PrivateRemoteImageState();
}

class _PrivateRemoteImageState extends State<PrivateRemoteImage> {
  Uint8List? bytes;
  String? error;
  bool loading = true;
  bool downloading = false;
  String? downloadError;
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
      downloadError = null;
      unawaited(evictPrivateImage(bytes));
      bytes = null;
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

  Future<void> download() async {
    if (bytes == null || downloading || widget.downloadName == null) return;
    setState(() {
      downloading = true;
      downloadError = null;
    });
    try {
      await downloadPrivateImage(bytes!, widget.downloadName!);
      if (mounted) {
        toast(context, 'Đã gửi ảnh đến trình tải xuống của trình duyệt.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => downloadError = 'Chưa tải ảnh xuống được. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => downloading = false);
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
          errorBuilder: (_, _, _) => Column(
            children: [
              const Text('Chưa hiển thị được ảnh riêng tư.'),
              TextButton(onPressed: read, child: const Text('Tải lại ảnh')),
            ],
          ),
        ),
      if (bytes != null &&
          widget.downloadName != null &&
          supportsPrivateImageDownload) ...[
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.center,
          child: AppButton(
            'Tải ảnh xuống',
            icon: Icons.download_outlined,
            outlined: true,
            busy: downloading,
            onPressed: download,
          ),
        ),
        if (downloadError != null)
          Semantics(liveRegion: true, child: Text(downloadError!)),
      ],
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
