import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/account_state.dart';
import '../../../app/content_provider.dart';
import '../../../app/content_navigation.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import 'admin_presentation.dart';
import 'order_presentation.dart' show adminOrderDate;
import 'content_models.dart';
import 'content_preview.dart';
import 'content_history.dart';
import 'content_unload.dart';

class RemoteContentPage extends ConsumerWidget {
  const RemoteContentPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AdminAsync(
    value: ref.watch(adminContentProvider),
    reload: () => ref.invalidate(adminContentProvider),
    builder: (data) => _ContentEditor(data: data),
  );
}

class _ContentEditor extends ConsumerStatefulWidget {
  const _ContentEditor({required this.data});
  final AdminRecord data;
  @override
  ConsumerState<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends ConsumerState<_ContentEditor> {
  final form = GlobalKey<FormState>();
  final top = GlobalKey();
  final unload = ContentUnloadGuard();
  late AdminRecord saved = widget.data;
  late Map<String, String> baseline = contentValues(saved);
  late final controllers = {
    for (final e in baseline.entries)
      e.key: TextEditingController(text: e.value),
  };
  late final AdminRepository repository;
  late final ContentRevision revision;
  late final ContentNavigation navigation;
  late final String? identity;
  late final Future<bool> Function() exitCheck = leave;
  int section = 0;
  bool saving = false,
      needsReload = false,
      adopting = false,
      confirming = false;
  String? operation, error;
  Map<String, String> get values => {
    for (final e in controllers.entries) e.key: e.value.text.trim(),
  };
  bool get dirty => contentDiffers(values, baseline);
  Map<String, String>? get live => saved['published'] is Map
      ? contentValues(Map<String, dynamic>.from(saved['published']))
      : null;
  bool get unpublished => live == null || contentDiffers(baseline, live!);
  bool get locked => saving || needsReload || confirming;
  bool get sameSession {
    final account = ref.read(adminAccountProvider);
    return account?.id == identity &&
        (identity == null || canStaff(account?.role, 'content.manage'));
  }

  @override
  void initState() {
    super.initState();
    repository = ref.read(adminRepositoryProvider);
    revision = ref.read(contentRevisionProvider.notifier);
    navigation = ref.read(contentNavigationProvider);
    identity = ref.read(adminAccountProvider)?.id;
    for (final c in controllers.values) {
      c.addListener(changed);
    }
    navigation.check = exitCheck;
  }

  void changed() {
    if (adopting || !mounted) return;
    unload.update(dirty || saving);
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _ContentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data['version'] != saved['version'] &&
        widget.data['version'] != oldWidget.data['version']) {
      final incoming = widget.data;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || incoming['version'] == saved['version']) return;
        setState(() {
          if (dirty || saving) {
            needsReload = true;
            error =
                'Bản lưu đã thay đổi. Nội dung bạn đang nhập vẫn được giữ để đối chiếu.';
          } else {
            accept(incoming);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    if (identical(navigation.check, exitCheck)) navigation.check = null;
    unload.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void accept(AdminRecord data) {
    adopting = true;
    saved = data;
    baseline = contentValues(data);
    for (final e in controllers.entries) {
      e.value.text = baseline[e.key]!;
    }
    adopting = false;
    needsReload = false;
    error = null;
    unload.update(false);
  }

  void refreshCaches() {
    if (!mounted) return;
    ref.invalidate(adminContentHistoryProvider);
    ref.invalidate(adminSummaryProvider);
  }

  Future<bool> confirm(
    String title,
    String message, {
    String action = 'Xác nhận',
    Widget? body,
  }) async {
    if (confirming) return false;
    setState(() => confirming = true);
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (c) => ContentSessionDialog(
              identity: identity,
              child: AlertDialog(
                title: Text(title),
                content: SizedBox(
                  width: 680,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(message),
                        if (body != null) ...[const SizedBox(height: 20), body],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Tiếp tục chỉnh sửa'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(action),
                  ),
                ],
              ),
            ),
          ) ==
          true;
    } finally {
      if (mounted) setState(() => confirming = false);
    }
  }

  Future<bool> leave() async {
    if (!mounted || !sameSession) return true;
    if (saving) {
      toast(context, 'Đang xử lý nội dung. Vui lòng chờ kết quả.');
      return false;
    }
    if (!dirty) return true;
    return confirm(
      'Rời trang khi chưa lưu?',
      'Các thay đổi đang nhập sẽ bị bỏ. Bản nháp đã lưu và nội dung công khai được giữ nguyên.',
      action: 'Rời trang',
    );
  }

  Future<void> reload() async {
    if (saving || confirming) return;
    if (dirty &&
        !await confirm(
          'Tải lại bản đã lưu?',
          'Thao tác này thay thế các chỉnh sửa chưa lưu bằng nội dung mới nhất trên máy chủ.',
          action: 'Tải lại',
        )) {
      return;
    }
    if (!mounted || !sameSession) return;
    setState(() {
      saving = true;
      operation = 'reload';
      error = null;
    });
    try {
      final data = await repository.content();
      if (mounted && sameSession) {
        setState(() => accept(data));
        refreshCaches();
        toast(context, 'Đã tải lại bản đã lưu.');
      }
    } catch (e) {
      if (mounted) setState(() => error = contentError(e));
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
          operation = null;
          unload.update(dirty);
        });
      }
    }
  }

  bool validate() {
    final invalid = contentFields.where(
      (f) => contentValidation(f.key, values[f.key]!) != null,
    );
    if (invalid.isEmpty) return true;
    setState(() => section = invalid.first.group);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        form.currentState?.validate();
      }
    });
    return false;
  }

  Future<void> submit(String action) async {
    if (locked || !sameSession) return;
    if (action == 'save' && !validate()) return;
    if (action == 'publish') {
      if (dirty || saved['version'] == 0 || !unpublished) return;
      if (!await confirm(
        'Xuất bản nội dung?',
        'Nội dung đã lưu bên dưới sẽ thay thế bản đang hiển thị cho khách hàng.',
        action: 'Xác nhận xuất bản',
        body: ContentComparison(draft: baseline, published: live),
      )) {
        return;
      }
    }
    if (action == 'restore') {
      if (live == null) return;
      if (!await confirm(
        'Khôi phục bản nháp?',
        'Thay thế bản nháp và các chỉnh sửa chưa lưu bằng nội dung đang công khai. Cửa hàng công khai không thay đổi.',
        action: 'Khôi phục bản nháp',
      )) {
        return;
      }
    }
    if (!mounted || !sameSession) return;
    setState(() {
      saving = true;
      operation = action;
      error = null;
    });
    unload.update(true);
    void late() {
      if (action == 'publish') revision.refresh();
      if (mounted) {
        setState(() => needsReload = true);
        refreshCaches();
      }
    }

    try {
      final AdminRecord result;
      if (action == 'publish') {
        result = await repository.publishContent(
          saved['version'] as int,
          onLateCompletion: late,
        );
      } else if (action == 'restore') {
        result = await repository.restoreContent(
          saved['version'] as int,
          onLateCompletion: late,
        );
      } else {
        final data = values;
        result = await repository.saveContent({
          'banner': data['banner'],
          'policy': data['policy'],
          'expectedVersion': saved['version'],
          'details': {
            for (final e in data.entries)
              if (!['banner', 'policy'].contains(e.key)) e.key: e.value,
          },
        }, onLateCompletion: late);
      }
      if (!mounted || !sameSession) return;
      setState(() => accept(result));
      refreshCaches();
      toast(context, switch (action) {
        'publish' => 'Đã xuất bản nội dung.',
        'restore' =>
          'Đã khôi phục bản nháp. Nội dung công khai được giữ nguyên.',
        _ => 'Đã lưu bản nháp. Chưa xuất bản.',
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = contentError(e);
          needsReload = e is! ApiException || ![400, 422].contains(e.status);
        });
      }
    } finally {
      if (action == 'publish') revision.refresh();
      if (mounted) {
        setState(() {
          saving = false;
          operation = null;
          unload.update(dirty);
        });
      }
    }
  }

  Future<void> preview({bool published = false}) async {
    final data = published ? live : values;
    if (data == null) return;
    await showDialog<void>(
      context: context,
      builder: (c) => ContentSessionDialog(
        identity: identity,
        child: AlertDialog(
          title: Text(
            published
                ? 'Nội dung đang công khai'
                : dirty
                ? 'Xem trước thay đổi chưa lưu'
                : 'Xem trước bản nháp đã lưu',
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: ContentPreview(values: data, full: true),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Đóng xem trước'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = values;
    final changedCount = contentFields
        .where((f) => current[f.key] != (live?[f.key] ?? ''))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminHeading(
          'Nội dung cửa hàng',
          'Soạn nội dung, kiểm tra bản xem trước và xuất bản khi sẵn sàng.',
          actions: [
            AppButton(
              'Xem trước',
              outlined: true,
              icon: Icons.preview_outlined,
              onPressed: saving ? null : () => preview(),
            ),
            AppButton(
              'Tải lại bản đã lưu',
              outlined: true,
              icon: Icons.refresh,
              onPressed: saving || confirming ? null : reload,
            ),
          ],
        ),
        AdminCard(
          child: Column(
            key: top,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AdminStatus(
                    needsReload
                        ? 'Cần tải lại'
                        : dirty
                        ? 'Chưa lưu thay đổi'
                        : saved['version'] == 0
                        ? 'Chưa có bản nháp'
                        : unpublished
                        ? 'Bản nháp chưa xuất bản'
                        : 'Đã đồng bộ với bản công khai',
                    color: dirty || needsReload
                        ? T.warning
                        : unpublished
                        ? T.accent
                        : T.success,
                  ),
                  Text('Phiên bản ${saved['version']}', style: T.small),
                  if (saved['updatedAt'] != null)
                    Text(
                      'Lưu ${adminOrderDate(saved['updatedAt'])} (UTC+7)',
                      style: T.small,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                live == null
                    ? 'Chưa xuất bản nội dung cửa hàng. Bản nháp chỉ quản trị viên nhìn thấy.'
                    : '$changedCount mục khác bản công khai. Lưu nháp không thay đổi nội dung khách đang xem.',
                style: T.body,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AppButton(
                    'Lưu bản nháp',
                    icon: Icons.save_outlined,
                    busy: operation == 'save',
                    onPressed: !locked && (dirty || saved['version'] == 0)
                        ? () => submit('save')
                        : null,
                  ),
                  AppButton(
                    'Xuất bản nội dung',
                    outlined: true,
                    icon: Icons.publish_outlined,
                    busy: operation == 'publish',
                    onPressed:
                        !locked &&
                            !dirty &&
                            saved['version'] != 0 &&
                            unpublished
                        ? () => submit('publish')
                        : null,
                  ),
                  TextButton(
                    onPressed: !locked && live != null && unpublished
                        ? () => submit('restore')
                        : null,
                    child: const Text('Khôi phục từ bản công khai'),
                  ),
                ],
              ),
              if (dirty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Lưu bản nháp trước khi xuất bản. Bạn vẫn có thể xem trước thay đổi đang nhập.',
                    style: T.small,
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: T.body.copyWith(color: T.danger),
                    ),
                  ),
                ),
              if (needsReload)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Không gửi lại yêu cầu trước khi tải lại để kiểm tra kết quả. Nội dung đang nhập được giữ để bạn đối chiếu.',
                    style: T.small,
                  ),
                ),
              if (saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final editor = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < contentGroups.length; i++)
                      ChoiceChip(
                        label: Text(contentGroups[i]),
                        selected: section == i,
                        onSelected: saving
                            ? null
                            : (_) => setState(() => section = i),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                AdminCard(
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AdminSectionTitle(contentGroups[section]),
                        Text(switch (section) {
                          0 =>
                            'Tiêu đề chiến dịch, tên và mô tả cửa hàng xuất hiện trên trang chủ.',
                          1 =>
                            'Kể câu chuyện và giới thiệu phong cách của cửa hàng.',
                          2 =>
                            'Các thông tin liên hệ để trống sẽ không hiển thị.',
                          _ =>
                            'Văn bản hiển thị trên các trang thông tin. Thay đổi ở đây không tự thay đổi phí giao hàng hoặc quy trình xử lý đơn.',
                        }, style: T.small),
                        const SizedBox(height: 20),
                        for (final f in contentFields.where(
                          (f) => f.group == section,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: TextFormField(
                              key: ValueKey(f.key),
                              controller: controllers[f.key],
                              enabled: !locked,
                              minLines: f.lines,
                              maxLines: f.lines == 1 ? 1 : 10,
                              maxLength: f.max,
                              keyboardType: f.key == 'email'
                                  ? TextInputType.emailAddress
                                  : f.key == 'phone'
                                  ? TextInputType.phone
                                  : f.lines > 1
                                  ? TextInputType.multiline
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                labelText: f.label,
                                alignLabelWithHint: true,
                              ),
                              validator: (v) =>
                                  contentValidation(f.key, v ?? ''),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () => Scrollable.ensureVisible(
                            top.currentContext!,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                          ),
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          label: const Text('Về thao tác lưu và xuất bản'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
            final publication = AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AdminSectionTitle('Nội dung đã xuất bản'),
                  if (live == null)
                    const Text('Chưa có bản công khai.', style: T.small)
                  else ...[
                    Text(
                      live!['banner']!,
                      style: T.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Phiên bản ${saved['published']['version']} · ${adminOrderDate(saved['published']['publishedAt'])} (UTC+7)',
                      style: T.small,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => preview(published: true),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Xem bản công khai'),
                    ),
                    if (GoRouter.maybeOf(context) != null)
                      TextButton.icon(
                        onPressed: () => context.go('/'),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Mở cửa hàng'),
                      ),
                  ],
                ],
              ),
            );
            if (c.maxWidth >= 1050 &&
                MediaQuery.textScalerOf(context).scale(14) <= 18) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: editor),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      children: [
                        AdminCard(child: ContentPreview(values: current)),
                        publication,
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [editor, publication],
            );
          },
        ),
        AdminCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Nhật ký nội dung'),
            subtitle: const Text('Lưu nháp, xuất bản và khôi phục'),
            children: const [ContentHistory()],
          ),
        ),
      ],
    );
  }
}
