import 'local_browser_origin_stub.dart'
    if (dart.library.js_interop) 'local_browser_origin_web.dart'
    as platform;

/// Local cookies and CORS use the API's configured host. Keep the page on that
/// host too, before restoring either browser session. Never redirect remote
/// deployments or change the page's port, route, query, or recovery fragment.
Uri? localBrowserRedirect(Uri page, Uri api) {
  const loopback = {'localhost', '127.0.0.1', '::1', '[::1]'};
  if (page.scheme != 'http' ||
      api.scheme != 'http' ||
      !loopback.contains(page.host) ||
      !loopback.contains(api.host) ||
      page.host == api.host ||
      page.userInfo.isNotEmpty ||
      api.userInfo.isNotEmpty) {
    return null;
  }
  return page.replace(host: api.host);
}

bool redirectLocalBrowser(String apiBaseUrl) {
  final api = Uri.tryParse(apiBaseUrl);
  if (api == null) return false;
  final destination = localBrowserRedirect(Uri.base, api);
  if (destination == null) return false;
  return platform.replaceBrowserLocation(destination.toString());
}
