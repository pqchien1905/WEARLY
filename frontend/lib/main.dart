import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/api_providers.dart';
import 'app/config.dart';
import 'core/network/local_browser_origin.dart';

void main() {
  // Real API is the application default. Fixtures require an explicit demo build.
  const demo = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
  const remoteApi = BrandConfig.useRemoteApi || !demo;
  const apiBaseUrl = BrandConfig.apiBaseUrl != ''
      ? BrandConfig.apiBaseUrl
      : 'http://localhost:3000/api/v1';
  if (remoteApi && redirectLocalBrowser(apiBaseUrl)) return;
  runApp(
    ProviderScope(
      overrides: [
        remoteApiProvider.overrideWithValue(remoteApi),
        apiBaseUrlProvider.overrideWithValue(apiBaseUrl),
      ],
      child: const NepApp(),
    ),
  );
}
