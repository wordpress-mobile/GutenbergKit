# Dependency patches

Sometimes there are problems with dependencies that can be solved by patching them. Gutenberg uses [patch-package](https://www.npmjs.com/package/patch-package) to patch npm dependencies when they're installed.

Existing patches should be described and justified here.

## Patches

### `@wordpress/block-editor`

-   Expose an `open` prop on the `Inserter` component, allowing toggling the inserter visibility via the quick inserter's "Browse all" button.
-   Disable `stripExperimentalSettings` in the `BlockEditorProvider` component so that the Patterns and Media inserter tabs function.
-   Allow setting popover props for the `Inserter` component, so we can improve the mobile screen reader experience by marking it as a modal dialog.

### `@wordpress/block-library`

-   Enable image resizing on mobile devices by removing the `isLargeViewport` check from the `isResizable` condition in the `Image` component. The resizing feature appears to work well enough now, in contrast to the description in https://github.com/WordPress/gutenberg/issues/2675.

### `@wordpress/components`

-   Apply workaround to `FormFileUpload` to address iOS Safari's lack of support for a wildcard `audio/*` MIME type. Can be removed once [the issue](https://github.com/WordPress/gutenberg/issues/70119) is resolved in a future release.

### `@wordpress/rich-text`

-   Fix `preventFocusCapture` causing uneditable text blocks on touch devices when scrolling by swiping outside of the block canvas--e.g., along the edge of the screen.
