import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote_payments.dart';
import '../core/network/payment_window.dart';
import 'api_providers.dart';

final paymentRepositoryProvider = Provider(
  (ref) => RemotePaymentRepository(ref.watch(apiClientProvider)),
);
final paymentMethodsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(paymentRepositoryProvider).available(),
);
final paymentLauncherProvider = Provider<void Function(Uri)>(
  (ref) => openPaymentWindow,
);
