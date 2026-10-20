bool isAdminPath(String path) => path == '/admin' || path.startsWith('/admin/');

/// Only return to a concrete page in the same sign-in area.
String loginDestination(String? next, {bool admin = false}) {
  final fallback = admin ? '/admin' : '/account';
  if (next == null ||
      !next.startsWith('/') ||
      next.startsWith('//') ||
      next.contains('\\') ||
      RegExp(r'[\x00-\x20]').hasMatch(next)) {
    return fallback;
  }
  final uri = Uri.tryParse(next);
  final rawPath = next.split(RegExp(r'[?#]')).first;
  if (uri == null ||
      uri.hasAuthority ||
      uri.hasScheme ||
      rawPath.contains('%') ||
      uri.pathSegments.any((s) => s == '.' || s == '..')) {
    return fallback;
  }
  // Uri normalizes dot segments; inspect the original path as well.
  if (rawPath.split('/').any((s) => s == '.' || s == '..')) {
    return fallback;
  }
  if (admin) {
    return isAdminPath(uri.path) &&
            uri.path != '/admin/login' &&
            !uri.path.startsWith('/admin/login/')
        ? next
        : fallback;
  }
  return !isAdminPath(uri.path) &&
          ![
            '/login',
            '/register',
            '/forgot-password',
            '/reset-password',
          ].contains(uri.path)
      ? next
      : fallback;
}
