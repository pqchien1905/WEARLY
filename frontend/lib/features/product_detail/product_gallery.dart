import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/catalog.dart';

class ProductGallery extends StatefulWidget {
  const ProductGallery({super.key, required this.product, required this.color});
  final Product product;
  final String color;
  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  int index = 0;
  bool focused = false;
  @override
  void didUpdateWidget(covariant ProductGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color ||
        oldWidget.product != widget.product) {
      index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final matching = p.media.where((m) => m.color == widget.color).toList();
    final photos = matching.isNotEmpty
        ? matching
        : p.media.isNotEmpty
        ? p.media
        : [ProductMedia(path: p.image, label: '${p.name}, ảnh minh họa')];
    final selected = photos[index.clamp(0, photos.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                setState(() => index = (index + 1) % photos.length),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => setState(
              () => index = (index - 1 + photos.length) % photos.length,
            ),
          },
          child: Focus(
            onFocusChange: (value) => setState(() => focused = value),
            child: LayoutBuilder(
              builder: (_, constraints) => SizedBox(
                height: (constraints.maxWidth * 1.25).clamp(0, 820),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: T.photo,
                      child: FashionImage(
                        selected.path,
                        label: selected.label,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: IconButton.filledTonal(
                        tooltip: 'Phóng to ảnh',
                        icon: const Icon(Icons.zoom_in_outlined),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              _PhotoViewer(photos: photos, initialIndex: index),
                        ),
                      ),
                    ),
                    if (focused)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: T.accent, width: 3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (photos.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < photos.length; i++)
                  Semantics(
                    selected: i == index,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(4),
                        side: BorderSide(
                          color: i == index ? T.accent : T.line,
                          width: i == index ? 2 : 1,
                        ),
                      ),
                      onPressed: () => setState(() => index = i),
                      child: SizedBox(
                        width: 56,
                        height: 72,
                        child: FashionImage(
                          photos[i].path,
                          label: 'Ảnh ${i + 1}: ${photos[i].label}',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(
            matching.isEmpty
                ? 'Chưa có ảnh màu ${widget.color}. Đang hiển thị ảnh tham khảo; màu đã chọn vẫn áp dụng cho giỏ hàng.'
                : 'Ảnh catalog minh họa · ${index + 1}/${photos.length}. Phóng to để xem rõ chi tiết.',
            style: T.small,
          ),
        ),
      ],
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initialIndex});
  final List<ProductMedia> photos;
  final int initialIndex;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int index = widget.initialIndex;
  void step(int delta) => setState(
    () => index = (index + delta + widget.photos.length) % widget.photos.length,
  );
  @override
  Widget build(BuildContext context) => Dialog(
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => step(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => step(-1),
      },
      child: Focus(
        autofocus: true,
        child: SizedBox(
          width: 900,
          height: MediaQuery.sizeOf(context).height * .85,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${index + 1} / ${widget.photos.length}',
                        style: T.small,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng ảnh',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Expanded(
                child: InteractiveViewer(
                  key: ValueKey(index),
                  child: FashionImage(
                    widget.photos[index].path,
                    label: widget.photos[index].label,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Ảnh trước',
                      onPressed: widget.photos.length > 1
                          ? () => step(-1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        widget.photos[index].label,
                        textAlign: TextAlign.center,
                        style: T.small,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Ảnh sau',
                      onPressed: widget.photos.length > 1
                          ? () => step(1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
