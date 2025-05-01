/**
 * WordPress dependencies
 */
import { createRoot, StrictMode } from '@wordpress/element';
import { dispatch } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { store as preferencesStore } from '@wordpress/preferences';
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';
import { registerCoreBlocks } from '@wordpress/block-library';

/**
 * Internal dependencies
 */
import Layout from '../components/layout';
import { getGBKit, getPost } from './bridge';

/**
 * Configure editor settings and styles, and render the editor.
 */
export function initializeEditor() {
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
	const post = getPost();

	createRoot( document.getElementById( 'root' ) ).render(
		<StrictMode>
			<Layout post={ post } hideTitle={ hideTitle } />
		</StrictMode>
	);
}
