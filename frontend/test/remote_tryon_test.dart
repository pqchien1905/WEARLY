import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/core/design/tokens.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/data/remote_catalog.dart';
import 'package:nep_storefront/features/virtual_tryon/remote_tryon_page.dart';
import 'package:nep_storefront/features/virtual_tryon/remote_tryon_history.dart';
import 'package:nep_storefront/features/virtual_tryon/private_remote_image.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_tryon.dart';
import 'remote_session_test.dart' show jsonResponse;
import 'remote_catalog_test.dart' show productJson;
import 'tryon_replacement_test.dart' show PhotoPicker, DelayedPhoto;

const photoId = '56c7f311-0efa-40da-bd51-d53eb42e81a0';
const jobId = '6e25d71e-75bb-4212-a6c5-7b3ce9f311f9';
const tryonKey = '79b8ba48-ecbb-4563-b3fc-539656d6d613';
Map<String, Object?> privatePhoto() => {
  'id': photoId,
  'requestKey': tryonKey,
  'mimeType': 'image/png',
  'size': 100,
  'width': 64,
  'height': 80,
  'createdAt': '2026-10-22T12:00:00Z',
  'expiresAt': '2026-10-23T12:00:00Z',
};
Map<String, Object?> remoteJob({String status = 'completed'}) => {
  'id': jobId,
  'requestKey': tryonKey,
  'imageId': photoId,
  'sku': 'WRL-1-MAIN-M',
  'status': status,
  'errorCode': null,
  'estimatedCostVnd': '3000',
  'resultAvailable': status == 'completed',
  'createdAt': '2026-10-22T12:00:00Z',
  'expiresAt': '2026-10-23T12:00:00Z',
};
Map<String, Object?> tryonStatus({bool configured = true, int remaining = 3}) =>
    {
      'configured': configured,
      'model': 'gemini-fixture',
      'used': 3 - remaining,
      'limit': 3,
      'remaining': remaining,
      'estimatedUsedVnd': '${(3 - remaining) * 3000}',
      'estimatedPerRequestVnd': '3000',
      'costIsEstimate': true,
      'resetsAt': '2026-10-23T00:00:00Z',
    };
void main() {
  ApiClient client(Future<http.Response> Function(http.Request) handler) {
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(handler),
    );
    api.tokens.set(accessToken: 'access', userId: 'customer');
    addTearDown(api.close);
    return api;
  }

  Future<void> mount(
    WidgetTester t,
    ApiClient api, {
    double width = 1000,
    Widget page = const RemoteTryOnPage(slug: 'nep-1'),
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(width, 1100);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final catalog = MockProductRepository(latency: Duration.zero);
    catalog.products
      ..clear()
      ..add(RemoteProductRepository.productFromJson(productJson()));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          productRepositoryProvider.overrideWithValue(catalog),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: SingleChildScrollView(child: page)),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String label) async {
    final target = find.widgetWithText(FilledButton, label);
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  Future<void> agree(WidgetTester t) async {
    final target = find.byKey(const ValueKey('tryon-ai-consent'));
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  http.Response defaultRead(
    http.Request r, {
    List<Object?> jobs = const [],
    bool configured = true,
  }) {
    if (r.url.path.endsWith('/status')) {
      return jsonResponse(tryonStatus(configured: configured));
    }
    if (r.url.path.endsWith('/jobs')) return jsonResponse({'items': jobs});
    if (r.url.path.endsWith('/images')) {
      return jsonResponse({
        'items': [privatePhoto()],
      });
    }
    // Byte loading failure is shown locally, never a fake result image.
    return jsonResponse({
      'error': {'code': 'STORAGE_UNAVAILABLE'},
    }, 503);
  }

  testWidgets(
    'missing configuration is honest and cannot create a simulated paid result',
    (t) async {
      var posts = 0;
      await mount(
        t,
        client((r) async {
          if (r.method == 'POST') posts++;
          return defaultRead(r, configured: false);
        }),
      );
      expect(find.text('Gemini chưa được cấu hình'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Thử trang phục'),
            )
            .onPressed,
        isNull,
      );
      expect(posts, 0);
    },
  );
  testWidgets(
    'owned photo still requires AI consent and a real selected SKU at375px',
    (t) async {
      var posts = 0;
      await mount(
        t,
        client((r) async {
          if (r.method == 'POST') {
            posts++;
            expect(jsonDecode(r.body), containsPair('sku', 'WRL-1-MAIN-M'));
            return jsonResponse(remoteJob(status: 'failed'));
          }
          return defaultRead(r);
        }),
        width: 375,
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Thử trang phục'),
            )
            .onPressed,
        isNull,
      );
      await agree(t);
      await tap(t, 'Thử trang phục');
      expect(posts, 1);
      expect(find.textContaining('không đảm bảo độ vừa vặn'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'lost job reply recovers through the owned list without a second POST',
    (t) async {
      var writes = 0;
      String? acceptedKey;
      await mount(
        t,
        client((r) async {
          if (r.method == 'POST') {
            writes++;
            acceptedKey = r.headers['Idempotency-Key'];
            throw http.ClientException('lost');
          }
          return defaultRead(
            r,
            jobs: acceptedKey == null
                ? []
                : [
                    {...remoteJob(), 'requestKey': acceptedKey},
                  ],
          );
        }),
      );
      await agree(t);
      await tap(t, 'Thử trang phục');
      await tap(t, 'Kiểm tra yêu cầu đã gửi');
      expect(writes, 1);
      expect(find.text('Đã tạo ảnh thử đồ'), findsOneWidget);
    },
  );
  testWidgets('reopening restores a completed job using GET only', (t) async {
    var writes = 0;
    final api = client((r) async {
      if (r.method == 'POST') writes++;
      return defaultRead(r, jobs: [remoteJob()]);
    });
    await mount(t, api);
    expect(find.text('Đã tạo ảnh thử đồ'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await mount(t, api);
    expect(find.text('Đã tạo ảnh thử đồ'), findsOneWidget);
    expect(writes, 0);
  });
  testWidgets('pending job polls status without creating another job', (
    t,
  ) async {
    var gets = 0, writes = 0;
    await mount(
      t,
      client((r) async {
        if (r.method == 'POST') writes++;
        if (r.url.path.endsWith('/jobs/$jobId')) {
          gets++;
          return jsonResponse(remoteJob());
        }
        return defaultRead(r, jobs: [remoteJob(status: 'processing')]);
      }),
    );
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(gets, 1);
    expect(writes, 0);
    expect(find.text('Đã tạo ảnh thử đồ'), findsOneWidget);
  });

  testWidgets('an accepted failed job needs an explicit new request key', (
    t,
  ) async {
    final keys = <String>[];
    await mount(
      t,
      client((r) async {
        if (r.method == 'POST') {
          keys.add(r.headers['Idempotency-Key']!);
          return jsonResponse({
            ...remoteJob(status: 'failed'),
            'requestKey': keys.last,
          });
        }
        return defaultRead(r);
      }),
    );
    await agree(t);
    await tap(t, 'Thử trang phục');
    await t.pump(const Duration(seconds: 10));
    expect(keys.length, 1);
    await tap(t, 'Thử lượt mới');
    expect(keys.length, 2);
    expect(keys.first, isNot(keys.last));
  });

  testWidgets('quota exhausted shows allowance and disables generation', (
    t,
  ) async {
    var writes = 0;
    await mount(
      t,
      client((r) async {
        if (r.method == 'POST') writes++;
        if (r.url.path.endsWith('/status')) {
          return jsonResponse(tryonStatus(remaining: 0));
        }
        return defaultRead(r);
      }),
    );
    await agree(t);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Thử trang phục'),
          )
          .onPressed,
      isNull,
    );
    expect(writes, 0);
    expect(find.textContaining('ước tính'), findsWidgets);
  });

  testWidgets(
    'upload needs separate consent and lost reply recovers without another upload',
    (t) async {
      final original = FileSelectorPlatform.instance;
      addTearDown(() => FileSelectorPlatform.instance = original);
      final image = (await rootBundle.load(
        'assets/images/shirt.jpg',
      )).buffer.asUint8List();
      final file = XFile.fromData(image, name: 'private.jpg');
      FileSelectorPlatform.instance = PhotoPicker(file, file);
      String? accepted;
      var uploads = 0, generations = 0;
      await mount(
        t,
        client((r) async {
          if (r.method == 'POST' && r.url.path.endsWith('/images')) {
            uploads++;
            accepted = r.headers['Idempotency-Key'];
            expect(r.headers['content-type'], contains('multipart/form-data'));
            throw http.ClientException('lost upload reply');
          }
          if (r.method == 'POST') generations++;
          if (r.url.path.endsWith('/images')) {
            return jsonResponse({
              'items': accepted == null
                  ? []
                  : [
                      {...privatePhoto(), 'requestKey': accepted},
                    ],
            });
          }
          return defaultRead(r);
        }),
      );
      await t.runAsync(() async {
        await t.tap(find.text('Chọn ảnh từ thiết bị'));
        for (
          var i = 0;
          i < 100 && find.text('Lưu ảnh riêng tư').evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await t.pump();
        }
      });
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Lưu ảnh riêng tư'),
            )
            .onPressed,
        isNull,
      );
      expect(uploads, 0);
      final consent = find.byKey(const ValueKey('tryon-upload-consent'));
      await t.ensureVisible(consent);
      await t.tap(consent);
      await t.pumpAndSettle();
      await tap(t, 'Lưu ảnh riêng tư');
      await tap(t, 'Kiểm tra ảnh đã gửi');
      expect(uploads, 1);
      expect(generations, 0);
      expect(find.text('Kiểm tra ảnh đã gửi'), findsNothing);
      expect(
        t
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('tryon-ai-consent')),
            )
            .value,
        isFalse,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'replacement blocks generation and late picked bytes cannot revive a disposed page',
    (t) async {
      final original = FileSelectorPlatform.instance;
      addTearDown(() => FileSelectorPlatform.instance = original);
      final pending = DelayedPhoto();
      FileSelectorPlatform.instance = PhotoPicker(pending, pending);
      var writes = 0;
      await mount(
        t,
        client((r) async {
          if (r.method == 'POST') writes++;
          return defaultRead(r);
        }),
      );
      await agree(t);
      final choose = find.widgetWithText(OutlinedButton, 'Đổi ảnh');
      await t.ensureVisible(choose);
      await t.tap(choose);
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Thử trang phục'),
            )
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
      pending.data.complete(Uint8List.fromList([255, 216, 255]));
      await t.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(writes, 0);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('corrupt photo is rejected before upload or generation', (
    t,
  ) async {
    final original = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = original);
    final file = XFile.fromData(
      Uint8List.fromList([255, 216, 255, 0]),
      name: 'bad.jpg',
    );
    FileSelectorPlatform.instance = PhotoPicker(file, file);
    var writes = 0;
    await mount(
      t,
      client((r) async {
        if (r.method == 'POST') writes++;
        return defaultRead(r);
      }),
    );
    final choose = find.widgetWithText(OutlinedButton, 'Đổi ảnh');
    await t.ensureVisible(choose);
    await t.runAsync(() async {
      await t.tap(choose);
      for (
        var i = 0;
        i < 100 && find.textContaining('Không đọc được ảnh').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await t.pump();
      }
    });
    await t.pumpAndSettle();
    expect(find.textContaining('Không đọc được ảnh'), findsOneWidget);
    expect(find.text('Lưu ảnh riêng tư'), findsNothing);
    expect(writes, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'history deletion hides an in-flight result and removes all jobs for the photo',
    (t) async {
      final pending = Completer<http.Response>();
      var deletes = 0, bytesRequested = 0;
      await mount(
        t,
        client((r) async {
          if (r.method == 'DELETE') {
            deletes++;
            expect(r.url.path.endsWith('/images/$photoId'), isTrue);
            return jsonResponse({'ok': true});
          }
          if (r.url.path.endsWith('/result')) {
            bytesRequested++;
            return pending.future;
          }
          return defaultRead(
            r,
            jobs: [
              remoteJob(),
              {...remoteJob(), 'id': 'another-job'},
            ],
          );
        }),
        page: const RemoteTryOnHistory(),
      );
      expect(bytesRequested, 0);
      final show = find.widgetWithText(OutlinedButton, 'Xem ảnh thử đồ').first;
      await t.ensureVisible(show);
      await t.tap(show);
      await t.pump();
      expect(bytesRequested, 1);
      final remove = find
          .widgetWithText(OutlinedButton, 'Xóa ảnh và các kết quả')
          .first;
      await t.ensureVisible(remove);
      await t.tap(remove);
      await t.pumpAndSettle();
      expect(deletes, 1);
      expect(find.byType(PrivateRemoteImage), findsNothing);
      expect(find.text('Xóa ảnh và các kết quả'), findsNothing);
      pending.complete(
        http.Response.bytes(
          [255, 216, 255],
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  test(
    'private image bytes require auth, preserve binary content and reject wrong formats',
    () async {
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      final api = client((r) async {
        expect(r.headers['Authorization'], 'Bearer access');
        expect(r.headers['Accept'], contains('image/png'));
        return http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      expect(await api.getBytes('uploads/images/$photoId/content'), bytes);
      final wrong = client(
        (_) async => http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(
        wrong.getBytes('uploads/images/$photoId/content'),
        throwsA(isA<ApiException>()),
      );
      final oversized = client(
        (_) async => http.Response.bytes(
          Uint8List(8 * 1024 * 1024 + 1),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await expectLater(
        oversized.getBytes('uploads/images/$photoId/content'),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'private bytes arriving after an account change are discarded',
    () async {
      final pending = Completer<http.Response>();
      final api = client((_) => pending.future);
      final result = api.getBytes('ai/try-on/jobs/$jobId/result');
      final denied = expectLater(
        result,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      api.tokens.clear();
      pending.complete(
        http.Response.bytes(
          [255, 216, 255],
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      );
      await denied;
    },
  );
  test(
    'job creation sends stable key and explicit consent; recovery is read only',
    () async {
      final methods = <String>[];
      final repo = RemoteTryOnRepository(
        client((r) async {
          methods.add(r.method);
          if (r.method == 'POST') {
            expect(r.headers['Idempotency-Key'], tryonKey);
            expect(jsonDecode(r.body), {
              'imageId': photoId,
              'sku': 'WRL-1-MAIN-M',
              'consent': true,
            });
            return jsonResponse(remoteJob(status: 'pending'));
          }
          if (r.url.path.endsWith('/jobs')) {
            return jsonResponse({
              'items': [remoteJob()],
            });
          }
          return jsonResponse(remoteJob());
        }),
      );
      final created = await repo.create(
        tryonKey,
        photoId,
        'WRL-1-MAIN-M',
        consent: true,
      );
      expect(created.pending, isTrue);
      expect((await repo.jobs()).single.requestKey, tryonKey);
      expect((await repo.get(jobId)).resultAvailable, isTrue);
      expect(methods, ['POST', 'GET', 'GET']);
    },
  );
  test(
    'owned photo list and usage retain expiry, key and estimated cost',
    () async {
      final repo = RemoteTryOnRepository(
        client(
          (r) async => jsonResponse(
            r.url.path.endsWith('/status')
                ? tryonStatus()
                : {
                    'items': [privatePhoto()],
                  },
          ),
        ),
      );
      expect((await repo.images()).single.requestKey, tryonKey);
      expect(
        (await repo.images()).single.expiresAt,
        DateTime.utc(2026, 10, 23, 12),
      );
      expect((await repo.status()).estimatedPerRequest, 3000);
    },
  );
}
