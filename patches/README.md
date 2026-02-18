# Dependency patches

Sometimes there are problems with dependencies that can be solved by patching them. Gutenberg uses [patch-package](https://www.npmjs.com/package/patch-package) to patch npm dependencies when they're installed.

Existing patches should be described and justified here.

## Patches

### `@wordpress/block-editor`

-   Expose an `open` prop on the `Inserter` component, allowing toggling the inserter visibility via the quick inserter's "Browse all" button.
-   Disable `stripExperimentalSettings` in the `BlockEditorProvider` component so that the Patterns and Media inserter tabs function.
-   Allow setting popover props for the `Inserter` component, so we can improve the mobile screen reader experience by marking it as a modal dialog.
-   Prevent the insertion point popover from appearing on touch devices in `InserterListItem`. The popover (triggered by `onMouseEnter`) disrupts tap/click events, requiring users to tap inserter items twice before they are inserted.
-   Add `./build-module/components/inserter/media-tab/*` and `./build-module/components/inserter/hooks/*` to the package's `exports` field to allow importing internal inserter modules used by the native inserter component. Note: Creating this patch required using `--exclude='^$'` due to a [patch-package limitation](https://github.com/ds300/patch-package/issues/250).

### `@wordpress/block-library`

-   Enable image resizing on mobile devices by removing the `isLargeViewport` check from the `isResizable` condition in the `Image` component. The resizing feature appears to work well enough now, in contrast to the description in https://github.com/WordPress/gutenberg/issues/2675.

### `@wordpress/editor`

-   Add `./build-style/*` to the package's `exports` field to allow importing CSS files. The package added an `exports` field in [this commit](https://github.com/WordPress/gutenberg/commit/f13dcfaa60) that restricts importable paths, but omitted CSS assets. Note: Creating this patch required using `--exclude='^$'` due to a [patch-package limitation](https://github.com/ds300/patch-package/issues/250).

### `@wordpress/format-library`

-   Add `./build-style/*` to the package's `exports` field to allow importing CSS files. The package added an `exports` field in [this commit](https://github.com/WordPress/gutenberg/commit/f13dcfaa60) that restricts importable paths, but omitted CSS assets. Note: Creating this patch required using `--exclude='^$'` due to a [patch-package limitation](https://github.com/ds300/patch-package/issues/250).

### `react-autosize-textarea`

-   Fix CJS/ESM interop issue where Vite's esbuild pre-bundling wraps the `__esModule`-flagged default export as a module object instead of the actual React component, causing the `PlainText` component to crash. The patch removes the `__esModule` flag and switches from `exports["default"]` to `module.exports`, matching [Gutenberg's upstream fix](https://github.com/WordPress/gutenberg/pull/73822).

### `@wordpress/rich-text`

-   Fix `preventFocusCapture` causing uneditable text blocks on touch devices when scrolling by swiping outside of the block canvas--e.g., along the edge of the screen.
