/**
 * Empty stub for Node.js modules imported by PostCSS.
 *
 * PostCSS marks `path`, `fs`, `url`, and `source-map-js` as `false` in its
 * `browser` field, but `@wordpress/block-editor` imports PostCSS via direct
 * file paths (e.g., `postcss/lib/processor`), bypassing that field. This stub
 * is aliased to those modules so Vite resolves them without emitting
 * "Module has been externalized for browser compatibility" warnings.
 *
 * @see https://github.com/postcss/postcss/blob/main/package.json
 */
export default {};
