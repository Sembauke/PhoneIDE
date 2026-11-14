part of 'editor.dart';

PythonIndentModel _analyzePythonInBackground(
        (String, PythonIndentOptions, int?) job) =>
    PythonIndentModel.analyze(job.$1, options: job.$2, virtualLine: job.$3);

extension _PythonEditorState on EditorState {
  bool get _isPython =>
      const {'python', 'py'}.contains(widget.defaultLanguage.toLowerCase());

  PythonIndentOptions get _pythonOptions =>
      widget.options.pythonIndentOptions ??
      PythonIndentOptions(indentSize: widget.options.indentSize);

  String get _analysisText => _currentDocument.analysisText;

  PythonIndentModel? get _currentPythonModel {
    if (!_isPython) return null;
    final text = _analysisText;
    final options = _pythonOptions;
    final virtualLine = _currentDocument.virtualAnalysisLine;
    if (_pendingPythonModel?.text == text &&
        _pendingPythonModel?.options == options &&
        _pendingPythonModel?.virtualLine == virtualLine) {
      return _pythonModel;
    }
    if (_pythonModel == null ||
        _pythonModel!.text != text ||
        _modelOptions != options ||
        _pythonModel?.virtualLine != virtualLine) {
      if (text.length > 80000) {
        _guideDebounce?.cancel();
        _pendingPythonModel = null;
        if (_backgroundText != text ||
            _backgroundOptions != options ||
            _backgroundVirtualLine != virtualLine) {
          _backgroundText = text;
          _backgroundOptions = options;
          _backgroundVirtualLine = virtualLine;
          final generation = ++_analysisGeneration;
          unawaited(_pythonAnalysisWorker
              .analyze(text, options: options, virtualLine: virtualLine)
              .then((model) {
            if (!mounted ||
                generation != _analysisGeneration ||
                model == null) {
              return;
            }
            _acceptPythonModel(model, options);
          }, onError: (Object error, StackTrace stack) {
            if (!mounted || generation != _analysisGeneration) return;
            FlutterError.reportError(FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'phone_ide',
                context: ErrorDescription('analyzing Python indentation')));
          }));
        }
        return _pythonModel;
      }
      _analysisGeneration++;
      _backgroundText = null;
      _modelOptions = options;
      _pythonCache.options = options;
      final next = _pythonCache.update(text, virtualLine: virtualLine);
      final previous = _pythonModel;
      _guideDebounce?.cancel();
      _pendingPythonModel = null;
      if (previous != null &&
          next.lines.last.endState.continued &&
          !previous.lines.last.endState
              .sameContinuationModes(next.lines.last.endState)) {
        _pendingPythonModel = next;
        _guideDebounce = Timer(const Duration(milliseconds: 240), () {
          if (!mounted || !identical(_pendingPythonModel, next)) return;
          _pendingPythonModel = null;
          _acceptPythonModel(next, options);
        });
      } else {
        _pythonModel = next;
        assert(() {
          _modelRevision++;
          return true;
        }());
      }
    }
    return _pythonModel;
  }

  PythonIndentModel get _inputPythonModel {
    final current = _currentPythonModel;
    final text = _analysisText;
    final pending = _pendingPythonModel;
    if (pending != null &&
        pending.text == text &&
        pending.options == _pythonOptions &&
        pending.virtualLine == _currentDocument.virtualAnalysisLine) {
      return pending;
    }
    if (current != null &&
        current.text == text &&
        current.options == _pythonOptions &&
        current.virtualLine == _currentDocument.virtualAnalysisLine) {
      return current;
    }
    assert(() {
      if (text.length > 80000) _syncInputAnalyses++;
      return true;
    }());
    return PythonIndentModel.analyze(text,
        options: _pythonOptions,
        virtualLine: _currentDocument.virtualAnalysisLine);
  }

  int _regionOffset(RegionPosition position) =>
      _currentDocument.offsetOf(position);

  int? get _globalCaretOffset {
    final controller = _controller(_activePosition);
    return controller.selection.isValid
        ? _regionOffset(_activePosition) + controller.selection.extentOffset
        : null;
  }
}
