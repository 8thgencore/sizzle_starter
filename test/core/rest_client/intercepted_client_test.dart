import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:sizzle_starter/src/core/rest_client/src/interceptor/intercepted_client.dart';

class FakeSequentialHttpInterceptorHeaders extends SequentialHttpInterceptor {
  final Map<String, String> headers;

  FakeSequentialHttpInterceptorHeaders(this.headers);

  int requestCount = 0;
  int responseCount = 0;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    request.headers.addAll(headers);
    handler.next(request);
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    responseCount++;
    handler.next(response);
  }
}

class FakeSequentialHttpInterceptorDeclining extends SequentialHttpInterceptor {
  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    handler.reject('rejected');
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    handler.reject('rejected');
  }
}

void main() {
  group('InterceptedClient', () {
    test('should intercept request', () async {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['foo'] = 'bar');
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      await expectLater(
        response,
        completion(
          predicate<StreamedResponse>((response) => response.statusCode == 200),
        ),
      );

      expect(req.headers['foo'], 'bar');
    });

    test('should intercept response', () async {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptResponse: (response, handler) {
              final res = Response(
                response.body,
                response.statusCode,
                headers: {...response.headers, 'foo': 'bar'},
              );
              handler.next(res);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      await expectLater(
        response,
        completion(
          predicate<StreamedResponse>(
            (response) =>
                response.statusCode == 200 && response.headers['foo'] == 'bar',
          ),
        ),
      );
    });

    test('should work together', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['foo'] = 'bar');
            },
            interceptResponse: (response, handler) {
              final res = Response(
                response.body,
                response.statusCode,
                headers: {...response.headers, 'foo': 'bar'},
              );
              handler.next(res);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      expectLater(
        response,
        completion(
          predicate<StreamedResponse>(
            (response) =>
                response.statusCode == 200 && response.headers['foo'] == 'bar',
          ),
        ),
      );
    });

    test('sequential interceptor', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['foo'] = 'bar');
            },
          ),
          SequentialHttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['bar'] = 'baz');
            },
            interceptResponse: (response, handler) {
              final res = Response(
                response.body,
                response.statusCode,
                headers: {...response.headers, 'foo': 'bar'},
              );
              handler.next(res);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      // then
      expectLater(
        response,
        completion(
          predicate<StreamedResponse>(
            (response) =>
                response.statusCode == 200 &&
                req.headers['bar'] == 'baz' &&
                req.headers['foo'] == 'bar' &&
                response.headers['foo'] == 'bar',
          ),
        ),
      );
    });

    test('reject declines other interceptors', () async {
      final sequentialInterceptor = FakeSequentialHttpInterceptorHeaders({
        'foo': 'bar',
      });

      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.reject('rejected 1');
            },
          ),
          sequentialInterceptor,
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      await expectLater(response, throwsA('rejected 1'));
      expect(req.headers['foo'], null);
      expect(sequentialInterceptor.requestCount, isZero);
    });

    test('reject declines other interceptors 2', () async {
      final sequentialInterceptor = FakeSequentialHttpInterceptorDeclining();

      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          sequentialInterceptor,
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.reject('rejected 2');
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.send(req);

      await expectLater(response, throwsA('rejected'));
      expect(req.headers['foo'], null);
    });

    test('same way for other methods', () {
      // given
      final client = InterceptedClient(
        inner: MockClient((request) async => Response('', 200)),
        interceptors: [
          HttpInterceptor.fromHandlers(
            interceptRequest: (request, handler) {
              handler.next(request..headers['foo'] = 'bar');
            },
            interceptResponse: (response, handler) {
              final res = Response(
                response.body,
                response.statusCode,
                headers: {...response.headers, 'foo': 'bar'},
              );
              handler.next(res);
            },
          ),
        ],
      );

      final req = Request('GET', Uri.parse('http://localhost'));

      // when
      final response = client.get(req.url);

      // then
      expectLater(
        response,
        completion(
          predicate<Response>(
            (response) =>
                response.statusCode == 200 && response.headers['foo'] == 'bar',
          ),
        ),
      );
    });
  });
}
