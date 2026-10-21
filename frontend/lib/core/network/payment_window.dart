import '../../data/remote_payments.dart';
import 'payment_window_stub.dart'
    if (dart.library.js_interop) 'payment_window_web.dart'
    as platform;

void openPaymentWindow(Uri url) =>
    platform.openPaymentWindow(sandboxPaymentUrl(url.toString()));
