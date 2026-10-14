// Default styles that are needed for the editor. The block content styles are
// global rather than passed to the block canvas, which would scope them under
// `.editor-styles-wrapper` and break selectors relying on `<body>` classes
// such as `wp-embed-responsive`. WordPress never scopes these either.
import componentsStyles from '@wordpress/components/build-style/style.css?inline';
import blockEditorStyles from '@wordpress/block-editor/build-style/style.css?inline';
import blockLibraryStyles from '@wordpress/block-library/build-style/style.css?inline';
import blockEditorContentStyles from '@wordpress/block-editor/build-style/content.css?inline';
import blockLibraryEditorStyles from '@wordpress/block-library/build-style/editor.css?inline';
import formatLibraryStyles from '@wordpress/format-library/build-style/style.css?inline';
import editorStyles from '@wordpress/editor/build-style/style.css?inline';
// Right-to-left counterparts, generated upstream by `rtlcss`.
import componentsStylesRTL from '@wordpress/components/build-style/style-rtl.css?inline';
import blockEditorStylesRTL from '@wordpress/block-editor/build-style/style-rtl.css?inline';
import blockLibraryStylesRTL from '@wordpress/block-library/build-style/style-rtl.css?inline';
import blockEditorContentStylesRTL from '@wordpress/block-editor/build-style/content-rtl.css?inline';
import blockLibraryEditorStylesRTL from '@wordpress/block-library/build-style/editor-rtl.css?inline';
import formatLibraryStylesRTL from '@wordpress/format-library/build-style/style-rtl.css?inline';
import editorStylesRTL from '@wordpress/editor/build-style/style-rtl.css?inline';

const LTR_STYLES = [
	componentsStyles,
	blockEditorStyles,
	blockLibraryStyles,
	blockEditorContentStyles,
	blockLibraryEditorStyles,
	formatLibraryStyles,
	editorStyles,
];

const RTL_STYLES = [
	componentsStylesRTL,
	blockEditorStylesRTL,
	blockLibraryStylesRTL,
	blockEditorContentStylesRTL,
	blockLibraryEditorStylesRTL,
	formatLibraryStylesRTL,
	editorStylesRTL,
];

const STYLE_ELEMENT_ID = 'gutenberg-kit-editor-styles';

/**
 * Injects the editor stylesheets matching the document's text direction.
 *
 * Only one variant is ever inserted. The `-rtl` bundles are full rewrites of
 * their left-to-right counterparts rather than overrides — across these
 * stylesheets hundreds of selectors appear in both files with conflicting
 * declarations, and almost none are scoped by a `[dir=rtl]` guard. Loading
 * both would leave the cascade to resolve those conflicts by source order,
 * applying one direction to every user regardless of locale.
 *
 * WordPress solves this server-side by swapping the enqueued file
 * (`is_rtl() ? 'style-rtl.css' : 'style.css'`). GutenbergKit ships both
 * variants in the bundle and selects between them here instead, since the
 * editor loads a single static `index.html`.
 *
 * The element is inserted before the first stylesheet link rather than
 * appended. These stylesheets are the base layer that GutenbergKit's own
 * styles build on, and several selectors tie on specificity across the two
 * (`.gutenberg-kit .components-button` against
 * `.editor-visual-editor .components-button`, both `0,2,0`). Ties resolve by
 * source order, so appending would silently hand those to WordPress. Building
 * these as a side-effect import placed them first; inserting first preserves
 * that.
 *
 * @param {boolean} isRTL Whether the editor renders right-to-left.
 *
 * @return {void}
 */
export function injectEditorStyles( isRTL ) {
	const existing = document.getElementById( STYLE_ELEMENT_ID );
	if ( existing ) {
		existing.remove();
	}

	const element = document.createElement( 'style' );
	element.id = STYLE_ELEMENT_ID;
	element.textContent = ( isRTL ? RTL_STYLES : LTR_STYLES ).join( '\n' );

	const firstStylesheet = document.head.querySelector(
		'link[rel="stylesheet"], style'
	);
	document.head.insertBefore( element, firstStylesheet );
}
