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
