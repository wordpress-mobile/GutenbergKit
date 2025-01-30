# Dependency patches

Sometimes there are problems with dependencies that can be solved by patching them. Gutenberg uses [patch-package](https://www.npmjs.com/package/patch-package) to patch npm dependencies when they're installed.

Existing patches should be described and justified here.

## Patches

### `@wordpress/block-editor`

Expose an `open` prop on the `Inserter` component, allowing toggling the inserter visibility via the quick inserter's "Browse all" button.

### `@wordpress/editor`

Revert https://github.com/WordPress/gutenberg/pull/64892 and export the private `useBlockEditorSettings` API as it is required for GutenbergKit's use of the block editor settings. This can be removed once GutenbergKit resides in the Gutenberg repository, where we can access all the necessary APIs—both public and private.
