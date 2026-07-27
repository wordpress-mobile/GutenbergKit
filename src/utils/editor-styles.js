/**
 * WordPress dependencies
 */
// Default styles that are needed for the editor.
import componentsStyles from '@wordpress/components/build-style/style.css?inline';
import blockEditorStyles from '@wordpress/block-editor/build-style/style.css?inline';
import blockLibraryEditorStyles from '@wordpress/block-library/build-style/editor.css?inline';
import formatLibraryStyles from '@wordpress/format-library/build-style/style.css?inline';
import editorStyles from '@wordpress/editor/build-style/style.css?inline';

// Right-to-left counterparts, generated upstream by `rtlcss`.
import componentsStylesRTL from '@wordpress/components/build-style/style-rtl.css?inline';
import blockEditorStylesRTL from '@wordpress/block-editor/build-style/style-rtl.css?inline';
import blockLibraryEditorStylesRTL from '@wordpress/block-library/build-style/editor-rtl.css?inline';
import formatLibraryStylesRTL from '@wordpress/format-library/build-style/style-rtl.css?inline';
import editorStylesRTL from '@wordpress/editor/build-style/style-rtl.css?inline';

// Order is significant — it mirrors the cascade the stylesheets relied upon
// when they were imported for their side effects.
const LTR_STYLES = [
	componentsStyles,
	blockEditorStyles,
	blockLibraryEditorStyles,
	formatLibraryStyles,
	editorStyles,
];

const RTL_STYLES = [
	componentsStylesRTL,
	blockEditorStylesRTL,
	blockLibraryEditorStylesRTL,
	formatLibraryStylesRTL,
	editorStylesRTL,
];

const STYLE_ELEMENT_ID = 'gutenberg-kit-editor-styles';

/**
 * Injects the editor stylesheets matching the document's text direction.
 *
 * Only one variant is ever inserted. The `-rtl` bundles are full rewrites of
 * their left-to-right counterparts rather than overrides — across the five
 * stylesheets roughly 690 selectors appear in both files with conflicting
 * declarations, and almost none are scoped by a `[dir=rtl]` guard. Loading
 * both would leave the cascade to resolve those conflicts by source order,
 * applying one direction to every user regardless of locale.
 *
 * WordPress solves this server-side by swapping the enqueued file
 * (`is_rtl() ? 'style-rtl.css' : 'style.css'`). GutenbergKit ships both
 * variants in the bundle and selects between them here instead, since the
 * editor loads a single static `index.html`.
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
	document.head.appendChild( element );
}
