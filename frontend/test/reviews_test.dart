import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_reviews.dart';
import 'remote_session_test.dart' show jsonResponse;

Map<String, dynamic> reviewJson({
  int rating = 4,
  String comment = 'Cotton mềm',
}) => {
  'id': 'r1',
  'rating': rating,
  'comment': comment,
  'createdAt': '2026-10-18T08:00:00.000Z',
  'updatedAt': '2026-10-18T08:00:00.000Z',
};
Map<String, dynamic> reviewPageJson(
  List<Map<String, dynamic>> items, {
  int page = 1,
  int? total,
}) => {
  'items': items,
  'total': total ?? items.length,
  'page': page,
  'limit': 5,
  'average': items.isEmpty ? null : 4,
};

void main() {
  test('API-valid supplementary characters decode without hiding the page', () {
    final value = ProductReview.fromJson(reviewJson(comment: '😀' * 1500));
    expect(value.comment.runes.length, 1500);
  });
  test(
    'commit after timeout and logout refreshes public data again without replay',
    () async {
      final lateResponse = Completer<http.Response>();
      var committed = false, writes = 0;
      final reads = <Future<ReviewPage>>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        timeout: const Duration(milliseconds: 15),
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return jsonResponse(reviewPageJson([if (committed) reviewJson()]));
          }
          writes++;
          return lateResponse.future;
        }),
      );
      addTearDown(api.close);
      api.tokens.set(accessToken: 'buyer', refreshToken: 'refresh');
      final repo = OwnerReviewRepository(
        api,
        onSettled: (id) {
          reads.add(PublicReviewRepository(api).list(id, 1));
        },
      );
      await expectLater(
        repo.save('product', rating: 4, comment: 'Cotton mềm'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
      );
      expect((await reads.single).total, 0);
      repo.dispose();
      api.tokens.clear();
      committed = true;
      lateResponse.complete(jsonResponse(reviewJson()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reads.length, 2);
      expect((await reads.last).total, 1);
      expect(writes, 1);
    },
  );
  test(
    'public review reads are anonymous and preserve paging/empty/error',
    () async {
      var status = 200;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          expect(r.headers['authorization'], isNull);
          expect(r.url.queryParameters, {'page': '2', 'limit': '5'});
          return jsonResponse(reviewPageJson([], page: 2), status);
        }),
      );
      addTearDown(api.close);
      api.tokens.set(accessToken: 'private', refreshToken: 'private');
      final page = await PublicReviewRepository(api).list('product', 2);
      expect(page.average, isNull);
      expect(page.items, isEmpty);
      expect(page.hasNext, isFalse);
      status = 503;
      await expectLater(
        PublicReviewRepository(api).list('product', 2),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'owner sends exact CAS body and invalidates after lost response without replay',
    () async {
      final requests = <http.Request>[];
      var settled = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          requests.add(r);
          if (r.method == 'GET') {
            return jsonResponse({'canReview': true, 'review': reviewJson()});
          }
          throw http.ClientException('Response lost after commit');
        }),
      );
      addTearDown(api.close);
      api.tokens.set(accessToken: 'buyer', refreshToken: 'refresh');
      final repo = OwnerReviewRepository(api, onSettled: (_) => settled++);
      final mine = await repo.mine('product');
      await expectLater(
        repo.save(
          'product',
          rating: 5,
          comment: 'Updated',
          previous: mine.review,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(requests.last.method, 'PATCH');
      expect(jsonDecode(requests.last.body), {
        'rating': 5,
        'comment': 'Updated',
        'expectedUpdatedAt': mine.review!.updatedAt,
      });
      expect(settled, 1);
      expect(requests.length, 2);
    },
  );
  test(
    'late committed response after logout cannot restore owner state but refreshes public data',
    () async {
      final response = Completer<http.Response>();
      var settled = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((_) => response.future),
      );
      addTearDown(api.close);
      api.tokens.set(accessToken: 'buyer', refreshToken: 'refresh');
      final repo = OwnerReviewRepository(api, onSettled: (_) => settled++);
      final pending = repo.save('product', rating: 4, comment: 'Good');
      final assertion = expectLater(
        pending,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      api.tokens.clear();
      repo.dispose();
      response.complete(jsonResponse(reviewJson()));
      await assertion;
      expect(settled, 1);
      await expectLater(repo.mine('product'), throwsA(isA<ApiException>()));
    },
  );
}
