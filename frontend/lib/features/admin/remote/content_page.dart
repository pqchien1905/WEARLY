import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/content_provider.dart';
import '../../../core/design/tokens.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/primitives.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';

class RemoteContentPage extends ConsumerStatefulWidget {
  const RemoteContentPage({super.key});
  @override
  ConsumerState<RemoteContentPage> createState() => _RemoteContentPageState();
}

class _RemoteContentPageState extends ConsumerState<RemoteContentPage> {
  int reloads = 0;
  void reload() {
    setState(() => reloads++);
    ref.invalidate(adminContentProvider);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AdminHeading(
        'Nội dung cửa hàng',
        'Lưu bản nháp để chuẩn bị. Chỉ xuất bản khi nội dung đã sẵn sàng cho khách hàng.',
      ),
      AdminAsync(
        value: ref.watch(adminContentProvider),
        reload: reload,
        builder: (data) => _ContentEditor(
          key: ValueKey('$reloads:${data['id']}:${data['version']}'),
          data: data,
          reload: reload,
        ),
      ),
    ],
  );
}

class _ContentEditor extends ConsumerStatefulWidget {
  const _ContentEditor({super.key, required this.data, required this.reload});
  final AdminRecord data;
  final VoidCallback reload;
  @override
  ConsumerState<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends ConsumerState<_ContentEditor> {
  final form = GlobalKey<FormState>();
  late final banner = TextEditingController(text: widget.data['banner']);
  late final policy = TextEditingController(text: widget.data['policy']);
  bool saving = false, needsReload = false;
  String? error;
  bool get dirty =>
      banner.text.trim() != widget.data['banner'] ||
      policy.text.trim() != widget.data['policy'];

  @override
  void dispose() {
    banner.dispose();
    policy.dispose();
    super.dispose();
  }

  Future<void> submit({bool publish = false}) async {
    if (saving || needsReload || !form.currentState!.validate()) return;
    final repository = ref.read(adminRepositoryProvider);
    final revision = ref.read(contentRevisionProvider.notifier);
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (publish) {
        await repository.publishContent(
          widget.data['version'] as int,
          onLateCompletion: revision.refresh,
        );
      } else {
        await repository.saveContent({
          'banner': banner.text.trim(),
          'policy': policy.text.trim(),
          'expectedVersion': widget.data['version'],
        });
      }
      if (!mounted) return;
      toast(
        context,
        publish ? 'Đã xuất bản nội dung.' : 'Đã lưu bản nháp. Chưa xuất bản.',
      );
      refreshAdmin(ref);
      widget.reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = adminError(e);
        needsReload = e is! ApiException || ![400, 422].contains(e.status);
      });
    } finally {
      // A lost response/session may still follow a committed publication.
      if (publish) revision.refresh();
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final published = widget.data['published'] as Map?;
    final canPublish =
        !saving &&
        !needsReload &&
        !dirty &&
        widget.data['version'] != 0 &&
        published?['version'] != widget.data['version'];
    return Form(
      key: form,
      onChanged: () => setState(() {}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Bản nháp', style: T.display(26)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: banner,
                  enabled: !saving && !needsReload,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu đề campaign',
                  ),
                  validator: (v) => requiredText(v, max: 120),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: policy,
                  enabled: !saving && !needsReload,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung chính sách',
                  ),
                  validator: (v) => requiredText(v, max: 5000),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tiêu đề xuất hiện ở trang chủ; chính sách ở trang Giao hàng & đổi trả. Nội dung chỉ là văn bản, không thay đổi cách tính phí đơn hàng.',
                  style: T.small,
                ),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(error!, style: T.body),
                  ),
                ],
                if (needsReload)
                  const Text(
                    'Tải lại bản đã lưu trước khi thao tác tiếp; các chỉnh sửa chưa lưu sẽ được thay thế.',
                    style: T.small,
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    AppButton(
                      'Lưu bản nháp',
                      onPressed:
                          !saving &&
                              !needsReload &&
                              (dirty || widget.data['version'] == 0)
                          ? submit
                          : null,
                    ),
                    AppButton(
                      'Xuất bản nội dung',
                      outlined: true,
                      onPressed: canPublish
                          ? () => submit(publish: true)
                          : null,
                    ),
                    AppButton(
                      'Tải lại bản đã lưu',
                      outlined: true,
                      onPressed: !saving ? widget.reload : null,
                    ),
                  ],
                ),
                if (saving) const LinearProgressIndicator(),
              ],
            ),
          ),
          AdminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nội dung đã xuất bản', style: T.display(26)),
                const SizedBox(height: 16),
                if (published == null)
                  const Text(
                    'Chưa xuất bản nội dung cửa hàng. Bản nháp chỉ quản trị viên nhìn thấy.',
                  )
                else ...[
                  Text(published['banner'] as String, style: T.body),
                  const SizedBox(height: 12),
                  Text(published['policy'] as String, style: T.body),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
