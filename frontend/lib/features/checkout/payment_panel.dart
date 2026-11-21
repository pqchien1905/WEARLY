import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/account_state.dart';
import '../../core/network/api_client.dart';
import 'package:go_router/go_router.dart';
import '../../app/commerce_state.dart';
import '../../app/payment_providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/remote_payments.dart';
import '../../domain/commerce.dart';

/// Payment block shown on an order. One primary action ("Thanh toán ngay")
/// opens the gateway in a new tab and this tab watches the result; the gateway
/// tab returns to /payments/return, which verifies it too. Opening the order
/// verifies a pending payment once, so a payment finished elsewhere shows up.
class PaymentPanel extends ConsumerStatefulWidget {
  const PaymentPanel({
    super.key,
    required this.order,
    this.onRefresh,
    this.enabled = true,
    this.autoCheck = true,
    this.framed = true,
  });
  final Order order;
  final Future<void> Function()? onRefresh;
  final bool enabled;
  final bool autoCheck;

  /// False when placed inside another card (order detail): no own border.
  final bool framed;
  @override
  ConsumerState<PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends ConsumerState<PaymentPanel> {
  PaymentState? result;
  bool busy = false, checking = false;
  String? error, notice;

  /// While the gateway tab is open this tab asks for the result periodically,
  /// so a payment finished there shows up here without a reload.
  Timer? watch;
  DateTime? watchUntil;
  static const _watchEvery = Duration(seconds: 10);

  static const _settled = ['PAID', 'PARTIALLY_REFUNDED', 'REFUNDED'];

  @override
  void dispose() {
    watch?.cancel();
    super.dispose();
  }

  bool get watching => watch != null;

  bool _open(PaymentState? state) =>
      state != null &&
      !_settled.contains(state.status) &&
      state.attemptStatus == 'PENDING' &&
      (state.expiresAt?.isAfter(DateTime.now()) ?? false);

  void _watch(DateTime until) {
    watchUntil = until;
    watch ??= Timer.periodic(_watchEvery, (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(watchUntil!)) {
        _stopWatching();
        return;
      }
      verify(silent: true);
    });
    if (mounted) setState(() {});
  }

  void _stopWatching() {
    watch?.cancel();
    watch = null;
    if (mounted) setState(() {});
  }

  void _afterResult(PaymentState state) {
    if (_open(state)) {
      _watch(state.expiresAt!);
    } else if (watching) {
      _stopWatching();
    }
  }

  @override
  void initState() {
    super.initState();
    final status = widget.order.paymentStatus;
    if (widget.autoCheck &&
        widget.enabled &&
        onlinePaymentProviders.contains(widget.order.paymentProvider) &&
        !_settled.contains(status) &&
        status != 'CANCELLED') {
      Future.microtask(() => verify(silent: true));
    }
  }

  Future<void> _refresh() async {
    try {
      await (widget.onRefresh?.call() ??
          ref.read(commerceProvider).refreshPaymentOrder(widget.order.id));
    } catch (_) {}
  }

  /// Starts (or resumes) a payment and opens the gateway in a new tab.
  Future<void> pay() async {
    if (busy || !widget.enabled) return;
    // A link that is still open is reopened at once, inside the click.
    final known = result?.checkoutUrl;
    if (known != null && _open(result)) {
      ref.read(paymentLauncherProvider)(known);
      _watch(result!.expiresAt!);
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final state = await ref
          .read(paymentRepositoryProvider)
          .start(widget.order.id);
      if (!mounted) return;
      setState(() => result = state);
      final url = state.checkoutUrl;
      if (_settled.contains(state.status)) {
        await _refresh();
      } else if (url != null) {
        ref.read(paymentLauncherProvider)(url);
        _watch(
          state.expiresAt ?? DateTime.now().add(const Duration(minutes: 15)),
        );
      } else {
        setState(
          () => error = 'Chưa tạo được trang thanh toán. Thử lại sau ít phút.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Asks the gateway for the result. Silent checks hide "too soon" errors.
  Future<void> verify({bool silent = false}) async {
    if (checking || !widget.enabled) return;
    setState(() {
      checking = true;
      error = null;
      notice = null;
    });
    try {
      final state = await ref
          .read(paymentRepositoryProvider)
          .reconcile(widget.order.id);
      if (!mounted) return;
      final wasPending = !_settled.contains(result?.status);
      setState(() {
        result = state;
        if (!silent && state.status == 'PENDING') {
          notice =
              'Chưa nhận được kết quả thanh toán. Nếu bạn vừa thanh toán, đợi ít phút rồi kiểm tra lại.';
        }
      });
      _afterResult(state);
      if (wasPending && _settled.contains(state.status) && mounted) {
        toast(context, 'Đã nhận thanh toán. Cảm ơn bạn!');
      }
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'PAYMENT_NOT_STARTED') {
        // Nothing to verify yet; the primary action starts the payment.
      } else if (!silent) {
        setState(() => error = e.message);
      }
    } catch (e) {
      if (mounted && !silent) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.order.paymentProvider;
    if (!onlinePaymentProviders.contains(provider)) {
      return const SizedBox.shrink();
    }
    final name = paymentProviderName(provider);
    final status = result?.status ?? widget.order.paymentStatus;
    final paid = _settled.contains(status);
    final canPay =
        !paid && status != 'CANCELLED' && widget.order.status == 'Chờ xác nhận';
    final (label, color, icon) = switch (status) {
      'PAID' => ('Đã thanh toán', T.success, Icons.check_circle_rounded),
      'PARTIALLY_REFUNDED' => (
        'Đã hoàn một phần',
        T.warning,
        Icons.replay_rounded,
      ),
      'REFUNDED' => ('Đã hoàn tiền', T.muted, Icons.replay_rounded),
      'FAILED' => (
        'Thanh toán chưa thành công',
        T.danger,
        Icons.error_outline_rounded,
      ),
      'CANCELLED' => ('Đã hủy thanh toán', T.muted, Icons.block_rounded),
      _ => ('Chờ thanh toán', T.warning, Icons.schedule_rounded),
    };
    final message = paid
        ? 'Đã nhận thanh toán qua $name.'
        : !canPay
        ? 'Đơn hàng không còn chờ thanh toán.'
        : status == 'FAILED'
        ? 'Giao dịch trước chưa thành công. Bạn chưa bị trừ tiền, có thể thanh toán lại.'
        : watching
        ? 'Trang $name đã mở ở tab mới. Hoàn tất thanh toán ở đó, trang này sẽ tự cập nhật.'
        : 'Hoàn tất thanh toán qua $name để cửa hàng xác nhận và giao đơn.';
    return Container(
      margin: EdgeInsets.symmetric(vertical: widget.framed ? 20 : 0),
      padding: widget.framed
          ? const EdgeInsets.all(20)
          : const EdgeInsets.only(top: 24),
      decoration: widget.framed
          ? BoxDecoration(
              color: T.surface,
              borderRadius: T.panelRadius,
              border: Border.all(color: T.line),
            )
          : const BoxDecoration(
              border: Border(top: BorderSide(color: T.line)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Thanh toán qua $name',
                  style: T.body.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusChip(label: label, color: color, icon: icon),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: T.body.copyWith(color: T.muted)),
          if (watching && canPay)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Icon(Icons.sync_rounded, size: 16, color: T.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đang chờ kết quả từ $name…',
                      style: T.small.copyWith(color: T.accent),
                    ),
                  ),
                ],
              ),
            ),
          if (result?.reviewRequired == true)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Có khoản thanh toán cần cửa hàng kiểm tra. Vui lòng liên hệ hỗ trợ.',
                style: TextStyle(color: T.danger),
              ),
            ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(notice!, style: T.small),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: T.danger)),
            ),
          if (canPay) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppButton(
                  status == 'FAILED'
                      ? 'Thanh toán lại'
                      : watching
                      ? 'Mở lại trang thanh toán'
                      : 'Thanh toán ngay',
                  icon: Icons.open_in_new_rounded,
                  busy: busy,
                  onPressed: busy || checking || !widget.enabled ? null : pay,
                ),
                TextButton.icon(
                  onPressed: busy || checking || !widget.enabled
                      ? null
                      : () => verify(),
                  icon: checking
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Kiểm tra kết quả'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Môi trường thử nghiệm: không trừ tiền thật.',
                style: T.small,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: T.small.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Landing page after a gateway sends the shopper back. The server redirect
/// names the order; the result shown here always comes from asking the
/// provider (reconcile), never from the gateway's query string.
class PaymentReturnPage extends StatelessWidget {
  const PaymentReturnPage({super.key, this.orderId, this.declined = false});
  final String? orderId;

  /// The gateway reported a cancel/failure. Only changes wording and skips
  /// polling; the payment state still comes from the server.
  final bool declined;
  @override
  Widget build(BuildContext context) {
    final id = orderId;
    if (id == null || !_uuid.hasMatch(id)) {
      return const PageBody(child: _ReturnContent());
    }
    return _SignedInResult(orderId: id, declined: declined);
  }
}

class _SignedInResult extends ConsumerWidget {
  const _SignedInResult({required this.orderId, required this.declined});
  final String orderId;
  final bool declined;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = orderId;
    if (ref.watch(accountProvider) == null) {
      return PageBody(
        child: StatePanel(
          title: 'Đăng nhập để xem kết quả thanh toán',
          message:
              'Phiên đăng nhập đã hết. Đăng nhập lại rồi mở lịch sử đơn hàng để kiểm tra kết quả.',
          icon: Icons.lock_outline,
          action: AppButton('Đăng nhập', onPressed: () => context.go('/login')),
        ),
      );
    }
    return PageBody(
      child: _PaymentResult(orderId: id, declined: declined),
    );
  }
}

enum _Phase { checking, paid, failed, pending, error }

class _PaymentResult extends ConsumerStatefulWidget {
  const _PaymentResult({required this.orderId, required this.declined});
  final String orderId;
  final bool declined;
  @override
  ConsumerState<_PaymentResult> createState() => _PaymentResultState();
}

class _PaymentResultState extends ConsumerState<_PaymentResult> {
  static const _interval = Duration(seconds: 11);
  static const _maxChecks = 6;
  _Phase phase = _Phase.checking;
  String provider = '';
  bool reviewRequired = false, paying = false;
  int checks = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    check();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void schedule() {
    timer?.cancel();
    timer = Timer(_interval, check);
  }

  Future<void> check() async {
    timer?.cancel();
    if (!mounted) return;
    setState(() => phase = _Phase.checking);
    checks++;
    try {
      final state = await ref
          .read(paymentRepositoryProvider)
          .reconcile(widget.orderId);
      if (!mounted) return;
      provider = state.provider;
      reviewRequired = state.reviewRequired;
      final paid = const [
        'PAID',
        'PARTIALLY_REFUNDED',
        'REFUNDED',
      ].contains(state.status);
      // A cancel reported by the gateway is final for this visit; the
      // provider may keep the attempt pending until it expires.
      final failed =
          const ['FAILED', 'CANCELLED'].contains(state.status) ||
          (!paid && widget.declined);
      setState(
        () => phase = paid
            ? _Phase.paid
            : failed
            ? _Phase.failed
            : checks < _maxChecks
            ? _Phase.checking
            : _Phase.pending,
      );
      if (!paid && !failed && checks < _maxChecks) schedule();
      try {
        await ref.read(commerceProvider).refreshPaymentOrder(widget.orderId);
      } catch (_) {}
    } on ApiException catch (e) {
      if (!mounted) return;
      // Another check ran moments ago (e.g. from the order page): wait it out.
      final retry = e.status == 429 || e.status == 503;
      if (widget.declined) {
        // The gateway already said it did not go through: offer a retry now.
        setState(() => phase = _Phase.failed);
      } else if (retry && checks < _maxChecks) {
        schedule();
      } else {
        setState(() => phase = _Phase.error);
      }
    } catch (_) {
      if (mounted) setState(() => phase = _Phase.error);
    }
  }

  Future<void> payAgain() async {
    if (paying) return;
    setState(() => paying = true);
    try {
      final state = await ref
          .read(paymentRepositoryProvider)
          .start(widget.orderId);
      final url = state.checkoutUrl;
      if (url != null && mounted) {
        ref.read(paymentLauncherProvider)(url);
        return;
      }
      if (mounted) context.go('/account/orders/${widget.orderId}');
    } catch (_) {
      if (mounted) context.go('/account/orders/${widget.orderId}');
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gateway = provider.isEmpty
        ? 'cổng thanh toán'
        : paymentProviderName(provider);
    final orderPath = '/account/orders/${widget.orderId}';
    final viewOrder = AppButton(
      'Xem đơn hàng',
      icon: Icons.receipt_long_outlined,
      onPressed: () => context.go(orderPath),
    );
    final (title, message, icon, action) = switch (phase) {
      _Phase.checking => (
        'Đang xác nhận thanh toán',
        'Cửa hàng đang hỏi $gateway kết quả giao dịch. Vui lòng giữ trang này trong giây lát.',
        Icons.hourglass_top_rounded,
        const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
            as Widget,
      ),
      _Phase.paid => (
        'Thanh toán thành công',
        reviewRequired
            ? 'Đã nhận thanh toán qua $gateway. Có chi tiết cần cửa hàng kiểm tra thêm, chúng tôi sẽ liên hệ nếu cần.'
            : 'Đơn hàng đã được thanh toán qua $gateway (môi trường thử nghiệm). Cảm ơn bạn! Bạn có thể đóng tab này.',
        Icons.check_circle_outline_rounded,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            viewOrder,
            AppButton(
              'Tiếp tục mua sắm',
              outlined: true,
              onPressed: () => context.go('/shop'),
            ),
          ],
        ),
      ),
      _Phase.failed => (
        'Thanh toán chưa hoàn tất',
        'Giao dịch qua $gateway đã bị hủy hoặc chưa hoàn tất, bạn chưa bị trừ tiền. Đơn hàng vẫn được giữ để bạn thanh toán lại.',
        Icons.error_outline_rounded,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            AppButton(
              'Thanh toán lại',
              icon: Icons.arrow_forward_rounded,
              busy: paying,
              onPressed: paying ? null : payAgain,
            ),
            AppButton(
              'Xem đơn hàng',
              outlined: true,
              onPressed: () => context.go(orderPath),
            ),
          ],
        ),
      ),
      _Phase.pending => (
        'Đang chờ $gateway xác nhận',
        'Giao dịch chưa có kết quả cuối cùng. Nếu bạn đã thanh toán, kết quả sẽ được cập nhật; bấm kiểm tra lại sau ít phút.',
        Icons.schedule_rounded,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            AppButton(
              'Kiểm tra lại',
              onPressed: () {
                checks = 0;
                check();
              },
            ),
            AppButton(
              'Xem đơn hàng',
              outlined: true,
              onPressed: () => context.go(orderPath),
            ),
          ],
        ),
      ),
      _Phase.error => (
        'Chưa kiểm tra được kết quả',
        'Không kết nối được tới máy chủ hoặc $gateway. Thử lại, hoặc mở đơn hàng và bấm “Kiểm tra kết quả”.',
        Icons.cloud_off_outlined,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            AppButton(
              'Thử lại',
              onPressed: () {
                checks = 0;
                check();
              },
            ),
            AppButton(
              'Xem đơn hàng',
              outlined: true,
              onPressed: () => context.go(orderPath),
            ),
          ],
        ),
      ),
    };
    return Semantics(
      liveRegion: true,
      child: StatePanel(
        title: title,
        message: message,
        icon: icon,
        action: action,
      ),
    );
  }
}

class _ReturnContent extends StatelessWidget {
  const _ReturnContent();
  @override
  Widget build(BuildContext context) => StatePanel(
    title: 'Đã quay lại từ trang thanh toán thử nghiệm',
    message:
        'Trở về tab cửa hàng ban đầu và bấm “Kiểm tra kết quả” trong đơn hàng. Nếu đã đóng tab đó, đăng nhập lại và mở lịch sử đơn hàng để kiểm tra.',
    icon: Icons.receipt_long_outlined,
    action: AppButton(
      'Lịch sử đơn hàng',
      onPressed: () => context.go('/account/orders'),
    ),
  );
}
