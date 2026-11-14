# Editor Widget

A versatile text editor widget for Flutter applications, supporting syntax highlighting, editable regions, and customizable appearance.

## Installation

Include the necessary imports in your Dart file:

```dart
import 'package:phone_ide/phone_ide.dart';
```

Requires Flutter 3.29.0 or later.

## Usage

Here's a basic example of how to integrate the `Editor` widget into your Flutter app:

```dart
Editor(
  options: EditorOptions(
    backgroundColor: Colors.black,
    linebarColor: Colors.grey.shade800,
    linebarTextColor: Colors.white,
    showLinebar: true,
    takeFullHeight: true,
    fontFamily: 'Courier',
    regionOptions: EditorRegionOptions(
      start: 3,
      end: 10,
      color: Colors.grey.shade900,
    ),
  ),
  defaultLanguage: 'dart',
  defaultValue: '''
void main() {
  print('Hello, World!');
}
''',
  path: 'main.dart',
);
```

### Parameters

- **options** (`EditorOptions`): Customize appearance and behavior of the editor.
- **defaultLanguage** (`String`): Initial programming language setting (for syntax highlighting).
- **defaultValue** (`String`): Initial content displayed in the editor.
- **path** (`String`): Identifier for the file, typically the filename.

## Customizing the Editor

Import the public API with `package:phone_ide/phone_ide.dart`. Surface, gutter,
caret, selection, active-line and syntax colors are configured per editor, so
light and dark editors can coexist without changing a global theme.

```dart
EditorOptions(
  backgroundColor: Colors.white,
  textColor: const Color(0xFF2B2140),
  linebarColor: const Color(0xFFFFF8EC),
  linebarTextColor: const Color(0xFF5E5470),
  linebarBorderColor: const Color(0xFFF1E2C8),
  cursorColor: const Color(0xFF5B4BDB),
  selectionColor: const Color(0x405B4BDB),
  activeLineColor: const Color(0xFFF6F6FE),
  activeLineBorderColor: const Color(0xFF5B4BDB),
  fontFamily: 'YourMonospaceFont',
  fontSize: 16,
  lineHeight: 1.5,
  linebarWidth: 28,
  syntaxTheme: const EditorSyntaxTheme(
    foreground: Color(0xFF2B2140),
    comment: Color(0xFF5E5470),
    keyword: Color(0xFF5B4BDB),
    string: Color(0xFF1E7F46),
    number: Color(0xFFB93D0A),
    type: Color(0xFF8B3FD9),
    function: Color(0xFF1F6FD1),
    tag: Color(0xFF5B4BDB),
    attribute: Color(0xFFC2185B),
    operator: Color(0xFF5E5470),
    punctuation: Color(0xFF5E5470),
    variable: Color(0xFF2B2140),
  ),
);
```

`lineHeight` is a font-size multiplier: 16 × 1.5 gives a 24 logical pixel row
before accessibility scaling. `linebarWidth` is a minimum; the gutter grows for
larger text or longer line numbers. Long source lines scroll horizontally.
The editor supplies its own field decoration, independently of the host's
`InputDecorationTheme`.

Tapping unused editor space or the gutter focuses the main editable region and
opens the keyboard. Direct taps on code keep their normal cursor placement;
scrolling and read-only editors do not trigger this focus behavior.

An editable region can span several lines. Its fill and optional leading border
cover the whole region, including an empty insertion row, and resize as code is
added. They stay visible when the caret moves elsewhere.

```dart
EditorRegionOptions(
  start: 1,
  end: 5,
  color: const Color(0xFFF6F6FE),
  borderColor: const Color(0xFF5B4BDB), // Optional 3 logical pixel border.
);
```

Custom syntax colors preserve their alpha values. Leaving `syntaxTheme` null
retains the original Atom One Dark colors. Supported languages are HTML, CSS,
JavaScript (`js`) and Python (`py`); HTML can contain embedded CSS and JavaScript. Unknown languages remain editable as plain text.

`EditorOptions` and `EditorRegionOptions` are immutable. Use `copyWith` to
change them, then rebuild an editor with the same key, path and starting value
to preserve code, selection and undo history. For example,
`options.copyWith(fontSize: 16, cursorColor: null)` changes the font size and
clears the custom cursor color. Omitted values stay unchanged. `fontSize` and
`lineHeight` must be finite and positive; `linebarWidth` must be finite and
nonnegative.

`EditorSyntaxTheme.atomOneDark.copyWith(comment: Colors.grey)` provides a
starting palette for custom token colors.

If you listen to the widget's streams, move those subscriptions to the
replacement `Editor` widget.
The editor state disposes its internal controllers and listeners; callers retain
ownership of subscriptions and public streams.

## Listening to Text Changes

You can listen for changes in the editor content through the provided streams:

```dart
final editor = Editor(
  options: EditorOptions(),
  defaultLanguage: 'dart',
  defaultValue: '',
  path: 'script.dart',
);

editor.onTextChange.stream.listen((content) {
  print('Editor content changed: \$content');
});

editor.editableRegion.stream.listen((editableContent) {
  print('Editable region content: \$editableContent');
});
```

## License

This project is licensed under the MIT License.
