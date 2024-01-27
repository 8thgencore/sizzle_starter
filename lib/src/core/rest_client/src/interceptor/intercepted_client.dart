import 'dart:async';

import 'package:collection/collection.dart';
import 'package:http/http.dart';

typedef _Interceptor<T extends Object, H extends Handler<T>> = void Function(
  T value,
  H handler,
);

/// Base class for all clients that intercept requests and responses.
base class InterceptedClient extends BaseClient {
  /// Creates a new [InterceptedClient].
  InterceptedClient({
    required Client inner,
    List<HttpInterceptor>? interceptors,
  })  : _inner = inner,
        _interceptors = interceptors ?? const [];

  final Client _inner;
  final List<HttpInterceptor> _interceptors;

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    var requestFuture = Future(() => request);

    for (final interceptor in _interceptors) {
      requestFuture = requestFuture.then(
        _requestInterceptorWrapper(
          interceptor is SequentialHttpInterceptor
              ? interceptor._interceptRequest
              : interceptor.interceptRequest,
        ),
      );
    }

    var responseFuture =
        requestFuture.then(_inner.send).then(Response.fromStream);

    for (final interceptor in _interceptors) {
      responseFuture = responseFuture.then(
        _responseInterceptorWrapper(
          interceptor is SequentialHttpInterceptor
              ? interceptor._interceptResponse
              : interceptor.interceptResponse,
        ),
      );
    }

    return responseFuture.then(
      (response) => StreamedResponse(
        ByteStream.fromBytes(response.bodyBytes),
        response.statusCode,
        contentLength: response.contentLength,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        request: response.request,
      ),
    );
  }

  // Wrapper for request interceptors to return future.
  FutureOr<BaseRequest> Function(BaseRequest) _requestInterceptorWrapper(
    _Interceptor<BaseRequest, RequestHandler> interceptor,
  ) =>
      (BaseRequest request) {
        final handler = RequestHandler();
        interceptor(request, handler);
        return handler._completer.future;
      };

  // Wrapper for response interceptors to return future.
  FutureOr<Response> Function(Response) _responseInterceptorWrapper(
    _Interceptor<Response, ResponseHandler> interceptor,
  ) =>
      (Response response) {
        final handler = ResponseHandler();
        interceptor(response, handler);
        return handler._completer.future;
      };
}

/// BaseHandler
abstract base class Handler<T extends Object> {
  final _completer = Completer<T>();

  void Function()? _processNextInQueue;
}

/// Handler that is used for requests
final class RequestHandler extends Handler<BaseRequest> {
  /// Creates a new [RequestHandler].
  RequestHandler();

  /// Rejects the request.
  void reject(Object error, [StackTrace? stackTrace]) {
    _completer.completeError(error, stackTrace);
    _processNextInQueue?.call();
  }

  /// Resolves the request.
  void next(BaseRequest request) {
    _completer.complete(request);
    _processNextInQueue?.call();
  }
}

/// Handler that is used for responses.
final class ResponseHandler extends Handler<Response> {
  /// Creates a new [ResponseHandler].
  ResponseHandler();

  /// Rejects the response.
  void reject(Object error, [StackTrace? stackTrace]) {
    _completer.completeError(error, stackTrace);
    _processNextInQueue?.call();
  }

  /// Resolves the response.
  void next(Response response) {
    _completer.complete(response);
    _processNextInQueue?.call();
  }
}

/// Interceptor that is used for both requests and responses.
class HttpInterceptor {
  /// Creates a new [HttpInterceptor].
  const HttpInterceptor();

  /// Creates a new [HttpInterceptor] from the given handlers.
  factory HttpInterceptor.fromHandlers({
    _Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    _Interceptor<Response, ResponseHandler>? interceptResponse,
  }) =>
      _HttpInterceptorWrapper(
        interceptRequest: interceptRequest,
        interceptResponse: interceptResponse,
      );

  /// Intercepts the request and returns a new request.
  void interceptRequest(BaseRequest request, RequestHandler handler) =>
      handler.next(request);

  /// Intercepts the response and returns a new response.
  void interceptResponse(Response response, ResponseHandler handler) =>
      handler.next(response);
}

final class _HttpInterceptorWrapper extends HttpInterceptor {
  _HttpInterceptorWrapper({
    _Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    _Interceptor<Response, ResponseHandler>? interceptResponse,
  })  : _interceptRequest = interceptRequest,
        _interceptResponse = interceptResponse;

  final _Interceptor<BaseRequest, RequestHandler>? _interceptRequest;
  final _Interceptor<Response, ResponseHandler>? _interceptResponse;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    if (_interceptRequest != null) {
      _interceptRequest!(request, handler);
    } else {
      handler.next(request);
    }
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    if (_interceptResponse != null) {
      _interceptResponse!(response, handler);
    } else {
      handler.next(response);
    }
  }
}

final class _TaskQueue<T> extends QueueList<T> {
  bool _isRunning = false;
}

/// Pair of value and handler.
typedef _ValueHandler<T extends Object, H extends Handler<T>> = ({
  T value,
  H handler,
});

/// Sequential interceptor is type of [HttpInterceptor] that maintains
/// queues of requests and responses. It is used to intercept requests and
/// responses in the order they were added.
class SequentialHttpInterceptor extends HttpInterceptor {
  /// Creates a new [SequentialHttpInterceptor].
  SequentialHttpInterceptor();

  /// Creates a new [SequentialHttpInterceptor] from the given handlers.
  factory SequentialHttpInterceptor.fromHandlers({
    _Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    _Interceptor<Response, ResponseHandler>? interceptResponse,
  }) =>
      _SequentialHttpInterceptorWrapper(
        interceptRequest: interceptRequest,
        interceptResponse: interceptResponse,
      );

  final _requestQueue =
      _TaskQueue<_ValueHandler<BaseRequest, RequestHandler>>();
  final _responseQueue = _TaskQueue<_ValueHandler<Response, ResponseHandler>>();

  /// Method that enqueues the request.
  void _interceptRequest(BaseRequest request, RequestHandler handler) =>
      _queuedHandler(_requestQueue, request, handler, interceptRequest);

  /// Method that enqueues the response.
  void _interceptResponse(Response response, ResponseHandler handler) =>
      _queuedHandler(_responseQueue, response, handler, interceptResponse);

  void _queuedHandler<T extends Object, H extends Handler<T>>(
    _TaskQueue<_ValueHandler<T, H>> taskQueue,
    T value,
    H handler,
    void Function(T value, H handler) intercept,
  ) {
    final task = (value: value, handler: handler);
    task.handler._processNextInQueue = () {
      if (taskQueue.isNotEmpty) {
        final nextTask = taskQueue.removeFirst();
        intercept(nextTask.value, nextTask.handler);
      } else {
        taskQueue._isRunning = false;
      }
    };

    taskQueue.add(task);

    if (!taskQueue._isRunning) {
      taskQueue._isRunning = true;
      final task = taskQueue.removeFirst();
      intercept(task.value, task.handler);
    }
  }
}

final class _SequentialHttpInterceptorWrapper
    extends SequentialHttpInterceptor {
  _SequentialHttpInterceptorWrapper({
    _Interceptor<BaseRequest, RequestHandler>? interceptRequest,
    _Interceptor<Response, ResponseHandler>? interceptResponse,
  })  : _$interceptRequest = interceptRequest,
        _$interceptResponse = interceptResponse;

  final _Interceptor<BaseRequest, RequestHandler>? _$interceptRequest;
  final _Interceptor<Response, ResponseHandler>? _$interceptResponse;

  @override
  void interceptRequest(BaseRequest request, RequestHandler handler) {
    if (_$interceptRequest != null) {
      _$interceptRequest!(request, handler);
    } else {
      handler.next(request);
    }
  }

  @override
  void interceptResponse(Response response, ResponseHandler handler) {
    if (_$interceptResponse != null) {
      _$interceptResponse!(response, handler);
    } else {
      handler.next(response);
    }
  }
}
