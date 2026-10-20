final managedCatalogImage = RegExp(
  r'^catalog/images/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String? catalogImageUrl(String baseUrl, String reference) {
  if (!managedCatalogImage.hasMatch(reference)) return null;
  final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
  return base.resolve(reference).toString();
}
