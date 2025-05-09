/**
 * WordPress dependencies
 */
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';

/**
 * Internal dependencies
 */
import Layout from '../components/layout';
import { createRoot, StrictMode } from '@wordpress/element';
import { dispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import { registerCoreBlocks } from '@wordpress/block-library';
import { unregisterDisallowedBlocks } from './blocks';
import { getGBKit, getPost } from './bridge';

/**
 * Configure editor settings and styles, and render the editor.
 *
 * Dependency injection is used for various `@wordpress` package functions so
 * that this utility can be used in both the local and remote editor, which
 * rely upon ES modules and global variables, respectively.
 *
 * @param {Object} [options]
 * @param {Array}  [options.allowedBlockTypes]
 */
export function initializeEditor( { allowedBlockTypes } = {} ) {
	const { themeStyles, hideTitle, editorSettings } = getGBKit();

	const settings = editorSettings || {
		defaultEditorStyles: [ { css: defaultEditorStyles } ],
	};
	dispatch( editorStore ).updateEditorSettings( settings );

	const preferenceDispatch = dispatch( preferencesStore );
	preferenceDispatch.setDefaults( 'core', {
		fixedToolbar: true,
	} );
	preferenceDispatch.setDefaults( 'core/edit-post', {
		themeStyles,
	} );

	registerCoreBlocks();
	unregisterDisallowedBlocks( allowedBlockTypes );
	const post = getPost();

	createRoot( document.getElementById( 'root' ) ).render(
		<StrictMode>
			<Layout post={ post } hideTitle={ hideTitle } />
		</StrictMode>
	);
}
