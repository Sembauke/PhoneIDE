import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'python_indentation.dart';

typedef _AnalysisRequest = (String, PythonIndentOptions, int?);

/// One reusable lexer isolate, with at most one running and one queued request.
/// Superseded callers receive null; the queued request always contains the most
/// recent document. An editor owns and disposes its worker.
class PythonAnalysisWorker {
  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _errors;
  Future<SendPort>? _ready;
  Completer<SendPort>? _handshake;
  SendPort? _port;
  bool _disposed = false;
  _AnalysisRequest? _queued;
  Completer<PythonIndentModel?>? _waiting;
  Completer<PythonIndentModel?>? _running;

  Future<PythonIndentModel?> analyze(String text,
      {required PythonIndentOptions options, int? virtualLine}) {
    if (_disposed) return Future.value(null);
    _waiting?.complete(null);
    _waiting = Completer<PythonIndentModel?>();
    final result = _waiting!.future;
    _queued = (text, options, virtualLine);
    _dispatch();
    return result;
  }

  Future<SendPort> _start() async {
    final ready = Completer<SendPort>();
    _handshake = ready;
    _responses = ReceivePort();
    final replyPort = _responses!.sendPort;
    _errors = ReceivePort();
    _errors!.listen((dynamic error) {
      final details = error as List<dynamic>;
      final failure = RemoteError('${details[0]}', '${details[1]}');
      if (!ready.isCompleted) ready.completeError(failure);
      _resetTransport();
      _finishError(failure);
    });
    _responses!.listen((dynamic message) {
      if (message is SendPort) {
        _port = message;
        ready.complete(message);
        _handshake = null;
      } else if (message is PythonIndentModel) {
        _finish(message);
      } else if (message is (String, String)) {
        _finishError(RemoteError(message.$1, message.$2));
      }
    });
    try {
      _isolate =
          await Isolate.spawn(_run, replyPort, onError: _errors!.sendPort);
    } catch (error, stack) {
      _resetTransport();
      if (!ready.isCompleted) ready.completeError(error, stack);
    }
    if (_disposed) {
      _isolate?.kill(priority: Isolate.immediate);
      if (!ready.isCompleted) ready.complete(replyPort);
    }
    return ready.future;
  }

  void _dispatch() {
    if (_disposed || _running != null || _queued == null) return;
    final request = _queued!;
    _queued = null;
    _running = _waiting;
    _waiting = null;
    if (kIsWeb) {
      // Isolates are unavailable on web; retain the same coalescing contract.
      Future(() => PythonIndentModel.analyze(request.$1,
              options: request.$2, virtualLine: request.$3))
          .then(_finish, onError: (Object error) => _finishError(error));
      return;
    }
    if (_port != null) {
      _port!.send(request);
      return;
    }
    (_ready ??= _start()).then((port) {
      if (!_disposed) port.send(request);
    }, onError: (Object error) => _finishError(error));
  }

  void _finish(PythonIndentModel model) {
    if (_disposed) return;
    _running?.complete(_queued == null ? model : null);
    _running = null;
    _dispatch();
  }

  void _finishError(Object error) {
    if (_disposed) return;
    _running?.completeError(error);
    _waiting?.completeError(error);
    _running = _waiting = null;
    _queued = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _running?.complete(null);
    _waiting?.complete(null);
    _running = _waiting = null;
    _queued = null;
    // Resolve startup too; disposal can precede the worker's first message.
    if (_handshake != null && !_handshake!.isCompleted) {
      _handshake!.complete(_responses!.sendPort);
    }
    _resetTransport();
  }

  void _resetTransport() {
    _isolate?.kill(priority: Isolate.immediate);
    _responses?.close();
    _errors?.close();
    _isolate = null;
    _responses = _errors = null;
    _port = null;
    _ready = null;
    _handshake = null;
  }

  static void _run(SendPort output) {
    final requests = ReceivePort();
    final cache = PythonIndentCache();
    output.send(requests.sendPort);
    requests.listen((dynamic message) {
      final request = message as _AnalysisRequest;
      try {
        cache.options = request.$2;
        output.send(cache.update(request.$1, virtualLine: request.$3));
      } catch (error, stack) {
        output.send((error.toString(), stack.toString()));
      }
    });
  }
}
