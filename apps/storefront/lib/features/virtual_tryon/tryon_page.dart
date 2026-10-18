import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/ai_providers.dart';
import '../../app/activity.dart';
import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../domain/ai.dart';

import 'image_validation.dart';
import 'private_image.dart';
import 'tryon_results.dart';

class TryOnPage extends ConsumerStatefulWidget {
  const TryOnPage({super.key, this.slug});
  final String? slug;
  @override
  ConsumerState<TryOnPage> createState() => _TryOnPageState();
}

class _TryOnPageState extends ConsumerState<TryOnPage> {
  Uint8List? bytes;
  String? imageName, error, selectedSlug, sku;
  bool consent = false, picking = false;
  TryOnJob? job;
  String scenario = 'success';
  int attempts = 0;
  int selectionVersion = 0;
  StreamSubscription<TryOnJob>? subscription;
  late TryOnRepository repo;
  bool get busy =>
      job?.status == TryOnStatus.queued ||
      job?.status == TryOnStatus.processing;
  @override
  void initState() {
    super.initState();
    selectedSlug = widget.slug;
    repo = ref.read(tryOnRepositoryProvider);
  }

  @override
  void dispose() {
    selectionVersion++;
    repo.cancel();
    subscription?.cancel();
    unawaited(evictPrivateImage(bytes));
    bytes = null;
    super.dispose();
  }

  Future<void> pick() async {
    if (picking || busy) return;
    final version = ++selectionVersion;
    repo.cancel();
    subscription?.cancel();
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'JPEG / PNG',
            extensions: ['jpg', 'jpeg', 'png'],
            mimeTypes: ['image/jpeg', 'image/png'],
          ),
        ],
      );
      if (!mounted || version != selectionVersion) {
        return;
      }
      if (file == null) {
        setState(
          () => error = 'Đã hủy chọn ảnh. Bạn có thể chọn lại khi sẵn sàng.',
        );
        return;
      }
      if (await file.length() > 8 * 1024 * 1024) {
        throw StateError('Ảnh vượt 8 MB. Hãy chọn ảnh nhỏ hơn.');
      }
      final data = await file.readAsBytes();
      if (!mounted || version != selectionVersion) return;
      final invalid = validateImage(data);
      if (invalid != null) {
        throw StateError(invalid);
      }
      // ImageDescriptor.width/height are unsupported by the web engine.
      // A decoded frame exposes dimensions on both web and native platforms.
      final codec = await ui.instantiateImageCodec(data);
      bool tooLarge;
      try {
        final frame = await codec.getNextFrame();
        tooLarge = frame.image.width * frame.image.height > 12000000;
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      if (tooLarge) {
        throw StateError(
          'Ảnh vượt 12 megapixel. Giảm kích thước ảnh rồi thử lại.',
        );
      }
      if (mounted && version == selectionVersion) {
        unawaited(evictPrivateImage(bytes));
        setState(() {
          bytes = data;
          imageName = file.name;
          job = null;
          attempts = 0;
          consent = false;
        });
      }
    } catch (e) {
      if (mounted && version == selectionVersion) {
        setState(() => error = 'Không đọc được ảnh. $e');
      }
    } finally {
      if (mounted && version == selectionVersion) {
        setState(() => picking = false);
      }
    }
  }

  void run() {
    if (picking || busy) return;
    if (bytes == null || !consent || sku == null) {
      setState(
        () => error =
            'Chọn trang phục, ảnh và đồng ý xử lý ảnh trước khi tạo bản demo.',
      );
      return;
    }
    if (attempts >= 3) {
      setState(
        () => error = 'Đã thử 3 lần. Xóa ảnh để bắt đầu phiên demo mới.',
      );
      return;
    }
    setState(() {
      error = null;
      attempts++;
      job = const TryOnJob('pending', TryOnStatus.queued);
    });
    subscription?.cancel();
    final version = ++selectionVersion;
    final runSlug = selectedSlug!;
    final runSku = sku!;
    subscription = repo
        .create(consent: consent, sku: sku!, scenario: scenario)
        .listen(
          (value) {
            if (mounted && version == selectionVersion) {
              ref
                  .read(activityProvider.notifier)
                  .add('Virtual Try-On', value.status.name);
              setState(() => job = value);
              if (value.status == TryOnStatus.succeeded) {
                ref
                    .read(tryOnResultsProvider.notifier)
                    .save(
                      TryOnResult(id: value.id, slug: runSlug, sku: runSku),
                    );
              }
            }
          },
          onError: (Object e) {
            if (mounted && version == selectionVersion) {
              setState(() {
                error = '$e';
                job = TryOnJob('error', TryOnStatus.failed, error: '$e');
              });
            }
          },
        );
  }

  void clear() {
    if (job != null) ref.read(tryOnResultsProvider.notifier).remove(job!.id);
    selectionVersion++;
    repo.cancel();
    subscription?.cancel();
    unawaited(evictPrivateImage(bytes));
    setState(() {
      bytes = null;
      imageName = null;
      job = null;
      consent = false;
      error = null;
      attempts = 0;
      picking = false;
    });
    toast(context, 'Đã xóa ảnh và kết quả khỏi phiên demo.');
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tryOnRepositoryProvider);
    final data = ref.watch(allProductsProvider);
    final compact = MediaQuery.sizeOf(context).width < 850;
    final step = sku == null
        ? 1
        : bytes == null
        ? 2
        : !consent
        ? 3
        : 4;
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phòng thử của bạn.',
            style: T.display(MediaQuery.sizeOf(context).width < 600 ? 36 : 48),
          ),
          TextButton.icon(
            onPressed: () => context.go('/account/try-ons'),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('Xem lịch sử thử đồ'),
          ),
          const SizedBox(height: 16),
          const DemoNotice(
            text:
                'Bản demo không kết nối AI. Ảnh chỉ nằm trong bộ nhớ của tab, không được tải lên mạng.',
          ),
          const SizedBox(height: 28),
          Semantics(
            liveRegion: true,
            child: Text(
              'Bước $step / 4 · ${['Chọn trang phục và size', 'Chọn ảnh của bạn', 'Xác nhận đồng ý', 'Tạo bản thử đồ'][step - 1]}',
              style: T.body.copyWith(
                fontWeight: FontWeight.w600,
                color: T.accent,
              ),
            ),
          ),
          if (!compact)
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                for (final step in [
                  '1. Trang phục',
                  '2. Ảnh của bạn',
                  '3. Đồng ý',
                  '4. Xem bản demo',
                ])
                  Text(step, style: T.body.copyWith(color: T.accent)),
              ],
            ),
          const SizedBox(height: 32),
          data.when(
            data: (page) {
              final products = page.items.where((p) => p.tryOn).toList();
              final p =
                  products.where((p) => p.slug == selectedSlug).firstOrNull ??
                  products.firstOrNull;
              if (p == null) {
                return const StatePanel(
                  title: 'Chưa có trang phục tương thích',
                  message: 'Hãy quay lại sau khi catalog được cập nhật.',
                );
              }
              selectedSlug = p.slug;
              final choose = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(p.slug),
                    isExpanded: true,
                    initialValue: p.slug,
                    decoration: const InputDecoration(
                      labelText: 'Trang phục muốn thử',
                    ),
                    items: products
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.slug,
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            selectedSlug = v;
                            sku = null;
                            job = null;
                          }),
                  ),
                  const SizedBox(height: 20),
                  if (!compact)
                    LayoutBuilder(
                      builder: (_, c) => SizedBox(
                        width: double.infinity,
                        height: (c.maxWidth * 1.25).clamp(0, 420),
                        child: ColoredBox(
                          color: T.photo,
                          child: FashionImage(
                            p.image,
                            label: p.name,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                          ),
                        ),
                      ),
                    ),
                  if (compact)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 64,
                          height: 80,
                          child: FashionImage(p.image, label: p.name),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: T.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Chọn màu và size bên dưới để tiếp tục.',
                                style: T.small,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    key: ValueKey('variant-${p.slug}'),
                    isExpanded: true,
                    initialValue: sku,
                    decoration: const InputDecoration(
                      labelText: 'Chọn màu và size',
                    ),
                    items: p.variants
                        .where((v) => v.stock > 0)
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.sku,
                            child: Text('${v.color} / ${v.size}'),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            sku = v;
                            job = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go('/products/${p.slug}'),
                    child: const Text('Xem sản phẩm & bảng size'),
                  ),
                ],
              );
              final workspace = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hình dung một cách phối mới.', style: T.display(30)),
                  const SizedBox(height: 16),
                  const Text(
                    'Chọn ảnh đứng rõ trang phục, đủ sáng, tối đa 8 MB / 12 MP. Chỉ dùng ảnh bạn có quyền sử dụng. Không cần ảnh để trò chuyện với Stylist.',
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: T.canvas,
                      border: Border.all(color: T.line),
                      borderRadius: T.radius,
                    ),
                    child: bytes == null
                        ? Column(
                            children: [
                              const Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 40,
                                color: T.accent,
                              ),
                              const SizedBox(height: 20),
                              const Text('Ảnh của bạn, trong phiên của bạn.'),
                              const SizedBox(height: 8),
                              const Text(
                                'JPEG hoặc PNG · Không lưu dài hạn',
                                style: T.small,
                              ),
                              const SizedBox(height: 24),
                              AppButton(
                                'Chọn ảnh từ thiết bị',
                                busy: picking,
                                onPressed: pick,
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              SizedBox(
                                height: 300,
                                child: Image.memory(
                                  bytes!,
                                  fit: BoxFit.contain,
                                  semanticLabel:
                                      'Ảnh đầu vào của bạn, chưa xử lý',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(imageName ?? 'Ảnh đã chọn', style: T.small),
                              Wrap(
                                spacing: 12,
                                children: [
                                  TextButton(
                                    onPressed: busy || picking ? null : pick,
                                    child: const Text('Đổi ảnh'),
                                  ),
                                  TextButton(
                                    onPressed: clear,
                                    child: const Text('Xóa ảnh & kết quả'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 20),
                  CheckboxListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => consent = v ?? false),
                    title: const Text(
                      'Tôi có quyền sử dụng ảnh và đồng ý giữ ảnh trong bộ nhớ của phiên demo.',
                      style: T.body,
                    ),
                    subtitle: const Text(
                      'Không gửi ảnh đến nhà cung cấp AI. Rời trang sẽ xóa ảnh.',
                      style: T.small,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                    'Tạo bản thử đồ demo',
                    busy: busy,
                    onPressed:
                        !picking &&
                            !busy &&
                            bytes != null &&
                            consent &&
                            sku != null &&
                            attempts < 3
                        ? run
                        : null,
                  ),
                  if (attempts >= 3 && !busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Đã dùng 3 lần thử của phiên demo. Xóa ảnh để bắt đầu lại.',
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: const TextStyle(color: T.danger),
                      ),
                    ),
                  if (job != null) ...[
                    const SizedBox(height: 24),
                    TryOnStatusPanel(
                      job: job!,
                      onCancel: () {
                        selectionVersion++;
                        repo.cancel();
                        subscription?.cancel();
                        setState(
                          () => job = TryOnJob(job!.id, TryOnStatus.cancelled),
                        );
                      },
                      onRetry: !picking && attempts < 3 ? run : null,
                    ),
                  ],
                  if (job?.status == TryOnStatus.succeeded) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      color: T.soft,
                      child: Column(
                        children: [
                          const Icon(
                            Icons.compare_outlined,
                            size: 36,
                            color: T.accent,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Ảnh minh họa giao diện – không phải kết quả AI thực tế',
                            style: T.body.copyWith(fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Ảnh đầu vào ở trên được giữ nguyên. Khi kết nối AI, kết quả mặc thử sẽ xuất hiện tại đây. Bản demo không tạo ảnh biến đổi và không xác nhận độ vừa vặn.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          AppButton(
                            'Xem trang kết quả',
                            outlined: true,
                            onPressed: () =>
                                context.go('/virtual-try-on/${job!.id}'),
                          ),
                          const SizedBox(height: 12),
                          AppButton(
                            'Trở lại chọn size & mua',
                            onPressed: () => context.go('/products/${p.slug}'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Kịch bản kiểm thử demo', style: T.small),
                    children: [
                      DropdownButton<String>(
                        isExpanded: true,
                        value: scenario,
                        items: const [
                          DropdownMenuItem(
                            value: 'success',
                            child: Text('Hoàn tất mô phỏng'),
                          ),
                          DropdownMenuItem(
                            value: 'error',
                            child: Text('Xử lý thất bại'),
                          ),
                          DropdownMenuItem(
                            value: 'timeout',
                            child: Text('Quá thời gian xử lý'),
                          ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(() => scenario = v!),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(
                                () => error =
                                    'Không có quyền truy cập ảnh (mô phỏng). Hãy chọn ảnh bằng trình chọn tệp hoặc kiểm tra quyền của trình duyệt.',
                              ),
                        child: const Text('Mô phỏng từ chối quyền'),
                      ),
                    ],
                  ),
                ],
              );
              return LayoutBuilder(
                builder: (_, c) => c.maxWidth < 850
                    ? Column(
                        children: [
                          choose,
                          const SizedBox(height: 32),
                          workspace,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: choose),
                          const SizedBox(width: 56),
                          Expanded(flex: 6, child: workspace),
                        ],
                      ),
              );
            },
            error: (_, _) => StatePanel(
              title: 'Chưa tải được trang phục',
              message: 'Thử lại kết nối catalog.',
              action: AppButton(
                'Thử lại',
                onPressed: () => ref.invalidate(allProductsProvider),
              ),
            ),
            loading: () => const LoadingPanel(),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class TryOnStatusPanel extends StatelessWidget {
  const TryOnStatusPanel({
    super.key,
    required this.job,
    required this.onCancel,
    this.onRetry,
  });
  final TryOnJob job;
  final VoidCallback onCancel;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final label = switch (job.status) {
      TryOnStatus.queued => 'Đang chờ lượt mô phỏng',
      TryOnStatus.processing => 'Đang xử lý bản demo',
      TryOnStatus.succeeded => 'Đã hoàn tất luồng mô phỏng',
      TryOnStatus.failed => 'Chưa tạo được bản demo',
      TryOnStatus.cancelled => 'Đã hủy xử lý',
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        color: T.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (job.status == TryOnStatus.queued ||
                job.status == TryOnStatus.processing) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: job.status == TryOnStatus.queued ? 0.25 : 0.65,
              ),
              TextButton(onPressed: onCancel, child: const Text('Hủy xử lý')),
            ],
            if (job.status == TryOnStatus.failed) ...[
              const SizedBox(height: 12),
              Text(job.error ?? 'Thử lại với kịch bản thành công.'),
              const SizedBox(height: 12),
              AppButton('Thử lại', outlined: true, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
