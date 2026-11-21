import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/primitives.dart';

class ProductDetailGallery extends StatefulWidget {
  const ProductDetailGallery({
    super.key,
    required this.images,
    required this.productName,
  });
  final List images;
  final String productName;
  @override
  State<ProductDetailGallery> createState() => _ProductDetailGalleryState();
}

class _ProductDetailGalleryState extends State<ProductDetailGallery> {
  int selected = 0;
  @override
  void didUpdateWidget(covariant ProductDetailGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images.isEmpty || widget.images.isEmpty) {
      selected = 0;
      return;
    }
    final previous =
        oldWidget.images[selected.clamp(0, oldWidget.images.length - 1)];
    final index = widget.images.indexWhere(
      (i) => (i['id'] ?? i['url']) == (previous['id'] ?? previous['url']),
    );
    selected = index < 0 ? 0 : index;
  }

  Future<void> expand() async {
    final index = await showDialog<int>(
      context: context,
      builder: (_) => _GalleryViewer(
        images: List.of(widget.images),
        productName: widget.productName,
        initialIndex: selected,
      ),
    );
    if (mounted && index != null && index < widget.images.length) {
      setState(() => selected = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const ColoredBox(
        color: T.canvas,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 44, color: T.muted),
              SizedBox(height: 12),
              Text('Chưa có ảnh sản phẩm', style: T.body),
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Thêm ảnh trong trang chỉnh sửa sản phẩm.',
                  textAlign: TextAlign.center,
                  style: T.small,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final image = widget.images[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: constraints.maxWidth.clamp(0.0, 520.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: T.canvas,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FashionImage(
                      key: const ValueKey('product-gallery-image'),
                      '${image['url']}',
                      label: '${image['alt'] ?? widget.productName}',
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    color: T.surface,
                    child: Text(
                      selected == 0 ? 'Ảnh bìa' : 'Ảnh ${selected + 1}',
                      style: T.small,
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: IconButton.filledTonal(
                    tooltip: 'Phóng to ảnh sản phẩm',
                    onPressed: expand,
                    icon: const Icon(Icons.zoom_in),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < widget.images.length; i++)
              Semantics(
                selected: selected == i,
                child: SizedBox(
                  width: 72,
                  height: 80,
                  child: OutlinedButton(
                    onPressed: () => setState(() => selected = i),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(4),
                      backgroundColor: T.surface,
                      side: BorderSide(
                        color: selected == i ? T.accent : T.line,
                        width: selected == i ? 2 : 1,
                      ),
                    ),
                    child: Semantics(
                      label: 'Xem ảnh ${i + 1}',
                      child: ExcludeSemantics(
                        child: FashionImage(
                          '${widget.images[i]['url']}',
                          label: '',
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${selected + 1}/${widget.images.length} ảnh · Chọn ảnh thu nhỏ để xem',
          style: T.small,
        ),
      ],
    );
  }
}

class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({
    required this.images,
    required this.productName,
    required this.initialIndex,
  });
  final List images;
  final String productName;
  final int initialIndex;
  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late int index = widget.initialIndex;
  final transform = TransformationController();
  Size imageSize = Size.zero;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  void move(int offset) {
    final next = index + offset;
    if (next < 0 || next >= widget.images.length) return;
    setState(() {
      index = next;
      transform.value = Matrix4.identity();
    });
  }

  void zoom(double scale) {
    final amount = scale.clamp(1.0, 4.0);
    transform.value = Matrix4.diagonal3Values(amount, amount, 1)
      ..setTranslationRaw(
        -imageSize.width * (amount - 1) / 2,
        -imageSize.height * (amount - 1) / 2,
        0,
      );
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.images[index];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => move(1),
      },
      child: Focus(
        autofocus: true,
        includeSemantics: false,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 1060,
            height: MediaQuery.sizeOf(context).height * .88,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: T.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng ảnh lớn',
                        onPressed: () => Navigator.pop(context, index),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRect(
                      child: ColoredBox(
                        color: T.canvas,
                        child: LayoutBuilder(
                          builder: (context, c) {
                            imageSize = c.biggest;
                            return InteractiveViewer(
                              transformationController: transform,
                              minScale: 1,
                              maxScale: 4,
                              child: SizedBox.expand(
                                child: FashionImage(
                                  '${image['url']}',
                                  label:
                                      '${image['alt'] ?? widget.productName}',
                                  fit: BoxFit.contain,
                                  alignment: Alignment.center,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Ảnh trước',
                        onPressed: index > 0 ? () => move(-1) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Text(
                          'Ảnh ${index + 1} / ${widget.images.length}',
                          style: T.body,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ảnh tiếp theo',
                        onPressed: index + 1 < widget.images.length
                            ? () => move(1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                      ValueListenableBuilder<Matrix4>(
                        valueListenable: transform,
                        builder: (_, matrix, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Thu nhỏ',
                              onPressed: matrix.getMaxScaleOnAxis() > 1.01
                                  ? () => zoom(matrix.getMaxScaleOnAxis() - .5)
                                  : null,
                              icon: const Icon(Icons.remove),
                            ),
                            TextButton(
                              onPressed: () => zoom(1),
                              child: Text(
                                '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                              ),
                            ),
                            IconButton(
                              tooltip: 'Phóng to',
                              onPressed: matrix.getMaxScaleOnAxis() < 3.99
                                  ? () => zoom(matrix.getMaxScaleOnAxis() + .5)
                                  : null,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
