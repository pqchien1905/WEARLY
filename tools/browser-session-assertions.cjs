// Anonymous startup probes are expected; every other HTTP error remains visible.
exports.isAnonymousRestore = response => response.status === 401 &&
  /^\/api\/v1\/auth\/browser\/(customer|admin)\/refresh$/.test(response.path);
