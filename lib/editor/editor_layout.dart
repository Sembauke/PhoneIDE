part of 'editor.dart';

const _contentPadding = 10.0;
const _caretClearance = 4.0;
const _gutterPadding = 8.0;
const _minimumGutterNumber = 99;
const _leadingBorderWidth = 3.0;
const _editorTouchSlop = 8.0;

TextPainter _layoutText(
        String text, TextStyle style, TextScaler scaler, StrutStyle strut) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      strutStyle: strut,
    )..layout();

double _measureText(
    String text, TextStyle style, TextScaler scaler, StrutStyle strut) {
  final painter = _layoutText(text, style, scaler, strut);
  final width = painter.width;
  painter.dispose();
  return width;
}

double _measureContentWidth(
    _EditorDocument document, TextStyle style, TextScaler scaler) {
  final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
  var width = 0.0;
  for (final region in document.regions) {
    for (final line in region.lines) {
      final lineWidth = _measureText(line, style, scaler, strut);
      width = math.max(width,
          lineWidth.ceilToDouble() + _contentPadding * 2 + _caretClearance);
    }
  }
  return width;
}

class _ContentWidthCache {
  _EditorDocument? _document;
  TextStyle? _style;
  TextScaler? _scaler;
  double _width = 0;

  double measure(_EditorDocument document, TextStyle style, TextScaler scaler) {
    if (!identical(document, _document) ||
        _style != style ||
        _scaler != scaler) {
      _width = _measureContentWidth(document, style, scaler);
      _document = document;
      _style = style;
      _scaler = scaler;
    }
    return _width;
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter(
      {required this.document,
      required this.controller,
      required this.width,
      required this.rowHeight,
      required this.style,
      required this.options});

  final _EditorDocument document;
  final ScrollController controller;
  final double width;
  final double rowHeight;
  final TextStyle style;
  final EditorOptions options;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        key: const ValueKey('phone-ide-gutter'),
        width: width,
        decoration: BoxDecoration(
            color: options.linebarColor,
            border:
                Border(right: BorderSide(color: options.linebarBorderColor))),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          controller: controller,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: document.lineCount,
          itemExtent: rowHeight,
          itemBuilder: (_, index) {
            return Align(
              key: ValueKey('phone-ide-line-${index + 1}'),
              alignment: Alignment.center,
              child: Text('${document.toFileLine(index + 1) ?? ''}',
                  textDirection: TextDirection.ltr,
                  strutStyle:
                      StrutStyle.fromTextStyle(style, forceStrutHeight: true),
                  style: style.copyWith(
                      color: options.linebarTextColor,
                      fontWeight: FontWeight.w400)),
            );
          },
        ),
      ),
    );
  }
}

class _ActiveLine extends StatelessWidget {
  const _ActiveLine(
      {required this.line,
      required this.region,
      required this.rowHeight,
      required this.color,
      required this.borderColor});

  final ValueListenable<int?> line;
  final _DocumentRegion region;
  final double rowHeight;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int?>(
        valueListenable: line,
        builder: (_, active, __) {
          if (active == null ||
              active < region.firstLine ||
              active >= region.firstLine + region.lineCount ||
              (color == null && borderColor == null)) {
            return const SizedBox.shrink();
          }
          return Positioned(
            top: (active - region.firstLine) * rowHeight,
            left: 0,
            right: 0,
            height: rowHeight,
            child: IgnorePointer(
                child: Container(
              key: const ValueKey('phone-ide-active-line'),
              decoration: BoxDecoration(
                  color: color,
                  border: Border(
                      left: BorderSide(
                          color: borderColor ?? Colors.transparent,
                          width: _leadingBorderWidth))),
            )),
          );
        },
      );
}

class _CodeField extends StatelessWidget {
  const _CodeField(
      {required this.region,
      required this.controller,
      required this.focusNode,
      required this.options,
      required this.style,
      required this.rowHeight,
      required this.activeLine,
      required this.onChanged,
      required this.onTap});

  final _DocumentRegion region;
  final TextEditingControllerIDE controller;
  final FocusNode focusNode;
  final EditorOptions options;
  final TextStyle style;
  final double rowHeight;
  final ValueListenable<int?> activeLine;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final regionOptions =
        region.position == RegionPosition.inner ? options.regionOptions : null;
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final border = regionOptions?.borderColor;
    return DecoratedBox(
      key: ValueKey('phone-ide-region-${region.position.name}'),
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
          border: border == null
              ? null
              : Border(
                  left: BorderSide(color: border, width: _leadingBorderWidth))),
      child: ColoredBox(
        color: regionOptions?.color ?? options.backgroundColor,
        child: Stack(children: [
          _ActiveLine(
              line: activeLine,
              region: region,
              rowHeight: rowHeight,
              color: options.activeLineColor,
              borderColor: options.activeLineBorderColor),
          TextField(
            focusNode: focusNode,
            controller: controller,
            readOnly: !options.isEditable,
            smartQuotesType: SmartQuotesType.disabled,
            smartDashesType: SmartDashesType.disabled,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            textDirection: TextDirection.ltr,
            cursorColor: options.cursorColor,
            selectionHeightStyle: BoxHeightStyle.strut,
            strutStyle: strut,
            decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                fillColor: Colors.transparent,
                isCollapsed: true,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: _contentPadding)),
            maxLines: null,
            minLines: region.lineCount,
            style: style,
            onChanged: onChanged,
            onTap: onTap,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[“”]'),
                  replacementString: '"'),
              FilteringTextInputFormatter.deny(RegExp(r'[‘’]'),
                  replacementString: "'"),
            ],
          ),
        ]),
      ),
    );
  }
}
