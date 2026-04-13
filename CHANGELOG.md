# GutenbergKit CHANGELOG

This file tracks **breaking changes** to help consumers plan upgrades. For the full list of changes in each release, see [GitHub Releases](https://github.com/wordpress-mobile/GutenbergKit/releases).

---

## Trunk

### Breaking Changes

_None_

## 0.15.0

### Breaking Changes

-   Move editor loading into the library — callers no longer manage the editor load lifecycle. [#326]
-   AJAX requests now use token authentication instead of cookie-based auth. [#181]

## 0.12.0

### Breaking Changes

-   Update to Swift 6 — requires Swift 6 compiler toolchain. [#252]
-   Disable cookies in EditorService. [#246]
-   Remove unused `setup` method from public API. [#244]

## 0.10.0

### Breaking Changes

-   Increase deployment target to iOS 17. [#189]
-   Remove unused `EditorNetworking`. [#208]

## 0.8.0

### Breaking Changes

-   Remove unnecessary WebView global configuration. [#172]

## 0.6.0

### Breaking Changes

-   Remove iOS cookie configuration. [#157]

[#157]: https://github.com/wordpress-mobile/GutenbergKit/pull/157
[#172]: https://github.com/wordpress-mobile/GutenbergKit/pull/172
[#181]: https://github.com/wordpress-mobile/GutenbergKit/pull/181
[#189]: https://github.com/wordpress-mobile/GutenbergKit/pull/189
[#208]: https://github.com/wordpress-mobile/GutenbergKit/pull/208
[#244]: https://github.com/wordpress-mobile/GutenbergKit/pull/244
[#246]: https://github.com/wordpress-mobile/GutenbergKit/pull/246
[#252]: https://github.com/wordpress-mobile/GutenbergKit/pull/252
[#326]: https://github.com/wordpress-mobile/GutenbergKit/pull/326
