### 4.0.0 (unreleased)

#### Breaking changes and migration

- Require Flutter 3.29.0 or later.
- `EditorOptions` and `EditorRegionOptions` are now immutable. Replace field assignments with `copyWith`, then rebuild the editor. Passing `null` explicitly clears a nullable option; omitting it retains the current value.
- Invalid typography values now throw `ArgumentError` in all builds: `fontSize` and `lineHeight` must be finite and positive, and `linebarWidth` must be finite and nonnegative. Indentation sizes must also be positive.
- Removed the public `EditorState` implementation helpers `currentFileName`, `updateLineCount`, `handleFileInit`, `handleRegionFields`, `editorView`, `editorField`, and `linecountBar`. Read `Editor.path` for the file name, and rebuild `Editor` with the new `path`, `defaultValue`, or region boundaries to load different content. Use the `Editor` widget to render the complete editor; its gutter and fields are now internal.
- Removed the unused `EditorState.getFontSize` helper. Use `MediaQuery.textScalerOf(context).scale(options.fontSize)` when a host needs the scaled font size.
- `EditorState.getTextHeight` now uses `EditorOptions.fontSize` when its optional `double? fontSize` argument is omitted. It returns the nominal scaled typography height, including `EditorOptions.lineHeight` and editor zoom, rather than measuring a glyph. Actual row positions come from native text layout.
- The `EditorState` text and scroll controllers are now `final` and owned and disposed by the editor. Do not replace or dispose them. Existing controller reads and updates remain available; toolbar integrations can continue using `textfieldData`.
- Removed the unused `Linebar`, `LinebarState`, and `Linebar.calculateTextSize` from `lib/editor/linebar.dart`. They were not exported by `phone_ide.dart`, but consumers importing that file directly must remove those imports. Use `EditorOptions.showLinebar` and the gutter options for the built-in gutter, or `TextPainter` for independent text measurement.
- Code rows now use a fixed strut with a default `lineHeight` of `1.5` and honor accessibility text scaling. Review fixed-height host layouts, and set `EditorOptions.fontSize` and `lineHeight` explicitly when matching existing designs.
- Host `InputDecorationTheme` no longer styles code fields. Configure editor, region, caret, selection, and gutter colors through `EditorOptions` and `EditorRegionOptions` instead. The default gutter border remains `#888888`; set `linebarBorderColor` to customize or hide it.
- Taps on unused editor space or the gutter now focus the main editable field. Focus changes no longer emit `onTextChange` or `editableRegion`; use `textfieldData` for focus/controller notifications and the text streams only for actual edits.
- Read-only editors reject toolbar/controller text mutations as well as keyboard edits. To replace read-only content, rebuild with a new `defaultValue`.

#### Added and fixed

- Add `EditorSyntaxTheme.atomOneDark` and `copyWith` for building custom palettes.
- Preserve transparency in custom syntax colors, including colors with identical RGB values and different alpha.
- Export `PythonIndentOptions` from the public library.
- Fix hardware arrow boundary navigation, read-only shortcut interception, multi-character IME commits, snippet paste indentation, composition-aware bracket pairing, tab-indented editing and mixed-selection dedent.
- Keep gutter offsets and cached native row geometry during edits. Preserve pending deferred formatting when the caret moves.
- Bound and group Python undo history, and support Cmd undo/redo alongside Ctrl shortcuts.
- Reuse unchanged line widths and guide painters, coalesce background analysis through one worker, reuse pending lexical models, and avoid delaying guide updates for ordinary typing inside open brackets.
- Compare incremental models over seeded edits, retain deterministic Python editing regressions, and exclude test fixtures from the published package.
- Add indentation guides, enabled by default, with configurable size and color, rendered space/tab alignment, and blank-line continuity across editable regions; derive blank-row guides from surrounding code and recognized block openings independently of blank whitespace, and cache geometry independently of caret movement.
- Preserve leading indentation and caret placement on Enter, with lexical Python indentation and basic opening-delimiter detection for JavaScript, CSS and JSON. Preserve active IME composition; Python paste retains relative snippet indentation.
- Move Backspace to the previous indentation stop within leading whitespace, preserving normal text deletion, selections and active IME composition.
- Update the active-line highlight independently of document layout on cursor movement; cache horizontal width measurements until content or typography changes.
- Keep source line numbering correct around empty editable regions and expose line-number accessibility labels for Python and other languages.
- Cover large documents, read-only toolbar input, initialization races, reseeding, subscription disposal, and active highlights after blur with behavior tests.
- Add per-editor syntax, caret, selection and active-line styling.
- Add an optional leading border that spans the full editable region as it grows.
- Focus the main editable field when tapping unused editor space or the gutter.
- Add Python highlighting and preserve IME composing underlines.
- Isolate code fields from host form decoration and replace gutter fields with text.
- Keep source and gutter rows aligned with accessibility text scaling and horizontal scrolling.
- Preserve edits and stream connections during live theme changes; stop reporting focus as a code edit.

### 3.0.0
- feat: adds TextMate syntax highlighting for `html`, `css`, and `javascript`, including embedded styles/scripts inside HTML.
- refactor: replaces `highlight` and `flutter_highlight` with `syntax_highlight`.
- fix: falls back to plain text when highlighter initialization fails so the editor remains usable.
- test: adds coverage for highlighting behavior and fallback paths.

### 2.0.1
- fix: having multiple editors at once will now have the correct highlighting for both editors

### 2.0.0

- feat: adds support to make the editor read-only.
- feat: adds support to make the editor take minium height instead of full height.
- feat: adds support to hide the line gutter.
- refactor: `filteTextStream` as it is no longer needed use `defaultValue` instead.
- refactor: changes `editorBackgroundColor` to `backgroundColor`.
- refactor: removes `hasRegion` just supply a `region` to the editor if you want to use it.
- fix: gets rid of `condition` a relic from the past.

### 1.5.1

- fixes a bug where the line gutter is not aligned with the editor when switching to another file.
- fixes a bug that inserted an extra blank line when switching to a file without an editable region.
- fixes a bug where the previous file would be displayed for a couple of
  millisecond when switching to another file.

### 1.5.0

- feat added a new stream that returns the text in the editable region.

### 1.4.0+1

- feat added the option to choose another font family.

### 1.3.0+1

- fixes a bug where smart quotes are inserted into the editor for IOS devices
- feat added a text controller stream to the editor which allows for the editor to be controlled from outside the editor based on which controller is focused.

### 1.2.4+1

- fixes a bug where the linecount is highlighted for JavaScript files
- fixes a bug where the linecount is being incorrectly displayed for single line content.
- fixes a bug where single line files are not being displayed in the editor.

### 1.2.3+1

- fixes a bug where the linecount does not align with the editor text in Flutter 3.16

### 1.2.2+1

- fixes a bug where the editable region starts at the beginning of the file in the scrollcontroller.

### 1.2.1+1

- made phoneIDE package compatible with Flutter 3.10

### 1.2.0+1

- fixes top-padding when no region field is present in any way.
- fixes scrolling beyond the list boundary for vertical and horizontal listview
- feat before and after fields will no longer be present when there is no text present. (When a region field is present)
- fixes out of index bug, which was caused by the scroll controller function which tried to split on an index which did not exist if the line count was one or less.

### 1.1.1+1

- fixes smart quoutes being inserted into the editor for IOS devices

### 1.1.0+1

- creates an example for the phoneIDE package

### 1.0.4+1

- fixes a bug where the linebanr does not correctly align with top of the editor

### 1.0.3+1

- fixes a bug where the linebar displays the incorrect amount of line numbers
- fixes a bug where the linebar does not scroll with the editor

### 1.0.2+1

- removes test file
- removes redundant options
- updated applicationId from `com.phone.ide` to `org.freecodecamp.phone_ide`

### 1.0.1+1

- updated `readme.md` to use right package name.

### 1.0.0+1

- removes file system
- removes file explorer
- removes highlight enums and history enums, which where no longer used
- removes directory model
- removes html package
- removes path_provider
- changes name from `flutter_code_editor` to `phone_ide`
- changes the default color of the editor text to white
- changes the circular progress indicator to "open file"
- updated `compileSDKversion` from 31 to 33
- updated `readme.md` to use the new example
- creates a library file which imports all separate files
- creates a good example `main.dart` file.
