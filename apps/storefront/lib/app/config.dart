abstract final class BrandConfig {
  static const name = 'wearly';
  static const displayName = 'Wearly';
  static const title = '$displayName — Tủ đồ đương đại';
  static const email = 'hello@wearly.example';
  static const demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);
  static const shippingFee = 30000;
  static const freeShippingAt = 1500000;
  static const expressFee = 50000;
}
