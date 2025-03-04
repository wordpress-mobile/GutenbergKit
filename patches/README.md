# Dependency patches

Sometimes there are problems with dependencies that can be solved by patching them. Gutenberg uses [patch-package](https://www.npmjs.com/package/patch-package) to patch npm dependencies when they're installed.

Existing patches should be described and justified here.

## Patches

### `@wordpress/block-editor`

-   Expose an `open` prop on the `Inserter` component, allowing toggling the inserter visibility via the quick inserter's "Browse all" button.
-   Disable `stripExperimentalSettings` in the `BlockEditorProvider` component so that the Patterns and Media inserter tabs function.
