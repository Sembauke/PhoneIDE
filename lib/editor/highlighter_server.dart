import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SyntaxHighlightingServer {
  HeadlessInAppWebView? _headlessWebView;
  InAppWebViewController? _controller;
  bool _isInitialized = false;

  String _tokenizeScript(String code) {
    final escapedCode = jsonEncode(code);
    return '''
      (function() {
        if (!window.grammar) {
          throw new Error('Grammar not initialized');
        }

        const code = $escapedCode;
        const result = window.grammar.tokenizeLine(code, window.INITIAL);
        return result.tokens;
      })();
    ''';
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      log('Loading TextMate assets...');

      // Load all assets with package prefix
      final onigurumaJs = await rootBundle.loadString(
        'packages/phone_ide/assets/highlighter/vscode-oniguruma.js',
      );
      final textmateJs = await rootBundle.loadString(
        'packages/phone_ide/assets/highlighter/vscode-textmate.js',
      );
      final wasmBytes = await rootBundle.load(
        'packages/phone_ide/assets/highlighter/onig.wasm',
      );
      final wasmBase64 = base64Encode(wasmBytes.buffer.asUint8List());

      final htmlGrammar = await rootBundle.loadString(
        'packages/phone_ide/assets/highlighter/html.tmLanguage.json',
      );
      final cssGrammar = await rootBundle.loadString(
        'packages/phone_ide/assets/highlighter/css.tmLanguage.json',
      );
      final jsGrammar = await rootBundle.loadString(
        'packages/phone_ide/assets/highlighter/JavaScript.tmLanguage.json',
      );

      log('Assets loaded, creating HTML document...');

      // Create HTML with embedded scripts
      final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>TextMate Highlighter</title>
</head>
<body>
<script>
$onigurumaJs
</script>
<script>
$textmateJs
</script>
<script>
(async function() {
  try {
    const wasmBase64 = "$wasmBase64";
    const wasmBinary = Uint8Array.from(atob(wasmBase64), c => c.charCodeAt(0));

    const onigLib = await onig.loadWASM(wasmBinary.buffer).then(() => {
      return {
        createOnigScanner: (patterns) => new onig.OnigScanner(patterns),
        createOnigString: (str) => new onig.OnigString(str)
      };
    });

    const htmlGrammar = $htmlGrammar;
    const cssGrammar = $cssGrammar;
    const jsGrammar = $jsGrammar;

    window.registry = new vscodetextmate.Registry({
      onigLib: Promise.resolve(onigLib),
      loadGrammar: async (scopeName) => {
        switch (scopeName) {
          case 'text.html.basic':
            return htmlGrammar;
          case 'source.css':
            return cssGrammar;
          case 'source.js':
            return jsGrammar;
          default:
            return null;
        }
      }
    });

    window.grammar = await window.registry.loadGrammar('text.html.basic');
    window.INITIAL = vscodetextmate.INITIAL;

    window.flutter_inappwebview.callHandler('onInitialized', 'ok');
  } catch (error) {
    console.error('Initialization error:', error);
    window.flutter_inappwebview.callHandler('onInitialized', 'error: ' + error.message);
  }
})();
</script>
</body>
</html>
      ''';

      final initCompleter = Completer<void>();

      // Create headless webview
      _headlessWebView = HeadlessInAppWebView(
        initialData: InAppWebViewInitialData(
          data: htmlContent,
          mimeType: 'text/html',
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
        ),
        onWebViewCreated: (controller) {
          _controller = controller;

          // Register handler for initialization callback
          controller.addJavaScriptHandler(
            handlerName: 'onInitialized',
            callback: (args) {
              if (args.isNotEmpty) {
                final result = args[0] as String;
                log('Initialization callback: $result');
                if (result == 'ok') {
                  _isInitialized = true;
                  if (!initCompleter.isCompleted) {
                    initCompleter.complete();
                  }
                  log('TextMate tokenizer initialized successfully');
                } else {
                  if (!initCompleter.isCompleted) {
                    initCompleter.completeError(
                      Exception('Tokenizer initialization failed: $result'),
                    );
                  }
                }
              }
            },
          );
        },
        onConsoleMessage: (controller, consoleMessage) {
          log('WebView console: ${consoleMessage.message}');
        },
      );

      await _headlessWebView!.run();

      // Wait for initialization with timeout
      await initCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('TextMate initialization timeout');
        },
      );
    } catch (e) {
      log('Error initializing SyntaxHighlightingServer: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> tokenizeLine(String code) async {
    if (!_isInitialized || _controller == null) {
      throw Exception('Server not initialized. Call initialize() first.');
    }

    try {
      final result = await _controller!.evaluateJavascript(
        source: _tokenizeScript(code),
      );

      if (result == null) {
        return [];
      }

      if (result is List) {
        return result;
      }

      return [];
    } catch (e) {
      log('Error tokenizing line: $e');
      return [];
    }
  }

  Future<void> dispose() async {
    if (_headlessWebView != null) {
      await _headlessWebView!.dispose();
      _headlessWebView = null;
    }
    _controller = null;
    _isInitialized = false;
  }
}
