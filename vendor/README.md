# Vendored Files

This directory contains vendored third-party files that GutenbergKit loads directly, since it does not include the full set of WordPress core assets.

## wp-util.js

- **Source**: [`wp-includes/js/wp-util.js`](https://github.com/WordPress/wordpress-develop/blob/117af7e9a37c02ee17ac8f143cb46b6b0f4cde15/src/js/_enqueues/wp/util.js)
- **Commit**: `117af7e9a37c02ee17ac8f143cb46b6b0f4cde15`

Provides `wp.ajax` (authenticated AJAX utilities) and `wp.template` (JavaScript templating). WordPress normally enqueues this as the `wp-util` script handle. GutenbergKit vendors it because the editor assets endpoint excludes core WordPress scripts, and the IIFE captures jQuery via closure at execution time — so it must be loaded after jQuery is on `window`.