import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../app/account_details.dart';
import '../../app/api_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/format.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_stylist.dart';
import '../../domain/ai.dart';

class RemoteStylistPage extends ConsumerStatefulWidget {
  const RemoteStylistPage({super.key, this.initialPrompt});
  final String? initialPrompt;
  @override
  ConsumerState<RemoteStylistPage> createState() => _RemoteStylistPageState();
}

class _RemoteStylistPageState extends ConsumerState<RemoteStylistPage> {
  late final repo = RemoteStylistRepository(ref.read(apiClientProvider));
  late final prompt = TextEditingController(text: widget.initialPrompt ?? '');
  final style = TextEditingController(), color = TextEditingController();
  int budget = 1500000, polls = 0;
  String size = 'M';
  bool consent = false, busy = false, loadingStatus = true;
  bool loadingRecovery = true;
  String? recoveryError;
  String? error, statusError, key;
  StylistRequest? submitted;
  StylistAvailability? availability;
  StylistReceipt? receipt;
  Timer? timer;
  bool get unresolved => key != null && (receipt == null || receipt!.pending);
  bool get locked =>
      busy || unresolved || loadingRecovery || recoveryError != null;
  @override
  void initState() {
    super.initState();
    unawaited(loadStatus());
    unawaited(loadLatest());
  }

  @override
  void dispose() {
    timer?.cancel();
    prompt.dispose();
    style.dispose();
    color.dispose();
    super.dispose();
  }

  Future<void> loadStatus() async {
    try {
      final value = await repo.status();
      if (mounted) {
        setState(() {
          availability = value;
          loadingStatus = false;
          statusError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loadingStatus = false;
          statusError = stylistError(e);
        });
      }
    }
  }

  Future<void> loadLatest() async {
    setState(() => loadingRecovery = true);
    try {
      final value = await repo.latest();
      if (!mounted) return;
      setState(() {
        recoveryError = null;
        key = value?.requestKey;
      });
      if (value != null) accept(value);
    } catch (e) {
      if (mounted) setState(() => recoveryError = stylistError(e));
    } finally {
      if (mounted) setState(() => loadingRecovery = false);
    }
  }

  Future<void> useProfile() async {
    if (locked) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await ref.read(accountDetailsProvider.future);
      if (data.styleError != null) throw data.styleError!;
      if (mounted) {
        setState(() {
          size = data.style.size;
          budget = data.style.budget;
          style.text = data.style.style;
          color.text = data.style.color;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Chưa tải được hồ sơ phong cách. Bạn vẫn có thể chọn trực tiếp ở bên dưới.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> start() async {
    if (locked ||
        !consent ||
        availability?.configured != true ||
        availability!.remaining < 1) {
      return;
    }
    if (prompt.text.trim().isEmpty) {
      setState(() => error = 'Hãy nhập dịp hoặc cách phối đồ bạn muốn.');
      return;
    }
    key = const Uuid().v4();
    submitted = StylistRequest(
      prompt: prompt.text.trim(),
      budget: budget,
      size: size,
      style: style.text.trim(),
      color: color.text.trim(),
    );
    receipt = null;
    polls = 0;
    await submit();
  }

  void accept(StylistReceipt value) {
    if (!mounted) return;
    setState(() {
      receipt = value;
      error = value.errorCode == null ? null : stylistError(value.errorCode!);
    });
    if (value.pending && ++polls <= 20) {
      timer?.cancel();
      timer = Timer(const Duration(seconds: 2), () {
        unawaited(recover(repostMissing: false));
      });
    }
  }

  void failed(Object e, {bool posting = false}) {
    if (!mounted) return;
    setState(() {
      error = stylistError(e);
      if (posting &&
          e is ApiException &&
          ([400, 401, 403, 409, 429].contains(e.status) ||
              e.code == 'AI_PROVIDER_NOT_CONFIGURED')) {
        key = null;
        submitted = null;
      }
    });
  }

  Future<void> submit() async {
    if (key == null || submitted == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      accept(await repo.create(key!, submitted!, consent: consent));
    } catch (e) {
      failed(e, posting: true);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        unawaited(loadStatus());
      }
    }
  }

  Future<void> recover({bool repostMissing = true}) async {
    if (busy || key == null) return;
    timer?.cancel();
    setState(() {
      busy = true;
      error = null;
    });
    var missing = false;
    try {
      accept(await repo.get(key!));
    } on ApiException catch (e) {
      missing = e.status == 404 && repostMissing;
      if (!missing) failed(e);
    } catch (e) {
      failed(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted) return;
    if (missing) {
      await submit();
    } else {
      unawaited(loadStatus());
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = availability;
    final canSend =
        !locked && consent && info?.configured == true && info!.remaining > 0;
    final budgets = {
      ...[800000, 1500000, 2500000],
      budget,
    }.toList()..sort();
    final sizes = {
      ...['XS', 'S', 'M', 'L', 'XL', 'XXL'],
      size,
    }.toList();
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kế hoạch của bạn', style: T.display(26)),
        const SizedBox(height: 16),
        TextField(
          controller: prompt,
          minLines: 2,
          maxLines: 4,
          maxLength: 1000,
          enabled: !locked,
          decoration: const InputDecoration(
            labelText: 'Bạn muốn phối đồ cho dịp nào?',
            hintText: 'Ví dụ: đi làm, thoải mái, dễ phối…',
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          'Dùng hồ sơ phong cách',
          outlined: true,
          onPressed: locked ? null : useProfile,
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          key: ValueKey('budget-$budget'),
          initialValue: budget,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Ngân sách cả trang phục',
          ),
          items: budgets
              .map((b) => DropdownMenuItem(value: b, child: Text(money(b))))
              .toList(),
          onChanged: locked ? null : (b) => setState(() => budget = b!),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('size-$size'),
          initialValue: size,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Size mong muốn'),
          items: sizes
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: locked ? null : (s) => setState(() => size = s!),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: style,
          maxLength: 80,
          enabled: !locked,
          decoration: const InputDecoration(
            labelText: 'Phong cách (không bắt buộc)',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: color,
          maxLength: 80,
          enabled: !locked,
          decoration: const InputDecoration(
            labelText: 'Màu (để trống nếu không giới hạn)',
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: consent,
          onChanged: locked
              ? null
              : (v) => setState(() => consent = v ?? false),
          title: const Text(
            'Tôi đồng ý gửi nội dung và lựa chọn ở trên tới Google Gemini để nhận gợi ý.',
          ),
          subtitle: const Text(
            'Không nhập thông tin riêng tư. Gợi ý được lưu tối đa 24 giờ tại cửa hàng.',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppButton(
              receipt == null ? 'Nhờ Gemini gợi ý' : 'Yêu cầu mới',
              busy: busy && !unresolved,
              onPressed: canSend ? start : null,
              icon: Icons.auto_awesome_outlined,
            ),
            if (unresolved)
              AppButton(
                'Kiểm tra / thử lại yêu cầu',
                busy: busy,
                onPressed: busy ? null : () => recover(),
              ),
          ],
        ),
      ],
    );
    final result = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gợi ý theo catalog', style: T.display(26)),
        const SizedBox(height: 16),
        if (busy || receipt?.pending == true)
          Semantics(
            liveRegion: true,
            child: const Text(
              'Đang tìm trang phục phù hợp. Yêu cầu được giữ lại để kiểm tra kết quả.',
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (receipt?.message != null) ...[
          Text(receipt!.message!),
          const SizedBox(height: 16),
          Text(
            'Tổng trang phục: ${money(receipt!.total)}',
            style: T.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Giá và tồn kho được kiểm tra khi nhận gợi ý. Vui lòng kiểm tra lại trên trang sản phẩm trước khi mua.',
            style: T.small,
          ),
          for (final pick in receipt!.picks)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    height: 116,
                    child: FashionImage(
                      pick.product.image,
                      label: pick.product.name,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pick.product.name,
                          style: T.body.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text('${pick.variant.size} · ${pick.variant.color}'),
                        Text(money(pick.variant.price)),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.go(
                            '/products/${Uri.encodeComponent(pick.product.slug)}',
                          ),
                          child: const Text('Xem sản phẩm'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ] else if (!busy && error == null && receipt?.pending != true)
          const Text(
            'Gemini sẽ chọn các món còn hàng theo size và ngân sách của bạn. Gợi ý chưa bao gồm phí vận chuyển.',
          ),
        if (receipt != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              'Chi phí dịch vụ ước tính của lượt này: ${money(receipt!.estimatedCost)}. Đây không phải khoản thu trong đơn hàng.',
              style: T.small,
            ),
          ),
      ],
    );
    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Góc stylist của bạn.',
            style: T.display(MediaQuery.sizeOf(context).width < 600 ? 36 : 48),
          ),
          const SizedBox(height: 12),
          const Text('Gợi ý từ Gemini, đối chiếu với sản phẩm của cửa hàng.'),
          const SizedBox(height: 24),
          if (loadingStatus) const LinearProgressIndicator(),
          if (loadingRecovery)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('Đang lấy lại gợi ý gần nhất của bạn…'),
            ),
          if (recoveryError != null)
            StatePanel(
              title: 'Chưa lấy lại được gợi ý gần nhất',
              message:
                  'Kiểm tra yêu cầu đã gửi trước khi tạo lượt mới. ${recoveryError!}',
              action: AppButton(
                'Tải lại gợi ý gần nhất',
                onPressed: loadingRecovery ? null : loadLatest,
              ),
            ),
          if (statusError != null)
            StatePanel(
              title: 'Chưa kiểm tra được dịch vụ',
              message: statusError!,
              action: AppButton('Kiểm tra lại dịch vụ', onPressed: loadStatus),
            ),
          if (info != null) ...[
            if (!info.configured)
              const StatePanel(
                title: 'Gemini chưa được cấu hình',
                message:
                    'Dịch vụ đang chờ cửa hàng kích hoạt. Bạn có thể xem sản phẩm trong lúc chờ.',
              ),
            Text(
              'Đã dùng ${info.used} / ${info.limit} lượt hôm nay · Còn ${info.remaining} lượt',
              style: T.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Chi phí dịch vụ ước tính: ${money(info.estimatedPerRequest)} / yêu cầu; hôm nay ${money(info.estimatedUsed)}. Không cộng vào tiền hàng.',
              style: T.small,
            ),
            const SizedBox(height: 8),
            Text(
              'Đặt lại hạn mức: ${_date(info.resetsAt.toLocal())}. Yêu cầu đã được tiếp nhận sẽ tính một lượt, kể cả khi dịch vụ trả lỗi.',
              style: T.small,
            ),
          ],
          const SizedBox(height: 32),
          LayoutBuilder(
            builder: (_, c) => c.maxWidth < 850
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [form, const SizedBox(height: 32), result],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: form),
                      const SizedBox(width: 40),
                      Expanded(child: result),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
