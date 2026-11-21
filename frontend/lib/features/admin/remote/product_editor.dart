import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/catalog_image.dart';
import '../../../core/widgets/primitives.dart';
import '../../../data/commerce_json.dart';
import '../../virtual_tryon/image_validation.dart';
import 'product_variants.dart';
import 'product_editor_widgets.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'product_widgets.dart';

export 'product_variants.dart' show ProductVariantSection;

class RemoteProductEditor extends ConsumerWidget {
  const RemoteProductEditor({super.key, this.id, this.returnTo});
  final String? id, returnTo;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AdminAsync(
    value: ref.watch(adminReferencesProvider),
    reload: () => ref.invalidate(adminReferencesProvider),
    builder: (references) {
      if (id == null) {
        return _ProductForm(references: references, returnTo: returnTo);
      }
      final key = (kind: 'products', id: id!);
      final value = ref.watch(adminDetailProvider(key));
      if (value.error case ApiException(status: 404)) {
        return StatePanel(
          title: 'Không tìm thấy sản phẩm',
          message: 'Sản phẩm không còn tồn tại hoặc đường dẫn không đúng.',
          action: AppButton(
            'Về danh sách sản phẩm',
            onPressed: () => context.go(productsBack(returnTo)),
          ),
        );
      }
      return AdminAsync(
        value: value,
        reload: () => ref.invalidate(adminDetailProvider(key)),
        builder: (product) => _ProductForm(
          key: ValueKey(id),
          product: product,
          references: references,
          returnTo: returnTo,
        ),
      );
    },
  );
}

class _ImageFields {
  _ImageFields(AdminRecord image)
    : url = TextEditingController(text: image['url'] ?? ''),
      alt = TextEditingController(text: image['alt'] ?? ''),
      color = TextEditingController(text: image['color'] ?? '');
  final TextEditingController url, alt, color;
  void dispose() {
    url.dispose();
    alt.dispose();
    color.dispose();
  }

  AdminRecord json() => {
    'url': url.text.trim(),
    'alt': alt.text.trim(),
    if (color.text.trim().isNotEmpty) 'color': color.text.trim(),
  };
}

class _PendingImage {
  _PendingImage(this.bytes, this.alt) : key = const Uuid().v4();
  final Uint8List bytes;
  final String alt, key;
  String get mimeType => bytes[0] == 137 ? 'image/png' : 'image/jpeg';
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({
    super.key,
    this.product,
    required this.references,
    this.returnTo,
  });
  final AdminRecord? product;
  final AdminRecord references;
  final String? returnTo;
  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final images = <_ImageFields>[];
  final removedImages = <_ImageFields>[];
  late final AdminRecord baseline;
  bool active = false, tryOn = false, saving = false;
  bool uploading = false, needsReload = false;
  String? expectedUpdatedAt;
  _PendingImage? pendingImage;
  bool get locked => saving || uploading || pendingImage != null || needsReload;
  bool get dirty => jsonEncode(draft()) != jsonEncode(baseline);
  String? category, brand, error;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    expectedUpdatedAt = p?['updatedAt'];
    for (final key in ['name', 'slug', 'description', 'material', 'style']) {
      fields[key] = TextEditingController(text: p?[key] ?? '');
    }
    active = p?['active'] ?? false;
    tryOn = p?['tryOnSupported'] ?? false;
    category = p?['categoryId'];
    brand = p?['brandId'];
    for (final image in (p?['images'] ?? []) as List) {
      images.add(_ImageFields(commerceMap(image)));
    }
    baseline = draft();
  }

  AdminRecord draft() => {
    for (final entry in fields.entries) entry.key: entry.value.text.trim(),
    'categoryId': category,
    'brandId': brand,
    'active': active,
    'tryOnSupported': tryOn,
    'images': images.map((i) => i.json()).toList(),
  };

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    for (final image in [...images, ...removedImages]) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (locked) return;
    final invalid = form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        duration: const Duration(milliseconds: 200),
        alignment: .15,
      );
      return;
    }
    final snapshot = draft();
    // PATCH only the fields edited in this form. In particular an unchanged
    // gallery must not replace images another administrator added meanwhile.
    final changes = widget.product == null
        ? snapshot
        : <String, dynamic>{
            for (final entry in snapshot.entries)
              if (jsonEncode(entry.value) != jsonEncode(baseline[entry.key]))
                entry.key: entry.value,
          };
    if (changes.isEmpty) {
      toast(context, 'Không có thay đổi cần lưu.');
      return;
    }
    final repo = ref.read(adminRepositoryProvider);
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final saved = await repo.saveProduct(widget.product?['id'], {
        ...changes,
        if (widget.product != null && expectedUpdatedAt != null)
          'expectedUpdatedAt': expectedUpdatedAt,
      });
      if (!mounted) return;
      // Advance only confirmed edits, not untouched fields from a newer server
      // response, since those may differ from the form still on screen.
      baseline.addAll(changes);
      expectedUpdatedAt = saved['updatedAt'] ?? expectedUpdatedAt;
      for (final key in fields.keys.where(changes.containsKey)) {
        fields[key]!.text = '${saved[key] ?? changes[key]}';
        baseline[key] = fields[key]!.text;
      }
      refreshAdmin(ref);
      ref.read(catalogRevisionProvider.notifier).refresh();
      toast(context, 'Đã lưu thông tin sản phẩm.');
      if (widget.product == null) {
        context.go(
          Uri(
            path: '/admin/products/${saved['id']}/edit',
            queryParameters: {'from': productsBack(widget.returnTo)},
          ).toString(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = adminError(e);
          needsReload =
              e is! ApiException ||
              (![400, 422].contains(e.status) &&
                  ![
                    'PRODUCT_SLUG_EXISTS',
                    'DUPLICATE_PRODUCT',
                  ].contains(e.code));
        });
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
        revealFeedback();
      }
    }
  }

  Future<void> upload() async {
    if (saving || uploading || needsReload || widget.product == null) return;
    if (pendingImage == null && jsonEncode(draft()) != jsonEncode(baseline)) {
      setState(() => error = 'Lưu các thay đổi hiện tại trước khi tải ảnh.');
      revealFeedback();
      return;
    }
    final repo = ref.read(adminRepositoryProvider);
    final revision = ref.read(catalogRevisionProvider.notifier);
    setState(() {
      uploading = true;
      error = null;
    });
    try {
      if (pendingImage == null) {
        final selected = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Ảnh JPEG hoặc PNG',
              extensions: ['jpg', 'jpeg', 'png'],
              mimeTypes: ['image/jpeg', 'image/png'],
            ),
          ],
        );
        if (!mounted || selected == null) return;
        if (await selected.length() > 8 * 1024 * 1024) {
          throw const ApiException(
            'IMAGE_TOO_LARGE',
            'Ảnh vượt 8 MB. Hãy chọn ảnh nhỏ hơn.',
          );
        }
        final bytes = await selected.readAsBytes();
        if (!mounted) return;
        final invalid = validateImage(bytes);
        if (invalid != null) throw ApiException('INVALID_IMAGE', invalid);
        pendingImage = _PendingImage(bytes, fields['name']!.text.trim());
      }
      final pending = pendingImage!;
      String? failure;
      try {
        await repo.uploadImage(
          widget.product!['id'],
          bytes: pending.bytes,
          mimeType: pending.mimeType,
          alt: pending.alt,
          key: pending.key,
          onLateCompletion: revision.refresh,
        );
      } on ApiException catch (e) {
        // A terminal reservation can only be abandoned after reconciling the
        // product. An uncertain or still-running request retains its exact key.
        if (e.code != 'UPLOAD_FAILED' &&
            e.code != 'GALLERY_FULL' &&
            e.status != 400 &&
            e.status != 413) {
          rethrow;
        }
        failure = e.code == 'GALLERY_FULL'
            ? 'Bộ ảnh đã đủ 20 ảnh. Bỏ bớt ảnh và lưu trước khi tải ảnh mới.'
            : 'Ảnh chưa được tải lên. Kiểm tra định dạng, kích thước rồi chọn lại ảnh.';
      }
      final product = await repo.detail('products', widget.product!['id']);
      if (!mounted) return;
      setState(() {
        removedImages.addAll(images);
        images.clear();
        for (final raw in product['images'] as List) {
          images.add(_ImageFields(commerceMap(raw)));
        }
        baseline['images'] = images.map((image) => image.json()).toList();
        expectedUpdatedAt = product['updatedAt'] ?? expectedUpdatedAt;
        pendingImage = null;
        error = failure;
      });
      refreshAdmin(ref);
      revision.refresh();
      if (failure == null) toast(context, 'Đã tải và lưu ảnh sản phẩm.');
    } catch (e) {
      revision.refresh();
      if (mounted) {
        setState(
          () => error = pendingImage == null
              ? adminError(e)
              : '${adminError(e)} Bấm “Kiểm tra lại ảnh tải lên” để lấy kết quả trước khi tiếp tục.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => uploading = false);
        revealFeedback();
      }
    }
  }

  Future<void> reloadProduct() async {
    if (saving || uploading) return;
    if (widget.product == null) {
      context.go(
        Uri(
          path: '/admin/products',
          queryParameters: {'q': fields['slug']!.text.trim()},
        ).toString(),
      );
      return;
    }
    setState(() => saving = true);
    try {
      final fresh = await ref
          .read(adminRepositoryProvider)
          .detail('products', widget.product!['id']);
      if (!mounted) return;
      setState(() {
        for (final key in fields.keys) {
          fields[key]!.text = '${fresh[key] ?? ''}';
        }
        category = fresh['categoryId'];
        brand = fresh['brandId'];
        active = fresh['active'] == true;
        tryOn = fresh['tryOnSupported'] == true;
        removedImages.addAll(images);
        images.clear();
        images.addAll(
          (fresh['images'] as List).map(
            (raw) => _ImageFields(commerceMap(raw)),
          ),
        );
        baseline.clear();
        baseline.addAll(draft());
        expectedUpdatedAt = fresh['updatedAt'];
        needsReload = false;
        error = null;
      });
      refreshAdmin(ref);
    } catch (e) {
      if (mounted) setState(() => error = adminError(e));
    } finally {
      if (mounted) {
        setState(() => saving = false);
        revealFeedback();
      }
    }
  }

  final infoAnchor = GlobalKey(),
      galleryAnchor = GlobalKey(),
      variantsAnchor = GlobalKey(),
      settingsAnchor = GlobalKey(),
      feedbackAnchor = GlobalKey();

  void revealFeedback() {
    if (error == null && !needsReload) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) jumpTo(feedbackAnchor);
    });
  }

  void jumpTo(GlobalKey anchor) {
    final target = anchor.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        alignment: .04,
      );
    }
  }

  Future<void> navigate(String destination) async {
    if (saving || uploading) return;
    if (dirty || pendingImage != null) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Rời trang khi chưa lưu?'),
          content: Text(
            pendingImage != null
                ? 'Kết quả tải ảnh chưa được xác nhận. Bạn có thể ở lại để kiểm tra trước khi rời trang.'
                : 'Các thay đổi chưa lưu sẽ bị bỏ. Ảnh đã tải từ máy và các thay đổi biến thể đã lưu vẫn được giữ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Tiếp tục chỉnh sửa'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Rời trang'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    if (mounted) context.go(destination);
  }

  Future<void> discard() async {
    if (locked || !dirty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bỏ các thay đổi chưa lưu?'),
        content: const Text(
          'Thông tin và bộ ảnh sẽ trở về lần lưu gần nhất. Ảnh đã tải từ máy vẫn được giữ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Tiếp tục chỉnh sửa'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Bỏ thay đổi'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      for (final key in fields.keys) {
        fields[key]!.text = '${baseline[key] ?? ''}';
      }
      category = baseline['categoryId'];
      brand = baseline['brandId'];
      active = baseline['active'] == true;
      tryOn = baseline['tryOnSupported'] == true;
      removedImages.addAll(images);
      images.clear();
      images.addAll(
        (baseline['images'] as List).map(
          (raw) => _ImageFields(commerceMap(raw)),
        ),
      );
      error = null;
    });
  }

  String referenceName(String kind, String? id) {
    for (final item in widget.references[kind] as List) {
      if (item['id'] == id) return '${item['name']}';
    }
    return '';
  }

  Widget saveButton({bool outlined = false}) => AppButton(
    'Lưu thông tin sản phẩm',
    outlined: outlined,
    icon: Icons.save_outlined,
    busy: saving,
    onPressed: locked ? null : save,
  );

  Widget draftStatus() => Semantics(
    liveRegion: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          dirty ? Icons.edit_outlined : Icons.check_circle_outline,
          size: 16,
          color: dirty ? T.warning : T.success,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            dirty
                ? 'Có thay đổi chưa lưu'
                : widget.product == null
                ? 'Sản phẩm mới'
                : 'Thông tin đã được lưu',
            style: T.small,
          ),
        ),
      ],
    ),
  );

  Widget pairs(List<Widget> children) => LayoutBuilder(
    builder: (context, c) => Wrap(
      spacing: 20,
      children: [
        for (final child in children)
          SizedBox(
            width: c.maxWidth >= 500 ? (c.maxWidth - 20) / 2 : c.maxWidth,
            child: child,
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final back = productsBack(widget.returnTo);
    final preview = <String, dynamic>{...?widget.product, ...draft()};
    final facts = ProductFacts(preview);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProductEditorSection(
          key: infoAnchor,
          title: 'Thông tin sản phẩm',
          description: 'Tên và nội dung khách hàng nhìn thấy tại cửa hàng.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                'name',
                'Tên sản phẩm',
                validator: (v) => requiredText(v, max: 200),
              ),
              _field(
                'slug',
                'Đường dẫn sản phẩm',
                validator: (s) =>
                    RegExp(
                          r'^[a-z0-9]+(?:-[a-z0-9]+)*$',
                        ).hasMatch((s ?? '').trim()) &&
                        (s?.trim().length ?? 0) <= 100
                    ? null
                    : 'Dùng chữ thường, số và dấu gạch ngang; tối đa 100 ký tự.',
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  '/products/${fields['slug']!.text.trim()}',
                  style: T.small,
                ),
              ),
              _field(
                'description',
                'Mô tả',
                maxLines: 5,
                validator: (v) =>
                    (v ?? '').length > 5000 ? 'Tối đa 5.000 ký tự.' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${fields['description']!.text.length}/5.000 ký tự',
                  style: T.small,
                ),
              ),
            ],
          ),
        ),
        ProductEditorSection(
          title: 'Phân loại & thuộc tính',
          description: 'Giúp khách hàng tìm đúng sản phẩm.',
          child: pairs([
            _select(
              'Danh mục',
              'categories',
              category,
              (v) => setState(() => category = v),
            ),
            _select(
              'Thương hiệu',
              'brands',
              brand,
              (v) => setState(() => brand = v),
            ),
            _field(
              'material',
              'Chất liệu',
              validator: (v) =>
                  (v ?? '').length > 200 ? 'Tối đa 200 ký tự.' : null,
            ),
            _field(
              'style',
              'Phong cách',
              validator: (v) =>
                  (v ?? '').length > 100 ? 'Tối đa 100 ký tự.' : null,
            ),
          ]),
        ),
      ],
    );
    final settings = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProductEditorPreview(
          product: preview,
          category: referenceName('categories', category),
          brand: referenceName('brands', brand),
        ),
        ProductEditorSection(
          key: settingsAnchor,
          title: 'Thiết lập bán hàng',
          description: '',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hiển thị sản phẩm'),
                value: active,
                onChanged: locked ? null : (v) => setState(() => active = v),
              ),
              const SizedBox(height: 8),
              const Text('Điều kiện hiển thị tại cửa hàng', style: T.small),
              ProductEditorCheck('Sản phẩm được bật', complete: active),
              ProductEditorCheck(
                'Có ảnh sản phẩm',
                complete: images.any((i) => i.url.text.trim().isNotEmpty),
              ),
              ProductEditorCheck(
                'Có biến thể đang bán',
                complete: facts.selling.isNotEmpty,
              ),
              const Divider(height: 32),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hỗ trợ thử đồ'),
                value: tryOn,
                onChanged: locked ? null : (v) => setState(() => tryOn = v),
              ),
              const Text(
                'Bật cho sản phẩm phù hợp với tính năng thử đồ AI.',
                style: T.small,
              ),
              if (widget.product == null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Lưu sản phẩm để tải ảnh từ máy và thêm biến thể.',
                  style: T.small,
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          widget.product == null ? 'Thêm sản phẩm' : 'Chỉnh sửa sản phẩm',
          widget.product == null
              ? 'Chuẩn bị thông tin, hình ảnh và các lựa chọn bán hàng.'
              : '${widget.product!['name']}',
          actions: [
            AppButton(
              'Về danh sách sản phẩm',
              outlined: true,
              icon: Icons.arrow_back,
              onPressed: saving || uploading ? null : () => navigate(back),
            ),
            saveButton(),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in <(String, GlobalKey)>[
                    ('Thông tin', infoAnchor),
                    ('Hình ảnh (${images.length})', galleryAnchor),
                    if (widget.product != null)
                      ('Biến thể (${facts.variants.length})', variantsAnchor),
                    ('Trạng thái bán', settingsAnchor),
                  ])
                    TextButton(
                      onPressed: () => jumpTo(entry.$2),
                      child: Text(entry.$1),
                    ),
                ],
              ),
              draftStatus(),
            ],
          ),
        ),
        if (error != null || needsReload)
          Container(
            key: feedbackAnchor,
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: T.danger.withValues(alpha: .05),
              border: Border.all(color: T.danger),
              borderRadius: T.radius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: T.body.copyWith(color: T.danger),
                    ),
                  ),
                if (needsReload) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.product == null
                        ? 'Kết quả lưu chưa được xác nhận. Tra cứu đường dẫn trước khi tạo lại để tránh trùng sản phẩm.'
                        : 'Tải lại dữ liệu mới nhất trước khi tiếp tục. Bản nháp hiện tại sẽ được thay bằng dữ liệu đã lưu.',
                    style: T.small,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      widget.product == null
                          ? 'Tra cứu sản phẩm đã tạo'
                          : 'Tải lại dữ liệu sản phẩm',
                      busy: saving,
                      onPressed: reloadProduct,
                    ),
                  ),
                ],
              ],
            ),
          ),
        Form(
          key: form,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) => c.maxWidth >= 980
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: info),
                          const SizedBox(width: 24),
                          Expanded(flex: 4, child: settings),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [info, settings],
                      ),
              ),
              ProductEditorSection(
                key: galleryAnchor,
                title: 'Bộ ảnh sản phẩm',
                description:
                    '${images.length}/20 ảnh. Ảnh đầu tiên là ảnh bìa.',
                actions: [
                  AppButton(
                    'Thêm ảnh',
                    outlined: true,
                    icon: Icons.add_photo_alternate_outlined,
                    onPressed: locked || images.length >= 20
                        ? null
                        : () => setState(() => images.add(_ImageFields({}))),
                  ),
                  if (widget.product != null)
                    AppButton(
                      pendingImage == null
                          ? 'Tải ảnh từ máy'
                          : 'Kiểm tra lại ảnh tải lên',
                      outlined: true,
                      icon: Icons.file_upload_outlined,
                      busy: uploading,
                      onPressed:
                          saving ||
                              uploading ||
                              needsReload ||
                              (pendingImage == null && images.length >= 20)
                          ? null
                          : upload,
                    ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (images.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 32,
                          horizontal: 20,
                        ),
                        color: T.canvas,
                        child: const Column(
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              color: T.muted,
                              size: 40,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Thêm ảnh đầu tiên cho sản phẩm',
                              style: T.body,
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Ảnh rõ nét giúp khách hàng dễ lựa chọn hơn.',
                              style: T.small,
                            ),
                          ],
                        ),
                      ),
                    for (var index = 0; index < images.length; index++)
                      _imageCard(images[index], index),
                    const SizedBox(height: 8),
                    Text(
                      widget.product == null
                          ? 'Lưu sản phẩm trước để tải ảnh từ máy.'
                          : 'JPEG/PNG, tối đa 8 MB. Ảnh tải từ máy được lưu ngay. Các chỉnh sửa và thứ tự ảnh cần bấm lưu.',
                      style: T.small,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 32),
                decoration: BoxDecoration(
                  color: T.soft.withValues(alpha: .5),
                  borderRadius: T.radius,
                ),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 16,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Hoàn tất thông tin trước khi chỉnh sửa biến thể.',
                      style: T.small,
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        TextButton(
                          onPressed: !locked && dirty ? discard : null,
                          child: const Text('Hủy thay đổi'),
                        ),
                        saveButton(outlined: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.product != null) ...[
          ProductVariantSection(
            key: variantsAnchor,
            product: widget.product!,
            locked: locked || dirty,
            tableOnWide: true,
            lockedReason: dirty
                ? 'Lưu hoặc hủy các thay đổi thông tin trước khi chỉnh sửa biến thể.'
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppButton(
                  'Xem chi tiết',
                  outlined: true,
                  icon: Icons.open_in_new,
                  onPressed: saving || uploading
                      ? null
                      : () => navigate(
                          Uri(
                            path: '/admin/products/${widget.product!['id']}',
                            queryParameters: {'from': back},
                          ).toString(),
                        ),
                ),
                if (ProductFacts(widget.product!).published)
                  AppButton(
                    'Xem tại cửa hàng',
                    outlined: true,
                    icon: Icons.storefront_outlined,
                    onPressed: saving || uploading
                        ? null
                        : () =>
                              navigate('/products/${widget.product!['slug']}'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _imageCard(_ImageFields image, int index) => Container(
    key: ObjectKey(image),
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: T.line),
      borderRadius: T.radius,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              index == 0 ? 'Ảnh bìa' : 'Ảnh ${index + 1}',
              style: T.body.copyWith(fontWeight: FontWeight.w600),
            ),
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Đưa ảnh lên trước',
                  onPressed: locked || index == 0
                      ? null
                      : () => setState(() {
                          images.removeAt(index);
                          images.insert(index - 1, image);
                        }),
                  icon: const Icon(Icons.arrow_upward, size: 20),
                ),
                IconButton(
                  tooltip: 'Đưa ảnh ra sau',
                  onPressed: locked || index == images.length - 1
                      ? null
                      : () => setState(() {
                          images.removeAt(index);
                          images.insert(index + 1, image);
                        }),
                  icon: const Icon(Icons.arrow_downward, size: 20),
                ),
                TextButton.icon(
                  onPressed: locked || index == 0
                      ? null
                      : () => setState(() {
                          images.remove(image);
                          images.insert(0, image);
                        }),
                  icon: const Icon(Icons.photo_outlined, size: 18),
                  label: const Text('Đặt làm ảnh bìa'),
                ),
                TextButton.icon(
                  onPressed: locked
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Bỏ ảnh khỏi sản phẩm?'),
                              content: const Text(
                                'Ảnh sẽ được gỡ khỏi bộ ảnh khi lưu. Hình ảnh trong đơn hàng đã đặt vẫn được giữ nguyên.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Giữ ảnh'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Bỏ ảnh'),
                                ),
                              ],
                            ),
                          );
                          if (mounted && confirm == true) {
                            setState(() {
                              images.remove(image);
                              removedImages.add(image);
                            });
                          }
                        },
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  label: const Text('Bỏ ảnh'),
                  style: TextButton.styleFrom(foregroundColor: T.danger),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final preview = SizedBox(
              height: 210,
              width: 210,
              child: image.url.text.isEmpty
                  ? const ColoredBox(
                      color: T.photo,
                      child: Icon(Icons.image_outlined, color: T.muted),
                    )
                  : FashionImage(
                      image.url.text,
                      label: image.alt.text,
                      fit: BoxFit.contain,
                    ),
            );
            final inputs = Column(
              children: [
                AppField(
                  label: 'Đường dẫn ảnh',
                  controller: image.url,
                  readOnly: locked,
                  validator: (s) =>
                      (managedCatalogImage.hasMatch(s ?? '') ||
                              RegExp(
                                r'^(https://[^\s]+|assets/images/[a-zA-Z0-9_./-]+)$',
                              ).hasMatch(s ?? '')) &&
                          (s?.length ?? 0) <= 2000
                      ? null
                      : 'Nhập đường dẫn ảnh HTTPS hoặc assets/images/ hợp lệ.',
                ),
                const SizedBox(height: 12),
                AppField(
                  label: 'Mô tả ảnh',
                  controller: image.alt,
                  readOnly: locked,
                  validator: (v) =>
                      (v ?? '').length > 200 ? 'Tối đa 200 ký tự.' : null,
                ),
                const SizedBox(height: 12),
                AppField(
                  label: 'Màu áp dụng (không bắt buộc)',
                  controller: image.color,
                  readOnly: locked,
                  validator: (v) =>
                      (v ?? '').length > 60 ? 'Tối đa 60 ký tự.' : null,
                ),
              ],
            );
            return c.maxWidth >= 620
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      preview,
                      const SizedBox(width: 20),
                      Expanded(child: inputs),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [preview, const SizedBox(height: 16), inputs],
                  );
          },
        ),
      ],
    ),
  );

  Widget _field(
    String key,
    String label, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: AppField(
      label: label,
      controller: fields[key],
      maxLines: maxLines,
      validator: validator,
      readOnly: locked,
    ),
  );
  Widget _select(
    String label,
    String kind,
    String? current,
    ValueChanged<String?> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$kind-$current'),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in widget.references[kind] as List)
          DropdownMenuItem(
            value: item['id'] as String,
            child: Text(item['name'], overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: locked ? null : change,
      validator: (s) => s == null ? 'Vui lòng chọn $label.' : null,
    ),
  );
}
