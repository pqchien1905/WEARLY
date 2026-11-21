import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../app/api_providers.dart';
import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_tryon.dart';
import '../../data/tryon_pending_store.dart';
import '../../domain/catalog.dart';
import 'image_validation.dart';
import 'private_image.dart';
import 'private_remote_image.dart';

class RemoteTryOnPage extends ConsumerStatefulWidget {
  const RemoteTryOnPage({super.key, this.slug, this.jobId});
  final String? slug, jobId;
  @override
  ConsumerState<RemoteTryOnPage> createState() => _RemoteTryOnPageState();
}

class _RemoteTryOnPageState extends ConsumerState<RemoteTryOnPage> {
  late final repo = RemoteTryOnRepository(ref.read(apiClientProvider));
  late final pendingStore = ref.read(tryOnPendingStoreProvider);
  late final owner = repo.api.tokens.userId ?? '';
  late final catalog = ref.read(productRepositoryProvider);
  final search = TextEditingController();
  List<Product> products = [];
  List<PrivateImageAsset> images = [];
  RemoteTryOnStatus? info;
  PrivateImageAsset? photo;
  RemoteTryOnJob? job;
  Uint8List? draft;
  String? draftType, selectedSlug, sku, error, loadError;
  String? uploadKey, requestKey, submittedImage, submittedSku;
  bool loading = true, busy = false, picking = false, uploadPending = false;
  bool uploadConsent = false, aiConsent = false, hidePrivate = false;
  int version = 0, polls = 0;
  Timer? timer;
  bool get unresolved => requestKey != null && (job == null || job!.pending);
  bool get locked =>
      loading ||
      busy ||
      picking ||
      uploadPending ||
      unresolved ||
      job?.pending == true ||
      loadError != null;
  Product? get product =>
      products.where((p) => p.slug == selectedSlug).firstOrNull;
  ProductVariant? get variant =>
      product?.variants.where((v) => v.sku == sku && v.stock > 0).firstOrNull;
  bool get canStart =>
      !locked &&
      aiConsent &&
      photo != null &&
      variant != null &&
      info?.configured == true &&
      info!.remaining > 0;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    version++;
    timer?.cancel();
    search.dispose();
    unawaited(evictPrivateImage(draft));
    draft = null;
    super.dispose();
  }

  bool current(int value) => mounted && value == version;
  void clearPending(String kind, String key) {
    try {
      pendingStore.clear(owner, kind, key);
    } catch (e) {
      loadError = tryonError(e);
    }
  }

  List<Product> eligible(ProductPage page) => page.items
      .where((p) => p.active && p.tryOn && p.variants.any((v) => v.stock > 0))
      .toList();
  void chooseProduct(String? slug, {String? preferredSku}) {
    selectedSlug = slug;
    final variants =
        product?.variants.where((v) => v.stock > 0).toList() ??
        <ProductVariant>[];
    sku = variants.any((v) => v.sku == preferredSku)
        ? preferredSku
        : variants.length == 1
        ? variants.single.sku
        : null;
  }

  Future<void> load() async {
    final mark = ++version;
    timer?.cancel();
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final pendingJob = pendingStore.read(owner, 'job');
      final pendingUpload = pendingStore.read(owner, 'upload');
      final values = await Future.wait<Object?>([
        repo.status(),
        repo.images(),
        repo.jobs(),
        catalog.list(const ProductQuery(limit: 100, inStock: true)),
        widget.slug == null ? Future.value(null) : catalog.bySlug(widget.slug!),
        widget.jobId == null ? Future.value(null) : repo.get(widget.jobId!),
        pendingUpload == null
            ? Future.value(null)
            : repo.uploadStatus(pendingUpload.key),
      ]);
      if (!current(mark)) return;
      final uploadState =
          values[6] as ({String state, PrivateImageAsset? image})?;
      if (pendingUpload != null &&
          ['available', 'unavailable'].contains(uploadState?.state)) {
        clearPending('upload', pendingUpload.key);
      }
      final jobs = values[2] as List<RemoteTryOnJob>;
      final pendingResult = pendingJob == null
          ? null
          : jobs.where((j) => j.requestKey == pendingJob.key).firstOrNull;
      if (pendingResult != null && !pendingResult.pending) {
        clearPending('job', pendingJob!.key);
      }
      setState(() {
        info = values[0] as RemoteTryOnStatus;
        images = values[1] as List<PrivateImageAsset>;
        products = eligible(values[3] as ProductPage);
        final requested = values[4] as Product?;
        if (requested != null &&
            requested.active &&
            requested.tryOn &&
            !products.any((p) => p.id == requested.id)) {
          products.insert(0, requested);
        }
        job = pendingJob != null
            ? pendingResult
            : values[5] as RemoteTryOnJob? ?? jobs.firstOrNull;
        submittedImage = pendingJob?.imageId;
        submittedSku = pendingJob?.sku;
        photo =
            images
                .where((p) => p.id == (pendingJob?.imageId ?? job?.imageId))
                .firstOrNull ??
            images.firstOrNull;
        final previousProduct = products
            .where(
              (p) =>
                  p.variants.any((v) => v.sku == (pendingJob?.sku ?? job?.sku)),
            )
            .firstOrNull;
        chooseProduct(
          (pendingJob != null || widget.jobId != null
                  ? previousProduct?.slug
                  : requested?.slug) ??
              previousProduct?.slug ??
              requested?.slug ??
              (products.length == 1 ? products.single.slug : null),
          preferredSku: pendingJob?.sku ?? job?.sku,
        );
        requestKey = pendingJob?.key ?? job?.requestKey;
        uploadPending =
            pendingJob == null &&
            pendingUpload != null &&
            !['available', 'unavailable'].contains(uploadState?.state);
        uploadKey = uploadPending ? pendingUpload?.key : null;
        if (uploadPending) {
          photo = null;
          job = null;
          requestKey = null;
        }
        if (uploadState?.image != null) {
          photo = uploadState!.image;
          if (!images.any((p) => p.id == photo!.id)) images.insert(0, photo!);
        }
        polls = 0;
        hidePrivate = false;
        error = job?.errorCode == null ? null : tryonError(job!.errorCode!);
      });
      schedule();
    } catch (e) {
      if (current(mark)) setState(() => loadError = tryonError(e));
    } finally {
      if (current(mark)) setState(() => loading = false);
    }
  }

  Future<void> updateStatus(int mark) async {
    try {
      final value = await repo.status();
      if (current(mark)) setState(() => info = value);
    } catch (_) {
      /* A later explicit refresh can recover usage. */
    }
  }

  Future<void> searchProducts() async {
    if (locked) return;
    final mark = version;
    setState(() => busy = true);
    try {
      final value = await catalog.list(
        ProductQuery(search: search.text.trim(), limit: 100, inStock: true),
      );
      if (current(mark)) {
        setState(() {
          products = eligible(value);
          if (!products.any((p) => p.slug == selectedSlug)) chooseProduct(null);
        });
      }
    } catch (e) {
      if (current(mark)) setState(() => error = tryonError(e));
    } finally {
      if (current(mark)) setState(() => busy = false);
    }
  }

  Future<void> pick() async {
    if (locked &&
        !(uploadPending &&
            !loading &&
            !busy &&
            !picking &&
            !unresolved &&
            loadError == null)) {
      return;
    }
    final mark = ++version;
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
      if (!current(mark) || file == null) return;
      if (await file.length() > 8 * 1024 * 1024) {
        throw StateError('Ảnh vượt 8 MB.');
      }
      final bytes = await file.readAsBytes();
      if (!current(mark)) return;
      final invalid = validateImage(bytes);
      if (invalid != null) throw StateError(invalid);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          if (codec.frameCount != 1 ||
              frame.image.width < 64 ||
              frame.image.height < 64 ||
              frame.image.width > 8192 ||
              frame.image.height > 8192 ||
              frame.image.width * frame.image.height > 16000000) {
            throw StateError(
              'Chọn ảnh tĩnh, từ 64 đến 8192 pixel mỗi chiều và tối đa 16 megapixel.',
            );
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (!current(mark)) return;
      unawaited(evictPrivateImage(draft));
      setState(() {
        draft = bytes;
        draftType = bytes[0] == 137 ? 'image/png' : 'image/jpeg';
        photo = null;
        job = null;
        uploadConsent = false;
        aiConsent = false;
        if (!uploadPending) uploadKey = null;
        requestKey = null;
        hidePrivate = false;
      });
    } catch (e) {
      if (current(mark)) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Không đọc được ảnh. Hãy chọn JPEG hoặc PNG khác.',
        );
      }
    } finally {
      if (current(mark)) setState(() => picking = false);
    }
  }

  void acceptPhoto(PrivateImageAsset value) {
    if (uploadKey != null) clearPending('upload', uploadKey!);
    unawaited(evictPrivateImage(draft));
    setState(() {
      photo = value;
      draft = null;
      draftType = null;
      uploadKey = null;
      uploadPending = false;
      aiConsent = false;
      if (!images.any((p) => p.id == value.id)) images.insert(0, value);
    });
  }

  Future<void> upload() async {
    if (busy || draft == null || !uploadConsent) return;
    final mark = version;
    final key = uploadKey ?? const Uuid().v4();
    try {
      pendingStore.save(owner, 'upload', PendingTryOn(key));
    } catch (e) {
      setState(() => error = tryonError(e));
      return;
    }
    uploadKey = key;
    setState(() {
      busy = true;
      uploadPending = true;
      error = null;
    });
    try {
      final value = await repo.upload(
        uploadKey!,
        draft!,
        draftType!,
        consent: true,
      );
      if (current(mark)) acceptPhoto(value);
    } catch (e) {
      if (current(mark)) {
        setState(() {
          error = tryonError(e);
          // A rejected reselection does not settle the original in-flight upload.
          if (e is ApiException && e.code == 'UPLOAD_UNAVAILABLE') {
            clearPending('upload', uploadKey!);
            uploadPending = false;
            uploadKey = null;
          }
        });
      }
    } finally {
      if (current(mark)) setState(() => busy = false);
    }
  }

  Future<void> recoverUpload() async {
    if (busy || uploadKey == null) return;
    final mark = version;
    setState(() {
      busy = true;
      error = null;
    });
    var missing = false;
    try {
      final status = await repo.uploadStatus(uploadKey!);
      if (!current(mark)) return;
      if (status.image != null) {
        acceptPhoto(status.image!);
      } else if (status.state == 'unavailable') {
        clearPending('upload', uploadKey!);
        setState(() {
          uploadPending = false;
          uploadKey = null;
          error =
              'Ảnh trước không còn khả dụng. Bạn có thể chọn và gửi ảnh mới.';
        });
      } else if (status.state == 'processing') {
        setState(
          () => error = 'Ảnh đang được lưu. Hãy kiểm tra lại sau ít giây.',
        );
      } else if (draft != null && uploadConsent) {
        missing = true;
      } else {
        setState(
          () => error =
              'Chọn lại đúng ảnh trước đó và đồng ý lưu để tiếp tục cùng yêu cầu.',
        );
      }
    } catch (e) {
      if (current(mark)) setState(() => error = tryonError(e));
    } finally {
      if (current(mark)) setState(() => busy = false);
    }
    if (missing && current(mark)) await upload();
  }

  Future<void> start() async {
    if (!canStart) return;
    final key = const Uuid().v4();
    try {
      pendingStore.save(
        owner,
        'job',
        PendingTryOn(key, imageId: photo!.id, sku: sku!),
      );
    } catch (e) {
      setState(() => error = tryonError(e));
      return;
    }
    requestKey = key;
    submittedImage = photo!.id;
    submittedSku = sku;
    polls = 0;
    setState(() {
      job = null;
      error = null;
    });
    await submit();
  }

  Future<void> submit() async {
    if (busy ||
        requestKey == null ||
        submittedImage == null ||
        submittedSku == null) {
      return;
    }
    final mark = version;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await repo.create(
        requestKey!,
        submittedImage!,
        submittedSku!,
        consent: true,
      );
      if (current(mark)) acceptJob(value);
    } catch (e) {
      if (current(mark)) {
        setState(() {
          error = tryonError(e);
          if (e is ApiException &&
              ([400, 401, 403, 404, 409, 429].contains(e.status) ||
                  e.code == 'AI_PROVIDER_NOT_CONFIGURED')) {
            clearPending('job', requestKey!);
            requestKey = null;
          }
        });
      }
    } finally {
      if (current(mark)) {
        setState(() => busy = false);
        unawaited(updateStatus(mark));
      }
    }
  }

  void acceptJob(RemoteTryOnJob value) {
    if (!value.pending && requestKey != null) clearPending('job', requestKey!);
    setState(() {
      job = value;
      requestKey = value.requestKey;
      error = value.errorCode == null ? null : tryonError(value.errorCode!);
    });
    schedule();
  }

  void schedule() {
    timer?.cancel();
    if (job?.pending == true && ++polls <= 60) {
      timer = Timer(const Duration(seconds: 2), () {
        unawaited(recover());
      });
    }
  }

  Future<void> recover() async {
    if (busy || (requestKey == null && job == null)) return;
    final mark = version;
    timer?.cancel();
    setState(() {
      busy = true;
      error = null;
    });
    var missing = false;
    try {
      final value = job != null
          ? await repo.get(job!.id)
          : (await repo.jobs())
                .where((j) => j.requestKey == requestKey)
                .firstOrNull;
      if (!current(mark)) return;
      if (value != null) {
        acceptJob(value);
      } else {
        missing = true;
      }
    } catch (e) {
      if (current(mark)) setState(() => error = tryonError(e));
    } finally {
      if (current(mark)) setState(() => busy = false);
    }
    if (!current(mark)) return;
    if (missing) {
      await submit();
    } else {
      unawaited(updateStatus(mark));
    }
  }

  Future<void> remove() async {
    if (loading || busy || picking) return;
    final id = photo?.id;
    final mark = ++version;
    timer?.cancel();
    unawaited(evictPrivateImage(draft));
    setState(() {
      hidePrivate = true;
      draft = null;
      busy = true;
      error = null;
    });
    try {
      if (id != null) await repo.deleteImage(id);
      if (current(mark)) {
        if (requestKey != null) clearPending('job', requestKey!);
        if (uploadKey != null) clearPending('upload', uploadKey!);
        setState(() {
          images.removeWhere((p) => p.id == id);
          photo = null;
          job = null;
          requestKey = null;
          uploadKey = null;
          uploadPending = false;
          aiConsent = false;
          uploadConsent = false;
        });
      }
    } catch (e) {
      if (current(mark)) {
        setState(() => error = 'Chưa xóa được ảnh. ${tryonError(e)}');
      }
    } finally {
      if (current(mark)) {
        setState(() => busy = false);
        unawaited(updateStatus(mark));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ảnh của bạn', style: T.display(26)),
        const SizedBox(height: 16),
        if (!hidePrivate && draft != null)
          Image.memory(
            draft!,
            height: 300,
            fit: BoxFit.contain,
            semanticLabel: 'Ảnh đã chọn trên thiết bị',
          ),
        if (!hidePrivate && photo != null)
          PrivateRemoteImage(
            key: ValueKey('source-${photo!.id}'),
            load: () => repo.photo(photo!.id),
            label: 'Ảnh gốc riêng tư',
          ),
        const SizedBox(height: 16),
        AppButton(
          uploadPending
              ? 'Chọn lại ảnh để tiếp tục'
              : draft == null && photo == null
              ? 'Chọn ảnh từ thiết bị'
              : 'Đổi ảnh',
          outlined: true,
          busy: picking,
          onPressed:
              locked &&
                  !(uploadPending &&
                      !loading &&
                      !busy &&
                      !picking &&
                      !unresolved &&
                      loadError == null)
              ? null
              : pick,
        ),
        const SizedBox(height: 8),
        const Text(
          'JPEG / PNG, tối đa 8 MB và 16 megapixel. Ảnh được lưu riêng tư tối đa 24 giờ.',
          style: T.small,
        ),
        if (images.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: DropdownButtonFormField<String>(
              key: ValueKey('photo-${photo?.id}'),
              initialValue: photo?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ảnh đã lưu'),
              items: images
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text('Ảnh ${_date(p.createdAt.toLocal())}'),
                    ),
                  )
                  .toList(),
              onChanged: locked
                  ? null
                  : (id) {
                      version++;
                      timer?.cancel();
                      unawaited(evictPrivateImage(draft));
                      setState(() {
                        photo = images.firstWhere((p) => p.id == id);
                        draft = null;
                        job = null;
                        requestKey = null;
                        aiConsent = false;
                        hidePrivate = false;
                      });
                    },
            ),
          ),
        if (draft != null) ...[
          CheckboxListTile(
            key: const ValueKey('tryon-upload-consent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: uploadConsent,
            onChanged: busy
                ? null
                : (v) => setState(() => uploadConsent = v ?? false),
            title: const Text(
              'Tôi đồng ý lưu ảnh này tại cửa hàng để thử đồ và có quyền sử dụng ảnh.',
            ),
          ),
        ],
        if (draft != null || uploadPending)
          AppButton(
            uploadPending ? 'Kiểm tra ảnh đã gửi' : 'Lưu ảnh riêng tư',
            busy: busy && uploadPending,
            onPressed: busy || picking
                ? null
                : uploadPending
                ? recoverUpload
                : uploadConsent
                ? upload
                : null,
          ),
        if (photo != null || draft != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppButton(
              'Xóa ảnh và các kết quả',
              outlined: true,
              onPressed: loading || busy || picking || uploadPending
                  ? null
                  : remove,
            ),
          ),
        if (photo != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Thời hạn ảnh: ${_date(photo!.expiresAt.toLocal())}',
              style: T.small,
            ),
          ),
      ],
    );
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Trang phục muốn thử', style: T.display(26)),
        const SizedBox(height: 16),
        TextField(
          controller: search,
          enabled: !locked,
          decoration: const InputDecoration(labelText: 'Tìm trang phục'),
          onSubmitted: (_) => searchProducts(),
        ),
        const SizedBox(height: 8),
        AppButton(
          'Tìm sản phẩm',
          outlined: true,
          onPressed: locked ? null : searchProducts,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('product-$selectedSlug'),
          initialValue: selectedSlug,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Chọn trang phục'),
          items: products
              .map(
                (p) => DropdownMenuItem(
                  value: p.slug,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: locked ? null : (v) => setState(() => chooseProduct(v)),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('sku-$sku'),
          initialValue: sku,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Chọn màu và size'),
          items: (product?.variants ?? <ProductVariant>[])
              .where((v) => v.stock > 0)
              .map(
                (v) => DropdownMenuItem(
                  value: v.sku,
                  child: Text(
                    '${v.color} / ${v.size} — ${money(v.price)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: locked || product == null
              ? null
              : (v) => setState(() => sku = v),
        ),
        if (product != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: SizedBox(
              height: 200,
              child: FashionImage(
                product!.image,
                label: product!.name,
                fit: BoxFit.contain,
              ),
            ),
          ),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const ValueKey('tryon-ai-consent'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: aiConsent,
          onChanged: locked
              ? null
              : (v) => setState(() => aiConsent = v ?? false),
          title: const Text(
            'Tôi đồng ý gửi ảnh của mình và ảnh trang phục tới Google Gemini để tạo ảnh thử đồ.',
          ),
        ),
        AppButton(
          job == null ? 'Thử trang phục' : 'Thử lượt mới',
          icon: Icons.auto_awesome_outlined,
          onPressed: canStart ? start : null,
        ),
        if (unresolved || job?.pending == true)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppButton(
              'Kiểm tra yêu cầu đã gửi',
              busy: busy,
              onPressed: busy ? null : recover,
            ),
          ),
        const SizedBox(height: 16),
        if (job != null) ...[
          Text(
            job!.resultAvailable
                ? 'Đã tạo ảnh thử đồ'
                : job!.pending
                ? 'Đang xử lý ảnh thử đồ'
                : 'Yêu cầu đã kết thúc',
            style: T.body.copyWith(fontWeight: FontWeight.w600),
          ),
          Text('Trang phục: ${job!.sku}', style: T.small),
          Text(
            'Chi phí dịch vụ ước tính của lượt này: ${money(job!.estimatedCost)}. Không cộng vào đơn hàng.',
            style: T.small,
          ),
        ],
        if (!hidePrivate && job?.resultAvailable == true)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: PrivateRemoteImage(
              key: ValueKey('result-${job!.id}'),
              load: () => repo.result(job!.id),
              label: 'Ảnh thử đồ do Gemini tạo',
            ),
          ),
      ],
    );
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phòng thử của bạn.',
            style: T.display(MediaQuery.sizeOf(context).width < 600 ? 36 : 48),
          ),
          const SizedBox(height: 12),
          const Text(
            'Xem trang phục trên ảnh của bạn. Ảnh AI mô phỏng vẻ ngoài, không đảm bảo độ vừa vặn.',
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.go('/account/try-ons'),
            child: const Text('Xem lịch sử thử đồ'),
          ),
          if (loading) const LinearProgressIndicator(),
          if (loadError != null)
            StatePanel(
              title: 'Chưa tải được phòng thử',
              message: loadError!,
              action: AppButton(
                'Tải lại phòng thử',
                onPressed: loading ? null : load,
              ),
            ),
          if (info != null) ...[
            if (!info!.configured)
              const StatePanel(
                title: 'Gemini chưa được cấu hình',
                message:
                    'Dịch vụ đang chờ cửa hàng kích hoạt. Các ảnh đã lưu vẫn có thể được xem và xóa.',
              ),
            Text(
              'Đã dùng ${info!.used} / ${info!.limit} lượt hôm nay · Còn ${info!.remaining} lượt',
              style: T.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Chi phí dịch vụ ước tính: ${money(info!.estimatedPerRequest)} / lượt; hôm nay ${money(info!.estimatedUsed)}. Không cộng vào tiền hàng.',
              style: T.small,
            ),
            Text(
              'Đặt lại hạn mức: ${_date(info!.resetsAt.toLocal())}. Yêu cầu đã tiếp nhận tính một lượt, kể cả khi không tạo được ảnh.',
              style: T.small,
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (_, c) => c.maxWidth < 850
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SurfacePanel(tinted: true, child: source),
                      const SizedBox(height: 24),
                      SurfacePanel(child: controls),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SurfacePanel(tinted: true, child: source),
                      ),
                      const SizedBox(width: 24),
                      Expanded(child: SurfacePanel(child: controls)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime date) =>
      '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
