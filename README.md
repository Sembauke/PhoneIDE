# Editor Widget

A versatile text editor widget for Flutter applications, supporting syntax highlighting, editable regions, and customizable appearance.

## Installation

Include the necessary imports in your Dart file:

```dart
import 'package:phone_ide/editor/editor.dart';
import 'package:phone_ide/editor/editor_options.dart';
```

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
- **enableSimpleAutocomplete** (`bool`, in `EditorOptions`): Enables lightweight built-in HTML/CSS/JS suggestions.
- **maxAutocompleteSuggestions** (`int`, in `EditorOptions`): Caps how many suggestions are shown in the dropdown.
- **autocompleteAssetPath** (`String`, in `EditorOptions`): JSON asset used for autocomplete suggestions.
  When this is the default bundled path (`packages/phone_ide/assets/autocomplete/suggestions.json`),
  the editor also merges `packages/phone_ide/assets/autocomplete/javascript_objects.generated.json`
  for JavaScript object-member completions.

## Customizing the Editor

You can adjust the appearance by tweaking the `EditorOptions`:

```dart
EditorOptions(
  backgroundColor: Colors.blueGrey,
  linebarColor: Colors.black54,
  fontFamily: 'Monaco',
  isEditable: false,
  enableSimpleAutocomplete: true,
  maxAutocompleteSuggestions: 8,
  autocompleteAssetPath:
      'packages/phone_ide/assets/autocomplete/suggestions.json',
);
```

## JSON Autocomplete Format

Autocomplete suggestions can be defined in an asset JSON file.

Default file:
`packages/phone_ide/assets/autocomplete/suggestions.json`

Supported fields per suggestion item:
- `value` (required): primary token used for matching.
- `label` (optional): text shown in the dropdown.
- `insertText` (optional): inserted text when tapped.
- `category` (optional): right-side metadata text.
- `detail` (optional): overrides category in the UI.
- `language` (optional): `html`, `css`, or `javascript`.
- `previewColor` (optional): hex color (for swatch).
- `priority` (optional): base ranking boost.
- `when` (optional): regex tested against context before caret.
- `whenBoost` (optional): extra ranking points when `when` matches.

Example:

```json
{
  "languages": {
    "javascript": [
      { "value": "const", "category": "JavaScript keyword" },
      {
        "value": "log",
        "label": "console.log",
        "insertText": "console.log()",
        "category": "JavaScript snippet",
        "when": "console\\.[a-zA-Z]*$",
        "whenBoost": 120
      }
    ]
  }
}
```

### Object-Member Schema (Nested)

For object-aware completions (for example `console.` -> `log`, `error`), the parser also supports:

```json
{
  "objects": {
    "javascript": {
      "console": {
        "members": [
          { "name": "log", "kind": "method" },
          { "name": "error", "kind": "method" }
        ]
      }
    }
  }
}
```

You can generate a starter schema from `@types/web`:

```bash
dart run tool/generate_dom_object_schema.dart --min-members=2
```

Generated file:
`assets/autocomplete/javascript_objects.generated.json`

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
