import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:phone_ide/controller/custom_text_controller.dart';
import 'package:phone_ide/editor/editor_options.dart';
import 'package:phone_ide/editor/linebar.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/models/textfield_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Editor extends StatefulWidget {
  Editor({
    Key? key,
    required this.options,
    required this.defaultLanguage,
    required this.defaultValue,
    required this.path,
  }) : super(key: key);

  // Stream that holds the entire editor content.
  final StreamController<String> onTextChange =
      StreamController<String>.broadcast();

  final StreamController<TextFieldData> textfieldData =
      StreamController<TextFieldData>.broadcast();

  // Stream that holds the contents of the editable region.
  final StreamController<String> editableRegion =
      StreamController<String>.broadcast();

  final EditorOptions options;

  // The starting value of the editor
  final String defaultValue;

  // The starting language of the editor
  final String defaultLanguage;

  // The path e.g. file name "index.html"
  final String path;

  @override
  State<StatefulWidget> createState() => EditorState();
}

class EditorState extends State<Editor> {
  ScrollController scrollController = ScrollController();
  ScrollController horizontalController = ScrollController();
  ScrollController linebarController = ScrollController();

  TextEditingControllerIDE beforeController = TextEditingControllerIDE();
  TextEditingControllerIDE inController = TextEditingControllerIDE();
  TextEditingControllerIDE afterController = TextEditingControllerIDE();

  late StreamSubscription<TextFieldData> _textfieldDataSub;

  int _currNumLines = 1;

  double _initialWidth = 28;

  String currentFileName = '';

  @override
  void initState() {
    super.initState();
    _initializeEditor();

    _textfieldDataSub = widget.textfieldData.stream.listen((event) {
      handleTextChange(
        event.controller.text,
        event.position,
        widget.options.regionOptions != null,
      );
    });

    scrollController.addListener(() {
      linebarController.jumpTo(scrollController.offset);
    });
  }

  @override
  void dispose() {
    super.dispose();
    scrollController.dispose();
    horizontalController.dispose();
    linebarController.dispose();
    _textfieldDataSub.cancel();
  }

  bool isLoading = true;

  Future<void> _initializeEditor() async {
    await TextMateHighlighterRegistry.instance.initialize();
    if (!mounted) return;
    try {
      await handleFileInit();
    } catch (error) {
      if (!mounted) return;
      debugPrint(
        'phone_ide: Editor initialization fallback due to error: $error',
      );
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<SharedPreferences?> _getPreferencesSafe() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint(
        'phone_ide: SharedPreferences unavailable, continuing without cache: '
        '$error',
      );
      return null;
    }
  }

  void updateLineCount(String event, RegionPosition region) async {
    if (!mounted) return;
    late String lines;

    if (widget.options.regionOptions != null) {
      switch (region) {
        case RegionPosition.before:
          lines = event +
              (event.isNotEmpty ? '\n' : '') +
              inController.text +
              (afterController.text.isNotEmpty ? '\n' : '') +
              afterController.text;
          break;
        case RegionPosition.inner:
          lines = beforeController.text +
              (beforeController.text.isNotEmpty ? '\n' : '') +
              event +
              (afterController.text.isNotEmpty ? '\n' : '') +
              afterController.text;
          break;
        case RegionPosition.after:
          lines = beforeController.text +
              (beforeController.text.isNotEmpty ? '\n' : '') +
              inController.text +
              (event.isNotEmpty ? '\n' : '') +
              event;
          break;
      }
    } else {
      lines = event;
    }

    setState(() {
      _currNumLines = lines.split('\n').length;
    });
  }

  double getTextHeight(BuildContext context, {double fontSize = 18}) {
    TextScaler textScaler = MediaQuery.of(context).textScaler;

    double calculatedFontSize = textScaler.scale(fontSize);

    Size textHeight = Linebar.calculateTextSize(
      'L',
      style: TextStyle(
        color: widget.options.linebarTextColor,
        fontSize: calculatedFontSize,
        fontFamily: widget.options.fontFamily,
      ),
      context: context,
    );

    return textHeight.height;
  }

  double getFontSize(BuildContext context, {double fontSize = 18}) {
    TextScaler textScaler = MediaQuery.of(context).textScaler;

    double calculatedFontSize = textScaler.scale(fontSize);

    return calculatedFontSize;
  }

  Future<void> handleFileInit() async {
    final prefs = await _getPreferencesSafe();
    String fileContent = widget.defaultValue;
    EditorRegionOptions? region = widget.options.regionOptions;

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      await handleRegionFields();

      if (region != null) {
        int regionStart = region.start!;
        if (prefs?.get(widget.path) != null) {
          regionStart = int.parse(
            prefs?.getString(widget.path)?.split(':')[0] ?? '',
          );
        }

        if (fileContent.split('\n').length > 7) {
          Future.delayed(const Duration(milliseconds: 250), () {
            if (!mounted) return;
            double offset = fileContent
                    .split('\n')
                    .sublist(0, regionStart - 1 < 0 ? 0 : regionStart - 1)
                    .length *
                getTextHeight(context);
            scrollController.animateTo(
              offset,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          });
        }
      }

      if (scrollController.hasClients && linebarController.hasClients) {
        linebarController.jumpTo(0);
        scrollController.jumpTo(0);
      }
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    });

    beforeController.language = widget.defaultLanguage;
    inController.language = widget.defaultLanguage;
    afterController.language = widget.defaultLanguage;
  }

  handleRegionFields() async {
    final prefs = await _getPreferencesSafe();
    EditorRegionOptions? region = widget.options.regionOptions;
    String path = widget.path;
    String fileContent = widget.defaultValue;

    if (region != null) {
      int regionStart = region.start!;
      int regionEnd = region.end!;

      if (prefs?.get(path) != null) {
        regionStart = int.parse(prefs?.getString(path)?.split(':')[0] ?? '');
        regionEnd = int.parse(prefs?.getString(path)?.split(':')[1] ?? '');
      }

      int lines = fileContent.split('\n').length;

      if (lines >= 1) {
        String beforeEditableRegionText =
            fileContent.split('\n').sublist(0, regionStart).join('\n');

        String inEditableRegionText = fileContent
            .split('\n')
            .sublist(regionStart, regionEnd - 1)
            .join('\n');

        String afterEditableRegionText = fileContent
            .split('\n')
            .sublist(regionEnd - 1, fileContent.split('\n').length)
            .join('\n');
        beforeController.text = beforeEditableRegionText;
        inController.text = inEditableRegionText;
        afterController.text = afterEditableRegionText;
      }
    } else {
      beforeController.text = '';
      inController.text = fileContent;
      afterController.text = '';
    }

    updateLineCount(inController.text, RegionPosition.inner);
  }

  handleRegionCaching(String event, RegionPosition region) async {
    final prefs = await _getPreferencesSafe();
    if (prefs == null) return;
    late int beforeRegionLines;
    late int inRegionLines;
    late int newRegionlines;

    if (region == RegionPosition.before) {
      beforeRegionLines = event.split('\n').length;
      inRegionLines = inController.text.split('\n').length + 1;
      newRegionlines = inRegionLines + beforeRegionLines;
    } else if (region == RegionPosition.inner) {
      beforeRegionLines = beforeController.text.split('\n').length;
      inRegionLines = event.split('\n').length + 1;
      newRegionlines = inRegionLines + beforeRegionLines;
    }

    prefs.setString(
      widget.path,
      '$beforeRegionLines:$newRegionlines',
    );
  }

  handleTextChange(String event, RegionPosition region, bool hasRegion) {
    if (!mounted) return;
    updateLineCount(event, region);

    late String text;

    switch (region) {
      case RegionPosition.before:
        text = '$event\n${inController.text}\n${afterController.text}';
        break;
      case RegionPosition.inner:
        if (hasRegion) {
          text = '${beforeController.text}\n$event\n${afterController.text}';
        } else {
          text = event;
        }
        widget.editableRegion.sink.add(event);
        break;
      case RegionPosition.after:
        text = '${beforeController.text}\n${inController.text}\n$event';
        break;
    }

    widget.onTextChange.sink.add(text);
  }

  handleCurrentFocusedTextfieldController(RegionPosition position) {
    if (!mounted) return;

    if (position == RegionPosition.before) {
      widget.textfieldData.sink.add(
        TextFieldData(
          controller: beforeController,
          position: RegionPosition.before,
        ),
      );
    } else if (position == RegionPosition.inner) {
      widget.textfieldData.sink.add(
        TextFieldData(
          controller: inController,
          position: RegionPosition.inner,
        ),
      );
    } else if (position == RegionPosition.after) {
      widget.textfieldData.sink.add(
        TextFieldData(
          controller: afterController,
          position: RegionPosition.after,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        if (isLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final mediaQueryData = MediaQuery.of(context);

        return MediaQuery(
          data: mediaQueryData.copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: Row(
            children: [
              if (widget.options.showLinebar)
                Container(
                  constraints: BoxConstraints(
                    minWidth: 1,
                    maxWidth: _initialWidth,
                  ),
                  decoration: BoxDecoration(
                    color: widget.options.linebarColor,
                    border: const Border(
                      right: BorderSide(
                        color: Color.fromRGBO(0x88, 0x88, 0x88, 1),
                      ),
                    ),
                  ),
                  child: linecountBar(),
                ),
              Expanded(
                child: Container(
                  color: widget.options.backgroundColor,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      gestureSettings: DeviceGestureSettings(touchSlop: 8.0),
                    ),
                    child: editorView(context),
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget editorView(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: horizontalController,
      child: Container(
        width: !widget.options.isEditable
            ? MediaQuery.of(context).size.width + 600
            : 5000,
        child: ListView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          shrinkWrap: !widget.options.takeFullHeight,
          children: [
            if (widget.options.regionOptions != null &&
                beforeController.text.isNotEmpty)
              editorField(context, RegionPosition.before),
            editorField(context, RegionPosition.inner),
            if (widget.options.regionOptions != null &&
                afterController.text.isNotEmpty)
              editorField(context, RegionPosition.after),
          ],
        ),
      ),
    );
  }

  TextField editorField(
    BuildContext context,
    RegionPosition position,
  ) {
    TextEditingController returnCorrectController(RegionPosition position) {
      switch (position) {
        case RegionPosition.before:
          return beforeController;
        case RegionPosition.inner:
          return inController;
        case RegionPosition.after:
          return afterController;
      }
    }

    return TextField(
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      enabled: widget.options.isEditable,
      controller: returnCorrectController(position),
      decoration: InputDecoration(
        border: InputBorder.none,
        filled: true,
        fillColor: widget.options.regionOptions != null &&
                position == RegionPosition.inner
            ? widget.options.regionOptions!.color
            : widget.options.backgroundColor,
        contentPadding: const EdgeInsets.only(
          left: 10,
        ),
        isDense: true,
      ),
      maxLines: null,
      style: TextStyle(
        fontSize: getFontSize(context, fontSize: 18),
        fontFamily: widget.options.fontFamily,
        color: Colors.white.withValues(alpha: 0.87),
      ),
      onChanged: (String event) {
        if (widget.options.regionOptions != null &&
            position != RegionPosition.after) {
          handleRegionCaching(event, position);
        }

        handleTextChange(event, position, widget.options.regionOptions != null);
      },
      onTap: () {
        handleCurrentFocusedTextfieldController(position);
      },
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'[“”]'),
            replacementString: '"'),
        FilteringTextInputFormatter.deny(RegExp(r'[‘’]'),
            replacementString: "'")
      ],
    );
  }

  linecountBar() {
    return Column(
      mainAxisSize:
          widget.options.takeFullHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            controller: linebarController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _currNumLines == 0 ? 1 : _currNumLines,
            itemBuilder: (_, i) {
              TextEditingController lineController = TextEditingController();
              lineController.text = (i + 1).toString();
              return Linebar(
                calculateBarWidth: () {
                  if (i + 1 > 9) {
                    SchedulerBinding.instance.addPostFrameCallback(
                      (timeStamp) {
                        if (!mounted) return;
                        setState(() {
                          _initialWidth = getTextHeight(context) +
                              (8 * (i + 1).toString().length);
                        });
                      },
                    );
                  }
                },
                child: TextField(
                  readOnly: true,
                  enableInteractiveSelection: false,
                  controller: lineController,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: getFontSize(context, fontSize: 18),
                    fontWeight: FontWeight.w500,
                    fontFamily: widget.options.fontFamily,
                    color: widget.options.linebarTextColor,
                  ),
                  maxLines: null,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              );
            },
          ),
        )
      ],
    );
  }
}
