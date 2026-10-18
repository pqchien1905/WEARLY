import '../../app/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/ai_providers.dart';
import '../../app/account_state.dart';
import '../../app/account_details.dart';
import '../../app/activity.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/widgets/primitives.dart';
import '../../core/widgets/product_card.dart';
import '../../domain/ai.dart';

class StylistPage extends ConsumerStatefulWidget {
  const StylistPage({super.key, this.prompt});
  final String? prompt;
  @override
  ConsumerState<StylistPage> createState() => _StylistPageState();
}

class _StylistPageState extends ConsumerState<StylistPage> {
  final input = TextEditingController();
  final messages = <(bool, String)>[];
  int budget = 1500000;
  String size = 'M',
      style = '',
      color = '',
      scenario = 'success',
      lastPrompt = '';
  bool busy = false;
  String? error;
  StylistReply? reply;
  @override
  void initState() {
    super.initState();
    input.text = widget.prompt ?? '';
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> send([String? prompt]) async {
    final text = (prompt ?? input.text).trim();
    if (text.isEmpty || busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      lastPrompt = text;
      messages.add((true, text));
      input.clear();
    });
    ref.read(activityProvider.notifier).add('AI Stylist', 'Đang xử lý');
    try {
      final response = await ref
          .read(stylistRepositoryProvider)
          .reply(
            StylistRequest(
              prompt: text,
              budget: budget,
              size: size,
              style: style,
              color: color,
            ),
            scenario: scenario,
          );
      if (mounted) {
        ref
            .read(activityProvider.notifier)
            .add('AI Stylist', 'Đã trả lời mô phỏng');
        setState(() {
          reply = response;
          messages.add((false, response.message));
        });
      }
    } catch (e) {
      if (mounted) {
        ref.read(activityProvider.notifier).add('AI Stylist', 'Lỗi mô phỏng');
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          color: T.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.auto_awesome_outlined,
                color: T.accent,
                size: 28,
              ),
              const SizedBox(height: 20),
              Text('Hôm nay, bạn muốn\nmặc như thế nào?', style: T.display(32)),
              const SizedBox(height: 16),
              const Text(
                'Chia sẻ dịp sử dụng và điều bạn thích. Mình sẽ chọn từ tủ đồ ${BrandConfig.displayName}, theo ngân sách và size bạn đặt.',
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                          'Đi làm thanh lịch',
                          'Hẹn hò cuối tuần',
                          'Tối giản mỗi ngày',
                        ]
                        .map(
                          (p) => ActionChip(
                            label: Text(p),
                            onPressed: busy ? null : () => send(p),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final m in messages)
          Align(
            alignment: m.$1 ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: m.$1 ? T.soft : T.canvas,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.$1 ? 'Bạn' : 'Stylist demo',
                    style: T.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: T.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(m.$2),
                ],
              ),
            ),
          ),
        if (busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Semantics(
              liveRegion: true,
              child: const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Đang chọn những món đồ phù hợp…')),
                ],
              ),
            ),
          ),
        if (error != null)
          StatePanel(
            title: 'Chưa có gợi ý mới',
            message: error!,
            action: AppButton('Thử lại', onPressed: () => send(lastPrompt)),
          ),
        TextField(
          controller: input,
          minLines: 2,
          maxLines: 4,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Bạn đang tìm một outfit như thế nào?',
            hintText: 'Ví dụ: đi làm, dễ phối, ít màu…',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              'Gửi yêu cầu',
              busy: busy,
              onPressed: () => send(),
              icon: Icons.north_east,
            ),
            if (reply != null)
              AppButton(
                'Gợi ý lại',
                outlined: true,
                onPressed: busy ? null : () => send(lastPrompt),
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      messages.clear();
                      reply = null;
                      error = null;
                    }),
              child: const Text('Xóa hội thoại'),
            ),
          ],
        ),
      ],
    );
    final looks = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(border: Border.all(color: T.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dành cho kế hoạch của bạn', style: T.display(25)),
          if (ref.watch(accountProvider) != null)
            ref
                .watch(accountDetailsProvider)
                .when(
                  data: (details) => Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: AppButton(
                      'Dùng hồ sơ phong cách',
                      outlined: true,
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              budget = details.style.budget;
                              size = details.style.size;
                              style = details.style.style;
                              color = details.style.color;
                            }),
                    ),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('Đang tải hồ sơ…', style: T.small),
                  ),
                  error: (_, _) => TextButton(
                    onPressed: () => ref.invalidate(accountDetailsProvider),
                    child: const Text('Tải lại hồ sơ phong cách'),
                  ),
                ),
          const SizedBox(height: 24),
          DropdownButtonFormField<int>(
            key: ValueKey('stylist-budget-$budget'),
            isExpanded: true,
            initialValue: budget,
            decoration: const InputDecoration(labelText: 'Ngân sách cả outfit'),
            items: [800000, 1500000, 2500000]
                .map((v) => DropdownMenuItem(value: v, child: Text(money(v))))
                .toList(),
            onChanged: busy ? null : (v) => setState(() => budget = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('stylist-size-$size'),
            isExpanded: true,
            initialValue: size,
            decoration: const InputDecoration(labelText: 'Size mong muốn'),
            items: [
              'XS',
              'S',
              'M',
              'L',
              'XL',
              'XXL',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: busy ? null : (v) => setState(() => size = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: style,
            key: ValueKey('stylist-style-$style'),
            decoration: const InputDecoration(labelText: 'Phong cách'),
            items: ['', 'Tối giản', 'Thanh lịch', 'Thư giãn']
                .map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(v.isEmpty ? 'Theo nội dung trao đổi' : v),
                  ),
                )
                .toList(),
            onChanged: busy ? null : (v) => setState(() => style = v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: color,
            key: ValueKey('stylist-color-$color'),
            decoration: const InputDecoration(labelText: 'Màu yêu thích'),
            items:
                [
                      '',
                      'Trắng',
                      'Đen',
                      'Mận',
                      'Xanh',
                      'Nâu',
                      'Hồng đất',
                      'Tím',
                      'Đỏ',
                    ]
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.isEmpty ? 'Không giới hạn màu' : v),
                      ),
                    )
                    .toList(),
            onChanged: busy ? null : (v) => setState(() => color = v!),
          ),
          const SizedBox(height: 24),
          if (reply == null)
            const Text(
              'Các thiết kế được chọn sẽ xuất hiện ở đây, với giá từ catalog demo.',
              style: T.small,
            )
          else ...[
            Text(
              'Tổng gợi ý: ${money(reply!.total)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            if (reply!.products.isEmpty)
              const Text('Thử tăng ngân sách hoặc chọn size còn hàng.')
            else
              ProductGrid(reply!.products, maxColumns: 2),
          ],
          const SizedBox(height: 24),
          ExpansionTile(
            key: const PageStorageKey('stylist:demo-scenarios'),
            tilePadding: EdgeInsets.zero,
            title: const Text('Kịch bản kiểm thử demo', style: T.small),
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: scenario,
                items: const [
                  DropdownMenuItem(
                    value: 'success',
                    child: Text('Phản hồi thành công'),
                  ),
                  DropdownMenuItem(value: 'error', child: Text('Lỗi mô phỏng')),
                  DropdownMenuItem(
                    value: 'timeout',
                    child: Text('Hết thời gian chờ'),
                  ),
                ],
                onChanged: busy ? null : (v) => setState(() => scenario = v!),
              ),
            ],
          ),
        ],
      ),
    );
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Góc stylist của bạn.',
            style: T.display(MediaQuery.sizeOf(context).width < 600 ? 36 : 48),
          ),
          const SizedBox(height: 16),
          const DemoNotice(),
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (_, c) => c.maxWidth < 850
                ? Column(children: [chat, const SizedBox(height: 32), looks])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: chat),
                      const SizedBox(width: 40),
                      Expanded(flex: 5, child: looks),
                    ],
                  ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
